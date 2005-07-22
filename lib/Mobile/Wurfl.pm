package Mobile::Wurfl;

$VERSION = '1.00';

use strict;
use warnings;
use DBI;
use File::Slurp;
use XML::Simple;
use LWP::Simple qw( head getstore );
use FindBin qw( $Bin );

my %tables = (
    device => [ qw( id actual_device_root user_agent fall_back ) ],
    capability => [ qw( groupid name value deviceid ) ],
);

sub new
{
    my $class = shift;
    my %opts = (
        wurfl_home => $Bin,
        db_descriptor => "DBI:mysql:database=wurfl:host=localhost", 
        db_username => 'wurfl',
        db_password => 'wurfl',
        wurfl_url => q{http://www.nusho.it/wurfl/dl.php?t=d&f=wurfl.xml},
        sql_file => "$Bin/wurfl.sql",
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
        open( LOG, ">wurfl.log" );
    }
    print LOG "connecting to $self->{db_descriptor} as $self->{db_username}\n";
    $self->{dbh} = DBI->connect( 
        $self->{db_descriptor},
        $self->{db_username},
        $self->{db_password},
        { RaiseError => 1 }
    ) or die "Cannot connect to $self->{db_descriptor}: " . $DBI::errstr;
    return $self;
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

sub touch( $$ ) 
{ 
    my $path = shift;
    my $time = shift;
    return utime( $time, $time, $path );
}

sub deviceid
{
    my $self = shift;
    my $ua = shift;
    $self->_init();
    $self->{device_sth}->execute( $ua );
    my $deviceid = $self->{device_sth}->fetchrow;
    die "can't find device id for user agent $ua\n" unless $deviceid;
    return $deviceid;
}

sub devices
{
    my $self = shift;
    $self->_init();
    $self->{devices_sth}->execute();
    return @{$self->{devices_sth}->fetchall_arrayref( {} )};
}

sub update
{
    my $self = shift;
    $self->{wurfl_file} = "$self->{wurfl_home}/wurfl.xml";
    print LOG "update wurfl ...\n";
    print LOG "HEAD $self->{wurfl_url} ...\n";
    my ( undef, $document_length, $modified_time ) = head( $self->{wurfl_url} ) 
        or die "can't head $self->{wurfl_url}\n"
    ;
    my ( $dl, $mt ) = 
        -e $self->{wurfl_file} ? 
            ( stat $self->{wurfl_file} )[ 7, 9 ] : 
            ( 0, 0 )
    ;
    if ( $mt == $modified_time && $document_length == $dl )
    {
        print LOG "$self->{wurfl_file} is up to date ...\n";
        return 0;
    }
    print LOG "getting $self->{wurfl_url} -> $self->{wurfl_file} ...\n";
    getstore( $self->{wurfl_url}, $self->{wurfl_file} ) 
        or die "can't get $self->{wurfl_url} -> $self->{wurfl_file}: $!\n"
    ;
    touch( $self->{wurfl_file}, $modified_time ) 
        or die "can't touch $self->{wurfl_file}: $!\n"
    ;
    print LOG "parse $self->{wurfl_file} ...\n";
    my $wurfl = XMLin( $self->{wurfl_file}, keyattr => [], forcearray => 1, ) 
        or die "Can't parse $self->{wurfl_file}\n"
    ;
    print LOG "flush dB tables ...\n";
    $self->{dbh}->do( "DELETE FROM device" );
    $self->{dbh}->do( "DELETE FROM capability" );
    for my $table ( keys %tables )
    {
        my @fields = @{$tables{$table}};
        my $fields = join( ",", @fields );
        my $placeholders = join( ",", map "?", @fields );
        my $sql = "INSERT INTO $table ( $fields ) VALUES ( $placeholders ) ";
        print LOG "$sql\n";
        $self->{$table}{sth} = $self->{dbh}->prepare( $sql );
    }
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
    for my $table ( keys %tables )
    {
        $self->{$table}{sth}->finish();
    }
    return 0;
}

sub create_tables
{
    my $self = shift;
    print LOG "read sql file $self->{sql_file} ...\n";
    my $sql = read_file( $self->{sql_file} ) || die "failed to read $self->{sql_file} : $!\n";
    for my $statement ( split( /\s*;\s*/, $sql ) )
    {
        next unless $statement =~ /\S/;
        print LOG "STATEMENT: $statement\n";
        $self->{dbh}->do( $statement );
    }
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
    $self->{device_sth}->execute( $ua );
    $deviceid = $self->{device_sth}->fetchrow;
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

sub lookup_value
{
    my $self = shift;
    my $row = $self->lookup( @_ );
    return $row ? $row->{value} : undef;
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

#------------------------------------------------------------------------------
#
# Start of POD
#
#------------------------------------------------------------------------------

=head1 NAME

Mobile::Wurfl - a perl module interface to WURFL (the Wireless Universal Resource File - L<http://wurfl.sourceforge.net/>).

=head1 SYNOPSIS

    my $wurfl = Mobile::Wurfl->new(
        wurfl_home => "/path/to/wurrl/home",
        db_descriptor => "DBI:mysql:database=wurfl:host=localhost", 
        db_username => 'wurfl',
        db_password => 'wurfl',
        wurfl_url => q{http://www.nusho.it/wurfl/dl.php?t=d&f=wurfl.xml},
        sql_file => "wurfl.sql",
        verbose => 1,
    );

    $wurfl->create_tables();
    $wurfl->update();

    my @groups = $wurfl->groups();
    my @capabilities = $wurfl->capabilities();
    for my $group ( @groups )
    {
        @capabilities = $wurfl->capabilities( $group );
    }

    my $ua = $wurfl->canonical_ua( "MOT-V980M/80.2F.43I MIB/2.2.1 Profile/MIDP-2.0 Configuration/CLDC-1.1" );

    my $wml_1_3 = $wurfl->lookup( $ua, "wml_1_3" );
    print "$wml_1_3->{name} = $wml_1_3->{value} : in $wml_1_3->{group}\n";
    my $fell_back_to = wml_1_3->{device};
    my $width = $wurfl->lookup_value( $ua, "max_image_height", no_fall_back => 1 );

=head1 DESCRIPTION

Mobile::Wurfl is a perl module that provides an interface to mobile device information represented in wurfl (L<http://wurfl.sourceforge.net/>). The Mobile::Wurfl module works by saving this device information in a database (preferably mysql). 

It offers an interface to create the relevant database tables from a SQL file containing "CREATE TABLE" statements (a sample is provided with the distribution). It also provides a method for updating the data in the database from the wurfl.xml file hosted at L<http://www.nusho.it/wurfl/dl.php?t=d&f=wurfl.xml>. 

It provides methods to query the database for lists of capabilities, and groups of capabilities. It also provides a method for generating a "canonical" user agent string (see L</canonical_ua>). 

Finally, it provides a method for looking up values for particular capability / user agent combinations. By default, this makes use of the hierarchical "fallback" structure of wurfl to lookup capabilities fallback devices if these capabilities are not defined for the requested device.

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

