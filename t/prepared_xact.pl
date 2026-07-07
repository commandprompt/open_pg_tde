# Two-phase commit (prepared transactions) on encrypted tables, including
# recovery of a prepared transaction across a crash.
#
# Prepared transactions persist their state to disk (pg_twophase) and are
# replayed from WAL during recovery. This checks that a prepared transaction
# touching an encrypted table commits correctly after a crash, with WAL
# encryption enabled.
use strict;
use warnings FATAL => 'all';
use pgtde;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $keydir = PostgreSQL::Test::Utils::tempdir;

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->append_conf(
	'postgresql.conf', q{
max_prepared_transactions = 10
shared_preload_libraries = 'open_pg_tde'
});
$node->start;

$node->safe_psql(
	'postgres', qq(
	CREATE EXTENSION open_pg_tde;
	SELECT open_pg_tde_add_database_key_provider_file('db', '$keydir/db.keys');
	SELECT open_pg_tde_create_key_using_database_key_provider('db-key', 'db');
	SELECT open_pg_tde_set_key_using_database_key_provider('db-key', 'db');

	SELECT open_pg_tde_add_global_key_provider_file('g', '$keydir/global.keys');
	SELECT open_pg_tde_create_key_using_global_key_provider('server-key', 'g');
	SELECT open_pg_tde_set_server_key_using_global_key_provider('server-key', 'g');
	ALTER SYSTEM SET open_pg_tde.wal_encrypt = 'on';
));
$node->restart;

is($node->safe_psql('postgres', 'SHOW open_pg_tde.wal_encrypt'),
	'on', 'WAL encryption is enabled');

$node->safe_psql(
	'postgres', q{
	CREATE TABLE t_enc (id int PRIMARY KEY, payload text) USING tde_heap;
	INSERT INTO t_enc VALUES (1, 'committed');
});

# Prepare a transaction that modifies the encrypted table, but do not commit.
$node->safe_psql(
	'postgres', q{
	BEGIN;
	INSERT INTO t_enc VALUES (2, 'prepared');
	UPDATE t_enc SET payload = 'changed' WHERE id = 1;
	PREPARE TRANSACTION 'tde_gxact';
});

# The prepared changes are not visible yet.
is($node->safe_psql('postgres', 'SELECT payload FROM t_enc WHERE id = 1'),
	'committed', 'prepared changes are not visible before commit');
is( $node->safe_psql(
		'postgres',
		"SELECT count(*) FROM pg_prepared_xacts WHERE gid = 'tde_gxact'"),
	'1',
	'prepared transaction is registered');

# Crash and recover: the prepared transaction must survive.
$node->stop('immediate');
PGTDE::poll_start($node);

is( $node->safe_psql(
		'postgres',
		"SELECT count(*) FROM pg_prepared_xacts WHERE gid = 'tde_gxact'"),
	'1',
	'prepared transaction survives crash recovery');

# Commit the recovered prepared transaction and verify the encrypted table.
$node->safe_psql('postgres', "COMMIT PREPARED 'tde_gxact';");

is($node->safe_psql('postgres', 'SELECT payload FROM t_enc WHERE id = 1'),
	'changed', 'committed prepared update is visible after recovery');
is($node->safe_psql('postgres', 'SELECT payload FROM t_enc WHERE id = 2'),
	'prepared', 'committed prepared insert is visible after recovery');

# The table is still encrypted at rest.
is( $node->safe_psql('postgres', "SELECT open_pg_tde_is_encrypted('t_enc')"),
	't',
	't_enc is encrypted after 2PC recovery');

# Also exercise ROLLBACK PREPARED.
$node->safe_psql(
	'postgres', q{
	BEGIN;
	INSERT INTO t_enc VALUES (3, 'to-roll-back');
	PREPARE TRANSACTION 'tde_gxact_rb';
});
$node->safe_psql('postgres', "ROLLBACK PREPARED 'tde_gxact_rb';");
is($node->safe_psql('postgres', 'SELECT count(*) FROM t_enc WHERE id = 3'),
	'0', 'rolled-back prepared transaction left no rows');

$node->stop;
done_testing();
