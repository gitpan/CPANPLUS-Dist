# $File: //depot/cpanplus/devel/lib/CPANPLUS/Dist/Ports.pm $ $Author: autrijus $
# $Revision: #13 $ $Change: 4453 $ $DateTime: 2003/02/27 16:04:39 $

###################################################################
###                     CPANPLUS/Dist/Ports.pm                  ###
### Module to provide an interface to the FreeBSD Ports System  ###
###                Written 27-01-2003 by Autrijus Tang          ###
###################################################################

package CPANPLUS::Dist::Ports;

use strict;

use CPANPLUS::Dist;

use Config;
use Cwd;
use File::Spec ();
use File::Copy ();
use File::Basename ();
use CPANPLUS::I18N;
use CPANPLUS::Tools::Check qw[check];

use Data::Dumper;

BEGIN {
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( CPANPLUS::Dist );
    $VERSION    =   $CPANPLUS::Dist::VERSION;
}

### accessors ###
for my $key (qw[makefile distinfo pkg_comment pkg_descr pkg_plist dir] ) {
    no strict 'refs';
    *{__PACKAGE__."::$key"} = sub {
        my $self = shift;
        $self->{$key} = $_[0] if @_;
        return $self->{$key};
    }
}


### installs a ports by it's Makefile
### call it as: my $bool = $ports->install( makefile => '/path/to/Makefile' )
sub install {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $local_path = File::Spec->catdir(
                         $conf->_get_build('base'),
                         $conf->_get_ftp('base'),
                         $self->path,
                     );

    my $tmpl = {
        makefile    => { default => $dist->makefile, strict_type => 1 },
        make        => { default => $conf->get_conf('make') },
        verbose     => { default => $conf->get_conf('verbose') },
        target      => { default => 'reinstall' },
        flags       => { default => ['-DFORCE_PKG_REGISTER', "DISTDIR=$local_path"] }
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    return undef unless $args->{makefile};

    my $make     = $args->{make} || 'make';
    my $makefile = $args->{makefile} ||
                   $self->{dist}->{ports}->{makefile} ||
                   return undef;

    my $dir = File::Basename::dirname($makefile);
    unless( $dir eq cwd() ) {
        unless (chdir $dir) {
            $err->trap(
                error => loc("%1 couldn't chdir to %2! I am in %3 now", 'install()', $dir, cwd()),
            );
            return undef;
        }
    }

    my $captured;
    my $rv = $obj->_run(
        command => [$make, $args->{target}, @{$args->{flags}}],
        buffer  => \$captured,
        verbose => 1
    );

    if (!$rv) {
        $err->trap( error => loc("Unable to install %1: %2", $makefile, '') );
        return undef;
    }

    $obj->_run(
        command => [$make, 'clean', @{$args->{flags}}],
        verbose => 1
    );

    $err->inform(
        msg     => loc("%1 installed succesfully", $makefile),
        quiet   => !$args->{verbose},
    );
    return $rv;
}

### uninstalls a ports by it's makefile
### call it as: my $bool = $ports->uninstall( makefile => '/path/to/Makefile' )
sub uninstall {
    my $dist = shift;
    $dist->install(@_, target => 'deinstall')
}

### creates a ports from a build dir.. can take a dir optioninally as argument
### otherwise will take the dir stored in the module object
### note, this module object will have to be REBLESSED into the C::Dist::Ports package
### for this to work -kane
### call it as: my $rv = $ports->create( dir => '/extract/dir/where/module/was/maked' )
sub create {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = {
        verbose     => { default => $conf->get_conf('verbose') },
        force       => { default => $conf->get_conf('force') },
        makeflags   => { default => $conf->_get_build('makeflags') },
        make        => { default => $conf->_get_build('make') },
        perl        => { default => ($conf->_get_build('perl') || $^X) },
        builddir    => { default => $self->status->make_dir },
        portsdir    => { default => '/usr/ports' },
        category    => { default => 'devel' },
        prefix      => { default => 'p5-' },
        distdir     => { default => '', },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    unless ( $args->{builddir} ) {
        $err->trap( error => loc(qq[Don't know what dir to build in!] ) );
        return undef;
    }

    my $makeflags   = $args->{makeflags};
    my $make        = $args->{make};
    my $perl        = $args->{perl};
    my $dir         = $args->{builddir};
    my $category    = $args->{category};
    my $prefix      = $args->{prefix};
    my $portsdir    = $args->{portsdir};
    my $username    = $ENV{NAME} || 'CPANPLUS User';
    my $email       = $ENV{EMAIL} || '<cpanplus@example.com>';

    my $perl_version = $obj->_perl_version( perl => $perl );

    my ($name, $ver, $fh);

    $name = $self->package_name;
    $ver  = $self->package_version;

    if (!defined($name) or !defined($ver)) {
        $err->trap( error => loc(qq[Cannot build ports without a valid package name and version!] ) );
        return undef;
    }

    my $path = $args->{distdir}
                  || File::Spec->catdir(
                        $conf->_get_build('base'),
                        $perl_version,
                        $conf->_get_build('distdir'),
                        'ports',
                        $category,
                        "$prefix$name",
                     );

    my ($makefile, $distinfo, $pkg_comment, $pkg_descr, $pkg_plist)
        = map File::Spec->catfile($path, $_),
            qw(Makefile distinfo pkg-comment pkg-descr pkg-plist);

    ### store this for later use ###
    $dist->dir($path);

    unless (-d $path) {
        unless( $obj->_mkdir( dir => $path ) ) {
            $err->inform(
                msg   => loc("Could not create %1", $path),
                quiet => !$args->{'verbose'},
            );
            return undef;
        }
    }

    unless( $path eq cwd() ) {
        unless (chdir $path) {
            $err->trap(
                error => loc("create() couldn't chdir to %1! I am in %2 now", $dir, cwd()),
            );
            return undef;
        }
    }

    unless( open $fh, ">$makefile" ) {
        $err->trap( error => loc("Could not open %1 for writing: %2", $makefile, $!) );
    } else {
        my $date = join(' ', (split(/ /, scalar gmtime))[1, 2, -1]);
        my $subdir = "../../authors/id/" . $self->path;
        my $blib = File::Spec->catdir($args->{builddir}, 'blib');
        my @man1 = map File::Basename::basename($_), <$blib/man1/*.1>;
        my @man3 = map File::Basename::basename($_), <$blib/man3/*.3>;
        my @depends; # XXX: M::B will let us fine tune this

        my $prereq  = $self->status->prereq;
        my $modtree = $obj->module_tree;

        # analyze prereq
        foreach my $mod (sort keys %$prereq) {
            next unless my $obj = $modtree->{$mod};
            my $modname = eval { $obj->package } or next;
            $modname =~ s/-[\d._]+(?:\.tar\.gz|\.zip|\.tgz)$//i or next;

            my $ports_dir = (glob("$portsdir/*/$prefix$modname"))[0];
            $ports_dir =~ s!^\Q$portsdir\E!! if $dir;
            $ports_dir ||= "/$category/$prefix$modname";

            my $modfile = $mod;
            $modfile =~ s!::!/!g;

            my $local_dir;

            if (-e File::Spec->catfile($Config{installsitearch}, "$modfile.pm")) {
                $local_dir = '${SITE_PERL}/${PERL_ARCH}';
            }
            elsif (-e File::Spec->catfile($Config{installsitelib}, "$modfile.pm")) {
                $local_dir = '${SITE_PERL}';
            }
            elsif (-e File::Spec->catfile($Config{installarchlib}, "$modfile.pm")) {
                next;
            }
            elsif (-e File::Spec->catfile($Config{installprivlib}, "$modfile.pm")) {
                next;
            }
            else {
                # take a wild guess here
                $local_dir = '${SITE_PERL}';
            }

            push @depends, "$local_dir/$modfile.pm:\${PORTSDIR}$ports_dir";
        }

        my $build_depends = join(" \\\n\t\t", @depends);
        my $description = $self->{description} || $name;

        $build_depends &&= << ".";
BUILD_DEPENDS=	$build_depends
RUN_DEPENDS=	\${BUILD_DEPENDS}

.
        $fh->print(<< "EOF");
# New ports collection makefile for:	$category/$prefix$name
# Date created:				$date
# Whom:					$username $email
#
# \$FreeBSD\$
#

PORTNAME=	$name
PORTVERSION=	$ver
CATEGORIES=	$category perl5
MASTER_SITES=	\${MASTER_SITE_PERL_CPAN}
MASTER_SITE_SUBDIR=	$subdir
PKGNAMEPREFIX=	$prefix

MAINTAINER=	$email
COMMENT=	$description

PERL_CONFIGURE=	yes

EOF

        $fh->print("MAN1=		@man1\n") if @man1;
        $fh->print("MAN3=		@man3\n") if @man3;
        $fh->print("\n");
        $fh->print(".include <bsd.port.mk>\n");
    }

    unless( open $fh, ">$distinfo" ) {
        $err->trap( error => loc("Could not open %1 for writing: %2", $distinfo, $!) );
    } else {
        my $use_list = { 'Digest::MD5' => '0.0' };

        unless ($obj->_can_use(modules => $use_list)) {
            $err->trap(
                error => loc("You don't have %1, cannot continue!", "Digest::MD5"),
            );
            return undef;
        }

        my $basedir = File::Spec->catdir(
                        $conf->_get_build('base'),
                        $conf->_get_ftp('base'),
                        $self->path,
                    );
        my $archive = File::Spec->catfile( $basedir, $self->package );
        my $_fh = new FileHandle;
        unless ( $_fh->open($archive) ) {
            $err->trap( error => loc("Could not open %1: %2", $archive, $!) );
            return undef;
        }
        binmode $_fh;
        my $md5 = Digest::MD5->new;
        $md5->addfile($_fh);
        print $fh "MD5 (", $self->package, ") = ";
        print $fh $md5->hexdigest, "\n";
        print $fh "SIZE (", $self->package, ") = ";
        print $fh -s $_fh, "\n";
    }

    unless( open $fh, ">$pkg_descr" ) {
        $err->trap( error => loc("Could not open %1 for writing: %2", $pkg_descr, $!) );
    } else {
        print $fh "# This space intentionally left blank.\n";
    }

    unless( open $fh, ">$pkg_plist" ) {
        $err->trap( error => loc("Could not open %1 for writing: %2", $pkg_plist, $!) );
    } else {
        require File::Find;
        my $blib = File::Spec->catdir($args->{builddir}, 'blib');
        my (@arch, @lib, %archdir, %libdir, %archroot, %libroot);

        File::Find::find({ wanted => sub {
            print $fh "bin/$_\n" if -f and $_ ne '.exists';
        }}, File::Spec->catdir($blib, 'script'));

        File::Find::find({ wanted => sub {
            my $f = substr( ${File::Find::name}, length($blib) );
            if (-f) { push @arch, $f; $archdir{substr(${File::Find::dir}, length($blib))}++ }
               else { $archroot{$f}++ if -d }
        }}, File::Spec->catdir($blib, 'arch'));
        File::Find::find({ wanted => sub {
            return if /^\.exists/;
            my $f = substr( ${File::Find::name}, length($blib) );
            if (-f) { push @lib, $f; $libdir{substr(${File::Find::dir}, length($blib))}++ }
               else { $libroot{$f}++ if -d; }
        }}, File::Spec->catdir($blib, 'lib'));

        # first, go thru @lib
        foreach my $file (sort @lib) {
            if (@arch > 1) {
                $file =~ s!^/lib!%%SITE_PERL%%/%%PERL_ARCH%%!;
            }
            else {
                $file =~ s!^/lib!%%SITE_PERL%%!;
            }
            print $fh "$file\n";
        }
        # next, go thru @arch
        foreach my $file (sort @arch) {
            substr($file, -6) = 'packlist' if substr($file, -7) eq '.exists';
            $file =~ s!^/arch!%%SITE_PERL%%/%%PERL_ARCH%%!;
            print $fh "$file\n";
        }
        # unlink @libdir
        foreach my $dir (sort { length $b <=> length $a or $a cmp $b } keys %libdir) {
            delete $libroot{$dir};
            next if $dir eq '/lib' or $dir =~ m!^/lib/auto!;
            if (@arch > 1) {
                $dir =~ s!^/lib!%%SITE_PERL%%/%%PERL_ARCH%%!;
            }
            else {
                $dir =~ s!^/lib!%%SITE_PERL%%!;
            }
            print $fh "\@dirrm $dir\n";
        }
        # unlink @archdir
        foreach my $dir (sort { length $b <=> length $a or $a cmp $b } keys %archdir) {
            delete $archroot{$dir};
            $dir =~ s!^/arch!%%SITE_PERL%%/%%PERL_ARCH%%!;
            print $fh "\@dirrm $dir\n";
        }
        # unlink @libroot
        foreach my $dir (sort { length $b <=> length $a or $a cmp $b } keys %libroot) {
            next if $dir eq '/lib' or $dir =~ m!^/lib/auto!;
            if (@arch > 1) {
                $dir =~ s!^/lib!%%SITE_PERL%%/%%PERL_ARCH%%!;
            }
            else {
                $dir =~ s!^/lib!%%SITE_PERL%%!;
            }
            print $fh "\@unexec rmdir %D/$dir 2>/dev/null || true\n";
        }
        # unlink @archroot
        foreach my $dir (sort { length $b <=> length $a or $a cmp $b } keys %archroot) {
            next if $dir eq '/arch' or $dir eq '/arch/auto';
            $dir =~ s!^/arch!%%SITE_PERL%%/%%PERL_ARCH%%!;
            print $fh "\@unexec rmdir %D/$dir 2>/dev/null || true\n";
        }
    }

    my $rv = {
        makefile    => $makefile,
        distinfo    => $distinfo,
        pkg_comment => $pkg_comment,
        pkg_descr   => $pkg_descr,
        pkg_plist   => $pkg_plist,
    };

    ### store the rv's in the object as well ###
    $dist->$_( $rv->{$_} ) for keys %$rv;

    ### return to the startdir ###
    $obj->_restore_startdir;

    return $rv;
}

1;

__END__

=pod

=head1 NAME

CPANPLUS::Dist::Ports - FreeBSD Ports Interface for CPANPLUS

=head1 DESCRIPTION

CPANPLUS::Dist::Ports is CPANPLUS's way to generate, install and uninstall FreeBSD Ports

=head1 METHODS

=head2 new( module => MODULE_OBJECT );

takes a module object as returned by CPANPLUS::Internals::Module (and the module_tree method in CPANPLUS::Backend), and returns a CPANPLUS::Dist::Ports object.

=head2 create ( dir => '/path/to/build/dir' );

=head2 install ( makefile => '/path/to/makefile' );

=head1 AUTHORS

This module by
Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>,
Jos Boumans E<lt>kane@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=head1 SEE ALSO

L<CPANPLUS::Backend/"ERROR OBJECT">

=cut


# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
