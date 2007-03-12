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

# * handle references to scalars gracefully, e.g., \"NOW()"
# * check for overload stuff

=pod

=head1 NAME

 JSON::DWIW - JSON converter that Does What I Want

=head1 SYNOPSIS

 my $json_obj = JSON::DWIW->new
 my $data = $json_obj->from_json($json_str);
 my $str = $json_obj->to_json($data);

 my $data = JSON::DWIW->from_json($json_str);
 my $str = JSON:DWIW->to_json($data);
 

=head1 DESCRIPTION

Other JSON modules require setting several parameters before
calling the conversion methods to do what I want.  This module
does things by default that I think should be done when working
with JSON in Perl.  This module also encodes and decodes faster
than JSON.pm or JSON::Syck.

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

our $VERSION = '0.01';

package JSON::DWIW;
bootstrap JSON::DWIW $VERSION;

package JSON::DWIW;

=pod

=head1 METHODS


=cut

sub new {
    my $proto = shift;
    my $self = bless {}, ref($proto) || $proto;
    return $self;
}

=pod

=head2 my $json_str = to_json($data)

 Returns the JSON representation of $data (arbitrary
 datastructure).  See http://www.json.org/ for details

=cut
sub to_json {
    my $proto = shift;
    my $data = shift;
    
    my $self = ref($proto) ? $proto : $proto->new(@_);
    # return _to_json($self, $data); # call as non-OO for speed, but pass $self
    return _xs_to_json($self, $data); # call as non-OO for speed, but pass $self
}
{
    no warnings 'once';
    
    *toJson = \&to_json;
    *toJSON = \&to_json;
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

=cut
sub from_json {
    my $proto = shift;
    my $json = shift;

    my $self = ref($proto) ? $proto : $proto->new(@_);

    my $error_msg;
    my $data = _xs_from_json($self, $json, \$error_msg);
    # return $data;
    return wantarray ? ($data, $error_msg) : $data;
}


=pod

=head1 BENCHMARKS

Benchmark using a small amount of data:

    Encode (50000 iterations):
    ==========================
                  Rate       JSON JSON::Syck JSON::DWIW
    JSON        2820/s         --       -70%       -88%
    JSON::Syck  9328/s       231%         --       -60%
    JSON::DWIW 23474/s       732%       152%         --


    Decode (50000 iterations):
    ==========================
                  Rate       JSON JSON::Syck JSON::DWIW
    JSON        2168/s         --       -79%       -91%
    JSON::Syck 10504/s       384%         --       -55%
    JSON::DWIW 23364/s       978%       122%         --




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

 0.01

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
