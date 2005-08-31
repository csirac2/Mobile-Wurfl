use ExtUtils::MakeMaker;
use File::Find;

my $name = 'Mobile::Wurfl';
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
%prereq_pm = map { $_ => 0 } grep { $_ ne $name } keys %module;
WriteMakefile(
    'NAME'		=> $name,
    'VERSION_FROM'	=> 'lib/Mobile/Wurfl.pm',
    'PREREQ_PM'		=> \%prereq_pm
);
