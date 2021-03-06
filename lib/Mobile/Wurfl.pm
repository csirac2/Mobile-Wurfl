package Mobile::Wurfl;

$VERSION = '2.00';

use strict;
use warnings;
use DBI;
use XML::Parser;
use LWP::UserAgent();
use Date::Parse;
use File::Spec;
use File::Basename;
use IO::Uncompress::Unzip qw(unzip $UnzipError);;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use File::Temp();
use POSIX;

my %tables = (
    device => [ qw( id actual_device_root user_agent fall_back ) ],
    capability => [ qw( groupid name value deviceid ) ],
);

sub log_debug {
    my ( $self, $msg ) = @_;

    if ( $self->{verbose} ) {
        if ( $self->{verbose} == 1 ) {
            print $self->{log_fh}( $msg || $self ) . "\n";
        }
        else {
            print STDERR ( $msg || $self ) . "\n";
        }
    }

    return;
}

sub new
{
    my $class = shift;
    my %opts = (
        db_descriptor => 'DBI:SQLite:dbname=$wurfl_home/wurfl.sqlite.db',
        db_username => 'wurfl',
        db_password => 'wurfl',
        device_table_name => 'device',
        capability_table_name => 'capability',
        verbose => 0,
        canonical_ua_method => 'canonical_ua_incremental',
        @_
    );
    if ( !defined $opts{wurfl_home} ) {
        $opts{wurfl_home} =
          File::Temp->newdir( 'wurfl_home_XXXX', CLEANUP => 1 );
    }

    my $self = bless \%opts, $class;
    if ( !$self->can( $self->{canonical_ua_method} ) ) {
        die 'Don\'t know how to \$self->'
          . ( $self->{canonical_ua_method} || '?' );
    }

    if ( $self->{verbose} == 1 && !$self->{log_fh} ) {
        open( $self->{log_fh}, '>',
            File::Spec->catfile( $self->{wurfl_home}, 'wurfl.log' ) );
    }
    $self->{db_descriptor} =~ s/\$wurfl_home\b/$self->{wurfl_home}/g;
    $self->log_debug("connecting to $self->{db_descriptor} as $self->{db_username}");
    $self->{dbh} ||= DBI->connect( 
        $self->{db_descriptor},
        $self->{db_username},
        $self->{db_password},
        { RaiseError => 1 }
    ) or die "Cannot connect to $self->{db_descriptor}: " . $DBI::errstr;
    die "no wurfl_url\n" unless $self->{wurfl_url};

    #get a filename from the URL and remove .zip or .gzip suffix
    my $name = (fileparse($self->{wurfl_url}, '.zip', '.gzip'))[0];
    $self->{wurfl_file} = "$self->{wurfl_home}/$name";

    $self->{ua} = LWP::UserAgent->new;
    return $self;
}


sub _tables_exist
{
    my $self = shift;
    my %db_tables = map { my $key = $_ =~ /(.*)\.(.*)/ ? $2 : $_ ; $key => 1 } $self->{dbh}->tables();
    for my $table ( keys %tables )
    {
        my $quoted_table = $self->{dbh}->quote_identifier($table);

        return 0 unless $db_tables{$table} or $db_tables{$quoted_table};

    }
    return 1;
}

