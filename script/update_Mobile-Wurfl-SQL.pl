#!/usr/bin/perl
use warnings;
use strict;
use File::Basename();
use File::Spec();

my $module_name        = 'Mobile::Wurfl::SQL';
my $script_path        = File::Basename::dirname(__FILE__);
my @script_path_dirs   = File::Spec->splitdir($script_path);
my $script_path_parent = File::Spec->catdir(
    scalar( @script_path_dirs[ 0 .. -1 ] )
    ? ( @script_path_dirs[ 0 .. -1 ] )
    : '.'
);

sub load_sql {
    my ($path) = @_;
    my %schemas;

    opendir( my $dh, $path ) or die "Tried to open dir '$path'\n" . $!;
    while ( my $file = readdir $dh ) {
        if ( $file =~ /^([^\.]+)\.sql$/i ) {
            my $driver = lc($1);
            open( my $fh, '<', File::Spec->catfile( $path, $file ) )
              or die $!;

            sysread( $fh, $schemas{$driver}, -s $fh ) or die $!;
            print "#   Found in '$path': '$file'\t"
              . length( $schemas{$driver} )
              . "\tfor $driver\n";
            close($fh) or die $!;
        }
    }
    close($dh);

    return \%schemas;
}

sub gather_sql {
    my ($base_dir) = @_;
    my $sql_path =
        $ENV{WURFL_SQL_DIR}
      ? $ENV{WURFL_SQL_DIR}
      : File::Spec->catdir( $base_dir, 'sql' );

    return load_sql($sql_path);
}

sub write_module {
    my ( $out_file, $schemas ) = @_;
    my $sql_start = <<"HERE";
package $module_name;
use strict;
use warnings;

my %SQL = (
    
HERE
    my @sql_middle;
    my $sql_end = <<'HERE';
);

sub get {
    my ( $class, $driver ) = @_;
    my $sql;

    $driver = lc($driver);
    if (!defined $SQL{$driver}) {
        warn "No SQL found for driver '$driver', using 'generic' instead...\n";
        $sql = $SQL{generic};
    }
    else {
        $sql = $SQL{$driver};
    }

    return $sql;
}

1;
HERE

    chomp($sql_start);
    while ( my ( $driver, $sql ) = each %{$schemas} ) {
        print "#   Appending to $out_file for $driver...\n";
        push( @sql_middle, <<"HEAR");
'$driver' => <<'HERE'
$sql
HERE
HEAR
    }
    open( my $fh, '>', $out_file ) or die "ERROR writing to $out_file\n" . $!;
    print $fh $sql_start;
    print $fh join( '    , ', @sql_middle );
    print $fh $sql_end;
    close($fh) or die $!;

    return;
}

sub run {
    my $schemas = gather_sql($script_path_parent);
    my @module = split( /::/, $module_name );
    my $out_file;

    $module[-1] .= '.pm';
    $out_file = File::Spec->catfile( $script_path_parent, 'lib', @module );

    write_module( $out_file, $schemas );

    return;
}

run();
