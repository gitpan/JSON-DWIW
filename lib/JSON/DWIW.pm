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

 my $json_obj = JSON::DWIW->new;
 my $data = $json_obj->from_json($json_str);
 my $str = $json_obj->to_json($data);

 my $data = JSON::DWIW->from_json($json_str);
 my $str = JSON:DWIW->to_json($data);
 

=head1 DESCRIPTION

Other JSON modules require setting several parameters before
calling the conversion methods to do what I want.  This module
does things by default that I think should be done when working
with JSON in Perl.  This module also encodes and decodes faster
than JSON.pm and JSON::Syck in my benchmarks.

This means that any piece of data in Perl will get converted to
something in JSON instead of throwing an exception.  It also
means that output will be strict JSON, while accepted input will
be flexible, without having to set any options.

=head2 Encoding

Perl objects get encoded as their underlying data structure.  For
example, a blessed hash ref will be represented as an object in
JSON, a blessed array will be represented as an array. etc.  A
reference to a scalar is dereferenced and represented as the
scalar itself.  Globs, filehandles, etc., get stringified.

=head2 Decoding

When decoding, null, true, and false become undef, 1, and 0,
repectively.

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

package JSON::DWIW;

use vars qw(@ISA @EXPORT);

require Exporter;
require DynaLoader;
@ISA = qw(Exporter DynaLoader);
package JSON::DWIW;
@EXPORT = qw( );

our $VERSION = '0.04';

package JSON::DWIW;
bootstrap JSON::DWIW $VERSION;

package JSON::DWIW;

=pod

=head1 METHODS

=head2 new(\%options)

 Create a new JSON::DWIW object.

 %options is an optional hash of parameters that will change the
 bahavior of this module when encoding to JSON.  The following
 options are supported:

=over 4

=item bare_keys

 If set to a true value, keys in hashes will not be quoted when
 converted to JSON if they look like identifiers.  This is valid
 Javascript in current browsers, but not in JSON.

=back

=cut

sub new {
    my $proto = shift;

    my $self = bless {}, ref($proto) || $proto;
    my $params = shift;
    
    return $self unless $params;

    unless (defined($params) and UNIVERSAL::isa($params, 'HASH')) {
        return $self;
    }

    foreach my $field (qw/bare_keys/) {
        if ($params->{$field}) {
            $self->{$field} = 1;
        }
    }

    return $self;
}

=pod

=head2 my $json_str = to_json($data)

 Returns the JSON representation of $data (arbitrary
 datastructure).  See http://www.json.org/ for details.

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

    # my $self = ref($proto) ? $proto : $proto->new(@_);
    # return _to_json($self, $data); # call as non-OO for speed, but pass $self
    return _xs_to_json($self, $data); # call as non-OO for speed, but pass $self
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

 Called in list context, this method returns a where the first
 element is the data and the second element is the error message,
 if any.  If $error_msg is defined, there was a problem parsing
 the JSON string, and $data will be undef.

 Aliases: fromJson, fromJSON, jsonToObj

=cut
sub from_json {
    my $proto = shift;
    my $json;
    my $self;

    if (UNIVERSAL::isa($proto, 'JSON::DWIW')) {    
        $json = shift;
        $self = ref($proto) ? $proto : $proto->new(@_);
    }
    else {
        $json = $proto;
        $self = JSON::DWIW->new;
    }

    # my $self = ref($proto) ? $proto : $proto->new(@_);

    my $error_msg;
    my $data = _xs_from_json($self, $json, \$error_msg);
    # return $data;
    return wantarray ? ($data, $error_msg) : $data;
}

{
    no warnings 'once';
    *jsonToObj = \&from_json;
    *fromJson = \&from_json;
    *fromJSON = \&from_json;
}


=pod

=head1 BENCHMARKS

 Latest benchmarks against JSON and JSON::Syck run on my MacBook
 Pro:

 Using a small data set:

    Encode (50000 iterations):
    ==========================
                  Rate       JSON JSON::Syck JSON::DWIW
    JSON        2670/s         --       -72%       -89%
    JSON::Syck  9416/s       253%         --       -61%
    JSON::DWIW 24155/s       805%       157%         --


    Decode (50000 iterations):
    ==========================
                  Rate       JSON JSON::Syck JSON::DWIW
    JSON        2300/s         --       -81%       -93%
    JSON::Syck 12195/s       430%         --       -64%
    JSON::DWIW 33784/s      1369%       177%         --



 Using a larger data set (8KB JSON string) generated from Yahoo!
 Local's search API (http://nanoref.com/yahooapis/mgPdGg)

    Encode (1000 iterations):
    =========================
                Rate       JSON JSON::Syck JSON::DWIW
    JSON       135/s         --       -54%       -74%
    JSON::Syck 290/s       115%         --       -45%
    JSON::DWIW 526/s       291%        82%         --


    Decode (1000 iterations):
    =========================
                 Rate       JSON JSON::Syck JSON::DWIW
    JSON       35.9/s         --       -92%       -94%
    JSON::Syck  444/s      1137%         --       -25%
    JSON::DWIW  595/s      1557%        34%         --



=head1 DEPENDENCIES

Perl 5.6 or later

=head1 AUTHOR

Don Owens <don@regexguy.com>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2007 Don Owens <don@regexguy.com>.  All rights reserved.

This is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.  See perlartistic.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.

=head1 SEE ALSO

 JSON
 JSON::Syck (included in YAML::Syck)

=head1 VERSION

 0.04

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