sub _init
{
    my $self = shift;
    return if $self->{initialised};
    if ( ! $self->_tables_exist() )
    {
        die "tables don't exist on $self->{db_descriptor}: try running $self->create_tables()\n";
    }

    $self->{last_update_sth} = $self->{dbh}->prepare( 
        "SELECT ts FROM $self->{device_table_name} ORDER BY ts DESC LIMIT 1"
    );
    $self->{user_agents_sth} = $self->{dbh}->prepare( 
        "SELECT DISTINCT user_agent FROM $self->{device_table_name}" 
    );
    $self->{devices_sth} = $self->{dbh}->prepare( 
        "SELECT * FROM $self->{device_table_name}" 
    );
    $self->{device_sth} = $self->{dbh}->prepare( 
        "SELECT * FROM $self->{device_table_name} WHERE id = ?"
    );
    $self->{deviceid_sth} = $self->{dbh}->prepare( 
        "SELECT id FROM $self->{device_table_name} WHERE user_agent = ?"
    );
    $self->{deviceid_like_sth} = $self->{dbh}->prepare( 
        "SELECT id,user_agent FROM $self->{device_table_name} WHERE user_agent LIKE ?"
    );
    $self->{deviceid_like_count_sth} = $self->{dbh}->prepare( 
        "SELECT COUNT(*) FROM $self->{device_table_name} WHERE user_agent LIKE ?"
    );
    $self->{lookup_sth} = $self->{dbh}->prepare(
        "SELECT * FROM $self->{capability_table_name} WHERE name = ? AND deviceid = ?"
    );
    $self->{fall_back_sth} = $self->{dbh}->prepare(
        "SELECT fall_back FROM $self->{device_table_name} WHERE id = ?"
    );
    $self->{groups_sth} = $self->{dbh}->prepare(
        "SELECT DISTINCT groupid FROM $self->{capability_table_name}"
    );
    $self->{group_capabilities_sth} = $self->{dbh}->prepare(
        "SELECT DISTINCT name FROM $self->{capability_table_name} WHERE groupid = ?"
    );
    $self->{capabilities_sth} = $self->{dbh}->prepare(
        "SELECT DISTINCT name FROM $self->{capability_table_name}"
    );
    for my $table ( keys %tables )
    {
	next if $self->{$table}{sth};
        my @fields = @{$tables{$table}};
        my $fields = join( ",", @fields );
        my $placeholders = join( ",", map "?", @fields );
        my $sql = "INSERT INTO $table ( $fields ) VALUES ( $placeholders ) ";
        $self->{$table}{sth} = $self->{dbh}->prepare( $sql );
    }
    $self->{initialised} = 1;
}

sub set
{
    my $self = shift;
    my $opt = shift;
    my $val = shift;

    die "unknown option $opt\n" unless exists $self->{$opt};
    return $self->{$opt} = $val;
}

sub get
{
    my $self = shift;
    my $opt = shift;

    die "unknown option $opt\n" unless exists $self->{$opt};
    return $self->{$opt};
}

sub _mangle_sql_names {
    my ( $self, $sql ) = @_;
    my %replace = (
        device     => $self->{device_table_name},
        capability => $self->{capability_table_name},
    );
    my @list;

    foreach my $token ( keys %replace ) {
        if ( $token ne $self->{ $token . '_table_name' } ) {
            push( @list, $token );
        }
    }
    if ( scalar(@list) ) {
        my $search_tokens = '\b' . join( '\b|\b', @list ) . '\b';

       #$sql =~ s/($search_tokens)/print "$1 -> $replace{$1}"; $replace{$1};/ge;
        $sql =~ s/($search_tokens)/$replace{$1};/gem;
    }

    return $sql;
}

sub create_tables
{
    my $self = shift;
    my $sql = shift;
    unless ( $sql )
    {
        require Mobile::Wurfl::SQL;
        my ( undef, $driver ) = DBI->parse_dsn( $self->{db_descriptor} );
        $sql = Mobile::Wurfl::SQL->get($driver);
        $sql = $self->_mangle_sql_names($sql);
    }
    for my $statement ( split( /\s*;\s*/, $sql ) )
    {
        next unless $statement =~ /\S/;
        $self->{dbh}->do( $statement ) or die "$statement failed\n";
    }
}

sub touch( $$ ) 
{ 
    my $path = shift;
    my $time = shift;
    die "no path" unless $path;
    die "no time" unless $time;
    log_debug("touch $path ($time)");
    return utime( $time, $time, $path );
}

sub last_update
{
    my $self = shift;
    $self->_init();
    $self->{last_update_sth}->execute();
    my ( $ts ) = str2time($self->{last_update_sth}->fetchrow());
    $ts ||= 0;
    $self->log_debug("last update: $ts");
    return $ts;
}

