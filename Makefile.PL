#!/usr/bin/perl
# $File: //member/autrijus/CPANPLUS-Dist/Makefile.PL $ $Author: autrijus $
# $Revision: #3 $ $Change: 7761 $ $DateTime: 2003/08/28 14:44:41 $

use 5.00503;
use ExtUtils::MakeMaker;

print << '.';
### PLEASE NOTE ###################################################

Please note that this module is *HIGHLY EXPERIMENTAL*.

Its API is subject to change during the CPANPLUS 0.05x development.
This version only works with CPANPLUS 0.043 and *NOTHING ELSE*.

Currently, only Ports, PAR and PPM work; the RPM backend is utterly
non-functional.

###################################################################
.

WriteMakefile(
    AUTHOR		=> 'Autrijus Tang (autrijus@autrijus.org)',
    ABSTRACT		=> 'Interface to package managers for CPANPLUS',
    NAME		=> 'CPANPLUS::Dist',
    VERSION_FROM	=> 'lib/CPANPLUS/Dist.pm', 
    DISTNAME		=> 'CPANPLUS-Dist',

    PREREQ_PM		=> {
	'CPANPLUS'	=> 0.043,
    },

    dist		=> {
        COMPRESS	=> 'gzip -9',
        SUFFIX		=> '.gz',
    },
);
