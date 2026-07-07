# open_pg_tde.require_fips startup enforcement.
#
# When require_fips is on, open_pg_tde verifies at startup that OpenSSL is in
# FIPS mode and raises a fatal error otherwise. This checks that a non-FIPS
# build refuses to start with require_fips on, and starts normally with it off.
#
# The refuse-to-start assertion assumes the OpenSSL used by the test build is
# not in FIPS mode, which is the case for a standard CI or developer
# environment. On a FIPS-configured host the server would instead start.
use strict;
use warnings FATAL => 'all';
use pgtde;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# require_fips off (the default): the server starts and reports the value.
my $off = PostgreSQL::Test::Cluster->new('fips_off');
$off->init;
$off->append_conf('postgresql.conf',
	"shared_preload_libraries = 'open_pg_tde'");
$off->start;
is($off->safe_psql('postgres', 'SHOW open_pg_tde.require_fips'),
	'off', 'require_fips defaults to off and the server starts');
$off->stop;

# require_fips on without a FIPS OpenSSL: the server refuses to start.
my $on = PostgreSQL::Test::Cluster->new('fips_required');
$on->init;
$on->append_conf('postgresql.conf',
	"shared_preload_libraries = 'open_pg_tde'");
$on->append_conf('postgresql.conf', 'open_pg_tde.require_fips = on');

my $started = eval { $on->start(fail_ok => 1); };
ok(!$started,
	'server refuses to start with require_fips on and no FIPS OpenSSL');

my $log = slurp_file($on->logfile);
like(
	$log,
	qr/require_fips is set but OpenSSL is not in FIPS mode/,
	'a clear fatal error explains why startup was refused');

done_testing();