sub rebuild_tables
{
    my $self = shift;

    my $local = ($self->get_local_stats())[1];
    my $last_update = $self->last_update();
    if ( $last_update && $local <= $last_update )
    {
        $self->log_debug("$self->{wurfl_file} has not changed since the last database update");
        return 0;
    }
    $self->log_debug("$self->{wurfl_file} is newer than the last database update");
    $self->log_debug("flush dB tables ...");
    $self->{dbh}->begin_work;
    $self->{dbh}->do( "DELETE FROM $self->{device_table_name}" );
    $self->{dbh}->do( "DELETE FROM $self->{capability_table_name}" );
    my ( $device_id, $group_id );
    $self->log_debug("create XML parser ...");
    my $xp = new XML::Parser(
        Style => "Object",
        Handlers => {
            Start => sub { 
                my ( $expat, $element, %attrs ) = @_;
                if ( $element eq 'group' )
                {
                    my %group = %attrs;
                    $group_id = $group{id};
                }
                if ( $element eq 'device' )
                {
                    my %device = %attrs;
                    my @keys = @{$tables{device}};
                    my @values = @device{@keys};
                    $device_id = $device{id};
                    $self->{device}{sth}->execute( @values );
                }
                if ( $element eq 'capability' )
                {
                    my %capability = %attrs;
                    my @keys = @{$tables{capability}};
                    $capability{deviceid} = $device_id;
                    $capability{groupid} = $group_id;
                    my @values = @capability{@keys};
                    $self->{capability}{sth}->execute( @values );
                }
            },
        }
    );
    $self->log_debug("parse XML ...");
    $xp->parsefile( $self->{wurfl_file} );
    $self->log_debug("commit dB ...");
    $self->{dbh}->commit;
    return 1;
}

sub update
{
    my $self = shift;
    $self->log_debug("get wurfl");
    my $got_wurfl = $self->get_wurfl();
    $self->log_debug("got wurfl: $got_wurfl");
    my $rebuilt ||= $self->rebuild_tables();
    $self->log_debug("rebuilt: $rebuilt");
    return $got_wurfl || $rebuilt;
}

sub get_local_stats
{
    my $self = shift;
    return ( 0, 0 ) unless -e $self->{wurfl_file};
    $self->log_debug("stat $self->{wurfl_file} ...");
    my @stat = ( stat $self->{wurfl_file} )[ 7,9 ];
    $self->log_debug("@stat");
    return @stat;
}

sub get_remote_stats
{
    my $self = shift;
    $self->log_debug("HEAD $self->{wurfl_url} ...");
    my $response = $self->{ua}->head( $self->{wurfl_url} );
    die $response->status_line unless $response->is_success;
    die "can't get content_length\n" unless $response->content_length;
    die "can't get last_modified\n" unless $response->last_modified;
    my @stat = ( $response->content_length, $response->last_modified );
    $self->log_debug("@stat");
    return @stat;
}

sub get_wurfl
{
    my $self = shift;
    my @local = $self->get_local_stats();
    my @remote = $self->get_remote_stats();
 
    if ( $local[1] == $remote[1] )
    {
        $self->log_debug("@local and @remote are the same");
        return 0;
    }
    $self->log_debug("@local and @remote are different");
    $self->log_debug("GET $self->{wurfl_url} -> $self->{wurfl_file} ...");

    #create a temp filename
    my $tempfile = "$self->{wurfl_home}/wurfl_$$";
    
    my $response = $self->{ua}->get( 
        $self->{wurfl_url},
        ':content_file' => $tempfile
    );
    die $response->status_line unless $response->is_success;
    if ($response->{_headers}->header('content-type') eq 'application/x-gzip') {
        gunzip($tempfile => $self->{wurfl_file}) || die "gunzip failed: $GunzipError\n";
        unlink($tempfile);
    } elsif ($response->{_headers}->header('content-type') eq 'application/zip') {
        unzip($tempfile => $self->{wurfl_file}) || die "unzip failed: $UnzipError\n";
        unlink($tempfile);
    } else {
        move($tempfile, $self->{wurfl_file});
    }
    touch( $self->{wurfl_file}, $remote[1] );
    return 1;
}

sub user_agents
{
    my $self = shift;
    $self->_init();
    $self->{user_agents_sth}->execute();
    return map $_->[0], @{$self->{user_agents_sth}->fetchall_arrayref()};
}

sub devices
{
    my $self = shift;
    $self->_init();
    $self->{devices_sth}->execute();
    return @{$self->{devices_sth}->fetchall_arrayref( {} )};
}

