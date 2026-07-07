# AES-256-XTS data-file cipher.
#
# Creates a tde_heap table with open_pg_tde.data_cipher = aes_256_xts, and
# checks that it encrypts at rest, reads back correctly, survives a restart,
# and coexists with an AES-128-XTS table in the same database.
use strict;
use warnings FATAL => 'all';
use pgtde;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $keydir = PostgreSQL::Test::Utils::tempdir;

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->append_conf('postgresql.conf',
	"shared_preload_libraries = 'open_pg_tde'");
$node->start;

$node->safe_psql(
	'postgres', qq(
	CREATE EXTENSION open_pg_tde;
	SELECT open_pg_tde_add_database_key_provider_file('kp', '$keydir/db.keys');
	SELECT open_pg_tde_create_key_using_database_key_provider('k', 'kp');
	SELECT open_pg_tde_set_key_using_database_key_provider('k', 'kp');
));

# AES-256-XTS table.
$node->safe_psql(
	'postgres', q{
	SET open_pg_tde.data_cipher = 'aes_256_xts';
	CREATE TABLE t256 (id int, s text) USING tde_heap;
	INSERT INTO t256 VALUES (1, 'XTS256_CANARY_falcon');
});

# AES-128-XTS table (the default) in the same database.
$node->safe_psql(
	'postgres', q{
	SET open_pg_tde.data_cipher = 'aes_xts';
	CREATE TABLE t128 (id int, s text) USING tde_heap;
	INSERT INTO t128 VALUES (1, 'XTS128_CANARY_otter');
	CHECKPOINT;
});

is($node->safe_psql('postgres', "SHOW open_pg_tde.data_cipher"),
	'aes_xts', 'data_cipher GUC round-trips through aes_256_xts');
is($node->safe_psql('postgres', "SELECT open_pg_tde_is_encrypted('t256')"),
	't', 'AES-256-XTS table is encrypted');
is($node->safe_psql('postgres', 'SELECT s FROM t256'),
	'XTS256_CANARY_falcon', 'AES-256-XTS table reads back correctly');
is($node->safe_psql('postgres', 'SELECT s FROM t128'),
	'XTS128_CANARY_otter',
	'AES-128-XTS table reads back correctly alongside AES-256-XTS');

# Ciphertext on disk for the AES-256-XTS table.
my $relpath =
  $node->safe_psql('postgres', "SELECT pg_relation_filepath('t256')");
my $raw = slurp_file($node->data_dir . '/' . $relpath);
unlike($raw, qr/XTS256_CANARY_falcon/,
	'AES-256-XTS data is ciphertext on disk');

# Both survive a restart.
$node->restart;
is($node->safe_psql('postgres', 'SELECT s FROM t256'),
	'XTS256_CANARY_falcon', 'AES-256-XTS table readable after restart');
is($node->safe_psql('postgres', 'SELECT s FROM t128'),
	'XTS128_CANARY_otter', 'AES-128-XTS table readable after restart');

$node->stop;
done_testing();
