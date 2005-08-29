# vim:filetype=perl
use strict;
use warnings;
use Test::More qw( no_plan );
use FindBin qw( $Bin );
use DBD::CSV;
use Data::Dumper;
use File::Path;

my $groups = [ qw(
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

my $verbose = 1;
BEGIN { use_ok( 'Mobile::Wurfl' ); }
require_ok( 'Mobile::Wurfl' );
my $wurfl_home = "$Bin/..";
my $csv_dir = "$wurfl_home/csv";
unless ( -e $csv_dir )
{
    ok( mkpath( $csv_dir ), "make csv dir" );
}
my %opts = (
    wurfl_home => $wurfl_home,
    db_descriptor => "DBI:CSV:f_dir=$csv_dir",
    verbose => $verbose,
);
print STDERR "\ntrying mysql version ... ";
my $wurfl = eval { Mobile::Wurfl->new( verbose => $verbose ); };
if ( $@ )
{
    print STDERR "\nfailed ($@) ... trying CSV version ... ";
    $wurfl ||= eval { Mobile::Wurfl->new( %opts ); };
    print STDERR $@ if $@;
    print STDERR "\ncreate tables ... ";
    ok( ! $@ , "create Mobile::Wurfl object" );
    {
        eval { $wurfl->create_tables( join( '', <DATA> ) ); };
        print STDERR $@ if $@;
        ok( ! $@ , "create db tables" );
    }
}
print STDERR "\nupdate ... ";
my $updated = eval { $wurfl->update(); };
print STDERR $@ if $@;
ok( ! $@, "update" );
ok( ! $wurfl->update(), "no update if not required" );
print STDERR "\ngroups ... ";
my @groups = $wurfl->groups();
is_deeply( \@groups, $groups, "group list" );
my %capabilities;
print STDERR "\ncapabilities ... ";
for my $group ( @groups )
{
    for ( $wurfl->capabilities( $group ) )
    {
        $capabilities{$_}++;
    }
}
my @capabilities = $wurfl->capabilities();
is_deeply( [ sort @capabilities ], [ sort keys %capabilities ], "capabilities list" );
print STDERR "\ncanonical_ua ... ";
my %ua = (
    "SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1.1" => { cua => "SonyEricssonK750i", deviceid => "sonyericsson_k750i_ver1" },
    "SonyEricssonT637/R101 Profile/MIDP-1.0 Configuration/CLDC-1.0 UP.Link/5.1.2.9" => { cua => 'SonyEricssonT637/R101 Profile/MIDP-1.0 Configuration/CLDC-1.0', deviceid => 'sonyericsson_t637_ver1_subr101' },
);
my $cua;
for my $ua ( keys %ua )
{
    $cua = $wurfl->canonical_ua( $ua );
    is( $cua, $ua{$ua}{cua}, "canonical ua" );
    my $deviceid = $wurfl->deviceid( $cua );
    is( $deviceid, $ua{$ua}{deviceid}, "deviceid" );
    my $device = $wurfl->device( $deviceid );
    is( $device->{id}, $ua{$ua}{deviceid}, "device" );
}
print STDERR "\nlookups ... ";
$cua = $wurfl->canonical_ua( "SonyEricssonK750i" );
my $deviceid = $wurfl->deviceid( $cua );
my $resolution_width = $wurfl->lookup_value( $cua, "resolution_width" );
ok( defined $resolution_width, "lookup_value returns defined value" );
is( $resolution_width, 176, "lookup_value is correct" );
my $row = $wurfl->lookup( $cua, "resolution_width" );
is( $row->{name}, "resolution_width", "test lookup (name)" );
is( $row->{value}, $resolution_width, "test lookup (value)" );
is( $row->{deviceid}, $deviceid, "test lookup (deviceid)" );
is( $row->{groupid}, "display", "test lookup (group)" );
my $ua = "SonyEricssonZ600";
$row = $wurfl->lookup( $ua, "video" );
is( $row->{deviceid}, "generic", "fallback to generic" );
$row = $wurfl->lookup( $ua, "video", no_fall_back => 1 );
is( $row->{deviceid}, undef, "no fallback" );

__DATA__

CREATE TABLE capability (
  name char(100),
  value char(100),
  groupid char(100),
  deviceid char(100)
);
CREATE TABLE device (
  user_agent char(100),
  actual_device_root char(100),
  id char(100),
  fall_back char(100)
);
