# Encrypted tables with data checksums and hint-bit updates.
#
# open_pg_tde encrypts a whole 8 kB page, so a hint-bit update re-encrypts the
# entire page. This checks that encryption is correct in a cluster initialized
# with data checksums: after hint bits are set and the pages are written and the
# server restarts, the data reads back correctly and no page fails checksum
# verification (the checksum is computed on the plaintext page, then the page is
# encrypted, so verification runs on the decrypted page). Both the AES-128-XTS
# and AES-256-XTS data ciphers are exercised.
#
# Data checksums also cause PostgreSQL to WAL-log hint-bit changes, which is
# what gives torn-page safety for hint-bit updates under whole-page encryption.
use strict;
use warnings FATAL => 'all';
use pgtde;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $keydir = PostgreSQL::Test::Utils::tempdir;

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init(extra => ['--data-checksums']);
$node->append_conf('postgresql.conf',
	"shared_preload_libraries = 'open_pg_tde'");
$node->start;

is($node->safe_psql('postgres', 'SHOW data_checksums'),
	'on', 'cluster has data checksums enabled');

$node->safe_psql(
	'postgres', qq(
	CREATE EXTENSION open_pg_tde;
	SELECT open_pg_tde_add_database_key_provider_file('kp', '$keydir/db.keys');
	SELECT open_pg_tde_create_key_using_database_key_provider('k', 'kp');
	SELECT open_pg_tde_set_key_using_database_key_provider('k', 'kp');
));

# One table per data cipher.
$node->safe_psql(
	'postgres', q{
	SET open_pg_tde.data_cipher = 'aes_xts';
	CREATE TABLE t_xts (id int PRIMARY KEY, s text) USING tde_heap;
	INSERT INTO t_xts SELECT g, 'xts-' || g FROM generate_series(1, 5000) g;

	SET open_pg_tde.data_cipher = 'aes_256_xts';
	CREATE TABLE t_xts256 (id int PRIMARY KEY, s text) USING tde_heap;
	INSERT INTO t_xts256 SELECT g, 'xts256-' || g FROM generate_series(1, 5000) g;
});

# The first read after a committed insert sets HEAP_XMIN_COMMITTED hint bits,
# dirtying the pages; CHECKPOINT then writes the hint-bit-modified, re-encrypted
# pages to disk.
$node->safe_psql('postgres', 'SELECT count(*) FROM t_xts');
$node->safe_psql('postgres', 'SELECT count(*) FROM t_xts256');
$node->safe_psql('postgres', 'CHECKPOINT');

# Restart forces the pages to be read from disk again: decrypt the hint-bit
# pages and verify their checksums.
$node->restart;

is($node->safe_psql('postgres', 'SELECT count(*) FROM t_xts'),
	'5000', 'XTS table reads back after hint bits, checksums, and restart');
is($node->safe_psql('postgres', "SELECT s FROM t_xts WHERE id = 4999"),
	'xts-4999', 'XTS row content is correct after restart');
is($node->safe_psql('postgres', 'SELECT count(*) FROM t_xts256'),
	'5000',
	'XTS-256 table reads back after hint bits, checksums, and restart');
is($node->safe_psql('postgres', "SELECT s FROM t_xts256 WHERE id = 4999"),
	'xts256-4999', 'XTS-256 row content is correct after restart');

# A full scan verifies the checksum of every page of each table; if any page
# failed verification the query would error.
is($node->safe_psql('postgres', 'SELECT sum(length(s)) > 0 FROM t_xts'),
	't', 'full scan of the XTS table passes page checksum verification');
is( $node->safe_psql('postgres', 'SELECT sum(length(s)) > 0 FROM t_xts256'),
	't',
	'full scan of the XTS-256 table passes page checksum verification');

# No checksum-verification failures were logged.
my $log = slurp_file($node->logfile);
unlike(
	$log,
	qr/invalid page in block\b|page verification failed/i,
	'no checksum verification failures were logged');

$node->stop;
done_testing();
