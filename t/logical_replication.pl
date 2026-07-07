# Logical replication with open_pg_tde encryption enabled.
#
# Sets up two independent clusters, a publisher and a subscriber, both with
# open_pg_tde loaded and their own encryption keys. The publisher has WAL
# encryption enabled, so logical decoding must read and decode changes from
# encrypted WAL. The subscriber applies those changes into its own encrypted
# (tde_heap) tables. This is distinct from t/replication.pl, which covers
# physical (streaming) replication.
use strict;
use warnings FATAL => 'all';
use pgtde;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $pub_keydir = PostgreSQL::Test::Utils::tempdir;
my $sub_keydir = PostgreSQL::Test::Utils::tempdir;

# --- Publisher: wal_level = logical, WAL encryption on -----------------------
my $publisher = PostgreSQL::Test::Cluster->new('publisher');
$publisher->init(allows_streaming => 'logical');
$publisher->append_conf(
	'postgresql.conf', q{
checkpoint_timeout = 1h
shared_preload_libraries = 'open_pg_tde'
});
$publisher->start;

$publisher->safe_psql(
	'postgres', qq(
	CREATE EXTENSION open_pg_tde;

	-- database key for encrypted user tables
	SELECT open_pg_tde_add_database_key_provider_file('pub-db', '$pub_keydir/db.keys');
	SELECT open_pg_tde_create_key_using_database_key_provider('pub-db-key', 'pub-db');
	SELECT open_pg_tde_set_key_using_database_key_provider('pub-db-key', 'pub-db');

	-- server key so WAL encryption can be enabled
	SELECT open_pg_tde_add_global_key_provider_file('pub-global', '$pub_keydir/global.keys');
	SELECT open_pg_tde_create_key_using_global_key_provider('pub-server-key', 'pub-global');
	SELECT open_pg_tde_set_server_key_using_global_key_provider('pub-server-key', 'pub-global');

	ALTER SYSTEM SET open_pg_tde.wal_encrypt = 'on';
));

# Restart so WAL encryption takes effect for all subsequent WAL.
$publisher->restart;

# Guard: the point of this test is decoding logical changes from ENCRYPTED
# WAL, so fail loudly if WAL encryption did not actually turn on.
is($publisher->safe_psql('postgres', 'SHOW open_pg_tde.wal_encrypt'),
	'on', 'WAL encryption is enabled on the publisher');

$publisher->safe_psql(
	'postgres', qq(
	CREATE TABLE t_enc (id int PRIMARY KEY, payload text) USING tde_heap;
	INSERT INTO t_enc VALUES (1, 'alpha'), (2, 'bravo');

	CREATE TABLE t_plain (id int PRIMARY KEY, payload text) USING heap;
	INSERT INTO t_plain VALUES (10, 'plain-ten');

	CREATE PUBLICATION pub_all FOR TABLE t_enc, t_plain;
));

is( $publisher->safe_psql(
		'postgres', "SELECT open_pg_tde_is_encrypted('t_enc')"),
	't',
	'publisher t_enc is encrypted');

# --- Subscriber: its own key, encrypted tables -------------------------------
my $subscriber = PostgreSQL::Test::Cluster->new('subscriber');
$subscriber->init;
$subscriber->append_conf(
	'postgresql.conf', q{
shared_preload_libraries = 'open_pg_tde'
});
$subscriber->start;

$subscriber->safe_psql(
	'postgres', qq(
	CREATE EXTENSION open_pg_tde;
	SELECT open_pg_tde_add_database_key_provider_file('sub-db', '$sub_keydir/db.keys');
	SELECT open_pg_tde_create_key_using_database_key_provider('sub-db-key', 'sub-db');
	SELECT open_pg_tde_set_key_using_database_key_provider('sub-db-key', 'sub-db');

	-- subscriber's copy of the encrypted table is also tde_heap
	CREATE TABLE t_enc (id int PRIMARY KEY, payload text) USING tde_heap;
	CREATE TABLE t_plain (id int PRIMARY KEY, payload text) USING heap;
));

my $pub_connstr = $publisher->connstr . ' dbname=postgres';
$subscriber->safe_psql('postgres',
	"CREATE SUBSCRIPTION sub_all CONNECTION '$pub_connstr' PUBLICATION pub_all;"
);

# --- Initial table sync ------------------------------------------------------
$subscriber->wait_for_subscription_sync($publisher, 'sub_all');

is( $subscriber->safe_psql('postgres', 'SELECT * FROM t_enc ORDER BY id'),
	"1|alpha\n2|bravo",
	'initial sync replicated encrypted table to subscriber');
is($subscriber->safe_psql('postgres', 'SELECT * FROM t_plain ORDER BY id'),
	"10|plain-ten", 'initial sync replicated plain table to subscriber');

# The subscriber's copy must itself be encrypted at rest.
is( $subscriber->safe_psql(
		'postgres', "SELECT open_pg_tde_is_encrypted('t_enc')"),
	't',
	'subscriber t_enc is encrypted');
is( $subscriber->safe_psql(
		'postgres', "SELECT open_pg_tde_is_encrypted('t_plain')"),
	'f',
	'subscriber t_plain is not encrypted');

# --- Incremental changes decoded from encrypted WAL --------------------------
$publisher->safe_psql(
	'postgres', q{
	INSERT INTO t_enc VALUES (3, 'charlie');
	UPDATE t_enc SET payload = 'ALPHA' WHERE id = 1;
	DELETE FROM t_enc WHERE id = 2;
	INSERT INTO t_plain VALUES (11, 'plain-eleven');
});

$publisher->wait_for_catchup('sub_all');

is( $subscriber->safe_psql('postgres', 'SELECT * FROM t_enc ORDER BY id'),
	"1|ALPHA\n3|charlie",
	'insert/update/delete on encrypted table replicated via logical decoding of encrypted WAL'
);
is( $subscriber->safe_psql('postgres', 'SELECT * FROM t_plain ORDER BY id'),
	"10|plain-ten\n11|plain-eleven",
	'changes on plain table replicated');

# Confirm the encrypted table data is ciphertext on disk on the subscriber.
my $relpath =
  $subscriber->safe_psql('postgres', "SELECT pg_relation_filepath('t_enc')");
$subscriber->safe_psql('postgres', 'CHECKPOINT');
my $datafile = $subscriber->data_dir . '/' . $relpath;
my $raw = slurp_file($datafile);
unlike($raw, qr/charlie/,
	'replicated row is ciphertext, not plaintext, on the subscriber');

$subscriber->stop;
$publisher->stop;

done_testing();
