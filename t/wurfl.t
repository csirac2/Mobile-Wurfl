# vim:filetype=perl
use strict;
use warnings;
use Test::More qw( no_plan );
use FindBin qw( $Bin );
use File::Path();
use DBD::SQLite();
use DBI();
use Git::Repository();
use File::Temp();
use File::Spec();
use File::Copy();
use File::Basename();
use Benchmark();

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
CREATE INDEX IF NOT EXISTS user_agent_idx
        ON device (user_agent COLLATE NOCASE);
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
        #verbose => 2,
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

my @capabilities_list = (
    qw(brand_name model_name),                                # product_info
    qw(resolution_height resolution_width max_image_width),   # display
    qw(xhtml_ui xhtml_make_phone_call_string xhtml_send_sms_string),
);                                                            # xhtml_ui

my %error_once; # :(
sub device_capabilities {
    my ($ua, $annotation, $test_wurfl) = @_;
    my $canon_ua = $test_wurfl->canonical_ua($ua);
    my %results;

    foreach my $cap ( @capabilities_list ) {
        if (my $value = eval { $test_wurfl->lookup_value( $canon_ua, $cap ) }) {
            $results{$cap} = $value;
        }
        else {
            my $c_ua = $canon_ua || '';
            my $msg = "('$c_ua', '$cap') for $annotation";
            if (!exists $error_once{$msg} ) {
                print "#   Error doing lookup_value$msg\n";
                $error_once{$msg} = 1;
            }
        }
    }

    return \%results;
}

sub get_new_wurfl {
    my ($method) = @_;

    return Mobile::Wurfl->new(
        canonical_ua_default_method => $method,
        map { $_ => $wurfl->{$_} } (qw(wurfl_url wurfl_home),
           qw(db_descriptor db_username db_password verbose))
    );
}

sub device_capabilities_timing_tests {
    my ($ua, $annotation, $count) = @_;
    my $canon_ua = $wurfl->canonical_ua($ua);
    my $method1 = 'canonical_ua_incremental';
    my $wurfl1 = get_new_wurfl($method1);
    my $method2 = 'canonical_ua_binary';
    my $wurfl2 = get_new_wurfl($method2);

    $count ||= 100;
    ok(defined $canon_ua && length($canon_ua),
        "got a canonical ua for $annotation");
    print "#   canonical_ua: '$canon_ua'\n" if $canon_ua;
    my $results = Benchmark::timethese($count,
        {
            $method1 =>
                sub { device_capabilities($ua, $annotation, $wurfl1) },
            $method2 =>
                sub { device_capabilities($ua, $annotation, $wurfl2) },
        }
    );
    Benchmark::cmpthese($results);

    return;
}

# A short UA string, caught in the wild.
device_capabilities_timing_tests(
    'LG-KU970/v1.0',
    'LG-KU970',
);

# A common UA string, caught in the wild.
device_capabilities_timing_tests(
    'Mozilla/5.0 (Linux; U; Android 2.3.6; en-au; GT-S5830 Build/GINGERBREAD) AppleWebKit/533.1 (KHTML, like Gecko) Version/4.0 Mobile Safari/533.1',
    'GT-S5830',
);

# A rare UA string, caught in the wild.
device_capabilities_timing_tests(
    'Nokia3600slide/2.0 (05.64) Profile/MIDP-2.1 Configuration/CLDC-1.1 Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; Trident/4.0; SLCC2;.NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; InfoPath.2) UCBrowser8.2.1.144/70/355',
    'Nokia3600',
);