sub groups
{
    my $self = shift;
    $self->_init();
    $self->{groups_sth}->execute();
    return map $_->[0], @{$self->{groups_sth}->fetchall_arrayref()};
}

sub capabilities
{
    my $self = shift;
    my $group = shift;
    $self->_init();
    if ( $group )
    {
        $self->{group_capabilities_sth}->execute( $group );
        return map $_->[0], @{$self->{group_capabilities_sth}->fetchall_arrayref()};
    }
    $self->{capabilities_sth}->execute();
    return map $_->[0], @{$self->{capabilities_sth}->fetchall_arrayref()};
}

sub _lookup
{
    my $self = shift;
    my $deviceid = shift;
    my $name = shift;
    $self->_init();
    $self->{lookup_sth}->execute( $name, $deviceid );
    return $self->{lookup_sth}->fetchrow_hashref;
}

sub _fallback
{
    my $self = shift;
    my $deviceid = shift;
    my $name = shift;
    $self->_init();
    my $row = $self->_lookup( $deviceid, $name );
    return $row if $row && ( $row->{value} || $row->{deviceid} eq 'generic' );
    $self->{fall_back_sth}->execute( $deviceid );
    my $fallback = $self->{fall_back_sth}->fetchrow 
        || die "no fallback for $deviceid\n"
    ;
    if ( $fallback eq 'root' )
    {
        die "fellback all the way to root: this shouldn't happen\n";
    }
    return $self->_fallback( $fallback, $name );
}

sub canonical_ua {
    my ( $self, $ua ) = @_;
    my $method = $self->{canonical_ua_method};

    return $self->$method($ua);
}

sub canonical_ua_incremental {
    no warnings 'recursion';
    my $self = shift;
    my $ua   = shift;
    $self->_init();
    $self->{deviceid_sth}->execute($ua);
    my $deviceid = $self->{deviceid_sth}->fetchrow;
    if ($deviceid) {
        $self->log_debug("$ua found");
        return $ua;
    }
    $ua = substr( $ua, 0, -1 );

    # $ua =~ s/^(.+)\/(.*)$/$1\// ;
    unless ( length $ua ) {
        $self->log_debug("can't find canonical user agent");
        return;
    }
    return $self->canonical_ua_incremental($ua);
}

sub canonical_ua_binary {
    my ( $self, $ua ) = @_;
    my ($partial_ua) = $self->_canonical_ua_binary($ua);
    my $canon_ua;

    if (0) {
        my $partial_ua_matches;
        my $partial_ua_escaped = $partial_ua;

        $partial_ua_escaped =~ s/\%/\[\%\]/g;    # SQL-escape % chars
        $self->{deviceid_like_count_sth}->execute( $partial_ua_escaped . '%' );
        ($partial_ua_matches) = $self->{deviceid_like_count_sth}->fetchrow;
        $self->log_debug( "Delegating to canonical_ua_incremental...\n"
              . "partial_ua_matches: $partial_ua_matches, length(partial_ua): "
              . length($partial_ua) );
    }
    $canon_ua = $self->canonical_ua_incremental($partial_ua);
    $self->log_debug(
        "canon_in:   $ua\ncanon_part: $partial_ua\ncanon_out:  "
          . ( $canon_ua || '' ) );

    return $canon_ua;
}

sub _canonical_ua_binary {
    my ( $self, $ua ) = @_;
    my $ua_pos_min = 0;
    my $ua_pos_max = 2 * length($ua);
    my $maxhit_ua  = '';
    my $maxhit_deviceid;
    my $maxhit_deviceid_ua;

    $self->_init();
    while ( $ua_pos_min <= $ua_pos_max ) {
        my $ua_pos_mid = int( ( $ua_pos_min + $ua_pos_max ) / 2 );
        my $trial_ua = substr( $ua, 0, $ua_pos_mid );
        my $trial_ua_escaped = $trial_ua;
        my ( $deviceid, $deviceid_ua );

        $trial_ua_escaped =~ s/\%/\[\%\]/g;    # SQL-escape % chars
        $self->{deviceid_like_sth}->execute( $trial_ua_escaped . '%' );
        ( $deviceid, $deviceid_ua ) = $self->{deviceid_like_sth}->fetchrow;

        if ($deviceid) {
            $self->log_debug("binary search, hit:  $trial_ua");

       #$self->log_debug( "\t(deviceid: $deviceid, deviceid_ua: $deviceid_ua)");
            if ( length($trial_ua) > length($maxhit_ua) ) {
                $maxhit_ua          = $trial_ua;
                $maxhit_deviceid    = $deviceid;
                $maxhit_deviceid_ua = $deviceid_ua;
            }
            $ua_pos_min = $ua_pos_mid + 1;
        }
        else {
            $self->log_debug( 'binary search, miss: ' . ( $trial_ua || '' ) );
            $ua_pos_max = $ua_pos_mid - 1;
        }
    }
    if ( length $maxhit_ua ) {
        $self->log_debug("UA maximum hit: $maxhit_ua");
    }
    else {
        $self->log_debug("can't find canonical user agent");
    }

    return ( $maxhit_ua, $maxhit_deviceid, $maxhit_deviceid_ua );
}

