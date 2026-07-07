# Tests for the pluggable data-file cipher selection (pg_tde.data_cipher).
#
# Covers: GUC validation and defaults, that the selected cipher is recorded
# per relation and honoured on read (including after a restart under a
# different setting), that different ciphers coexist in one cluster, and that
# data is ciphertext at rest.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->append_conf('postgresql.conf', q{shared_preload_libraries = 'pg_tde'});
$node->start;

my $keyring = $node->basedir . '/cipher_selection.per';
$node->safe_psql(
	'postgres', qq{
	CREATE EXTENSION pg_tde;
	SELECT pg_tde_add_database_key_provider_file('kp', '$keyring');
	SELECT pg_tde_create_key_using_database_key_provider('k', 'kp');
	SELECT pg_tde_set_key_using_database_key_provider('k', 'kp');
});

# --- GUC validation -------------------------------------------------------

is($node->safe_psql('postgres', 'SHOW pg_tde.data_cipher'),
	'aes_xts', 'pg_tde.data_cipher defaults to aes_xts');

is( $node->safe_psql(
		'postgres', 'SET pg_tde.data_cipher = aes_256; SHOW pg_tde.data_cipher'),
	'aes_256',
	'pg_tde.data_cipher accepts aes_256');

is( $node->safe_psql(
		'postgres', 'SET pg_tde.data_cipher = aes_128; SHOW pg_tde.data_cipher'),
	'aes_128',
	'pg_tde.data_cipher accepts aes_128');

is( $node->safe_psql(
		'postgres', 'SET pg_tde.data_cipher = aes_xts; SHOW pg_tde.data_cipher'),
	'aes_xts',
	'pg_tde.data_cipher accepts aes_xts');

my ($rc, $stdout, $stderr) =
  $node->psql('postgres', 'SET pg_tde.data_cipher = aes_999');
isnt($rc, 0, 'pg_tde.data_cipher rejects an unknown cipher');
like($stderr, qr/invalid value for parameter "pg_tde.data_cipher"/,
	'unknown cipher produces the expected error');

# --- inherit follows pg_tde.cipher ---------------------------------------

is( $node->safe_psql(
		'postgres',
		'SET pg_tde.cipher = aes_256; SET pg_tde.data_cipher = inherit; '
		  . 'CREATE TABLE t_inherit(id int) USING tde_heap; '
		  . 'INSERT INTO t_inherit VALUES (1); SELECT count(*) FROM t_inherit;'),
	'1',
	'inherit creates a working encrypted table following pg_tde.cipher');

# --- per-relation selection + coexistence --------------------------------

my $canary256 = 'CANARY_two_five_six';
my $canary128 = 'CANARY_one_two_eight';

$node->safe_psql(
	'postgres', qq{
	SET pg_tde.data_cipher = aes_256;
	CREATE TABLE t256(id int, s text) USING tde_heap;
	INSERT INTO t256 VALUES (1, '$canary256');
	SET pg_tde.data_cipher = aes_128;
	CREATE TABLE t128(id int, s text) USING tde_heap;
	INSERT INTO t128 VALUES (1, '$canary128');
	CHECKPOINT;
});

is($node->safe_psql('postgres', 'SELECT s FROM t256'),
	$canary256, 't256 (aes_256) round-trips');
is($node->safe_psql('postgres', 'SELECT s FROM t128'),
	$canary128, 't128 (aes_128) round-trips');

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
# Restart with pg_tde.data_cipher forced to aes_128. t256 was created with
# aes_256; if reads used the live setting instead of the recorded cipher, the
# 256-bit key unwrap / page decrypt would fail. Both tables must still decrypt.

$node->append_conf('postgresql.conf', q{pg_tde.data_cipher = 'aes_128'});
$node->restart;

is($node->safe_psql('postgres', 'SELECT s FROM t256'),
	$canary256, 't256 still decrypts after restart under a mismatched GUC');
is($node->safe_psql('postgres', 'SELECT s FROM t128'),
	$canary128, 't128 still decrypts after restart');

done_testing();
