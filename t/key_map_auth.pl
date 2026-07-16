# Verifies that key_base_iv in the key map file is authenticated (M2).
#
# key_base_iv is the per-relation IV/tweak base for the data files. In the v5
# on-disk format it was stored outside the AEAD additional authenticated data,
# so an actor with write access to the key file could change it undetected,
# silently shifting every block IV of the relation. In v6 it is part of the AAD,
# so tampering with it fails decryption of the relation key on read.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->append_conf('postgresql.conf',
	"shared_preload_libraries = 'open_pg_tde'");
$node->start;

my $keydir = PostgreSQL::Test::Utils::tempdir;
$node->safe_psql(
	'postgres', qq{
	CREATE EXTENSION open_pg_tde;
	SELECT open_pg_tde_add_database_key_provider_file('kp', '$keydir/db.keys');
	SELECT open_pg_tde_create_key_using_database_key_provider('k', 'kp');
	SELECT open_pg_tde_set_key_using_database_key_provider('k', 'kp');
	CREATE TABLE secret(id int) USING tde_heap;
	INSERT INTO secret VALUES (1), (2), (3);
	CHECKPOINT;
});

is($node->safe_psql('postgres', 'SELECT count(*) FROM secret'),
	'3', 'encrypted table reads before tampering');

my $dboid = $node->safe_psql('postgres',
	q{SELECT oid FROM pg_database WHERE datname = 'postgres'});
my $relnode =
  $node->safe_psql('postgres', q{SELECT pg_relation_filenode('secret')});

$node->stop;

# Locate the map entry for 'secret' and flip one byte of its key_base_iv.
#
# v6 TDEMapEntry layout: cipher(4) spcOid(4) relNumber(4) type(4)
# key_base_iv(16) entry_iv(16) aead_tag(16) encrypted_key_data(64). We find the
# entry by its relNumber (a uint32 at entry offset 8) rather than assuming a
# fixed header size, then corrupt a byte inside key_base_iv at entry offset 16.
my $mapfile = $node->data_dir . "/open_pg_tde/${dboid}_keys";
open(my $rfh, '<:raw', $mapfile) or die "open $mapfile for read: $!";
local $/;
my $data = <$rfh>;
close $rfh;

my $pos = index($data, pack('L<', $relnode));
die "map entry for relfilenode $relnode not found in $mapfile" if $pos < 0;
my $kbi_off = ($pos - 8) + 16;
substr($data, $kbi_off, 1) =
  chr(ord(substr($data, $kbi_off, 1)) ^ 0xFF);

open(my $wfh, '>:raw', $mapfile) or die "open $mapfile for write: $!";
print $wfh $data;
close $wfh;

$node->start;

my ($rc, $stdout, $stderr) =
  $node->psql('postgres', 'SELECT count(*) FROM secret');
isnt($rc, 0, 'read fails after key_base_iv is tampered with');
like(
	$stderr,
	qr/corrupted key file|failed to decrypt key|incorrect principal key/i,
	'tampering with key_base_iv is detected (key_base_iv is authenticated)');

$node->stop;

done_testing();
