#!/usr/bin/env perl

# Creation date: 2008-03-26 07:19:22
# Authors: don

use strict;
use warnings;

use Test;

BEGIN { plan tests => 3 }

use JSON::DWIW;

my $json_str;
my $data;

# rt.cpan.org #33121 -- "Escaped quotes cause JSON::DWIW::deserialize to crash Perl"
JSON::DWIW::deserialize( q([{'aaaaaa':"bbbbbbbbbbbbbbb\\"ccccc\\"dd"}]) );
ok(1); # used to abort here on Linux

# rt.cpan.org #34285 -- accept hex escape sequences
$json_str = '{"key":"\x76al"}';
$data = JSON::DWIW::deserialize($json_str);
ok($data and $data->{key} eq 'val');

# rt.cpan.org #34320 -- accept $ in bare keys
$json_str = '{$var1:true,var2:false,var3:null}';
$data = JSON::DWIW::deserialize($json_str);
ok(ref($data) eq 'HASH' and $data->{'$var1'} and not $data->{var2}
   and exists($data->{var3}) and not defined($data->{var3}));

