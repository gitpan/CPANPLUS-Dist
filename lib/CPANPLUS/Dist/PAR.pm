# $File: //member/autrijus/CPANPLUS-Dist/lib/CPANPLUS/Dist/PAR.pm $ $Author: autrijus $
# $Revision: #1 $ $Change: 7708 $ $DateTime: 2003/08/25 19:29:17 $

#########################################################
###                 CPANPLUS/Dist/PAR.pm              ###
### Module to provide an interface to the PAR System  ###
###            Written 27-01-2003 by Autrijus Tang    ###
#########################################################

package CPANPLUS::Dist::PAR;

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
for my $key (qw[dist_par dir] ) {
    no strict 'refs';
    *{__PACKAGE__."::$key"} = sub {
        my $self = shift;
        $self->{$key} = $_[0] if @_;
        return $self->{$key};
    }
}


### installs a ports by it's Makefile
### call it as: my $bool = $ports->install( dist_par => '/path/to/distfile.par' )
sub install {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = {
        dist_par    => { default => $dist->dist_par, strict_type => 1 },
        target      => { default => 'install' },
    };

    my $args = check( $tmpl, \%hash ) or return undef;
    my $distfile = $args->{dist_par} or return undef;

    require PAR::Dist;
    no strict 'refs';
    return {
        ok => &{"PAR::Dist::$args->{target}_par"}(dist => $distfile),
    };
}

### uninstalls a ports by it's makefile
### call it as: my $bool = $ports->uninstall( makefile => '/path/to/Makefile' )
sub uninstall {
    my $dist = shift;
    $dist->install(@_, target => 'uninstall')
}

### creates a PAR from a build dir.. can take a dir optioninally as argument
### otherwise will take the dir stored in the module object
### note, this module object will have to be REBLESSED into the C::Dist::PAR package
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
        distdir     => { default => '', },
        distfile    => { default => '', },
        suffix      => { default => "$Config{archname}-$Config{version}.par", },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    unless ( $args->{builddir} ) {
        $err->trap( error => loc("Don't know what dir to build in!" ) );
        return undef;
    }

    my $makeflags   = $args->{makeflags};
    my $make        = $args->{make};
    my $perl        = $args->{perl};
    my $dir         = $args->{builddir};
    my $suffix      = $args->{suffix};

    my $perl_version = $obj->_perl_version( perl => $perl );

    my ($name, $ver);

    $name = $self->package_name;
    $ver  = $self->package_version;

    if (!defined($name) or !defined($ver)) {
        $err->trap( error => loc(qq[Cannot build PAR without a valid package name and version!] ) );
        return undef;
    }

    my $path = $args->{distdir}
                  || File::Spec->catdir(
                        $conf->_get_build('base'),
                        $perl_version,
                        $conf->_get_build('distdir'),
                        'PAR',
                     );
    my $distfile = $args->{distfile}
                  || File::Spec->catfile(
                        $path,
                        "$name-$ver-$suffix",
                    );

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

    unless( $dir eq cwd() ) {
        unless (chdir $dir) {
            $err->trap(
                error => loc("create() couldn't chdir to %1! I am in %2 now", $dir, cwd()),
            );
            return undef;
        }
    }

    require PAR::Dist;
    PAR::Dist::blib_to_par( dist => $distfile );

    my $rv = { dist_par => $distfile };

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

CPANPLUS::Dist::PAR - FreeBSD PAR Interface for CPANPLUS

=head1 DESCRIPTION

CPANPLUS::Dist::PAR is CPANPLUS's way to generate, install and uninstall FreeBSD PAR

=head1 METHODS

=head2 new( module => MODULE_OBJECT );

takes a module object as returned by CPANPLUS::Internals::Module (and the module_tree method in CPANPLUS::Backend), and returns a CPANPLUS::Dist::PAR object.

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
