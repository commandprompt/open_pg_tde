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
$off->stop;

# Encrypted node: canary must be absent.
my $on = PostgreSQL::Test::Cluster->new('temp_enc');
$on->init;
configure($on, 'on');
$on->start;
check_node($on, 0, 'encryption on');
$on->stop;

done_testing();
