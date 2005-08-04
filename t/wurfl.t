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
    # verbose => 1,
);
warn "\ntrying mysql version ...\n";
my $wurfl = eval { Mobile::Wurfl->new( ); };
if ( $@ )
{
    warn "\nfailed ($@) ... trying CSV version ...\n";
    $wurfl ||= eval { Mobile::Wurfl->new( %opts ); };
    warn $@ if $@;
    ok( ! $@ , "create Mobile::Wurfl object" );
}
unless ( -e "$csv_dir/device" )
{
    eval { $wurfl->create_tables( join( '', <DATA> ) ); };
    warn $@ if $@;
    ok( ! $@ , "create db tables" );
}
my $updated = eval { $wurfl->update(); };
warn $@ if $@;
ok( ! $@, "update" );
if ( ! $updated )
{
    ok( ! $wurfl->update(), "no update if not required" );
}
my @groups = $wurfl->groups();
is_deeply( \@groups, $groups, "group list" );
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
my $ua = "SonyEricssonZ600/foo/bar/foo bar/1.2.3.4";
my $cua = $wurfl->canonical_ua( $ua );
is( $cua, "SonyEricssonZ600", "canonical ua" );
my $deviceid = $wurfl->deviceid( $cua );
is( $deviceid, "sonyericsson_z600_ver1", "deviceid" );
my $device = $wurfl->device( $deviceid );
is( $device->{id}, "sonyericsson_z600_ver1", "device" );
my $max_image_width = $wurfl->lookup_value( $cua, "max_image_width" );
ok( defined $max_image_width, "lookup_value returns defined value" );
is( $max_image_width, 128, "lookup_value is correct" );
my $row = $wurfl->lookup( $cua, "max_image_width" );
is( $row->{name}, "max_image_width", "test lookup (name)" );
is( $row->{value}, $max_image_width, "test lookup (value)" );
is( $row->{deviceid}, $deviceid, "test lookup (deviceid)" );
is( $row->{groupid}, "display", "test lookup (groop)" );
$row = $wurfl->lookup( $cua, "video" );
is( $row->{deviceid}, "generic", "fallback to generic" );
$row = $wurfl->lookup( $cua, "video", no_fall_back => 1 );
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
