# Verify that encrypt_temp_files encrypts query-spill temporary files.
#
# A large sort with a small work_mem spills to temporary files. With the GUC
# on, the on-disk temp files must not contain the plaintext canary, and the
# query must still return correct results, which proves the encrypt-on-write
# and decrypt-on-read round trip. A control run with the GUC off confirms the
# canary is otherwise present, so the test is not silently passing.
use strict;
use warnings FATAL => 'all';
use pgtde;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $canary = 'CANARY_TEMPFILE_MARKER';

# Concatenated contents of all temp files under base/pgsql_tmp.
sub slurp_temp_files
{
	my ($node) = @_;
	my $dir = $node->data_dir . '/base/pgsql_tmp';
	my $data = '';

	opendir(my $dh, $dir) or return '';
	for my $f (readdir $dh)
	{
		next if $f eq '.' || $f eq '..';
		next unless -f "$dir/$f";
		$data .= slurp_file("$dir/$f");
	}
	closedir $dh;
	return $data;
}

# Runs a spilling sort behind a held cursor, then inspects the temp files.
sub check_node
{
	my ($node, $expect_plaintext, $label) = @_;

	# Correctness: the spilling sort returns all rows.
	my $count = $node->safe_psql('postgres',
			"SELECT count(*) FROM (SELECT '$canary' || g AS p "
		  . "FROM generate_series(1, 200000) g ORDER BY p) s;");
	is($count, '200000', "$label: spilling sort returns correct row count");

	# Hold a cursor open so the sort tapes stay on disk while we inspect them.
	my $bp = $node->background_psql('postgres');
	$bp->query_safe('BEGIN');
	$bp->query_safe("DECLARE c CURSOR FOR SELECT '$canary' || g AS p "
		  . "FROM generate_series(1, 200000) g ORDER BY p");
	$bp->query_safe('FETCH 1 FROM c');

	my $blob = slurp_temp_files($node);
	ok(length($blob) > 0, "$label: temp files exist on disk");

	if ($expect_plaintext)
	{
		like($blob, qr/\Q$canary\E/, "$label: temp files are plaintext");
	}
	else
	{
		unlike($blob, qr/\Q$canary\E/, "$label: temp files are ciphertext");
	}

	$bp->query_safe('COMMIT');
	$bp->quit;
}

# The contents of each temp file under base/pgsql_tmp, one entry per file.
sub temp_file_contents
{
	my ($node) = @_;
	my $dir = $node->data_dir . '/base/pgsql_tmp';
	my @out;

	opendir(my $dh, $dir) or return @out;
	for my $f (sort readdir $dh)
	{
		next if $f eq '.' || $f eq '..';
		next unless -f "$dir/$f";
		push @out, slurp_file("$dir/$f");
	}
	closedir $dh;
	return @out;
}

# True if any two arguments are byte-identical.
sub has_dup
{
	my %seen;

	for my $x (@_)
	{
		return 1 if $seen{$x}++;
	}
	return 0;
}

# Run two identical spilling sorts behind held cursors so both of their
# temporary files are on disk at once, then return the per-file contents. The
# two sorts consume the same input in the same order, so their BufFiles hold
# byte-identical plaintext.
sub two_identical_temp_files
{
	my ($node) = @_;
	my @bp;

	for my $i (0, 1)
	{
		my $h = $node->background_psql('postgres');
		$h->query_safe('BEGIN');
		$h->query_safe("DECLARE c CURSOR FOR SELECT '$canary' || g AS p "
			  . "FROM generate_series(1, 200000) g ORDER BY p");
		$h->query_safe('FETCH 1 FROM c');
		push @bp, $h;
	}

	my @contents = temp_file_contents($node);

	for my $h (@bp)
	{
		$h->query_safe('COMMIT');
		$h->quit;
	}
	return @contents;
}

sub configure
{
	my ($node, $mode) = @_;
	$node->append_conf('postgresql.conf', 'work_mem = 64kB');
	$node->append_conf('postgresql.conf',
		"shared_preload_libraries = 'open_pg_tde'");
	$node->append_conf('postgresql.conf', "encrypt_temp_files = $mode");
}

# encrypt_temp_files is a core GUC added by the open_pg_tde temp-file patch. On a
# server that carries the storage/WAL hooks but not the temp-file hook (for
# example Percona Server for PostgreSQL, which the CI matrix builds against), the
# GUC does not exist and setting it would make startup fail. Probe for it with a
# node that does not set it, and skip the whole test if the feature is absent.
{
	my $probe = PostgreSQL::Test::Cluster->new('temp_probe');
	$probe->init;
	$probe->append_conf('postgresql.conf',
		"shared_preload_libraries = 'open_pg_tde'");
	$probe->start;
	my $have = $probe->safe_psql('postgres',
		"SELECT count(*) FROM pg_settings WHERE name = 'encrypt_temp_files'");
	$probe->stop;

	if ($have eq '0')
	{
		plan skip_all =>
		  'encrypt_temp_files not available (server built without the open_pg_tde temp-file hook)';
	}
}

# Control node: encryption off, canary must be present.
my $off = PostgreSQL::Test::Cluster->new('temp_plain');
$off->init;
configure($off, 'off');
$off->start;
check_node($off, 1, 'encryption off');

# Encrypted node: canary must be absent.
my $on = PostgreSQL::Test::Cluster->new('temp_enc');
$on->init;
configure($on, 'on');
$on->start;
check_node($on, 0, 'encryption on');

# Temp-file IV reuse (H3): two BufFiles that hold identical plaintext must not
# encrypt to identical ciphertext. Each spilling sort is its own BufFile, and
# the block position that feeds the IV resets to zero in every BufFile, so with
# a cluster-global key and base IV the only thing keeping the two ciphertexts
# apart is the per-BufFile salt (open_pg_tde_tempfile.c mixes it into the XTS
# tweak / CTR IV). The control run with encryption off proves the two sorts
# really do produce byte-identical files, so the encrypted run's difference is
# the salt and not incidental.
my @plain = two_identical_temp_files($off);
ok(scalar(@plain) >= 2 && has_dup(@plain),
	'off: two identical sorts leave byte-identical temp files (control)');

my @cipher = two_identical_temp_files($on);
ok(scalar(@cipher) >= 2 && !has_dup(@cipher),
	'on: identical plaintext yields distinct ciphertext (per-BufFile salt)');

# Shared filesets (parallel workers): a BufFile written by one process and read
# by another derives its salt deterministically from the fileset identity, so
# the writer and reader must agree or the reader would decrypt to garbage. A
# parallel hash join that spills to shared temp files exercises that path; a
# correct result proves the salts agree.
$on->safe_psql('postgres',
	'CREATE TABLE t AS SELECT g FROM generate_series(1, 200000) g');
my $pcount = $on->safe_psql(
	'postgres', q{
	SET max_parallel_workers_per_gather = 2;
	SET enable_parallel_hash = on;
	SET work_mem = '64kB';
	SET parallel_setup_cost = 0;
	SET parallel_tuple_cost = 0;
	SET min_parallel_table_scan_size = '0';
	SELECT count(*) FROM t a JOIN t b USING (g);
});
is($pcount, '200000',
	'on: parallel hash join over encrypted shared temp files returns correct rows'
);

$off->stop;
$on->stop;

done_testing();
