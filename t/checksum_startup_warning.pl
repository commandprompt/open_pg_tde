# Startup warning when neither data checksums nor wal_log_hints is enabled.
#
# open_pg_tde encrypts a whole page as one unit, so hint-bit updates must be
# WAL-logged for torn-page safety. On load it warns if neither data checksums
# nor wal_log_hints is enabled. This checks the warning fires when both are off
# and is silent when either is on.
use strict;
use warnings FATAL => 'all';
use pgtde;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $warning = qr/neither data checksums nor wal_log_hints is enabled/;

# PostgreSQL 18 enables data checksums by default, so disabling them needs an
# explicit flag; earlier versions default to off.
my $pg_version = `pg_config --version`;
my @no_checksums =
	($pg_version =~ /PostgreSQL (\d+)/ && $1 >= 18)
  ? ('--no-data-checksums')
  : ();

sub log_of
{
	my ($node) = @_;
	return slurp_file($node->logfile);
}

# Neither enabled: warning expected.
my $unsafe = PostgreSQL::Test::Cluster->new('unsafe');
$unsafe->init(extra => [@no_checksums]);
$unsafe->append_conf('postgresql.conf',
	"shared_preload_libraries = 'open_pg_tde'");
$unsafe->start;
is($unsafe->safe_psql('postgres', 'SHOW data_checksums'),
	'off', 'unsafe node has data checksums off');
like(log_of($unsafe), $warning,
	'warning is emitted when neither checksums nor wal_log_hints is enabled');
$unsafe->stop;

# Data checksums on: no warning.
my $checksums = PostgreSQL::Test::Cluster->new('checksums');
$checksums->init(extra => ['--data-checksums']);
$checksums->append_conf('postgresql.conf',
	"shared_preload_libraries = 'open_pg_tde'");
$checksums->start;
unlike(log_of($checksums), $warning,
	'no warning when data checksums are enabled');
$checksums->stop;

# wal_log_hints on (no checksums): no warning.
my $hints = PostgreSQL::Test::Cluster->new('hints');
$hints->init(extra => [@no_checksums]);
$hints->append_conf('postgresql.conf',
	"shared_preload_libraries = 'open_pg_tde'");
$hints->append_conf('postgresql.conf', 'wal_log_hints = on');
$hints->start;
unlike(log_of($hints), $warning, 'no warning when wal_log_hints is enabled');
$hints->stop;

done_testing();
