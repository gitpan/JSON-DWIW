# Creation date: 2007-02-19 16:54:44
# Authors: don
#
# Copyright (c) 2007 Don Owens <don@regexguy.com>.  All rights reserved.
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.  See perlartistic.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE.

=pod

=head1 NAME

JSON::DWIW - JSON converter that Does What I Want

=head1 SYNOPSIS

 use JSON::DWIW;
 my $json_obj = JSON::DWIW->new;
 my $data = $json_obj->from_json($json_str);
 my $str = $json_obj->to_json($data);

 my $data = JSON::DWIW->from_json($json_str);
 my $str = JSON:DWIW->to_json($data);

 my $data = JSON::DWIW->from_json($json_str, \%options);
 my $str = JSON::DWIW->to_json($data, \%options);

 my $true_value = JSON::DWIW->true;
 my $false_value = JSON::DWIW->false;
 my $data = { var1 => "stuff", var2 => $true_value,
              var3 => $false_value, };
 my $str = JSON::DWIW->to_json($data);

 use JSON::DWIW qw(:all);
 my $data = from_json($json_str);
 my $str = to_json($data);

=head1 DESCRIPTION

Other JSON modules require setting several parameters before
calling the conversion methods to do what I want.  This module
does things by default that I think should be done when working
with JSON in Perl.  This module also encodes and decodes faster
than JSON.pm and JSON::Syck in my benchmarks.

This means that any piece of data in Perl (assuming it's valid
unicode) will get converted to something in JSON instead of
throwing an exception.  It also means that output will be strict
JSON, while accepted input will be flexible, without having to
set any options.

=head2 Encoding

Perl objects get encoded as their underlying data structure, with
the exception of Math::BigInt and Math::BigFloat, which will be
output as numbers, and JSON::DWIW::Boolean, which will get output
as a true or false value (see the true() and false() methods).
For example, a blessed hash ref will be represented as an object
in JSON, a blessed array will be represented as an array. etc.  A
reference to a scalar is dereferenced and represented as the
scalar itself.  Globs, Code refs, etc., get stringified, and
undef becomes null.

Scalars that have been used as both a string and a number will be
output as a string.  A reference to a reference is currently
output as an empty string, but this may change.

=head2 Decoding

When decoding, null, true, and false become undef, 1, and 0,
repectively.  Numbers that appear to be too long to be supported
natively are converted to Math::BigInt or Math::BigFloat objects,
if you have them installed.  Otherwise, long numbers are turned
into strings to prevent data loss.

The parser is flexible in what it accepts and handles some
things not in the JSON spec:

=over 4

=item quotes

 Both single and double quotes are allowed for quoting a string, e.g.,

    [ "string1", 'string2' ]

=item bare keys

 Object/hash keys can be bare if they look like an identifier, e.g.,

    { var1: "myval1", var2: "myval2" }

=item extra commas

 Extra commas in objects/hashes and arrays are ignored, e.g.,

    [1,2,3,,,4,]

 becomes a 4 element array containing 1, 2, 3, and 4.


=back

=cut

use strict;
use warnings;

use 5.006_00;

use JSON::DWIW::Boolean;

package JSON::DWIW;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require Exporter;
require DynaLoader;
# @ISA = qw(Exporter DynaLoader);
@ISA = qw(DynaLoader);
package JSON::DWIW;
@EXPORT = ( );
@EXPORT_OK = ();
%EXPORT_TAGS = (all => [ 'to_json', 'from_json' ]);

Exporter::export_ok_tags('all');

our $VERSION = '0.10';

{
    package JSON::DWIW::Exporter;
    use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    @ISA = qw(Exporter);

    *EXPORT = \@JSON::DWIW::EXPORT;
    *EXPORT_OK = \@JSON::DWIW::EXPORT_OK;
    *EXPORT_TAGS = \%JSON::DWIW::EXPORT_TAGS;

    sub import {
        JSON::DWIW::Exporter->export_to_level(2, @_);
    }

    sub to_json {
        return JSON::DWIW->to_json(@_);
    }

    sub from_json {
        return JSON::DWIW->from_json(@_);
    }
}

sub import {
    JSON::DWIW::Exporter::import(@_);
}

package JSON::DWIW;
bootstrap JSON::DWIW $VERSION;

package JSON::DWIW;

{
    # workaround for weird importing bug on some installations
    local($SIG{__DIE__}); 
    eval qq{ 
        use Math::BigInt; 
        use Math::BigFloat;
    };
} 


