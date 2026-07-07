# Migration of the key map format from version 4 to version 5.
#
# AES-256-XTS needs a 64-byte internal key, which enlarged the on-disk key map
# entry and bumped the file version from 4 to 5. This starts a cluster from a
# preexisting version-4 data directory (created by the previous release) and
# checks that the key map migrates on startup and the encrypted table created
# under version 4 remains readable.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# The fixture was generated on PostgreSQL 18.
my $pg_version = `pg_config --version`;
if ($pg_version !~ /PostgreSQL 18/)
{
	plan skip_all => 'PostgreSQL 18 required for the version-4 fixture';
}

my $node = PostgreSQL::Test::Cluster->new('main');
my $host = $node->host;
my $port = $node->port;
my $data_dir = $node->data_dir;

mkdir $data_dir or die "could not create $data_dir: $!";
system_or_bail('tar', 'xf', 't/aes256xts_v4_datadir.tar.gz', '-C', $data_dir);
chmod(0700, $data_dir) or die "could not chmod $data_dir: $!";

$node->append_conf('postgresql.conf', "unix_socket_directories = '$host'");
$node->append_conf('postgresql.conf', "listen_addresses = ''");
$node->append_conf('postgresql.conf', "port = '$port'");

$node->start;

my ($result, $stdout, undef) = $node->psql(
	'postgres',
	'SELECT payload FROM test_v4 ORDER BY id',
	extra_params => [ '-q', '-A', '-t', '--no-psqlrc', '-U', 'vagrant' ]);

is($result, 0, 'query the migrated version-4 table succeeds');
is($stdout, "v4-alpha\nv4-bravo",
	'encrypted table created under version 4 is readable after migration');

$stdout = $node->safe_psql(
	'postgres',
	"SELECT open_pg_tde_is_encrypted('test_v4')",
	extra_params => [ '-U', 'vagrant' ]);
is($stdout, 't', 'migrated table is still encrypted');

$node->stop;
done_testing();
