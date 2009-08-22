
=pod

=head1 NAME

JSON::DWIW::Changes - List of significant changes to JSON::DWIW

=head1 CHANGES

=head2 Version 0.36 (Sat 2009-08-22)

=over 4

=item Added ascii, bare_solidus, and minimal_escaping options.

=item Began to use Test::More for some of the unit tests.

=back


=head2 Version 0.35

=over 4

=item Apparent fix for [rt.cpan.org #47344].

=back

=head2 Version 0.34

=over 4

=item Fixed another memory leak, this time while inserting into a hash

=back

=head2 Version 0.33

=over 4

=item Fixed memory leak -- the stack was getting allocated in
init_cbs(), but never deallocated.

=back

=head2 Version 0.32

=over 4

=item Fixed segfault on Solaris 10 (on Sparc) when compiled with
Sun Studio.  It was a 64-bit versus 32-bit bug on my part, but
apparently GCC catches this and does the right thing.

=back

=head2 Version 0.30

=over 4

=item Added _GNU_SOURCE define to pull in asprintf on some platforms

=back

=head2 Version 0.29

=over 4

=item Fixed another segfault problem on 64-bit Linux (in vset_error).

=back

=head2 Version 0.28

=over 4

=item Fixed segfault problem on 64-bit Linux (rt.cpan.org #40879)

=item Fixed test problem on Solaris (rt.cpan.org #41129)

=back

=cut
