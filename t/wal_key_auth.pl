# Verifies that key_base_iv in the WAL key file is authenticated (M2, WAL).
#
# key_base_iv is the base IV for WAL data (AES-CTR). In the version-2 on-disk
# format it was stored outside the AEAD additional authenticated data, so an
# actor with write access to the WAL key file could change it undetected,
# silently shifting the WAL IV. In version 3 it is part of the AAD, so tampering
# with it fails decryption of the WAL key when it is read.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->append_conf('postgresql.conf',
	"shared_preload_libraries = 'open_pg_tde'");
$node->append_conf('postgresql.conf', "wal_level = 'logical'");
$node->start;

my $keydir = PostgreSQL::Test::Utils::tempdir;
$node->safe_psql(
	'postgres', qq{
	CREATE EXTENSION open_pg_tde;
	SELECT open_pg_tde_add_global_key_provider_file('kp', '$keydir/wal.keys');
	SELECT open_pg_tde_create_key_using_global_key_provider('k', 'kp');
	SELECT open_pg_tde_set_server_key_using_global_key_provider('k', 'kp');
});

$node->safe_psql('postgres',
	'ALTER SYSTEM SET open_pg_tde.wal_encrypt = on;');
$node->restart;

# Generate WAL so a WAL key/range is written and encrypted.
$node->safe_psql(
	'postgres', q{
	CREATE TABLE wal_probe (id int);
	INSERT INTO wal_probe VALUES (1);
	CHECKPOINT;
});
is($node->safe_psql('postgres', 'SHOW open_pg_tde.wal_encrypt;'),
	'on', 'WAL encryption is enabled before tampering');

$node->stop;

# Flip one byte of key_base_iv in the last WAL key entry, the entry that is read
# when the server needs the current WAL key.
#
# v3 WalKeyFileEntry layout: cipher(4) range_type(4) key_base_iv(16)
# range_start(16) entry_iv(16) aead_tag(16) encrypted_key_data(32) = 104 bytes.
# key_base_iv sits at entry offset 8. We address the last entry from the end of
# the file so we do not depend on the header size.
use constant WAL_KEY_ENTRY_SIZE => 104;
use constant KEY_BASE_IV_OFFSET => 8;

my $wal_key_file = $node->data_dir . '/open_pg_tde/wal_keys';
open(my $rfh, '<:raw', $wal_key_file) or die "open $wal_key_file: $!";
local $/;
my $data = <$rfh>;
close $rfh;

my $kbi_off = length($data) - WAL_KEY_ENTRY_SIZE + KEY_BASE_IV_OFFSET;
die "WAL key file too small" if $kbi_off < 0;
substr($data, $kbi_off, 1) = chr(ord(substr($data, $kbi_off, 1)) ^ 0xFF);

open(my $wfh, '>:raw', $wal_key_file) or die "open $wal_key_file: $!";
print $wfh $data;
close $wfh;

# The tampered key_base_iv is now part of the AAD, so decrypting the WAL key
# fails. The server reads the WAL key at startup, so it must refuse to start.
my $started = $node->start(fail_ok => 1);
ok(!$started, 'server refuses to start after key_base_iv is tampered with');

my $log = slurp_file($node->logfile);
like(
	$log,
	qr/corrupted key file|failed to decrypt key|incorrect principal key/i,
	'tampering with key_base_iv is detected (key_base_iv is authenticated)');

done_testing();
