#!/usr/bin/env perl

# Creation date: 2007-05-11 07:43:10
# Authors: don

use strict;
use Test;

# main
{
    plan tests => 5;

    use JSON::DWIW;
    
    ok(JSON::DWIW->is_valid_utf8("\x{706b}"));

    ok(not JSON::DWIW->is_valid_utf8("\xe9s"));

    my $str = "";
    ok(not JSON::DWIW->flagged_as_utf8($str));

    JSON::DWIW->flag_as_utf8($str);
    ok(JSON::DWIW->flagged_as_utf8($str));
    
    JSON::DWIW->unflag_as_utf8($str);
    ok(not JSON::DWIW->flagged_as_utf8($str));

}

exit 0;

###############################################################################
# Subroutines

