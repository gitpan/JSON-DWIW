#!/usr/bin/env perl

# Creation date: 2007-02-20 19:51:06
# Authors: don

use strict;
use Test;

# main
{
    BEGIN { plan tests => 14 }

    use JSON::DWIW;

    my $data;

    #    my $expected_str = '{"var1":"val1","var2":["first_element",{"sub_element":"sub_val","sub_element2":"sub_val2"}],"var3":"val3"}';

    my $expected_str1 = '{"var1":"val1","var2":["first_element",{"sub_element":"sub_val","sub_element2":"sub_val2"}]}';
    my $expected_str2 = '{"var2":["first_element",{"sub_element":"sub_val","sub_element2":"sub_val2"}],"var1":"val1"}';
    my $expected_str3 = '{"var2":["first_element",{"sub_element2":"sub_val2","sub_element":"sub_val"}],"var1":"val1"}';
    my $expected_str4 = '{"var1":"val1","var2":["first_element",{"sub_element2":"sub_val2","sub_element":"sub_val"}]}';

    my $json_obj = JSON::DWIW->new;
    my $json_str;
    # print STDERR "\n" . $json_str . "\n\n";

    my $expected_str;

    $data = 'stuff';
    $json_str = $json_obj->to_json($data);
    ok($json_str eq '"stuff"');

    $data = "stu\nff";
    $json_str = $json_obj->to_json($data);
    ok($json_str eq '"stu\nff"');

    $data = [ 1, 2, 3 ];
    $expected_str = '[1,2,3]';
    $json_str = $json_obj->to_json($data);

    ok($json_str eq $expected_str);

    $data = { var1 => 'val1', var2 => 'val2' };
    $json_str = $json_obj->to_json($data);

    ok($json_str eq '{"var1":"val1","var2":"val2"}'
       or $json_str eq '{"var2":"val2","var1":"val1"}');
    
    $data = { var1 => 'val1',
              var2 => [ 'first_element',
                        { sub_element => 'sub_val', sub_element2 => 'sub_val2' },
                      ],
              #                 var3 => 'val3',
            };

    $json_str = $json_obj->to_json($data);

    ok($json_str eq $expected_str1 or $json_str eq $expected_str2
       or $json_str eq $expected_str3 or $json_str eq $expected_str4);

    $data = '';
    $json_str = $json_obj->to_json($data);
    ok($json_str eq '""');

    $data = { str => '' };
    $json_str = $json_obj->to_json($data);
    ok($json_str eq '{"str":""}');

    $data = [ "1", "" ];
    $json_str = $json_obj->to_json($data);
    ok($json_str eq '["1",""]');

    $data = undef;
    $json_str = $json_obj->to_json($data);
    ok($json_str eq 'null');

    $data = [undef];
    $json_str = $json_obj->to_json($data);
    ok($json_str eq '[null]');

    $data = { var => undef };
    $json_str = $json_obj->to_json($data);
    ok($json_str eq '{"var":null}');


    $data = {
             body => 'foo blarg <a href="http://example.com/?id=386">adfasdf</a>',
            };
    $json_str = $json_obj->to_json($data);
    ok($json_str eq '{"body":"foo blarg <a href=\"http:\/\/example.com\/?id=386\">adfasdf<\/a>"}');

    $data = { stuff => "Don's test string" };
    $json_str = $json_obj->to_json($data);
    ok($json_str eq q{{"stuff":"Don's test string"}});

    $data = { stuff => "http://example.com/" };
    $json_str = $json_obj->to_json($data);
    $json_str = $json_obj->to_json({ test => $json_str });
    ok($json_str eq '{"test":"{\\"stuff\\":\\"http:\\\\\\/\\\\\\/example.com\\\\\\/\\"}"}');
    

}

exit 0;

###############################################################################
# Subroutines

