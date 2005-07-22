use ExtUtils::MakeMaker;
use File::Find;

sub get_version
{
    my $module = shift;
    # eval "require $module" or die "$@\n";
    my $version = eval '$' . $module . '::VERSION';
    return 0 unless $version;
    return $version;
}

my %module;
find(
    sub {
        return unless -f;
        return unless -T;
        return unless /\.(pm|t|pl|cgi)$/i;
        open( FH, $_ );
        for ( <FH> )
        {
            $module{$1}++ if /(?:use|require)\s+([A-Z][A-Za-z0-9:]+)/;
        }
    }, "." 
);
%prereq_pm = map { $_ => geT_version } keys %module;
WriteMakefile(
    'NAME'		=> 'Mobile::Wurfl',
    'VERSION_FROM'	=> 'lib/Mobile/Wurfl.pm',
    'PREREQ_PM'		=> {
	CGI::Lite => 0,
	DBD::CSV => 0,
	DBI => 0,
	Data::Dumper => 0,
	ExtUtils::MakeMaker => 0,
	File::Find => 1.07,
	File::Path => 0,
	File::Slurp => 0,
	FindBin => 0,
	LWP::Simple => 0,
	Test::More => 0,
	XML::Simple => 0,
    }
);
