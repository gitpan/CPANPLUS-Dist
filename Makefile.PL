#!/usr/bin/perl
# $File: //member/autrijus/CPANPLUS-Dist/Makefile.PL $ $Author: autrijus $
# $Revision: #2 $ $Change: 7721 $ $DateTime: 2003/08/26 10:53:44 $

use 5.00503;
use ExtUtils::MakeMaker;

print << '.';
### PLEASE NOTE ###################################################

Please note that this module is *HIGHLY EXPERIMENTAL*.

Its API is subject to change during the CPANPLUS 0.05x development.
This version only works with CPANPLUS 0.043 and *NOTHING ELSE*.

###################################################################
.

WriteMakefile(
    AUTHOR		=> 'Autrijus Tang (autrijus@autrijus.org)',
    ABSTRACT		=> 'Interface Vendor distribution formats for CPANPLUS',
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