=pod

=head1 METHODS

=head2 new(\%options)

 Create a new JSON::DWIW object.

 %options is an optional hash of parameters that will change the
 bahavior of this module when encoding to JSON.  You may also
 pass these options as the second argument to to_json() and
 from_json().  The following options are supported:

=head3 bare_keys

 If set to a true value, keys in hashes will not be quoted when
 converted to JSON if they look like identifiers.  This is valid
 Javascript in current browsers, but not in JSON.

=head3 use_exceptions

 If set to a true value, errors found when converting to or from
 JSON will result in die() being called with the error message.
 The default is to not use exceptions.

=head3 bad_char_policy

 This options indicates what should be done if bad characters are
 found, e.g., bad utf-8 sequence.  The default is to return an
 error and drop all the output.

 The following values for bad_char_policy are supported:

=head4 error

 default action, i.e., drop any output built up and return an error

=head4 convert

 Convert to a utf-8 char using the value of the byte as a code
 point.  This is basically the same as assuming the bad character
 is in latin-1 and converting it to utf-8.

=head4 pass_through

 Ignore the error and pass through the raw bytes (invalid JSON)

=head3 escape_multi_byte

 If set to a true value, escape all multi-byte characters (e.g.,
 \u00e9) when converting to JSON.

=head3 pretty

 Add white space to the output when calling to_json() to make the
 output easier for humans to read.

=head3 convert_bool

 When converting from JSON, return objects for booleans so that
 "true" and "false" can be maintained when encoding and decoding.
 If this flag is set, then "true" becomes a JSON::DWIW::Boolean
 object that evaluates to true in a boolean context, and "false"
 becomes an object that evaluates to false in a boolean context.
 These objects are recognized by the to_json() method, so they
 will be output as "true" or "false" instead of "1" or "0".

=cut

sub new {
    my $proto = shift;

    my $self = bless {}, ref($proto) || $proto;
    my $params = shift;
    
    return $self unless $params;

    unless (defined($params) and UNIVERSAL::isa($params, 'HASH')) {
        return $self;
    }

    foreach my $field (qw/bare_keys use_exceptions bad_char_policy dump_vars pretty
                          escape_multi_byte convert_bool/) {
        if (exists($params->{$field})) {
            $self->{$field} = $params->{$field};
        }
    }

    return $self;
}

=pod

=head2 to_json($data)

 Returns the JSON representation of $data (arbitrary
 datastructure).  See http://www.json.org/ for details.

 Called in list context, this method returns a list whose first
 element is the encoded JSON string and the second element is an
 error message, if any.  If $error_msg is defined, there was a
 problem converting to JSON.  You may also pass a second argument
 to to_json() that is a reference to a hash of options -- see
 new().

     my $json_str = JSON::DWIW->to_json($data);

     my ($json_str, $error_msg) = JSON::DWIW->to_json($data);

     my $json_str = JSON::DWIW->to_json($data, { use_exceptions => 1 });

 Aliases: toJson, toJSON, objToJson

=cut

sub to_json {
    my $proto = shift;
    my $data;
    
    my $self;
    if (UNIVERSAL::isa($proto, 'JSON::DWIW')) {
        $data = shift;
        my $options = shift;
        if ($options) {
            if (ref($proto) and $proto->isa('HASH')) {
                if (UNIVERSAL::isa($options, 'HASH')) {
                    $options = { %$proto, %$options };
                }
            }

            $self = $proto->new($options, @_);
        }
        else {
            $self = ref($proto) ? $proto : $proto->new(@_);
        }
    }
    else {
        $data = $proto;
        $self = JSON::DWIW->new(@_);
    }

    my $error_msg;
    my $str = _xs_to_json($self, $data, \$error_msg); # call as non-OO for speed, but pass $self
    if (defined($error_msg) and $self->{use_exceptions}) {
        die $error_msg;
    }
    return wantarray ? ($str, $error_msg) : $str;
}
{
    no warnings 'once';
    
    *toJson = \&to_json;
    *toJSON = \&to_json;
    *objToJson = \&to_json;
}

=pod

=head2 my ($data, $error_msg) = from_json($json_str)

 Returns the Perl data structure for the given JSON string.  The
 value for true becomes 1, false becomes 0, and null gets
 converted to undef.

 Called in list context, this method returns a list whose first
 element is the data and the second element is the error message,
 if any.  If $error_msg is defined, there was a problem parsing
 the JSON string, and $data will be undef.  You may also pass a
 second argument to from_json() that is a reference to a hash of
 options -- see new().

     my $data = from_json($json_str)

     my ($data, $error_msg) = from_json($json_str)

     my $data = from_json($json_str, { use_exceptions => 1 })


 Aliases: fromJson, fromJSON, jsonToObj

