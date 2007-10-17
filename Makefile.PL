#!/usr/bin/env perl

# Creation date: 2007-02-19 16:49:01
# Authors: don

use strict;
use Carp;

# main
{
    local($SIG{__DIE__}) = sub { &Carp::confess };

    use 5.006_00;
    
    use ExtUtils::MakeMaker;

    WriteMakefile(
                  NAME => 'JSON::DWIW',
                  DISTNAME => 'JSON-DWIW',
                  VERSION_FROM => 'lib/JSON/DWIW.pm',
                  ABSTRACT => 'JSON converter that does what I want',
                  AUTHOR => 'DON OWENS <don@regexguy.com>',
                  PM => { 'lib/JSON/DWIW.pm' => '$(INST_LIBDIR)/DWIW.pm',
                          'lib/JSON/DWIW/Boolean.pm' => '$(INST_LIBDIR)/DWIW/Boolean.pm',
                        },
                  dist => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
                  DIR => [],
                  EXE_FILES => [],
                  PREREQ_PM => {
                               },
                  
                  # OPTIMIZE => '-Wall -O3',
                  );


}

exit 0;

###############################################################################
# Subroutines

