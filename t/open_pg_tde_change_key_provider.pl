use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

use JSON;

command_like([ 'open_pg_tde_change_key_provider', '--help' ],
	qr/Usage:/, 'displays help');

command_like(
	[ 'open_pg_tde_change_key_provider', '--version' ],
	qr/open_pg_tde_change_key_provider \(PostgreSQL\) /,
	'displays version');

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->append_conf('postgresql.conf', q{shared_preload_libraries = 'open_pg_tde'});
$node->start;

$node->safe_psql('postgres', q{CREATE EXTENSION open_pg_tde});
$node->safe_psql('postgres',
	q{SELECT open_pg_tde_add_global_key_provider_file('global-provider', '/tmp/open_pg_tde_change_key_provider-global')}
);
$node->safe_psql('postgres',
	q{SELECT open_pg_tde_add_database_key_provider_file('database-provider', '/tmp/open_pg_tde_change_key_provider-database')}
);
my $db_oid = $node->safe_psql('postgres',
	q{SELECT oid FROM pg_catalog.pg_database WHERE datname = 'postgres'});
my $options;

my $token_file = "${PostgreSQL::Test::Utils::tmp_check}/openbao_token";
append_to_file($token_file, 'DUMMY');

$node->stop;

command_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		$db_oid,
		'database-provider',
		'file',
		'/tmp/open_pg_tde_change_key_provider-database-2',
	],
	qr/Key provider updated successfully!/,
	'updates key provider to file type');

$node->start;

is( $node->safe_psql(
		'postgres',
		q{SELECT type FROM open_pg_tde_list_all_database_key_providers() WHERE name = 'database-provider'}
	),
	'file',
	'provider type is set to file');

$options = decode_json(
	$node->safe_psql(
		'postgres',
		q{SELECT options FROM open_pg_tde_list_all_database_key_providers() WHERE name = 'database-provider'}
	));
is( $options->{path},
	'/tmp/open_pg_tde_change_key_provider-database-2',
	'path is set correctly for file provider');

$node->stop;

command_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		$db_oid,
		'database-provider',
		'openbao',
		'https://openbao-server.example:8200/',
		'mount-path',
		$token_file,
		'/tmp/ca_path',
	],
	qr/Key provider updated successfully!/,
	'updates key provider to openbao type');

$node->start;

is( $node->safe_psql(
		'postgres',
		q{SELECT type FROM open_pg_tde_list_all_database_key_providers() WHERE name = 'database-provider'}
	),
	'openbao',
	'provider type is set to openbao');

$options = decode_json(
	$node->safe_psql(
		'postgres',
		q{SELECT options FROM open_pg_tde_list_all_database_key_providers() WHERE name = 'database-provider'}
	));
is($options->{url}, 'https://openbao-server.example:8200/',
	'url is set correctly for openbao provider');
is($options->{mountPath}, 'mount-path',
	'mount path is set correctly for openbao provider');
is($options->{tokenPath}, $token_file,
	'tokenPath is set correctly for openbao provider');
is($options->{caPath}, '/tmp/ca_path',
	'CA path is set correctly for openbao provider');

$node->stop;

command_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		$db_oid,
		'database-provider',
		'kmip',
		'kmip-server.example',
		'12345',
		'/tmp/cert_path',
		'/tmp/key_path',
		'/tmp/ca_path',
	],
	qr/Key provider updated successfully!/,
	'updates key provider to kmip type');

$node->start;

is( $node->safe_psql(
		'postgres',
		q{SELECT type FROM open_pg_tde_list_all_database_key_providers() WHERE name = 'database-provider'}
	),
	'kmip',
	'provider type is set to kmip');

$options = decode_json(
	$node->safe_psql(
		'postgres',
		q{SELECT options FROM open_pg_tde_list_all_database_key_providers() WHERE name = 'database-provider'}
	));
is($options->{host}, 'kmip-server.example',
	'host is set correctly for kmip provider');
is($options->{port}, '12345', 'port is set correctly for kmip provider');
is($options->{certPath}, '/tmp/cert_path',
	'client cert path is set correctly for kmip provider');
is($options->{keyPath}, '/tmp/key_path',
	'client cert key path is set correctly for kmip provider');
is($options->{caPath}, '/tmp/ca_path',
	'CA path is set correctly for kmip provider');

$node->stop;

command_fails_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => '/non/existing/path',
		'1664',
		'global-provider',
		'file',
		'/tmp/file',
	],
	qr{open_pg_tde_change_key_provider: error: could not open file "/non/existing/path/global/pg_control" for reading: No such file or directory},
	'gives error on incorrect data dir');

$node->start;
command_fails_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		'1664',
		'global-provider',
		'file',
		'/tmp/file',
	],
	qr/open_pg_tde_change_key_provider: error: cluster must be shut down/,
	'gives error on if cluster is running');
$node->stop;

command_fails_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		'12345678',
		'global-provider',
		'file',
		'/tmp/file',
	],
	qr/error: could not open tde file "[^"]+": No such file or directory/,
	'gives error on unknown database oid');

command_fails_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		'1664',
		'incorrect-global-provider',
		'file',
		'/tmp/file',
	],
	qr/error: provder "incorrect-global-provider" not found for database 1664/,
	'gives error on unknown key provider');

command_fails_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		'1664',
		'global-provider',
		'incorrect-provider-type',
	],
	qr/error: unknown provider type "incorrect-provider-type"/,
	'gives error on unknown provider type');

command_fails_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		'1664',
		'global-provider',
		'file',
	],
	qr/error: wrong number of arguments for "file"/,
	'gives error on missing arguments for file provider');

command_fails_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		'1664',
		'global-provider',
		'kmip',
	],
	qr/error: wrong number of arguments for "kmip"/,
	'gives error on missing arguments for kmip provider');

command_fails_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		'1664',
		'global-provider',
		'openbao',
	],
	qr/error: wrong number of arguments for "openbao"/,
	'gives error on missing arguments for openbao provider');

# A provider parameter longer than the JSON buffer must be rejected cleanly
# rather than overflowing the fixed-size stack buffer in build_json().
command_fails_like(
	[
		'open_pg_tde_change_key_provider',
		'-D' => $node->data_dir,
		'1664',
		'global-provider',
		'file',
		'A' x 5000,
	],
	qr/configuration too long/,
	'rejects an over-long provider parameter without overflowing');

done_testing();
