
use strict;
use warnings;

use Module::Build;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => 0,
  },
  "configure_requires" => {
    "ExtUtils::MakeMaker" => "6.30",
    "Module::Build" => 0,
  },
  "dist_abstract" => "a perl module interface to WURFL (the Wireless Universal Resource File - L<http://wurfl.sourceforge.net/>).",
  "dist_author" => [
    "Ave Wrigley <Ave.Wrigley\@itn.co.uk>",
    "Paul Harvey <csirac2\@yahoo.com.au>"
  ],
  "dist_name" => "Mobile-Wurfl",
  "dist_version" => "2.0",
  "license" => "perl",
  "module_name" => "Mobile::Wurfl",
  "recommends" => {
    "Git::Repository" => 0
  },
  "recursive_test_files" => 1,
  "requires" => {
    "DBI" => 0,
    "Date::Parse" => 0,
    "File::Basename" => 0,
    "File::Copy" => 0,
    "File::Spec" => 0,
    "File::Temp" => 0,
    "FindBin" => 0,
    "Getopt::Long" => 0,
    "IO::Uncompress::Gunzip" => 0,
    "IO::Uncompress::Unzip" => 0,
    "LWP::UserAgent" => 0,
    "POSIX" => 0,
    "Pod::Find" => 0,
    "Pod::Usage" => 0,
    "XML::Parser" => 0,
    "lib" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "script_files" => [],
  "test_requires" => {
    "Benchmark" => 0,
    "DBD::SQLite" => 0,
    "File::Path" => 0,
    "Test::More" => 0
  }
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  my $tr = delete $module_build_args{test_requires};
  my $br = $module_build_args{build_requires};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
