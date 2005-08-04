package Mobile::Wurfl;

$VERSION = '1.01';

use strict;
use warnings;
use DBI;
use DBD::mysql;
use File::Slurp;
use XML::Simple;
use LWP::Simple qw( head getstore );

my %tables = (
    device => [ qw( id actual_device_root user_agent fall_back ) ],
    capability => [ qw( groupid name value deviceid ) ],
);

sub _touch( $$ ) 
{ 
    my $path = shift;
    my $time = shift;
    return utime( $time, $time, $path );
}

sub new
{
    my $class = shift;
    my %opts = (
        wurfl_home => ".",
        db_descriptor => "DBI:mysql:database=wurfl:host=localhost", 
        db_username => 'wurfl',
        db_password => 'wurfl',
        wurfl_url => q{http://www.nusho.it/wurfl/dl.php?t=d&f=wurfl.xml},
        verbose => 0,
        @_
    );
    my $self = bless \%opts, $class;
    if ( $self->{verbose} )
    {
        open( LOG, ">&STDERR" );
    }
    else
    {
        open( LOG, ">$self->{wurfl_home}/wurfl.log" );
    }
    print LOG "connecting to $self->{db_descriptor} as $self->{db_username}\n";
    $self->{dbh} = DBI->connect( 
        $self->{db_descriptor},
        $self->{db_username},
        $self->{db_password},
        { RaiseError => 1 }
    ) or die "Cannot connect to $self->{db_descriptor}: " . $DBI::errstr;
    $self->{wurfl_file} = "$self->{wurfl_home}/wurfl.xml";
    return $self;
}

sub _init
{
    my $self = shift;
    return if $self->{initialised};
    for ( keys %tables )
    {
        eval { $self->{dbh}->do( "SELECT * FROM $_" ); };
        if ( $@ )
        {
            die "table $_ doesn't exist on $self->{db_descriptor}: try running $self->create_tables()\n";
        }
    }
    $self->{devices_sth} = $self->{dbh}->prepare( 
        "SELECT * FROM device" 
    );
    $self->{device_sth} = $self->{dbh}->prepare( 
        "SELECT * FROM device WHERE id = ?"
    );
    $self->{deviceid_sth} = $self->{dbh}->prepare( 
        "SELECT id FROM device WHERE user_agent = ?"
    );
    $self->{lookup_sth} = $self->{dbh}->prepare(
        "SELECT * FROM capability WHERE name = ? AND deviceid = ?"
    );
    $self->{fall_back_sth} = $self->{dbh}->prepare(
        "SELECT fall_back FROM device WHERE id = ?"
    );
    my $sth = $self->{dbh}->prepare( 
        "SELECT name, groupid FROM capability WHERE deviceid = 'generic'"
    );
    $sth->execute();
    while ( my ( $name, $group ) = $sth->fetchrow() )
    {
        $self->{groups}{$group}{$name}++;
        $self->{capabilities}{$name}++ ;
    }
    $sth->finish();
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

sub create_tables
{
    my $self = shift;
    my $sql = shift || join( '', <DATA> );
    for my $statement ( split( /\s*;\s*/, $sql ) )
    {
        next unless $statement =~ /\S/;
        print LOG "STATEMENT: $statement\n";
        $self->{dbh}->do( $statement );
    }
}

sub update
{
    my $self = shift;
    my %opts = @_;

    print LOG "update wurfl ...\n";
    unless ( $opts{force} )
    {
	return 0 unless $self->_needs_update();
    }
    print LOG "getting $self->{wurfl_url} -> $self->{wurfl_file} ...\n";
    getstore( $self->{wurfl_url}, $self->{wurfl_file} ) 
        or die "can't get $self->{wurfl_url} -> $self->{wurfl_file}: $!\n"
    ;
    _touch( $self->{wurfl_file}, $self->{modified_time} ) 
        or die "can't touch $self->{wurfl_file}: $!\n"
    ;
    $self->rebuild_tables();
    return 1;
}

sub _needs_update
{
    my $self = shift;
    return 1 unless -e $self->{wurfl_file};
    print LOG "HEAD $self->{wurfl_url} ...\n";
    my %remote;
    @remote{qw( content_type document_length modified_time )} = 
        head( $self->{wurfl_url} ) 
            or die "can't head $self->{wurfl_url}\n"
    ;
    $self->{wurfl} = \%remote;
    my %local;
    @local{qw( document_length modified_time )} = ( stat $self->{wurfl_file} )[ 7, 9 ];
    if ( 
        $local{modified_time} == $remote{modified_time} &&
        $local{document_length} == $remote{document_length} 
    )
    {
	print LOG "$self->{wurfl_file} is up to date ...\n";
	return 0;
    }
    return 1;
}

sub rebuild_tables
{
    my $self = shift;

    print LOG "parse $self->{wurfl_file} ...\n";
    my $wurfl = XMLin( $self->{wurfl_file}, keyattr => [], forcearray => 1, ) 
        or die "Can't parse $self->{wurfl_file}\n"
    ;
    print LOG "flush dB tables ...\n";
    $self->{dbh}->do( "DELETE FROM device" );
    $self->{dbh}->do( "DELETE FROM capability" );
    $self->_create_sths();
    my $devices = $wurfl->{devices}[0]{device};
    for my $device ( @$devices )
    {
        print LOG "$device->{id}\n";
        $self->{device}{sth}->execute( @$device{ @{$tables{device}} } );
        if ( my $group = $device->{group} )
        {
            foreach my $g ( @$group )
            {
                foreach my $capability ( @{$g->{capability}} )
                {
                    $capability->{groupid} = $g->{id};
                    $capability->{deviceid} = $device->{id};
                    $self->{capability}{sth}->execute( 
                        @$capability{ @{$tables{capability}} } 
                    );
                }
            }
        }
    }
}

sub _create_sths
{
    my $self = shift;

    for my $table ( keys %tables )
    {
	next if $self->{$table}{sth};
        my @fields = @{$tables{$table}};
        my $fields = join( ",", @fields );
        my $placeholders = join( ",", map "?", @fields );
        my $sql = "INSERT INTO $table ( $fields ) VALUES ( $placeholders ) ";
        print LOG "$sql\n";
        $self->{$table}{sth} = $self->{dbh}->prepare( $sql );
    }
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
    return keys %{$self->{groups}};
}

sub capabilities
{
    my $self = shift;
    my $group = shift;
    $self->_init();
    if ( $group )
    {
        return keys %{$self->{groups}{$group}};
    }
    return keys %{$self->{capabilities}};
}

sub _lookup
{
    my $self = shift;
    my $deviceid = shift;
    my $name = shift;
    $self->{lookup_sth}->execute( $name, $deviceid );
    return $self->{lookup_sth}->fetchrow_hashref;
}

sub _fallback
{
    my $self = shift;
    my $deviceid = shift;
    my $name = shift;
    my $row = $self->_lookup( $deviceid, $name );
    return $row if $row && ( $row->{value} || $row->{deviceid} eq 'generic' );
    print LOG "can't find $name for $deviceid ... trying fallback ...\n";
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

sub canonical_ua
{
    my $self = shift;
    my $ua = shift;
    $self->_init();
    my $deviceid ;
    $self->{deviceid_sth}->execute( $ua );
    $deviceid = $self->{deviceid_sth}->fetchrow;
    return $ua if $deviceid;
    print LOG "$ua not found ... \n";
    my @ua = split "/", $ua;
    if ( @ua <= 1 )
    {
        print LOG "can't find canonical user agent for $ua\n";
        return;
    }
    pop( @ua );
    $ua = join( "/", @ua );
    print LOG "trying $ua\n";
    return $self->canonical_ua( $ua );
}

sub device
{
    my $self = shift;
    my $deviceid = shift;
    $self->_init();
    $self->{device_sth}->execute( $deviceid );
    my $device = $self->{device_sth}->fetchrow_hashref;
    die "can't find device for user deviceid $deviceid\n" unless $device;
    return $device;
}

sub deviceid
{
    my $self = shift;
    my $ua = shift;
    $self->_init();
    $self->{deviceid_sth}->execute( $ua );
    my $deviceid = $self->{deviceid_sth}->fetchrow;
    die "can't find device id for user agent $ua\n" unless $deviceid;
    return $deviceid;
}

sub lookup
{
    my $self = shift;
    my $ua = shift;
    my $name = shift;
    my %opts = @_;
    $self->_init();
    die "$name is not a valid capability\n" unless $self->{capabilities}{$name};
    print LOG "user agent: $ua\n";
    my $deviceid = $self->deviceid( $ua );
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
    my $row = $self->lookup( @_ );
    return $row ? $row->{value} : undef;
}

sub cleanup
{
    my $self = shift;
    if ( $self->{dbh} )
    {
        $self->{dbh}->do( "DROP TABLE $_" ) for keys %tables;
    }
    return unless $self->{wurfl_file};
    return unless -e $self->{wurfl_file};
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

    my $wurfl = Mobile::Wurfl->new(
        wurfl_home => "/path/to/wurfl/home",
        db_descriptor => "DBI:mysql:database=wurfl:host=localhost", 
        db_username => 'wurfl',
        db_password => 'wurfl',
        wurfl_url => q{http://www.nusho.it/wurfl/dl.php?t=d&f=wurfl.xml},
        verbose => 1,
    );

    my $desc = $wurfl->get( 'db_descriptor' );
    $wurfl->set( wurfl_home => "/another/path" );

    $wurfl->create_tables( "wurfl.sql" );
    $wurfl->update( force => 1 );
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

    my $ua = $wurfl->canonical_ua( "MOT-V980M/80.2F.43I MIB/2.2.1 Profile/MIDP-2.0 Configuration/CLDC-1.1" );
    my $deviceid = $wurfl->deviceid( $ua );

    my $wml_1_3 = $wurfl->lookup( $ua, "wml_1_3" );
    print "$wml_1_3->{name} = $wml_1_3->{value} : in $wml_1_3->{group}\n";
    my $fell_back_to = wml_1_3->{deviceid};
    my $width = $wurfl->lookup_value( $ua, "max_image_height", no_fall_back => 1 );
    $wurfl->cleanup();

=head1 DESCRIPTION

Mobile::Wurfl is a perl module that provides an interface to mobile device information represented in wurfl (L<http://wurfl.sourceforge.net/>). The Mobile::Wurfl module works by saving this device information in a database (preferably mysql). 

It offers an interface to create the relevant database tables from a SQL file containing "CREATE TABLE" statements (a sample is provided with the distribution). It also provides a method for updating the data in the database from the wurfl.xml file hosted at L<http://www.nusho.it/wurfl/dl.php?t=d&f=wurfl.xml>. 

It provides methods to query the database for lists of capabilities, and groups of capabilities. It also provides a method for generating a "canonical" user agent string (see L</canonical_ua>). 

Finally, it provides a method for looking up values for particular capability / user agent combinations. By default, this makes use of the hierarchical "fallback" structure of wurfl to lookup capabilities fallback devices if these capabilities are not defined for the requested device.

=head1 METHODS

=head2 new

The Mobile::Wurfl constructor takes an optional list of named options; e.g.:

    my $wurfl = Mobile::Wurfl->new(
        wurfl_home => "/path/to/wurfl/home",
        db_descriptor => "DBI:mysql:database=wurfl:host=localhost", 
        db_username => 'wurfl',
        db_password => 'wurfl',
        wurfl_url => q{http://www.nusho.it/wurfl/dl.php?t=d&f=wurfl.xml},
        verbose => 1,
    );

The list of possible options are as follows:

=over 4

=item wurfl_home

Used to set the default home diretory for Mobile::Wurfl. This is where the cached copy of the wurfl.xml file is stored. It defaults to current directory.

=item db_descriptor

A database descriptor - as used by L<DBI> to define the type, host, etc. of database to connect to. This is where the data from wurfl.xml will be stored, in two tables - device and capability. The default is "DBI:mysql:database=wurfl:host=localhost" (i.e. a mysql database called wurfl, hosted on localhost.

=item db_username

The username used to connect to the database defined by L</METHODS/new/db_descriptor>. Default is "wurfl".

=item db_password

The password used to connect to the database defined by L</METHODS/new/db_descriptor>. Default is "wurfl".

=item wurfl_url

The URL from which to get the wurfl.xml file. Default is L<http://www.nusho.it/wurfl/dl.php?t=d&f=wurfl.xml>.

=item verbose

If set to a true value, various status messages will be output to STDERR. If false, these messages will be written to a logfile called wurfl.log in L</METHODS/new/wurfl_home>.

=back

=head2 set / get

The set and get methods can be used to set / get values for the constructor options described above. Their usage is self explanatory:

    my $desc = $wurfl->get( 'db_descriptor' );
    $wurfl->set( wurfl_home => "/another/path" );

=head2 create_tables

The create_tables method is used to create the database tables required for Mobile::Wurfl to store the wurfl.xml data in. It can be passed as an argument a string containing appropriate SQL "CREATE TABLE" statements. If this is not passed, it uses appropriate statements for a mysql database (see __DATA__ section of the module for the specifics). This should only need to be called as part of the initial configuration.

=head2 update( [ force => 1 ] )

The update method is called to update the database tables with the latest information from wurfl.xml. It first checks to see if the locally cached version of the wurfl.xml file is up to date by doing a HEAD request on the WURFL URL, and comparing modification times. If there is a newer version of the file at the WURFL URL, or if the locally cached file does not exist, then the module will GET the wurfl.xml file from the WURFL URL. If this has been done, the module will parse the wurfl.xml file, and populate the database with the new data. The update method can be passed a "force" option, which will force the wurfl.xml file to be fetched and the database tables re-populated even if the WURFL URL is not newer than the locally cached copy.

=head2 rebuild_tables

The rebuild_tables method is called by the update method if the WURFL URL is more recent than the locally cached copy of wurfl.xml. It can also be called directly if you wish to re-parse the wurfl.xml file and rebuild the database tables without checking (and possibly retrieving) the WURFL URL.

=head2 devices

This method returns a list of all the devices in WURFL. This is returned as a list of hashrefs, each of which has keys C<user_agent>, C<actual_device_root>, C<id>, and C<fall_back>.

=head2 groups

This method returns a list of the capability groups in WURFL.

=head2 capabilities( group )

This method returns a list of the capabilities in a group in WURFL. If no group is given, it returns a list of all the capabilites.

=head2 canonical_ua( ua_string )

This method takes a user agent string as an argument, and tries to find a matching "canonical" user agent in WURFL. It does this simply by recursively doing a lookup on the string, and if this fails, chopping anything after and including the last "/" in the string. So, for example, for the user agent string:

    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1.1

the canonical_ua method would try the following:

    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration/CLDC-1.1
    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile/MIDP-2.0 Configuration
    SonyEricssonK750i/R1J Browser/SEMC-Browser/4.2 Profile
    SonyEricssonK750i/R1J Browser/SEMC-Browser
    SonyEricssonK750i/R1J Browser
    SonyEricssonK750i

until it found a user agent string in WURFL, and then return it (or return undef if none were found). In the above case (for WURFL v2.0) it returns the string "SonyEricssonK750i".

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

__DATA__

# MySQL dump 8.16
#
# Host: localhost    Database: wurfl
#--------------------------------------------------------
# Server version	4.0.21-max

#
# Table structure for table 'capability'
#

DROP TABLE IF EXISTS capability;
CREATE TABLE capability (
  name varchar(100) NOT NULL default '',
  value varchar(100) default '',
  groupid varchar(100) NOT NULL default '',
  deviceid varchar(100) NOT NULL default '',
  KEY groupid (groupid),
  KEY name_deviceid (name,deviceid)
) TYPE=InnoDB;

#
# Table structure for table 'device'
#

DROP TABLE IF EXISTS device;
CREATE TABLE device (
  user_agent varchar(100) NOT NULL default '',
  actual_device_root enum('true','false') default 'false',
  id varchar(100) NOT NULL default '',
  fall_back varchar(100) NOT NULL default '',
  KEY user_agent (user_agent),
  KEY id (id)
) TYPE=InnoDB;
