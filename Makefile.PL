
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "a perl module interface to WURFL (the Wireless Universal Resource File - L<http://wurfl.sourceforge.net/>).",
  "AUTHOR" => "Ave Wrigley <Ave.Wrigley\@itn.co.uk>, Paul Harvey <csirac2\@yahoo.com.au>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Mobile-Wurfl",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Mobile::Wurfl",
  "PREREQ_PM" => {
    "DBI" => 0,
    "File::Basename" => 0,
    "File::Spec" => 0,
    "File::Temp" => 0,
    "HTTP::Date" => 0,
    "IO::Uncompress::Gunzip" => 0,
    "IO::Uncompress::Unzip" => 0,
    "LWP::UserAgent" => 0,
    "POSIX" => 0,
    "XML::Parser" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "TEST_REQUIRES" => {
    "Benchmark" => 0,
    "DBD::SQLite" => 0,
    "File::Copy" => 0,
    "File::Path" => 0,
    "FindBin" => 0,
    "Git::Repository" => 0,
    "Test::More" => 0,
    "lib" => 0
  },
  "VERSION" => "2.0",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
  my $br = $WriteMakefileArgs{BUILD_REQUIRES};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



