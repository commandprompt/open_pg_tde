# pg_dump / pg_restore round trip of encrypted data.
#
# Verifies that a logical dump of a database with encrypted (tde_heap) tables
# preserves both the data and the tde_heap access method, and that restoring
# into a fresh database re-encrypts the restored tables at rest.
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

# Source database with an encrypted and a plain table.
$node->safe_psql(
	'postgres', qq(
	CREATE EXTENSION open_pg_tde;
	SELECT open_pg_tde_add_database_key_provider_file('src-db', '$keydir/src.keys');
	SELECT open_pg_tde_create_key_using_database_key_provider('src-key', 'src-db');
	SELECT open_pg_tde_set_key_using_database_key_provider('src-key', 'src-db');

	CREATE TABLE t_enc (id int PRIMARY KEY, payload text) USING tde_heap;
	INSERT INTO t_enc SELECT g, 'row-' || g FROM generate_series(1, 100) g;

	CREATE TABLE t_plain (id int PRIMARY KEY, payload text) USING heap;
	INSERT INTO t_plain VALUES (1, 'plain');
));

# Dump the source database.
my $dumpfile = $node->backup_dir . '/dump.sql';
$node->command_ok(
	[ 'pg_dump', '-f', $dumpfile, '-d', $node->connstr('postgres') ],
	'pg_dump of a database with encrypted tables succeeds');

# The dump must record the tde_heap access method for the encrypted table.
my $dump = slurp_file($dumpfile);
like(
	$dump,
	qr/SET default_table_access_method = tde_heap/,
	'dump records the tde_heap access method for the encrypted table');

# Restore into a fresh database that has its own key.
$node->safe_psql(
	'postgres', qq(
	CREATE DATABASE restored;
));
$node->safe_psql(
	'restored', qq(
	CREATE EXTENSION open_pg_tde;
	SELECT open_pg_tde_add_database_key_provider_file('dst-db', '$keydir/dst.keys');
	SELECT open_pg_tde_create_key_using_database_key_provider('dst-key', 'dst-db');
	SELECT open_pg_tde_set_key_using_database_key_provider('dst-key', 'dst-db');
));

$node->command_ok(
	[ 'psql', '-d', $node->connstr('restored'), '-f', $dumpfile ],
	'restore into a database with its own key succeeds');

# Data survived the round trip.
is($node->safe_psql('restored', 'SELECT count(*) FROM t_enc'),
	'100', 'all encrypted rows restored');
is($node->safe_psql('restored', "SELECT payload FROM t_enc WHERE id = 42"),
	'row-42', 'restored encrypted row content is correct');
is($node->safe_psql('restored', 'SELECT count(*) FROM t_plain'),
	'1', 'plain rows restored');

# The restored encrypted table is encrypted under the new database's key.
is( $node->safe_psql('restored', "SELECT open_pg_tde_is_encrypted('t_enc')"),
	't',
	'restored t_enc is encrypted');
is( $node->safe_psql(
		'restored', "SELECT open_pg_tde_is_encrypted('t_plain')"),
	'f',
	'restored t_plain is not encrypted');

# And its data is ciphertext on disk.
my $relpath =
  $node->safe_psql('restored', "SELECT pg_relation_filepath('t_enc')");
$node->safe_psql('restored', 'CHECKPOINT');
my $raw = slurp_file($node->data_dir . '/' . $relpath);
unlike($raw, qr/row-42/,
	'restored encrypted data is ciphertext, not plaintext, on disk');

$node->stop;
done_testing();