=cut

sub from_json {
    my $proto = shift;
    my $json;
    my $self;

    if (UNIVERSAL::isa($proto, 'JSON::DWIW')) {
        $json = shift;
        my $options = shift;
        if ($options) {
            if (ref($proto) and $proto->isa('HASH')) {
                if (UNIVERSAL::isa($options, 'HASH')) {
                    $options = { %$proto, %$options };
                }
            }

            $self = $proto->new($options, @_);
        }
        else {
            $self = ref($proto) ? $proto : $proto->new(@_);
        }
    }
    else {
        $json = $proto;
        $self = JSON::DWIW->new(@_);
    }

    my $error_msg;
    my $data = _xs_from_json($self, $json, \$error_msg);
    if (defined($error_msg) and $self->{use_exceptions}) {
        die $error_msg;
    }

    return wantarray ? ($data, $error_msg) : $data;
}

{
    no warnings 'once';
    *jsonToObj = \&from_json;
    *fromJson = \&from_json;
    *fromJSON = \&from_json;
}

=pod

=head2 true()

 Returns an object that will get output as a true value when encoding to JSON.

=cut

sub true {
    return JSON::DWIW::Boolean->true;
}

=pod

=head2 false()

 Returns an object that will get output as a false value when encoding to JSON.

=cut

sub false {
    return JSON::DWIW::Boolean->false;
}

=pod

=head1 BENCHMARKS

 Latest benchmarks against JSON and JSON::Syck run on my MacBook
 Pro:

 Using a small data set:

    Encode (50000 iterations):
    ==========================
                  Rate       JSON JSON::Syck JSON::DWIW
    JSON        2648/s         --       -72%       -86%
    JSON::Syck  9416/s       256%         --       -51%
    JSON::DWIW 19380/s       632%       106%         --


    Decode (50000 iterations):
    ==========================
                  Rate       JSON JSON::Syck JSON::DWIW
    JSON        2288/s         --       -81%       -93%
    JSON::Syck 12195/s       433%         --       -60%
    JSON::DWIW 30675/s      1240%       152%         --


 Using a larger data set (8KB JSON string) generated from Yahoo!
 Local's search API (http://nanoref.com/yahooapis/mgPdGg)


    Encode (1000 iterations):
    =========================
                Rate       JSON JSON::Syck JSON::DWIW
    JSON       133/s         --       -54%       -66%
    JSON::Syck 289/s       118%         --       -26%
    JSON::DWIW 389/s       193%        35%         --


    Decode (1000 iterations):
    =========================
                 Rate       JSON JSON::Syck JSON::DWIW
    JSON       35.5/s         --       -92%       -94%
    JSON::Syck  427/s      1103%         --       -25%
    JSON::DWIW  571/s      1508%        34%         --


=head1 DEPENDENCIES

Perl 5.6 or later

=head1 BUGS/LIMITATIONS

If you find a bug, please file a tracker request at
<http://rt.cpan.org/Public/Dist/Display.html?Name=JSON-DWIW>.

When decoding a JSON string, it is a assumed to be utf-8 encoded.
The module should detect whether the input is utf-8, utf-16, or
utf-32.

=head1 AUTHOR

Don Owens <don@regexguy.com>

=head1 ACKNOWLEDGEMENTS

Thanks to Asher Blum for help with testing.

Thanks to Nigel Bowden for helping with compilation on Windows.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2007 Don Owens <don@regexguy.com>.  All rights reserved.

This is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.  See perlartistic.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.

=head1 SEE ALSO

 The JSON home page: L<http://json.org/>
 The JSON spec: L<http://www.ietf.org/rfc/rfc4627.txt>
 The JSON-RPC spec: L<http://json-rpc.org/wd/JSON-RPC-1-1-WD-20060807.html>

 L<JSON>
 L<JSON::Syck> (included in L<YAML::Syck>)

=head1 VERSION

0.10

=cut

1;

# Local Variables: #
# mode: perl #
# tab-width: 4 #
# indent-tabs-mode: nil #
# cperl-indent-level: 4 #
# perl-indent-level: 4 #
# End: #
# vim:set ai si et sta ts=4 sw=4 sts=4:
