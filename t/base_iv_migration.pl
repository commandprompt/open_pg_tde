# Migration of the key map format from version 5 to version 6.
#
# Version 6 moves key_base_iv into the AEAD additional authenticated data so it
# is authenticated (previously it was stored after the tag and unauthenticated).
# This starts a cluster from a preexisting version-5 data directory and checks
# that the key map migrates on startup and the encrypted table created under
# version 5 remains readable, exercising the version-5 migration reader.
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
	plan skip_all => 'PostgreSQL 18 required for the version-5 fixture';
}

my $node = PostgreSQL::Test::Cluster->new('main');
my $host = $node->host;
my $port = $node->port;
my $data_dir = $node->data_dir;

mkdir $data_dir or die "could not create $data_dir: $!";
system_or_bail('tar', 'xf', 't/base_iv_v5_datadir.tar.gz', '-C', $data_dir);
chmod(0700, $data_dir) or die "could not chmod $data_dir: $!";

$node->append_conf('postgresql.conf', "unix_socket_directories = '$host'");
$node->append_conf('postgresql.conf', "listen_addresses = ''");
$node->append_conf('postgresql.conf', "port = '$port'");

$node->start;

my ($result, $stdout, undef) = $node->psql(
	'postgres',
	'SELECT payload FROM test_v5 ORDER BY id',
	extra_params => [ '-q', '-A', '-t', '--no-psqlrc', '-U', 'tde_fixture' ]);

is($result, 0, 'query the migrated version-5 table succeeds');
is($stdout, "v5-alpha\nv5-bravo",
	'encrypted table created under version 5 is readable after migration');

$stdout = $node->safe_psql(
	'postgres',
	"SELECT open_pg_tde_is_encrypted('test_v5')",
	extra_params => [ '-U', 'tde_fixture' ]);
is($stdout, 't', 'migrated table is still encrypted');

$node->stop;
done_testing();
