# Migration of the WAL key file format from version 2 to version 3.
#
# Version 3 moves key_base_iv into the AEAD additional authenticated data so it
# is authenticated (in version 2 it was stored after the tag and
# unauthenticated). This starts a cluster from a preexisting version-2 data
# directory with WAL encryption enabled and checks that the WAL key file
# migrates on startup: the version-2 WAL key is decrypted with the old AAD and
# re-wrapped as version 3. A failure of the version-2 reader would abort startup
# with a decryption error, so a clean start already exercises the reader; we
# also confirm the on-disk file is version 3 afterwards and the cluster is
# usable.
#
# The fixture uses a relative keyring path so it is self-contained: the file
# provider's keyring lives inside the data directory and is resolved against it
# after extraction.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# The fixture was generated on PostgreSQL 18.
my $pg_version = `pg_config --version`;
if ($pg_version !~ /PostgreSQL 18/)
{
	plan skip_all => 'PostgreSQL 18 required for the version-2 fixture';
}

my $node = PostgreSQL::Test::Cluster->new('main');
my $host = $node->host;
my $port = $node->port;
my $data_dir = $node->data_dir;

mkdir $data_dir or die "could not create $data_dir: $!";
system_or_bail('tar', 'xf', 't/wal_keys_v2_datadir.tar.gz', '-C', $data_dir);
chmod(0700, $data_dir) or die "could not chmod $data_dir: $!";

$node->append_conf('postgresql.conf', "unix_socket_directories = '$host'");
$node->append_conf('postgresql.conf', "listen_addresses = ''");
$node->append_conf('postgresql.conf', "port = '$port'");

# The WAL key file is version 2 before we start.
my $wal_key_file = "$data_dir/open_pg_tde/wal_keys";
is(wal_key_file_version($wal_key_file),
	2, 'fixture WAL key file is version 2');

# Starting the cluster runs the version-2 -> version-3 migration. If the
# version-2 reader used the wrong AAD the WAL key would not decrypt and startup
# would fail here.
$node->start;

is(wal_key_file_version($wal_key_file),
	3, 'WAL key file is version 3 after migration');

# WAL encryption is still enabled and the migrated key is usable.
is( $node->safe_psql(
		'postgres',
		'SHOW open_pg_tde.wal_encrypt;',
		extra_params => [ '-U', 'tde_fixture' ]),
	'on',
	'WAL encryption is still enabled after migration');

is( $node->safe_psql(
		'postgres',
		'SELECT note FROM wal_probe ORDER BY id',
		extra_params => [ '-U', 'tde_fixture' ]),
	"v2-wal-alpha\nv2-wal-bravo",
	'data written under version 2 is readable after migration');

# A new WAL-generating workload works with the migrated (version-3) key.
$node->safe_psql(
	'postgres',
	'INSERT INTO wal_probe VALUES (3, $$v3-wal-charlie$$); CHECKPOINT;',
	extra_params => [ '-U', 'tde_fixture' ]);
is( $node->safe_psql(
		'postgres',
		'SELECT count(*) FROM wal_probe',
		extra_params => [ '-U', 'tde_fixture' ]),
	'3',
	'new rows can be written after migration');

$node->stop;

done_testing();

# Read the numeric version from the little-endian file magic in the header.
sub wal_key_file_version
{
	my ($path) = @_;
	open(my $fh, '<:raw', $path) or die "open $path: $!";
	read($fh, my $buf, 4) == 4 or die "short read on $path";
	close $fh;
	my $magic = unpack('L<', $buf);
	return ($magic & 0xF000000) >> 24;
}