sub device
{
    my $self = shift;
    my $deviceid = shift;
    $self->_init();
    $self->{device_sth}->execute( $deviceid );
    my $device = $self->{device_sth}->fetchrow_hashref;
    $self->log_debug("can't find device for user deviceid $deviceid") unless $device;
    return $device;
}

sub deviceid
{
    my $self = shift;
    my $ua = shift;
    $self->_init();
    $self->{deviceid_sth}->execute( $ua );
    my $deviceid = $self->{deviceid_sth}->fetchrow;
    $self->log_debug("can't find device id for user agent " . ($ua || '')) unless $deviceid;
    return $deviceid;
}

sub lookup
{
    my $self = shift;
    my $ua = shift;
    my $name = shift;
    $self->_init();
    my %opts = @_;
    my $deviceid = $self->deviceid( $ua );
    return unless $deviceid;
    return 
        $opts{no_fall_back} ? 
            $self->_lookup( $deviceid, $name )
        : 
            $self->_fallback( $deviceid, $name ) 
    ;
}

sub lookup_value
{
    my $self = shift;
    $self->_init();
    my $row = $self->lookup( @_ );
    return $row ? $row->{value} : undef;
}

sub cleanup
{
    my $self = shift;
    $self->log_debug("cleanup ...");
    if ( $self->{dbh} )
    {
        $self->log_debug("drop tables");
        for ( keys %tables )
        {
            $self->log_debug("DROP TABLE IF EXISTS $_");
            $self->{dbh}->do( "DROP TABLE IF EXISTS $_" );
        }
    }

    # List of all data members
    $self->{ua}                      = undef;
    $self->{log_fh}                  = undef;
    $self->{verbose}                 = undef;
    $self->{initialized}             = undef;
    $self->{canonical_ua_method}     = undef;
    $self->{wurfl_home}              = undef;
    $self->{wurfl_file}              = undef;
    $self->{wurfl_url}               = undef;
    $self->{dbh}                     = undef;
    $self->{db_descriptor}           = undef;
    $self->{db_username}             = undef;
    $self->{db_password}             = undef;
    $self->{device_table_name}       = undef;
    $self->{capability_table_name}   = undef;
    $self->{devices}                 = undef;
    $self->{capabilities}            = undef;
    $self->{last_update_sth}         = undef;
    $self->{user_agents_sth}         = undef;
    $self->{devices_sth}             = undef;
    $self->{device_sth}              = undef;
    $self->{deviceid_sth}            = undef;
    $self->{deviceid_like_sth}       = undef;
    $self->{deviceid_like_count_sth} = undef;
    $self->{lookup_sth}              = undef;
    $self->{fall_back_sth}           = undef;
    $self->{groups_sth}              = undef;
    $self->{group_capabilities_sth}  = undef;
    $self->{capabilities_sth}        = undef;
    return unless $self->{wurfl_file};
    return unless -e $self->{wurfl_file};
    $self->log_debug("unlink $self->{wurfl_file}");
    unlink $self->{wurfl_file} || die "Can't remove $self->{wurfl_file}: $!\n";
}

#------------------------------------------------------------------------------
#
# Start of POD
#
#------------------------------------------------------------------------------

=head1 NAME

