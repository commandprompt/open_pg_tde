# Tests for the pluggable data-file cipher selection (open_pg_tde.data_cipher).
#
# Covers: GUC validation and defaults (only XTS variants are selectable for data
# files), that the selected cipher is recorded per relation and honoured on read
# (including after a restart under a different setting), that different ciphers
# coexist in one cluster, and that data is ciphertext at rest.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->append_conf('postgresql.conf', q{shared_preload_libraries = 'open_pg_tde'});
$node->start;

my $keyring = $node->basedir . '/cipher_selection.per';
$node->safe_psql(
	'postgres', qq{
	CREATE EXTENSION open_pg_tde;
	SELECT open_pg_tde_add_database_key_provider_file('kp', '$keyring');
	SELECT open_pg_tde_create_key_using_database_key_provider('k', 'kp');
	SELECT open_pg_tde_set_key_using_database_key_provider('k', 'kp');
});

# --- GUC validation -------------------------------------------------------

is($node->safe_psql('postgres', 'SHOW open_pg_tde.data_cipher'),
	'aes_xts', 'open_pg_tde.data_cipher defaults to aes_xts');

is( $node->safe_psql(
		'postgres', 'SET open_pg_tde.data_cipher = aes_256_xts; SHOW open_pg_tde.data_cipher'),
	'aes_256_xts',
	'open_pg_tde.data_cipher accepts aes_256_xts');

is( $node->safe_psql(
		'postgres', 'SET open_pg_tde.data_cipher = aes_xts; SHOW open_pg_tde.data_cipher'),
	'aes_xts',
	'open_pg_tde.data_cipher accepts aes_xts');

# The non-tweakable CBC ciphers are no longer selectable for data files; only
# the XTS variants (and inherit) are valid. An unknown cipher is also rejected.
for my $bad (qw(aes_128 aes_256 aes_999))
{
	my ($rc, $stdout, $stderr) =
	  $node->psql('postgres', "SET open_pg_tde.data_cipher = $bad");
	isnt($rc, 0, "open_pg_tde.data_cipher rejects $bad");
	like($stderr, qr/invalid value for parameter "open_pg_tde.data_cipher"/,
		"$bad produces the expected error");
}

# --- inherit follows open_pg_tde.cipher strength but stays XTS ------------
#
# open_pg_tde.cipher selects the principal key length (and is the inherit
# target). Even when it is a non-XTS AES cipher, an inherited data cipher maps
# to the XTS variant of the same strength, so the table is created and works.

is( $node->safe_psql(
		'postgres',
		'SET open_pg_tde.cipher = aes_256; SET open_pg_tde.data_cipher = inherit; '
		  . 'CREATE TABLE t_inherit(id int) USING tde_heap; '
		  . 'INSERT INTO t_inherit VALUES (1); SELECT count(*) FROM t_inherit;'),
	'1',
	'inherit creates a working encrypted table (mapped to XTS)');

# --- per-relation selection + coexistence --------------------------------

my $canary256 = 'CANARY_two_five_six';
my $canary128 = 'CANARY_one_two_eight';

$node->safe_psql(
	'postgres', qq{
	SET open_pg_tde.data_cipher = aes_256_xts;
	CREATE TABLE t256(id int, s text) USING tde_heap;
	INSERT INTO t256 VALUES (1, '$canary256');
	SET open_pg_tde.data_cipher = aes_xts;
	CREATE TABLE t128(id int, s text) USING tde_heap;
	INSERT INTO t128 VALUES (1, '$canary128');
	CHECKPOINT;
});

is($node->safe_psql('postgres', 'SELECT s FROM t256'),
	$canary256, 't256 (aes_256_xts) round-trips');
is($node->safe_psql('postgres', 'SELECT s FROM t128'),
	$canary128, 't128 (aes_xts) round-trips');

# --- ciphertext at rest ---------------------------------------------------

for my $case ([ 't256', $canary256 ], [ 't128', $canary128 ])
{
	my ($tbl, $canary) = @$case;
	my $rel = $node->safe_psql('postgres', "SELECT pg_relation_filepath('$tbl')");
	my $blob = slurp_file($node->data_dir . '/' . $rel);
	unlike($blob, qr/\Q$canary\E/, "$tbl is ciphertext on disk");
}

# --- persistence: recorded cipher is used on read, not the live GUC -------
#
# Restart with open_pg_tde.data_cipher forced to aes_xts (128-bit). t256 was
# created with aes_256_xts; if reads used the live setting instead of the
# recorded cipher, the 256-bit key unwrap / page decrypt would fail. Both tables
# must still decrypt.

$node->append_conf('postgresql.conf', q{open_pg_tde.data_cipher = 'aes_xts'});
$node->restart;

is($node->safe_psql('postgres', 'SELECT s FROM t256'),
	$canary256, 't256 still decrypts after restart under a mismatched GUC');
is($node->safe_psql('postgres', 'SELECT s FROM t128'),
	$canary128, 't128 still decrypts after restart');

done_testing();
