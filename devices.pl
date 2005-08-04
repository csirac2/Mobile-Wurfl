#!/bin/env perl

#------------------------------------------------------------------------------
#
# Standard pragmas
#
#------------------------------------------------------------------------------

use strict;
use warnings;
use lib 'lib';
use Mobile::Wurfl;

warn "create Mobile::Wurfl object\n";
my $wurfl = Mobile::Wurfl->new();
my $uas = do "/export/home/cdbi/cdbi/log/uas.pl";
my $ua_env = do "/export/home/cdbi/cdbi/log/ua_env.pl";
for my $ua ( keys %$uas )
{
    my $cua = $wurfl->canonical_ua( $ua );
    if ( $cua ne $ua )
    {
        die "$ua\n$cua\n";
        # print "$ua : $cua\n";
    }
    else
    {
        my $env = $ua_env->{$ua};
        if ( $env )
        {
            print "Can't find $ua\n";
            print map "\t$_ = $env->{$_}\n", keys %$env;
        }
        else
        {
            print "no env for $ua\n";
        }
    }
}

#------------------------------------------------------------------------------
#
# Start of POD
#
#------------------------------------------------------------------------------

=head1 NAME

=head1 SYNOPSIS

=head1 DESCRIPTION

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