Mobile::Wurfl - a perl module interface to WURFL (the Wireless Universal Resource File - L<http://wurfl.sourceforge.net/>).

=head1 SYNOPSIS

NB: The sourceforge wurfl_url link below is dead - see L</"IMPORTANT - WURFL DATA LICENSE CHANGE">

    my $wurfl = Mobile::Wurfl->new(
        wurfl_home => "/path/to/wurfl/home",

        # db_descriptor: $wurfl_home is expanded before being passed to DBI
        db_descriptor => 'DBI:SQLite=$wurfl_home/wurfl.sqlite.db',
        # db_username/db_password: unnecessary for DBI:SQLite
        # db_username => 'wurfl',
        # db_password => 'wurfl',
        wurfl_url => q{http://sourceforge.net/projects/wurfl/files/WURFL/latest/wurfl-latest.xml.gz/download},
    );

    # db_descriptor: an example connecting to MySQL
    my $dbh = DBI->connect( "DBI:mysql;database=wurfl;host=localhost", $db_username, $db_password );
    my $wurfl = Mobile::Wurfl->new( dbh => $dbh );

    my $desc = $wurfl->get( 'db_descriptor' );
    $wurfl->set( wurfl_home => "/another/path" );

    $wurfl->create_tables( $sql );
    $wurfl->update();
    $wurfl->get_wurfl();
    $wurfl->rebuild_tables();

    my @devices = $wurfl->devices();

    for my $device ( @devices )
    {
        print "$device->{user_agent} : $device->{id}\n";
    }

    my @groups = $wurfl->groups();
    my @capabilities = $wurfl->capabilities();
    for my $group ( @groups )
    {
        @capabilities = $wurfl->capabilities( $group );
    }

    my $ua = $wurfl->canonical_ua( "SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1.1" );
    my $deviceid = $wurfl->deviceid( $ua );

    my $wml_1_3 = $wurfl->lookup( $ua, "wml_1_3" );
    print "$wml_1_3->{name} = $wml_1_3->{value} : in $wml_1_3->{group}\n";
    my $fell_back_to = wml_1_3->{deviceid};
    my $width = $wurfl->lookup_value( $ua, "max_image_height", no_fall_back => 1 );
    $wurfl->cleanup();

=head1 DESCRIPTION

Mobile::Wurfl is a perl module that provides an interface to mobile device information represented in wurfl (L<http://wurfl.sourceforge.net/>). The Mobile::Wurfl module works by saving this device information in a database supported by L<DBI> (for example: SQLite, MySQL, PostgreSQL, etc).

It offers an interface to create the relevant database tables from a SQL file containing "CREATE TABLE" statements (a sample is provided with the distribution). It also provides a method for updating the data in the database from the wurfl xml files hosted by ScientiaMobile, Inc.

It provides methods to query the database for lists of capabilities, and groups of capabilities. It also provides a method for generating a "canonical" user agent string (see L</canonical_ua>). 

Finally, it provides a method for looking up values for particular capability / user agent combinations. By default, this makes use of the hierarchical "fallback" structure of wurfl to lookup capabilities fallback devices if these capabilities are not defined for the requested device.

=head2 IMPORTANT - WURFL DATA LICENSE CHANGE

=over

Mobile::Wurfl was written during a time when the WURFL data was still freely
licensed. See L<Net::WURFL::ScientiaMobile> for the official CPAN module which
is the new (only?) way to work with the current WURFL data without paying fees.

The last version of the WURFL XML which still had a permissive license was
released 2011-04-24, and contained the following text:

 All the information listed here has been collected by many different people
 from many different countries. You are allowed to use WURFL in any of your
 applications, free or commercial. The only thing required is to make public
 any modification to this file, following the original spirit and idea of the
 creators of this project.

=back

=head1 METHODS

=head2 new

The Mobile::Wurfl constructor takes an optional list of named options; e.g.:

    my $wurfl = Mobile::Wurfl->new(
        wurfl_home => "/path/to/wurfl/home",
        db_descriptor => "DBI:mysql;database=wurfl;host=localhost",
        db_username => 'wurfl',
        db_password => 'wurfl',
        wurfl_url => q{http://sourceforge.net/projects/wurfl/files/WURFL/latest/wurfl-latest.xml.gz/download},,
        verbose => 1,
    );

NB: The sourceforge wurfl_url link above is dead - see L</"IMPORTANT - WURFL DATA LICENSE CHANGE">

The list of possible options are as follows:

=over 4

=item wurfl_home

Used to set the default home diretory for Mobile::Wurfl. This is where the cached copy of the wurfl.xml file is stored. It defaults to a random directory assigned by C<<< File::Temp->newdir('wurfl_home_XXXX', CLEANUP => 1) >>>.

=item db_descriptor

A database descriptor - as used by L<DBI> to define the type, host, etc. of database to connect to. This is where the data from wurfl.xml will be stored, in two tables - device and capability. The default is C<<<<<'DBI:SQLite=$wurfl_home/wurfl.sqlite.db'>>>>> (where C<$wurfl_home> is expanded before being passed on to L<DBI>), an MySQL example would be C<<<<<"DBI:mysql;database=wurfl;host=localhost">>>>> (i.e. a mysql database called wurfl, hosted on localhost).

=item db_username

The username used to connect to the database defined by L</METHODS/new/db_descriptor>. Default is "wurfl".

=item db_password

The password used to connect to the database defined by L</METHODS/new/db_descriptor>. Default is "wurfl".

=item dbh

A DBI database handle.

=item wurfl_url

The URL from which to get the wurfl.xml file, this can be uncompressed or compressed with zip or gzip. Historically this option has defaulted to a sourceforge URL, but this was removed - see L</"IMPORTANT - WURFL DATA LICENSE CHANGE">

=item verbose

If set to a true value, various status messages will be output. If value is 1, these messages will be written to a logfile called wurfl.log in L</METHODS/new/wurfl_home>, if > 1 to STDERR.

=back

=head2 set / get

The set and get methods can be used to set / get values for the constructor options described above. Their usage is self explanatory:

    my $desc = $wurfl->get( 'db_descriptor' );
    $wurfl->set( wurfl_home => "/another/path" );

=head2 create_tables

The create_tables method is used to create the database tables required for Mobile::Wurfl to store the wurfl.xml data in. It can be passed as an argument a string containing appropriate SQL "CREATE TABLE" statements. If this is not passed, L<Mobile::Wurfl::SQL> attempts to obtain an appropriate set of SQL statements for the DBI driver specified in the C<db_descriptor>. This should only need to be called as part of the initial configuration.

At the time of writing there are schemas defined for PostgreSQL, SQLite and MySQL in the C<sql/> directory at the root of this installation - see C<sql/pg.sql>, C<sql/sqlite.sql> and C<sql/mysql.sql> respectively. If files here are added (name them lower-case C<driver.sql>) or modified, there is a script in C<script/update_Mobile-Wurfl-SQL.pl> to update/re-write the L<Mobile::Wurfl::SQL> package again. 

=head2 update

The update method is called to update the database tables with the latest information from wurfl.xml. It calls get_wurfl, and then rebuild_tables, each of which work out what if anything needs to be done (see below). It returns true if there has been an update, and false otherwise.

=head2 rebuild_tables

The rebuild_tables method is called by the update method. It checks the modification time of the locally cached copy of the wurfl.xml file against the last modification time on the database, and if it is greater, rebuilds the database table from the wurfl.xml file.

=head2 get_wurfl

The get_wurfl method is called by the update method. It checks to see if the locally cached version of the wurfl.xml file is up to date by doing a HEAD request on the WURFL URL, and comparing modification times. If there is a newer version of the file at the WURFL URL, or if the locally cached file does not exist, then the module will GET the wurfl.xml file from the WURFL URL.

=head2 devices

This method returns a list of all the devices in WURFL. This is returned as a list of hashrefs, each of which has keys C<user_agent>, C<actual_device_root>, C<id>, and C<fall_back>.

=head2 groups

This method returns a list of the capability groups in WURFL.

=head2 capabilities( group )

This method returns a list of the capabilities in a group in WURFL. If no group is given, it returns a list of all the capabilites.

=head2 canonical_ua( ua_string )

This method takes a user agent string as an argument, and tries to find a matching "canonical" user agent in WURFL. It is a simple wrapper to one of two algorithms; the default is C<canonical_ua_incremental> but may also be set to C<canonical_ua_binary>, which is usually faster as it performs fewer database queries (especially on longer strings). For caveats, see the L</canonical_ua_binary> documentation

Set the desired algorithm in the C<canonical_ua_method> constructor option:
    my $wurfl = Mobile::Wurfl->new(
        canonical_ua_method => 'canonical_ua_binary',
        wurfl_url => $url,
        db_descriptor => ....

=head2 canonical_ua_incremental

An implementation of L</canonical_ua> which finds the best exact-match user
agent string in the DB by shortening the supplied C<$ua> one character at a
time until an exact match in the DB is discovered. Each test results in a
separate SQL query, L</canonical_ua_binary> may be substantially faster.

C<canonical_ua_incremental> was originally named L</canonical_ua> in
L<Mobile::Wurfl> versions prior to 2.0. L</canonical_ua> still delegates 
to this method by default - which can be overridden with the
C<canonical_ua_method> constructor option.

Given:
    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1.1

This method would try the following:
    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1.1
    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1.
    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1
    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-
    ... 66 queries later ...
    SonyEricssonK750i

until it found a user agent string in WURFL, and then return it (or return undef if none were found). In the above case (for WURFL v2.0) it returns the string "SonyEricssonK750i".

=head2 canonical_ua_binary

An implementation of L</canonical_ua> which uses a binary search approach to
drastically reduce the number of database queries on long or uncommon user
agent strings. However, for this to have an advantage over
L</canonical_ua_incremental> you may need to create special indexes on the
C<device.user_agent> column to aid the SQL C<LIKE 'Foo%'> queries used in this
method. For example, SQLite users will need an C<COLLATE NOCASE> index in order
for C<LIKE> queries to have a chance of being optimized (see
L<http://www.sqlite.org/optoverview.html#like_opt> for more), Eg:

  CREATE INDEX user_agent_idx ON device (user_agent COLLATE NOCASE);

Once the binary search phase yields the longest truncated version of C<$ua>
which has a match to the beginning of one or more UAs in the DB, the partial
C<$ua> is passed on to L</canonical_ua_incremental> to find an exact match in
the DB.

Given:
    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1.1

This method would try the following:
    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1.1
    SonyEricssonK750i/R1J Browser/SEMC-Browser
    SonyEricssonK750i/R1
    SonyEricssonK750i/R1J Browser/S
    SonyEricssonK750i/R1J Bro
    SonyEricssonK750i/R1J 
    SonyEricssonK750i/R1J
    SonyEricssonK750i/R1 # There is a UA in the DB which begins with this string
    SonyEricssonK750i/R  # using canonical_ua_incremental
    SonyEricssonK750i/   # using canonical_ua_incremental
    SonyEricssonK750i    # using canonical_ua_incremental

=cut

=head2 deviceid( ua_string )

This method returns the deviceid for a given user agent string.

=head2 device( deviceid )

This method returns a hashref for a given deviceid. The hashref has keys C<user_agent>, C<actual_device_root>, C<id>, and C<fall_back>.

=head2 lookup( ua_string, capability, [ no_fall_back => 1 ] )

This method takes a user agent string and a capability name, and returns a hashref representing the capability matching this combination. The hashref has the keys C<name>, C<value>, C<groupid> and C<deviceid>. By default, if a capability has no value for that device, it recursively falls back to its fallback device, until it does find a value. You can discover the device "fallen back to" by accessing the C<deviceid> key of the hash. This behaviour can be controlled by using the "no_fall_back" option.

=head2 lookup_value( ua_string, capability, [ no_fall_back => 1 ] )

This method is similar to the lookup method, except that it returns a value instead if a hash.

=head2 cleanup()

This method forces the module to C<DROP> all of the database tables it has created, and remove the locally cached copy of wurfl.xml.

=head1 AUTHOR

Ave Wrigley <Ave.Wrigley@itn.co.uk>

=head1 COPYRIGHT

Copyright (c) 2004 Ave Wrigley. All rights reserved. This program is free
software; you can redistribute it and/or modify it under the same terms as Perl
itself.

=cut

#------------------------------------------------------------------------------
#
# End of POD
#
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
#
# True ...
#
#------------------------------------------------------------------------------

1;
