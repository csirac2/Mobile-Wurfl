# vim:filetype=perl
use strict;
use warnings;
use Test::More qw( no_plan );
use FindBin qw( $Bin );
use File::Path;
use DBD::SQLite;
use DBI;
use Git::Repository();
use File::Temp();
use File::Spec();
use File::Copy();
use File::Basename();

use lib 'lib';

my $t_path = File::Basename::dirname(__FILE__); # Figure out where t/ lives
my $wurfl_home = File::Temp::tempdir('wurfl_home_XXXX', CLEANUP => 1);
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
my $WURFL_URL;

$| = 1;
ok ( require Mobile::Wurfl, "require Mobile::Wurfl" ); 
my $wurfl = eval {
    my %opts = (
        wurfl_home => $wurfl_home,
        db_descriptor => "dbi:SQLite:dbname=" .
            File::Spec->catfile($wurfl_home, 'wurfl.db'),
        db_username => '',
        db_password => '',
        # verbose => 2,
    );
    if ( defined $ENV{WURFL_URL} ) {
        $WURFL_URL = $ENV{WURFL_URL};
    }
    else {
        $WURFL_URL = get_free_wurfl_file();
        ok( ($WURFL_URL && -e $WURFL_URL),
            "WURFL_URL is not set, so try to clone something from github"
        );
    }
    $opts{wurfl_url} = $WURFL_URL;
    Mobile::Wurfl->new(%opts);
};

ok( $wurfl && ! $@, "create Mobile::Wurfl object: $@" );
exit unless $wurfl;
eval { $wurfl->create_tables( $create_sql ) };
ok( ! $@ , "create db tables: $@" );
SKIP: {
    if ( defined $ENV{WURFL_URL} ) {
        print "# WURFL_URL is set to '$WURFL_URL'\n";
    }
    else {
        ok( $wurfl->rebuild_tables(),
            "rebuild_tables because WURFL_URL was not set"
        );
        skip("WURFL_URL not set, so we can't test get_wurfl() or update()", 5);
    }

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
is( $ua, $device->{user_agent}, "ua lookup" );
my $cua = $wurfl->canonical_ua( "$device->{user_agent}/ random stuff ..." );
is( $cua, $device->{user_agent}, "canonical ua lookup" );
$cua = $wurfl->canonical_ua( $long_user_agent->{string} );
is( $cua, $long_user_agent->{canonical}, "canonical_ua deep recursion" );
my $deviceid = $wurfl->deviceid( $device->{user_agent} );
is( $deviceid, $device->{id}, "deviceid ua lookup" );
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
    my $xml_path_from_t = File::Spec->catfile($t_path, $xml_fname);

    if ( -e $xml_path_from_t ) {
        $xml_path = File::Spec->catfile($wurfl_home, $xml_fname);
        print "#   Copying existing '$xml_path_from_t' into '$wurfl_home'...\n";
        File::Copy::copy($xml_path_from_t, $xml_path) or die $!;
    }
    else {
        my $git_url = 'git://github.com/bdelacretaz/wurfl';

        # Git::Repository clones into parent dir unless there's a trailing slash
        my $git_dir = File::Spec->catdir($wurfl_home,
            'github.com-bdelacretaz-wurfl', ''
        );
        my $xml_git_path = File::Spec->catfile($git_dir, $xml_fname);
        $xml_path = File::Spec->catfile($wurfl_home, $xml_fname);

        print <<"HERE";
#   '$xml_path_from_t' not found - trying to git-clone it from
#   '$git_url' into '$git_dir'
HERE
        Git::Repository->run( clone => $git_url, $git_dir );
        print "# Copying '$xml_git_path' into '$wurfl_home'...\n";
        File::Copy::copy($xml_git_path, $xml_path) or die $!;
    }
    print "#   Full path to '$xml_fname' is '$xml_path'\n";

    return $xml_path;
}

ok( eval { $wurfl->cleanup(); 1; }, "cleanup");
print '#   cleanup error: ' . $@ if ($@);
