# vim:filetype=perl
use strict;
use warnings;
use Test::More qw( no_plan );
use FindBin qw( $Bin );
use Data::Dumper;
use File::Path;
use lib 'lib';

my $groups = [ sort qw(
    sms
    drm
    bugs
    streaming
    display
    j2me
    wml_ui
    markup
    sound_format
    product_info
    wta
    image_format
    xhtml_ui
    chtml_ui
    wap_push
    object_download
    security
    storage
    mms
    cache
) ];

$| = 1;
my $wurfl;
my %db = (
    database => "wurfl",
    username => "wurfl",
    password => "wurfl",
    cleanup => "no",
);
print STDERR "\n\nMobile::Wurfl requires a mysql database to install. You will be prompted for a database name, a username, and a password for this (the username must have CREATE permimssions on the database). The test process will create two tables (called 'device', and 'capability') in this database. Optionally, both tables created can be dropped at the end of the tests, if the 'cleanup' option is set to 'yes'\n";
for ( qw( database username password cleanup ) )
{
    print STDERR "$_ ($db{$_}): ";
    my $ans = <>;
    chomp $ans;
    $db{$_} = $ans || $db{$_};
}
require_ok( 'Mobile::Wurfl' );
$wurfl = eval { Mobile::Wurfl->new( 
    db_descriptor => "DBI:mysql:database=$db{database}", 
    db_username => $db{username},
    db_password => $db{password},
); };
ok( $wurfl && ! $@, "create Mobile::Wurfl object: $@" );
exit unless $wurfl;
if ( $db{cleanup} eq 'yes' )
{
    eval { $wurfl->cleanup() };
    ok( ! $@ , "cleanup: $@" );
}
eval { $wurfl->create_tables() };
ok( ! $@ , "create db tables: $@" );
my $updated = eval { $wurfl->update(); };
ok( ! $@ , "update: $@" );
if ( $db{cleanup} eq 'yes' )
{
    ok( $updated, "updated" );
}
ok( ! $wurfl->update(), "no update if not required" );
ok( ! $wurfl->rebuild_tables(), "no rebuild_tables if not required" );
ok( ! $wurfl->get_wurfl(), "no get_wurfl if not required" );
my @groups = sort $wurfl->groups();
# is_deeply( \@groups, $groups, "group list" );
my %capabilities;
for my $group ( @groups )
{
    for ( $wurfl->capabilities( $group ) )
    {
        $capabilities{$_}++;
    }
}
my @capabilities = $wurfl->capabilities();
is_deeply( [ sort @capabilities ], [ sort keys %capabilities ], "capabilities list" );
my @devices = $wurfl->devices();
my $device = $devices[int(rand(@devices))];
my $ua = $wurfl->canonical_ua( $device->{user_agent} );
is( $device->{user_agent}, $ua, "ua lookup" );
my $cua = $wurfl->canonical_ua( "$device->{user_agent}/ random stuff ..." );
is( $device->{user_agent}, $cua, "canonical ua lookup" );
my $deviceid = $wurfl->deviceid( $device->{user_agent} );
is( $device->{id}, $deviceid, "deviceid ua lookup" );
for my $cap ( @capabilities )
{
    my $val = $wurfl->lookup( $ua, $cap );
    ok( defined $val, "lookup $cap" );
}
if ( $db{cleanup} eq 'yes' )
{
    eval { $wurfl->cleanup() };
    ok( ! $@ , "cleanup: $@" );
}
