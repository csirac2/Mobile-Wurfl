# vim:filetype=perl
use strict;
use warnings;
use Test::More qw( no_plan );
use FindBin qw( $Bin );
use Data::Dumper;
use File::Path;
use DBD::SQLite;
use DBI;
use Git::Repository();
use File::Temp();
use File::Spec();

use lib 'lib';

my $create_sql = <<EOF;
DROP TABLE IF EXISTS capability;
CREATE TABLE capability (
        name char(255) NOT NULL default '',
        value char(255) default '',
        groupid char(255) NOT NULL default '',
        deviceid char(255) NOT NULL default '',
        ts DATETIME default CURRENT_TIMESTAMP
        );
CREATE INDEX IF NOT EXISTS groupid ON capability (groupid);
CREATE INDEX IF NOT EXISTS name_deviceid ON capability (name,deviceid);
DROP TABLE IF EXISTS device;
CREATE TABLE device (
        user_agent varchar(255) NOT NULL default '',
        actual_device_root char(255),
        id char(255) NOT NULL default '',
        fall_back char(255) NOT NULL default '',
        ts DATETIME default CURRENT_TIMESTAMP
        );
CREATE INDEX IF NOT EXISTS user_agent ON device (user_agent);
CREATE INDEX IF NOT EXISTS id ON device (id);
EOF

my $long_user_agent = {
    string => "Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; InfoPath.2; Creative ZENcast v2.01.01)",
    canonical => "Mozilla/4.0",
};

# WURFL data has a restrictive license these days. The last free version was
# released on 2011-04-24 and contains the following license text:
#
# All the information listed here has been collected by many different people
# from many different countries. You are allowed to use WURFL in any of your
# applications, free or commercial. The only thing required is to make public
# any modification to this file, following the original spirit and idea of the
# creators of this project.
my $USE_FREE_WURFL = defined $ENV{USE_FREE_WURFL} ? $ENV{USE_FREE_WURFL} : 1;

$| = 1;
ok ( require Mobile::Wurfl, "require Mobile::Wurfl" ); 
my $wurfl = eval {
    my %opts = (
        wurfl_home => "/tmp/",
        db_descriptor => "dbi:SQLite:dbname=/tmp/wurfl.db",
        db_username => '',
        db_password => '',
        # verbose => 2,
    );
    if ($USE_FREE_WURFL) {
        $opts{wurfl_url} = get_free_wurfl_file();
    }
    Mobile::Wurfl->new(%opts);
};

ok( $wurfl && ! $@, "create Mobile::Wurfl object: $@" );
exit unless $wurfl;
eval { $wurfl->create_tables( $create_sql ) };
ok( ! $@ , "create db tables: $@" );
SKIP: {
    skip('USE_FREE_WURFL is true, so we can\'t test get_wurfl() or update()',
        5) if $USE_FREE_WURFL;

    my $updated = eval { $wurfl->update(); };
    ok( ! $@ , "update: $@" );
    ok( $updated, "updated" );
    ok( ! $wurfl->update(), "no update if not required" );
    ok( ! $wurfl->rebuild_tables(), "no rebuild_tables if not required" );
    ok( ! $wurfl->get_wurfl(), "no get_wurfl if not required" );
}
my @groups = sort $wurfl->groups();
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
$cua = $wurfl->canonical_ua( $long_user_agent->{string} );
is( $long_user_agent->{canonical}, $cua, "canonical_ua deep recursion" );
my $deviceid = $wurfl->deviceid( $device->{user_agent} );
is( $device->{id}, $deviceid, "deviceid ua lookup" );
for my $cap ( @capabilities )
{
    my $val = $wurfl->lookup( $ua, $cap );
    ok( defined $val, "lookup $cap" );
}

# Sadly, the only place hosting this last freely licensed version of the WURFL
# xml is a github repo. And it's too big for github to serve raw, so we must
# clone it to somewhere where we can get at it.
sub get_free_wurfl_file {
    my $xml_fname = '2011-04-24-wurfl.xml';
    my $xml_path;

    if ( -e $xml_fname ) {
        print "Using existing '$xml_fname'...\n";
        $xml_path = $xml_fname;
    }
    else {
        my $git_url = 'git://github.com/bdelacretaz/wurfl';
        my $git_dir = File::Temp->tempdir('wurfl_git_repo_XXXX');

        print <<"HERE";
'$xml_fname' not found - trying to git-clone it from
'$git_url' into '$git_dir'
HERE
        $xml_path = File::Spec->catfile($git_dir, $xml_fname);
        Git::Repository->run( clone => $git_url, $git_dir );
    }
    print "Full path to '$xml_fname' is '$xml_path'\n";

    return $xml_path;
}

eval { $wurfl->cleanup() };
ok( ! $@ , "cleanup: $@" );
