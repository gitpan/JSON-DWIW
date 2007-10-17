#!/usr/bin/env perl

# Creation date: 2007-10-02 18:51:38
# Authors: don

use strict;
use warnings;

# main
{
    use Test;
    BEGIN {
        plan tests => 18;
    }

    use JSON::DWIW;
    my $json_obj = JSON::DWIW->new;
    
    my $str = qq{{"test":"\xc3\xa4","funky":"\\u70":"key":"val"}};
    my ($data, $error) = JSON::DWIW->from_json($str);

    ok($error);

    ok(defined $error and $error =~ /bad unicode character specification/);
    ok(defined $error and $error =~ /char 26/);
    ok(defined $error and $error =~ /byte 27/);
    ok(defined $error and $error =~ /line 1/);
    ok(defined $error and $error =~ /, col 26/);
    ok(defined $error and $error =~ /byte col 27/);
    ok(defined JSON::DWIW->get_error_string);

    $str = qq{{"test":"\xc3\xa4",\n"funky":"\\u70":"key":"val"}};
    ($data, $error) = JSON::DWIW->from_json($str);
    ok(defined $error and $error =~ /char 27/);
    ok(defined $error and $error =~ /byte 28/);
    ok(defined $error and $error =~ /line 2/);
    ok(defined $error and $error =~ /, col 14/);
    ok(defined $error and $error =~ /byte col 14/);

    $str = qq{{"test":"\xc3\xa4","test2":"}};
    ($data, $error) = JSON::DWIW->from_json($str);
    ok(defined $error and $error =~ /unterminated string starting at byte 22/);
    ok(defined $error and $error =~ /char 22/);
    ok(defined $error and $error =~ /byte 23/);

    $str = qq|{"var1":1,"var2":"val2","var3":[1,2,3,4,5], "test":true, "check":null}\n{"var4":"val4"}|;
    ($data, $error) = JSON::DWIW->from_json($str);
    ok(defined $error);

    
    ($data, $error) = $json_obj->from_json($str);
    ok(defined $json_obj->get_error_string);

}

exit 0;

###############################################################################
# Subroutines

