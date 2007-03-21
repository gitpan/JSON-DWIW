#!/usr/bin/env perl

# Creation date: 2007-03-20 18:01:54
# Authors: don

use strict;
use warnings;
use Test;

# main
{
    BEGIN { plan tests => 9 }

    use JSON::DWIW;

    # bare keys
    my $json_str = '{var1:true,var2:false,var3:null}';
    my $data = JSON::DWIW->from_json($json_str);
    
    ok(ref($data) eq 'HASH');
    ok(ref($data) eq 'HASH' and $data->{var1});
    ok(ref($data) eq 'HASH' and not $data->{var2});
    ok(ref($data) eq 'HASH' and exists($data->{var3}) and not defined($data->{var3}));


    # extra commas
    $json_str = '{,"var1":true,,"var2":false,"var3":null,, ,}';
    $data = JSON::DWIW->from_json($json_str);
    ok(ref($data) eq 'HASH');
    ok(ref($data) eq 'HASH' and $data->{var1});
    ok(ref($data) eq 'HASH' and not $data->{var2});
    ok(ref($data) eq 'HASH' and exists($data->{var3}) and not defined($data->{var3}));

    
    # C++ style comments
    $json_str = '{"test_empty_hash":{} ' . "\n" . '//,"test_empty_array":[] ' . "\n" . '}';
    $data = JSON::DWIW->from_json($json_str);
    ok(ref($data) eq 'HASH' and scalar(keys(%$data)) == 1
       and ref($data->{test_empty_hash}) eq 'HASH'
       and scalar(keys %{$data->{test_empty_hash}}) == 0);
}

exit 0;

###############################################################################
# Subroutines

