#!/usr/bin/env perl

# Creation date: 2007-02-19 16:49:01
# Authors: don

use strict;

use 5.006_00;
    
use ExtUtils::MakeMaker;
use File::Spec;

my $src_dir = 'libjsonevt';

my $use_jsonevt = 1;

# skip on Windows for now
if ($^O =~ /MSWin/) {
    # $use_jsonevt = 0;
}

sub MY::postamble {
    my $stuff = '';

    if ($use_jsonevt) {
        $stuff .= "\$(INST_DYNAMIC): evt\$(OBJ_EXT) jsonevt\$(OBJ_EXT)\n\n";
        $stuff .= "evt\$(OBJ_EXT): evt.c\n\n";
        $stuff .= "jsonevt\$(OBJ_EXT): " . File::Spec->catfile($src_dir, 'jsonevt.c') . " ";
        $stuff .= join(' ', map { File::Spec->catfile($src_dir, $_) }
                       ('jsonevt.h', 'jsonevt_private.h', 'jsonevt.c'));
        $stuff .= "\n";
        $stuff .= "\t" . '$(CCCMD) $(CCCDLFLAGS) "-I$(PERL_INC)" $(PASTHRU_DEFINE) $(DEFINE) ';
        $stuff .= File::Spec->catfile($src_dir, 'jsonevt.c') . "\n";
        $stuff .= "\n";
    }

    return $stuff;
}

my $args = {
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
            OPTIMIZE => '-Wall -O3 -fno-non-lvalue-assign -g',
           };

if ($use_jsonevt) {
    $args->{DEFINE} = "-DHAVE_JSONEVT -DNO_VERSION_IN_ERROR";
    $args->{LDFROM} = "\$(OBJECT) jsonevt\$(OBJ_EXT) evt\$(OBJ_EXT)";
    $args->{INC} = "-I$src_dir";
}

WriteMakefile(%$args);


