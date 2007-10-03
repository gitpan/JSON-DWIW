#!/usr/bin/env perl

# Creation date: 2007-05-11 07:43:10
# Authors: don

use strict;
use Test;

# main
{
    plan tests => 6;

    use JSON::DWIW;
    
    ok(JSON::DWIW->is_valid_utf8("\x{706b}"));

    ok(not JSON::DWIW->is_valid_utf8("\xe9s"));

    my $str = "";
    ok(not JSON::DWIW->flagged_as_utf8($str));

    JSON::DWIW->flag_as_utf8($str);
    ok(JSON::DWIW->flagged_as_utf8($str));
    
    JSON::DWIW->unflag_as_utf8($str);
    ok(not JSON::DWIW->flagged_as_utf8($str));

    # Test utf8 sequences in hash keys.  In Perl 5.8, a utf8 key
    # that can be represented in latin1 will get converted to
    # latin1 at the C layer, breaking things if it is not checked
    # explicitly
    my $utf8_str = "\xc3\xa4";
    JSON::DWIW->flag_as_utf8($str);
    my %hash;
    $hash{$utf8_str} = 'blah';
    my ($json_str, $error) = JSON::DWIW->to_json(\%hash);
    ok(not $error);
}

exit 0;

###############################################################################
# Subroutines

