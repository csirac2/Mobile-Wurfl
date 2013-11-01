package Mobile::Wurfl::UpdateScript;
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Pod::Find qw(pod_where);
use FindBin;
use lib "$FindBin::Bin/../lib";
use DBI();
use File::Spec();
use File::Copy();
use Mobile::Wurfl();
use Mobile::Wurfl::UpdateScript;

my %getopts_translation = (
    url      => 'wurfl_url',
    home     => 'wurfl_home',
    dsn      => 'db_descriptor',
    username => 'db_username',
    password => 'db_password',
    verbose  => 'verbose',
);

%getopts_translation =
  map { $_ => $getopts_translation{$_}, $getopts_translation{$_} => $_ }
  keys %getopts_translation;

sub init {
    my ( $self, $opts, $ARGV ) = @_;
    my %getopts;
    local @ARGV = @{$ARGV};

    # We used to use GetOptionsFromArray, but that's not exported in
    # Getopt::Long v2.35 shipped with perl 5.8.8 on Centos 5.0 (long story)...
    GetOptions(
        \%getopts,    'url|u=s',    'home|h=s',   'dsn|d=s',
        'username=s', 'password=s', 'verbose|v+', 'help|?',
        'man',
      )
      or pod2usage(
        -verbose => 2,
        -input   => pod_where( { -inc => 1 }, __PACKAGE__ )
      );
    pod2usage(
        -verbose => 1,
        -input   => pod_where( { -inc => 1 }, __PACKAGE__ )
    ) if $getopts{help};
    pod2usage(
        -exitval => 0,
        -verbose => 2,
        -input   => pod_where( { -inc => 1 }, __PACKAGE__ )
    ) if $getopts{man};
    foreach my $getopt_key ( keys %getopts ) {
        $opts->{ $getopts_translation{$getopt_key} } = $getopts{$getopt_key};
    }

    return;
}

# ENV variables understood by this script:
my %ENVmap = (
    WURFL_URL  => 'wurfl_url',      # URL to wurfl data .xml. May be a file path
    WURFL_HOME => 'wurfl_home',     # work dir; defaults to File::Temp::tempdir
    WURFL_DSN  => 'db_descriptor',  # DBI->connect DSN string
    WURFL_DB_USER => 'db_username', # Username for above
    WURFL_DB_PASS => 'db_password', # Password for above
);

sub new_wurfl {
    my ( $self, $opts ) = @_;
    my %required = ( WURFL_HOME => 1, WURFL_DSN => 1, );

    foreach my $env_key ( keys %ENVmap ) {
        my $wurfl_key   = $ENVmap{$env_key};
        my $getopts_key = $getopts_translation{$wurfl_key};

        if ( defined $ENV{$env_key} && !defined $opts->{$wurfl_key} ) {
            $opts->{$wurfl_key} = $ENV{$env_key};
        }
        if ( $required{$env_key} && !$opts->{$wurfl_key} ) {
            print "Missing required option: --$getopts_key\n\n";
            pod2usage(
                -exitval => 0,
                -input   => pod_where( { -inc => 1 }, __PACKAGE__ )
            );
        }
    }
    if ( !defined $ENV{WURFL_URL} ) {
        $opts->{wurfl_url} = $self->get_free_wurfl_file($opts);
    }
    if ( $opts->{verbose} ) {
        $opts->{verbose} = 2;
    }

    return Mobile::Wurfl->new( %{$opts} );
}

sub proc_xml {
    my ( $self, $wurfl ) = @_;

    # Skip unless we have a WURFL_URL that looks like a url://
    print "#   WURFL_URL: $ENV{WURFL_URL}\n" if defined $ENV{WURFL_URL};
    if ( !defined $ENV{WURFL_URL} || $ENV{WURFL_URL} !~ /^[a-z]+:\/\//i ) {
        if ( defined $ENV{WURFL_URL} ) {
            my ($wurfl_fname) = File::Basename::fileparse( $ENV{WURFL_URL} );
            my $wurfl_path =
              File::Spec->catfile( $wurfl->{wurfl_home}, $wurfl_fname );

            print "#   Copying '$wurfl->{wurfl_url}' to '$wurfl_path'...\n";
            File::Copy::copy( $wurfl->{wurfl_url}, $wurfl_path ) or die $!;
        }
        print "Rebuilding tables...\n";
        $wurfl->rebuild_tables();
    }
    else {
        print "Updating...\n";
        $wurfl->update();
    }
}

# Sadly, the only place hosting this last freely licensed version of the WURFL
# xml is a github repo. And it's too big for github to serve raw, so we must
# clone it to somewhere where we can get at it.
sub get_free_wurfl_file {
    my ( $self, $opts ) = @_;
    my $wurfl_home = $opts->{wurfl_home};
    my $xml_fname  = '2011-04-24-wurfl.xml';
    my $xml_path   = File::Spec->catfile( $wurfl_home, $xml_fname );

    if ( !-e $xml_path ) {
        my $git_url = 'git://github.com/bdelacretaz/wurfl';

        # Git::Repository clones into parent dir unless there's a trailing slash
        my $git_dir =
          File::Spec->catdir( $wurfl_home, 'github.com-bdelacretaz-wurfl', '' );
        my $xml_giscript_path = File::Spec->catfile( $git_dir, $xml_fname );

        print <<"HERE";
#   '$xml_path' not found - trying to git-clone it from
#   '$git_url' into '$git_dir'
HERE
        if ( !eval { require Git::Repository } ) {
            die
"Git::Repository missing, needed to clone wurfl XML from github. Try to obtain manually, then set WURFL_URL=/path/to/wurfl.xml";
        }
        Git::Repository->run( clone => $git_url, $git_dir );
        print "#   Copying '$xml_giscript_path' into '$wurfl_home'...\n";
        File::Copy::copy( $xml_giscript_path, $xml_path ) or die $!;
    }
    print "#   Full path to '$xml_fname' is '$xml_path'\n";

    return $xml_path;
}

sub run {
    my ( $class, $opts, $ARGV ) = @_;
    my $wurfl;

    $class->init( $opts, $ARGV );
    $wurfl = $class->new_wurfl($opts);
    print "Creating tables...\n";
    $wurfl->create_tables();

    return $class->proc_xml($wurfl);
}

1;

__END__
=head1 NAME
 update_wurfl.pl - update a wurfl database

=head1 SYNOPSIS

 update_wurfl.pl --home=/tmp --dsn=DBI:SQLite;dbname=/tmp/foo.db

 OPTIONS
   --home     REQUIRED wurfl_home    working dir
   --url      REQUIRED wurfl_url     to wurfl XML data. May be a filename
   --dsn      REQUIRED db_descriptor DB connection as understood by DBI
   --username db_username            for the db_descriptor connection
   --password db_password            for the db_descriptor connection
   --help     brief help message
   --man      full documentation

=head2 USING ENV VARIABLES

MySQL example:
 WURFL_DB_USER=wurfl WURFL_DB_PASS=wurfl WURFL_DSN=DBI:mysql;host=localhost:database=wurfl update_wurfl.pl

SQLite example:
 WURFL_DSN='DBI:SQLite;dbname=/tmp/wurfl.sqlite.db' update_wurfl.pl

PostgreSQL example:
 WURFL_DB_USER=wurfl WURFL_DB_PASS=wurfl WURFL_DSN='DBI:Pg;host=localhost;database=wurfl' update_wurfl.pl

=head1 DESCRIPTION
B<update_wurfl.pl> populates a database from XML data for use with Mobile::Wurfl

=cut
