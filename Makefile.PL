#!/usr/bin/env perl

# Creation date: 2007-02-19 16:49:01
# Authors: don

use strict;

use 5.006_00;
    
use ExtUtils::MakeMaker;
use File::Spec;

my $src_dir = 'libjsonevt';

my $on_windows;
# for stuff to skip/change on Windows
if ($^O =~ /MSWin/) {
    $on_windows = 1;
    # $use_jsonevt = 0;
}

my @utf_files = qw/utf8 utf16 utf32/;
my @utf_headers = map { "$_.h" } @utf_files;

my $obj_str = join(' ', map { "$_\$(OBJ_EXT)" } @utf_files, 'evt', 'jsonevt', 'old_parse',
                   'old_common');

sub MY::postamble {
    my ($self) = @_;

    my $stuff = '';

    my $exec_output_name = sub { my ($name) = @_;
                                 if ($on_windows and $self->{CC}
                                     and $self->{CC} =~ /\Acl(?:\.exe)?\Z/) {
                                     return "/Fe$name";
                                 }
                                 else {
                                     return "-o $name";
                                 }
                             };
    
    my $cc = '$(CCCMD) $(CCCDLFLAGS) "-I$(PERL_INC)" $(PASTHRU_DEFINE) $(DEFINE) ';
    my $cc_main = '$(CC) $(PASTHRU_INC) $(INC) $(CCFLAGS) $(OPTIMIZE) $(PERLTYPE) $(MPOLLUTE) $(DEFINE_VERSION) $(XS_DEFINE_VERSION) ';
    my $config_h = File::Spec->catfile($src_dir, 'jsonevt_config.h');

    $stuff .= "\$(INST_DYNAMIC): $obj_str $config_h\n\n";
    
    $stuff .= "evt\$(OBJ_EXT): evt.c\n\n";
    $stuff .= "old_parse\$(OBJ_EXT): old_parse.c old_parse.h old_common.h\n\n";
    $stuff .= "old_common\$(OBJ_EXT): old_common.c old_common.h\n\n";
    $stuff .= "DWIW\$(OBJ_EXT): DWIW.h old_parse.h old_common.h $config_h\n\n";
    # $stuff .= "DWIW.c: DWIW.h old_parse.h old_common.h $config_h\n\n";

    my $make_conf = File::Spec->catfile($src_dir, 'make_config');
    # my $exec_make_conf = File::Spec->rel2abs('make_config');
    my $exec_make_conf = File::Spec->rel2abs($make_conf);
    $exec_make_conf .= " $config_h " . $cc;

#     print "\n\nmake_conf=$make_conf\n\n";
#     print "cc_main=$cc_main\n\n";
    
    $stuff .= "$obj_str: $config_h\n\n";

    $stuff .= "$config_h: $make_conf\n\t$exec_make_conf\n\n";
    $stuff .= "$make_conf: $make_conf.c\n\t$cc_main " . $exec_output_name->($make_conf)
        . " $make_conf.c\n\n";
    
    $stuff .= "jsonevt\$(OBJ_EXT): ";
    $stuff .= join(' ', map { File::Spec->catfile($src_dir, $_) }
                   ('jsonevt.h', 'jsonevt_private.h', @utf_headers, 'uni.h', 'jsonevt.c'));
    $stuff .= "\n";
    $stuff .= "\t$cc " . File::Spec->catfile($src_dir, 'jsonevt.c') . "\n";
    $stuff .= "\n";
    
    foreach my $file (@utf_files) {
        $stuff .= "$file\$(OBJ_EXT): ";
        $stuff .= join(' ', map { File::Spec->catfile($src_dir, $_) }
                       ("$file.c", "$file.h", 'uni.h'));
        $stuff .= "\n";
        
        # . File::Spec->catfile($src_dir, 'utf8.c') . "\n";
        $stuff .= "\t" . '$(CCCMD) $(CCCDLFLAGS) "-I$(PERL_INC)" $(PASTHRU_DEFINE) $(DEFINE) ';
        $stuff .= File::Spec->catfile($src_dir, "$file.c") . "\n";
        $stuff .= "\n";
    }
    
    return $stuff;
}

my $clean_str = join(' ', map { File::Spec->catfile('libjsonevt', $_) }
                     ('*.a', '*.so', '*$(OBJ_EXT)'));

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
            clean => { FILES => $clean_str },
            # OPTIMIZE => '-Wall -O3 -fno-non-lvalue-assign -g',
            # OPTIMIZE => '-O2 -g -Wall',
           };

$args->{DEFINE} = "-DHAVE_JSONEVT -DNO_VERSION_IN_ERROR";
$args->{LDFROM} = "\$(OBJECT) $obj_str";
$args->{INC} = "-I$src_dir";

WriteMakefile(%$args);


