#!/usr/bin/env perl

# Creation date: 2007-09-12 19:27:49
# Authors: don

use strict;
use warnings;
use Test;

# main
{
    plan tests => 4;

    use JSON::DWIW;
    my $json_obj = JSON::DWIW->new;

    my $data = $json_obj->from_json_file("t/parse_file.json");
    ok($data and $data->{var1} eq 'val1');

    $data = JSON::DWIW->from_json_file("t/parse_file.json");
    ok($data and $data->{var1} eq 'val1');

    my $error;
    ($data, $error) = JSON::DWIW->from_json_file("t/parse_file.json");
    ok(not $error and $data and $data->{var1} eq 'val1');

    ($data, $error) = JSON::DWIW->from_json_file("t/non_existent_file.json");
    ok($error and $error =~ /couldn't open input file/);
}

exit 0;

###############################################################################
# Subroutines