# Something insanely long, caught in the wild.
device_capabilities_timing_tests(
    'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; Trident/4.0; IWSS31:kNxp0whxzXqOQeKEfLa9Dzomf6vmX0Vq; IWSS31:kNxp0whxzXrMsytr+3nreBUjAcoilEhv; IWSS31:kNxp0whxzXq9Yn89BPspI8n8uJeXo30N; IWSS31:kNxp0whxzXppnE8wMnS/y+IgSvp/xQLI; IWSS31:kNxp0whxzXqHk2fHml6j10FMEDAbRkZH; IWSS31:kNxp0whxzXqwyrd6rIIWW87VIpe2YCAR; IWSS31:kNxp0whxzXq3K61YtnoDTh4ncPAzABTj; IWSS31:kNxp0whxzXrb5J+ea4IJKoXHG6CHtzIB; IWSS31:kNxp0whxzXp5BuQjzicqs570XUtQlm1U; IWSS31:kNxp0whxzXo4pdsFP6i9/7yHHzzRSwNT; IWSS31:kNxp0whxzXr3OzKUyXkxluL2v/YTYr3q; IWSS31:kNxp0whxzXoUpmDisiNbvRaRgk+wML6X; IWSS31:kNxp0whxzXqEu+IYeyTXVryHNWWEcZPH; IWSS31:kNxp0whxzXrmOx44r+PnfKIA0KjEb16h; IWSS31:kNxp0whxzXpcHUYOGoW59qZdtZ9ReiI5; IWSS31:kNxp0whxzXphh5THSJRywyu1GFxpTH0j; IWSS31:kNxp0whxzXrHjv2xUoq1rYnAVgXyHBxY; IWSS31:kNxp0whxzXoD9LfEWA7KSUhGlxzEgvzb; IWSS31:kNxp0whxzXqRK0oSw4mwiweZjLwrlc4s; IWSS31:kNxp0whxzXrk/z/mAYlZoAQ+WeAIq8hj; IWSS31:kNxp0whxzXoEt20VLIDPPw616ILSt+17; IWSS31:kNxp0whxzXqADuwJ04Dy0CqgjdiiMaZX; IWSS31:kNxp0whxzXpSC1UYVdIbIo/XgsVJsJxI; IWSS31:kNxp0whxzXrHK7ss0CpvaremQg+VL+fk; IWSS31:kNxp0whxzXpp3Mn12NbaahzWpL9XnOQT; IWSS31:kNxp0whxzXpiPhxMKV4wPOtl4Fm+As/Z; IWSS31:kNxp0whxzXqHI7BkwHE3PfuWMlKpEsgS; IWSS31:kNxp0whxzXoTsh4jwz0tB5fWINw92ZjC; IWSS31:kNxp0whxzXpHkI1nWDvV9CcwNS+HBA6d; IWSS31:kNxp0whxzXqfLcmoyZTs8Vel+XI7f7vJ; IWSS31:kNxp0whxzXp8vT8XEiyFGCmDqpyijzaH; IWSS31:kNxp0whxzXpyDsPH/XqNfFW5J0xFh+VB; IWSS31:kNxp0whxzXqSO6/4hM9c1TWZrSNvjait; IWSS31:kNxp0whxzXr/NPn6CMMtq+3kEUr57hdU; IWSS31:kNxp0whxzXpraLb1f3d28p0g2k6BhLhK; IWSS31:kNxp0whxzXr+q93Ux/zDaxHRU4LK73JL; IWSS31:kNxp0whxzXqTcxW9/RWRmPAkBJYrwZYS; IWSS31:kNxp0whxzXqPjezIBb0BEjCRNjGdUm8P; IWSS31:kNxp0whxzXrGNqQCa/TqLRdZeWPaZhY3; IWSS31:kNxp0whxzXr/b2VHfs1HL/10nMG5LxEC; IWSS31:kNxp0whxzXqayqVDwmzFzPtTZo2mUYsW; IWSS31:kNxp0whxzXo5aLesMEgawL5gWaFidOyQ; IWSS31:kNxp0whxzXrQdLbMJba88+f3MlYbPciV; IWSS31:kNxp0whxzXqPX8xDFnriPHr/9trm/Wxi; IWSS31:kNxp0whxzXpRjqg2/RiRpIW8Hl+o+8o6; IWSS31:kNxp0whxzXqSW56X5Vr/Czj4tibm20Zf; IWSS31:kNxp0whxzXrMFiz365LcholBrXLQmWAo; IWSS31:kNxp0whxzXp//qoxBDWPTol/BoSKvj1G; IWSS31:kNxp0whxzXoJlfRVj3gg0Znec1AyYemn; IWSS31:kNxp0whxzXqkpsX77fUDpwqhrnW3WHs/; IWSS31:kNxp0whxzXo0GiJCfSTTAf19Dm06LeLg; IWSS31:kNxp0whxzXrkPqlmuk5lBaqaFAin845B; IWSS31:kNxp0whxzXpadh7261yB6lUl10zkbGN+; IWSS31:kNxp0whxzXoq1KgrM48jehE5yVO5Dt2I; IWSS31:kNxp0whxzXrKPQ2mdpSR0igXmEZI5BET; IWSS31:kNxp0whxzXqmG95oBvpGV6ShVZZ6yV/7; IWSS31:kNxp0whxzXoNhcMqnOTmuWOfMPixwANE; IWSS31:kNxp0whxzXqwvjtOzkgac5UrRVxKcDz6; IWSS31:kNxp0whxzXpiBuNGuC++bvNFaFaH0MKk; IWSS31:kNxp0whxzXr/IXbo81cl2SGf2Tc1ienv; IWSS31:kNxp0whxzXrV3XxmgQLjiy4fjUpd+JMC; IWSS31:kNxp0whxzXoDkKYWVJgpji0zR1FGkFu1; IWSS31:kNxp0whxzXqb4VitOhdo/BvoIBRjXUOa; IWSS31:kNxp0whxzXovlxk6GWDYke1t4RNP6ERd; IWSS31:kNxp0whxzXohniJ1k+vIHbbLVslruRwt; IWSS31:kNxp0whxzXqSyOo+4DaMJkiZgSJZ3/WY; IWSS31:kNxp0whxzXpZBTrkagfFczu5HGJQQSHl; IWSS31:kNxp0whxzXqff769N5K4B+IndWLQadca; IWSS31:kNxp0whxzXonXVTbNtReBtPZYoBUtDyk; IWSS31:kNxp0whxzXrdTynddCidh0a4U6Sx/0Yl; IWSS31:kNxp0whxzXpSLnN3Qv4YeW3EUwsNtLPu; IWSS31:kNxp0whxzXoKeyAGgLxVQdD60wcU8+l8; IWSS31:kNxp0whxzXpkVURkanQ7pavSFZOzWAis; IWSS31:kNxp0whxzXoFSEAu5CVtBChrWa+V809E; IWSS31:kNxp0whxzXpi18Bt3zsm+q1/SF1TNrE0; IWSS31:kNxp0whxzXree6KJZnC8nufqJseaZRY/; IWSS31:kNxp0whxzXonADTXjm9rbHjuXZ4VXxyx; IWSS31:kNxp0whxzXokoNngJje31zoaUp3OuikA; IWSS31:kNxp0whxzXq3BhpYlaWagIfd4pkYLWXP; IWSS31:kNxp0whxzXrodrmrnOo3TwIqxpxTAjpP; IWSS31:kNxp0whxzXoYuM2cEni6Mqp3vkkaFP0x; IWSS31:kNxp0whxzXr5qVr2FFriC/jdnbxpFJoO; IWSS31:kNxp0whxzXp/+54SNTAw3aqxoIa8s8Or; IWSS31:kNxp0whxzXqHmdgyWCcoxm2lIL2R3CuM; IWSS31:kNxp0whxzXrfLJA4rGYgDVeP5RCuqlGD; IWSS31:kNxp0whxzXqifSkW5Rts+4oa4uWH6PTA; IWSS31:kNxp0whxzXqCzxnacSjlvE04Rzll01b5; IWSS31:kNxp0whxzXqbY93o9jYe3B8196CwwE3V; IWSS31:kNxp0whxzXpogDHWqUiZQsV4lNjF5baL; IWSS31:kNxp0whxzXr7IBtqoodfVCHuhgY8rvEm; IWSS31:kNxp0whxzXo9KycksIZrsjKUxAy+Xksa; IWSS31:kNxp0whxzXpe74P89JSjQm2qD/18Hl1Q; IWSS31:kNxp0whxzXqnZjXpXKp9VTLORHHHi3I3; IWSS31:kNxp0whxzXqwEpoEhJZQUEC1ky0bc1qC; IWSS31:kNxp0whxzXpzXDHCKGFfbXcvR4Yl+8AB; IWSS31:kNxp0whxzXpKnsR4DTCCTvBluIAs1DBF; IWSS31:kNxp0whxzXqdhVlMT9BuecjF11bThF+9; IWSS31:kNxp0whxzXpYD2VPwwylGsjSi2Ay7bqr; IWSS31:kNxp0whxzXrfqbzJ0KWp5OSympaOVibc; IWSS31:kNxp0whxzXrBnha7+8PGQEVA0uDy0rwi; IWSS31:kNxp0whxzXofUB67qkviZ2Z8cedT8Lm2; IWSS31:kNxp0whxzXpUKSN4SRWweuXakH/VU4x+; IWSS31:kNxp0whxzXpcKYEygOQM3bqU+bDdx9tW; IWSS31:kNxp0whxzXp7JDNWXBQFBNhEgWRa3OLu; IWSS31:kNxp0whxzXpG1C5l26qo6ll8YFTrZy3/; IWSS31:kNxp0whxzXo0beCdVe6Iof1/2V8+tuNN; IWSS31:kNxp0whxzXocrIDkFMlhtIFA5RDChg3v; IWSS31:kNxp0whxzXrNuVnqM7Nh66uquZ+8Snd5; IWSS31:kNxp0whxzXo9WkXhyku04vRGcBVJRHvH; IWSS31:kNxp0whxzXqUS22F/BMho8aXRId/ILuw; IWSS31:kNxp0whxzXrQhAnG9nYyS0DfST1z2EDD; IWSS31:kNxp0whxzXrSypUscCQsIA6SEo8QpvPz; IWSS31:kNxp0whxzXoq3InS2fk5K9TT69DoBQnj; IWSS31:kNxp0whxzXpNNgTbIcWcZ66iRYd316Sg; IWSS31:kNxp0whxzXo/VjP3o/HKj1hUVl/T6n++; IWSS31:kNxp0whxzXoexdYWCjz5gQ3OLeOW3CP7; IWSS31:kNxp0whxzXobQyDOv4VDoKrSFnobyNbs; IWSS31:kNxp0whxzXpccGZNBe/PAea0Gei14KPL; IWSS31:kNxp0whxzXo7u1TGQL0m6l9oiXwE7Xc3; IWSS31:kNxp0whxzXqHl3rZLJQYbdhs7blvLAXt; IWSS31:kNxp0whxzXrWTWjLZudBf5yGthq9a0Zl; IWSS31:kNxp0whxzXqJB3xabexUDr9Kt15Tbfdh; IWSS31:kNxp0whxzXqNVjs1ljd4LKJDhQcauWcA; IWSS31:kNxp0whxzXpOoG2dh5EfxE1zIqQiSSX9; IWSS31:kNxp0whxzXq9nDZLIwnwIFqVm2HIG8/Y; IWSS31:kNxp0whxzXriVL6jq0DNWXPx5GihGWnY; IWSS31:kNxp0whxzXo4rnbknzNsTCO4lMFnVZns; IWSS31:kNxp0whxzXqxUi29wyPtyof1g7I07oEq; IWSS31:kNxp0whxzXqazl3F6eYt9/mgGKsibYhY; IWSS31:kNxp0whxzXr14skOGPgyGLFudyQL9SPf; IWSS31:kNxp0whxzXrahBznoLMXVyG5TGNaM691; IWSS31:kNxp0whxzXr/ofb2XUJGnZLeL224I0bT; IWSS31:kNxp0whxzXqvG2akQcl74wuH/ZxuQ1lV; IWSS31:kNxp0whxzXrm6rA8k/kVm0lkiIto2a/n; IWSS31:kNxp0whxzXpmGU+mEapKbewBKp7VwxC2; IWSS31:kNxp0whxzXp0vzq3BPHOvjpva12HkAb9; IWSS31:kNxp0whxzXoV6b66jhFc+MPgL27VT/nj; IWSS31:kNxp0whxzXqqhkS6sKVfy2x1MRV+IsUa; IWSS31:kNxp0whxzXrGYzygpvIauke5BBr7zAuq; IWSS31:kNxp0whxzXrumqNVbEnOXHrlSyUV4nG5; IWSS31:kNxp0whxzXoMEyjgff86ohAcRxd4gLQJ; IWSS31:kNxp0whxzXptClSTR4Fu7z7ljiPdIQ69; IWSS31:kNxp0whxzXqowzSNsgPuipImkQbHmjTF; IWSS31:kNxp0whxzXpSHzY+qjPMw/j0NRmS/eP9; IWSS31:kNxp0whxzXpqoc0BZAti80wo4Zxw8Un7; IWSS31:kNxp0whxzXoxf4ES1PIb7vowhzzeOCx3; IWSS31:kNxp0whxzXo89xpUMDd/j/b0bSbbk/NK; IWSS31:kNxp0whxzXqe4b/ZiWANxvFSITMRXf4z; IWSS31:kNxp0whxzXrrU4bqKrummkXTXTqhslcR; IWSS31:kNxp0whxzXprf2joj+dmrkhuXw+mM8D6; IWSS31:kNxp0whxzXr/7AdCt4LL+gXPYNfP63hu; IWSS31:kNxp0whxzXq1rUvBZje8sX8lpDYbU9IN; IWSS31:kNxp0whxzXpfcX5JLwL5lRmResNNoeMb; IWSS31:kNxp0whxzXogDNprzz7DLcmyq8s4O8Ug; IWSS31:kNxp0whxzXqOt5FzzDCN9tr0ZTFfBC/M; IWSS31:kNxp0whxzXrxKCHjctELekxIc3q4tyz6; IWSS31:kNxp0whxzXos++kvTfPZfER1s6p38d5J; IWSS31:kNxp0whxzXqC1wGZg3CGu024SzY/egQx; IWSS31:kNxp0whxzXqkKuNSM02D2i528BWTLXVH; IWSS31:kNxp0whxzXrA5j3iSii4Kle/aewALhwe; IWSS31:kNxp0whxzXoQnINthaRuSAHTMsbWSoK7; IWSS31:kNxp0whxzXpaqnbtwjp5aDe1y45IRr0V; IWSS31:kNxp0whxzXpPzmAEb/7DAwPwi2ti5mX7; IWSS31:kNxp0whxzXpA+qe9cfVSlBzcPfrwgss8; IWSS31:kNxp0whxzXpuslkM9recpnp3dKTz9OVO; IWSS31:kNxp0whxzXr0XthJ/0puySyBlLv7bA6P; IWSS31:kNxp0whxzXrkGfRT9UvGt/ZJIG8MvQYp; IWSS31:kNxp0whxzXrOiCPx5skdhbDGakn0mS9p; IWSS31:kNxp0whxzXrkKAtGLkG+4ALGhxWqBsts; IWSS31:kNxp0whxzXojgrunE213BaJQogPiYRG/; IWSS31:kNxp0whxzXoON/Cc56oz6PB2BA6WeyYB; IWSS31:kNxp0whxzXrS07vosyzp1RVE849mIzt5; IWSS31:kNxp0whxzXo4MC++g7kfQJ3uE2ak6RED; IWSS31:kNxp0whxzXolnrp/mk2/iTzTl8va6MZf; IWSS31:kNxp0whxzXqE3aLJEMpNy0DZu8ItS0hW; IWSS31:kNxp0whxzXpTWTy4La7Q+Kqckhbn7xHw; IWSS31:kNxp0whxzXrop4GRSi6yKUY9QqsxHe4X; IWSS31:kNxp0whxzXoFvvTzytCXHi8yZ9psQPZC; IWSS31:kNxp0whxzXqGEkIq732h8WKKFU96V35s; IWSS31:kNxp0whxzXqLGzSDWLJX5iJHcHqafSmU; IWSS31:kNxp0whxzXpEAC5R/BQnpNGnaVwfPRzu; IWSS31:kNxp0whxzXpNtOoDZUH1MHqz+lIkF1TH; IWSS31:kNxp0whxzXr4boB0w54Xujh3nGIb9Nc6; IWSS31:kNxp0whxzXoGeTF9ScNy+3b8KcW+Kq0I; IWSS31:kNxp0whxzXpDrtcZoXHSAT7PZl5e08qN; IWSS31:kNxp0whxzXrp0Xqm4m/7aYAXI0iZ79+K; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; CMDTDF; InfoPath.2)',
    'uberlong_ua_string',
);

ok( eval { $wurfl->cleanup(); 1; }, "cleanup");
print '#   cleanup error: ' . $@ if ($@);
