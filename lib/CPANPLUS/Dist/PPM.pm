###################################################################
###                     CPANPLUS/Dist/PPM.pm                    ###
### Module to provide an interface to the PPM package manager   ###
###                 Written 23-04-2002 by Jos Boumans           ###
###################################################################

package CPANPLUS::Dist::PPM;

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
for my $key (qw[tgz ppd zip readme dir] ) {
    no strict 'refs';
    *{__PACKAGE__."::$key"} = sub {
        my $self = shift;
        $self->{$key} = $_[0] if @_;
        return $self->{$key};
    }
}


### installs a ppm by it's ppd... ppm is standard in .zip for,
### so if you still need to extract it, use CPANPLUS::Backend->extract()
### a .ppd file will always have the name of the extract_dir . '.ppd'
### call it as: my $bool = $ppm->install( ppd => '/path/to/file.ppd' )
sub install {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = {
        ppd     => { default => $dist->ppd, strict_type => 1 },
        verbose => { default => $conf->get_conf('verbose') }
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    return undef unless $args->{ppd};

    #return 0 unless $args{ppd};

    my $uselist = { PPM => '0.0' };

    ### from perldoc PPM in regard to the PPM::InstallPackage() function
    ### PPM::InstallPackage(``package'' => $package, ``location'' => $location, ``root'' => $root);

    #    - the PPD file for the package is read
    #    - a directory for this package is created in the directory specified in
    #      <BUILDDIR> in the PPM data file.
    #    - the file specified with the <CODEBASE> tag in the PPD file is
    #      retrieved/copied into the directory created above.
    #    - the package is unarchived in the directory created for this package
    #    - individual files from the archive are installed in the appropriate
    #      directories of the local Perl installation.
    #    - perllocal.pod is updated with the install information.
    #    - if provided, the <INSTALL> script from the PPD is executed in the
    #      directory created above.
    #    - information about the installation is stored in the PPM data file.

    if( $obj->_can_use( modules => $uselist, complain => 1 ) ) {

        ### it could be stored in the object as well, but currently we bail
        ### if it's not provided as an argument
        my $ppd =   $args->{ppd} ||
                    $self->{dist}->{ppm}->{ppd} ||
                    return undef;

        my $rv = PPM::InstallPackage( package => $ppd );

        unless($rv){
            $err->trap( error => loc("Unable to install %1: %2", $ppd, $PPM::PPMERR) );
            return undef;
        } else {
            $err->inform(
                    msg     => loc("%1 installed succesfully", $ppd),
                    quiet   => !$args->{verbose},
            );
        }

        return $rv;

    } else {

        my $mods = join ' ', keys %$uselist;

        $err->trap( error => loc("You are missing at least one of these modules: %1", $mods) );
        return undef;
    }
}

### uninstalls a given ppm file by it's ppd.. also the name of the ppm might work, but ppd is safer.
### currently, only the NAME of the ppd file is supported.
### it will read the ppd file and uninstall the package using the PPM module
### call it as: my $bool = $ppm->uninstall( ppd => '/path/to/file.ppd', force => BOOL )
sub uninstall {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = {
        ppd     => { default => $dist->ppd, strict_type => 1 },
        verbose => { default => $conf->get_conf('verbose') },
        force   => { default => $conf->get_conf('force') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;
    return undef unless $args->{ppd};

    #return 0 unless $args{ppd};

    my $uselist = { PPM => '0.0' };

    if( $obj->_can_use( modules => $uselist, complain => 1 ) ) {

        ### from perldoc PPM:
        ### PPM::RemovePackage(``package'' => $package, ``force'' => $force)

        # Removes the specified package from the system. Reads the package's PPD
        # (stored during installation) for removal details. If 'force' is specified,
        # even a package required by PPM will be removed (useful when installing an upgrade).

        ### it could be stored in the object as well, but currently we bail
        ### if it's not provided as an argument
        my $ppd =   $args->{ppd} ||
                    $self->{dist}->{ppm}->{ppd} ||
                    return undef;

        my $fh;
        unless( open $fh, "$ppd" ) {
            $err->trap( error => loc("Could not open %1 for reading: %2", $ppd, $!) );
            return undef;
        }

        my $pkg;
        while(<$fh>){
            next unless ($pkg) = m|<title>(\S+)</title>|i;
            last if $pkg;
        }

        my $rv = PPM::RemovePackage( package => $pkg, force => $args->{force});

        unless($rv){
            $err->trap( error => loc("Unable to uninstall %1: %2", $ppd, $PPM::PPMERR) );
            return 0;
        } else {
            $err->inform(
                    msg     => loc("%1 uninstalled succesfully", $ppd),
                    quiet   => !$args->{'verbose'},
            );
        }

        return $rv;


    } else {
        my $mods = join ' ', keys %$uselist;

        $err->trap( error => loc("You are missing at least one of these modules: %1", $mods) );
        return 0;
    }
}




### creates a PPM from a build dir.. can take a dir optioninally as argument
### otherwise will take the dir stored in the module object
### note, this module object will have to be REBLESSED into the C::Dist::PPM package
### for this to work -kane
### call it as: my $rv = $ppm->install( dir => '/extract/dir/where/module/was/maked' )
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
        builddir    => { default => $self->status->{make}->{dir} },
        distdir     => { default => '', },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    unless ( $args->{builddir} ) {
        $err->trap( error => loc(qq[Don't know what dir to build in!] ) );
        return undef;
    }

    ### in case it wasn't defined yet, store it for later use
    $self->{status}->{make}->{dir} ||= $args->{builddir};

    my $makeflags   = $args->{makeflags};
    my $make        = $args->{make};
    my $perl        = $args->{perl};
    my $dir         = $args->{builddir};

    my $perl_version = $obj->_perl_version( perl => $perl );

    my $path = $args->{distdir}
                  || File::Spec->catdir(
                        $conf->_get_build('base'),
                        $perl_version,
                        $conf->_get_build('distdir'),
                        'PPM',
                        File::Basename::basename( $self->status->{make}->{dir} )
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

    my $ppd;
    unless( $ppd = $dist->_make_ppd(
                            make        => $make,
                            makeflags   => $makeflags,
                            path        => $dist->dir
    ) ) {
        $err->trap( error => loc("An error occurred while writing the .pdd file") );
        return undef;
    }

    my $tgz;
    unless( $tgz = $dist->_tar_blib( path => $path ) ) {
        $err->trap( error => loc("An error occurred while compressing the blib/ directory") );
        return undef;
    }

    unless ( $path eq cwd() ) {
        unless (chdir $path) {
            $err->trap(
                error => loc("create() couldn't chdir to %1! I am in %2 now", $path, cwd()),
            );
            return undef;
        }
    }

    my $readme;
    unless( $readme = $dist->_make_readme( ppd_file => $ppd ) ) {
        $err->trap( error => loc("An error occurred while creating the README file") );
    }

    my $zip;
    unless( $zip = $dist->_zip_ppm_distribution( ppd_file => $ppd, tarball => $tgz, readme => $readme ) ) {
        $err->trap( error => loc("An error occurred while zipping a distribution") );
    }

    my $rv = {
        tgz     => $tgz,
        ppd     => $ppd,
        zip     => $zip,
        readme  => $readme
    };

    ### store the rv's in the object as well ###
    $dist->$_( $rv->{$_} ) for keys %$rv;

    ### return to the startdir ###
    $obj->_restore_startdir;

    return $rv;
}

sub _tar_blib {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = {
        verbose     => { default => $conf->get_conf('verbose') },
        force       => { default => $conf->get_conf('force') },
        path        => { required => 1, allow => sub { -d pop() && -w _ } },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $dir = File::Spec->catdir( cwd(), 'blib' );

    unless( -d $dir ) {
        $err->trap( error => loc("%1 does not exist, can not PPMify it!", $dir) );
        return undef;
    }


    ### temp temp ###
    my $package = $self->package;

    ### change it to a .tar.gz if it was a zip file ###
    $package =~ s|\.zip$|.tar.gz|i;

    my $uselist = {
        'Archive::Tar'  => '0.0',
        'File::Find'    => '0.0',
        'File::Path'    => '0.0',
    };

    my $file = File::Spec->catfile( $args->{path}, $package );

    if( $obj->_can_use( modules => $uselist, complain => 1 ) ) {
        ### use archive::Tar

        my @blib_files;
        File::Find::find(
            sub {
                push @blib_files, "$File::Find::name/" if -d;
                push @blib_files, $File::Find::name if -f;
            }, "blib"
        );

        my $tar = Archive::Tar->new();
        $tar->add_files(@blib_files);

        $err->inform(
                msg     => qq[Writing to $file],
                quiet   => !$args->{'verbose'},
        );

        $tar->write($file,1);

        if( $Archive::Tar::error ) {
            $err->trap( error => loc("Writing %1 failed with error: %2", $file, $Archive::Tar::error) );
            return undef;
        }
    } else {
        ### use bin/tar ###
        $err->inform( msg => loc("/bin/tar solution not yet implemented, sorry!") );
        return undef;
    }

    return $file;
}

sub _make_ppd {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = {
        verbose     => { default => $conf->get_conf('verbose') },
        force       => { default => $conf->get_conf('force') },
        makeflags   => { default => $conf->get_conf('makeflags') },
        make        => { default => $conf->get_conf('make') },
        path        => { required => 1, allow => sub { -d pop() && -w _ } },

    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $make    = $args->{make};
    my $flags   = join ' ', @{$obj->_flags_arrayref( $args->{makeflags} )};

    my $captured; my $target;
    if ( $obj->_run(
            command => [$make, $flags, 'ppd'],
            buffer  => \$captured,
            verbose => 1
    ) ) {
        my $file = $dist->_get_ppd_file() or return undef;

        $dist->_check_ppd( ppd_file => $file ) or return undef;

        my $ppd_file = File::Basename::basename( cwd() ) . '.ppd';

        ### File::Copy is littered with DIE statements.. must eval -kane
        my $current = $file;
        $target  = File::Spec->catfile( $args->{path}, $ppd_file );

        $err->inform(   msg     => loc("Moving %1 to %2", $current, $target),
                        quiet   => !$args->{'verbose'}
        );

        my $rv = eval { File::Copy::move( $current, $target ) };

        if ($@) {
            chomp($@);
            $err->trap( error => loc("Could not move %1 to %2: %3", $current, $target, $@) );
            return undef;
        }
    }
    return $target;
}

sub _check_ppd {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;
    my $obj  = $self->_make_object();
    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = {
        ppd_file    => { default => '', required => 1, strict_type => 1 },
        verbose     => { default => $conf->get_conf('verbose') },
        force       => { default => $conf->get_conf('force') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $file        = $args->{'ppd_file'};
    my $osname      = $Config{'osname'}      or return undef;
    my $archname    = $Config{'archname'}    or return undef;

    ### from PPM 3's source code: *SIGH*
    # my $varchname = $Config{archname};
    # Append "-5.8" to architecture name for Perl 5.8 and later
    # if (length($^V) && ord(substr($^V,1)) >= 8) {
    # $varchname .= sprintf("-%d.%d", ord($^V), ord(substr($^V,1)));
    ### and later:
    #    parsePPD(%PPD);
    #if (!$current_package{'CODEBASE'} && !$current_package{'INSTALL_HREF'}) {
    #    &Trace("Read a PPD for '$package', but it is not intended for this build of Perl ($varchname)")
    ### so this means we have to do the same trick =/
    my $version = sprintf "%vd", $^V;
    $archname .= '-' . substr($version,0,3)
                if (substr($version,0,1) == 5) && (substr($version,2,1) >= 8);

    $err->inform( msg => loc("Checking PPD..."), quiet => !$args->{'verbose'} );

    ### change it to a .tar.gz if it was a zip file ###
    my $package = $self->{package};
    $package =~ s|\.zip|.tar.gz|i;

    my $PPD;
    if ( open $PPD, "+< $file" ) {
        local $/ ;
        my $ppd = <$PPD>;

        $ppd =~ s|(<OS NAME=")[^"]+(" />)|$1$osname$2|;
        $ppd =~ s|(<ARCHITECTURE NAME=")[^"]+(" />)|$1$archname$2|;
        $ppd =~ s|(<CODEBASE HREF=")[^"]*(" />)|$1$package$2|;
        unless( seek $PPD, 0, 0 ) {
            $err->trap( error => loc("Can't rewind %1: %2", $file, $!) );
            return undef;
        }

        unless( truncate $PPD, 0 ) {
            $err->trap( error => loc("Can't truncate %1: %2", $file, $!) );
            return undef;
        }

        unless( print $PPD $ppd ) {
            $err->trap( error => loc("Can't write to %1: %2", $file, $!) );
            return undef;
        }

        close $PPD;

    } else {
        $err->trap( error => loc("Can't open[r/w] %1: %2", $file, $!) );
        return undef;
    }

    return 1;
}

sub _get_ppd_file {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = { };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $dir = $self->status->{make}->{dir};

    my $DIR;
    unless( opendir $DIR, "$dir" ) {
        $err->trap( error => loc("Can not open %1: %2", $dir, $!) );
        return undef;
    }

    ### find the NEWEST ppd file ###
    my @list = grep { /\.ppd$/ && -f } readdir $DIR;

    closedir $DIR;

    my @sorted =    map  { $_->[0] }
                    sort { $a->[1] cmp $b->[1] }
                    map  { [ $_ => (stat)[9] ] } @list;

    my $file;

    unless( $file = shift @sorted ) {
        $err->trap( error => loc("Could not find a .ppd file in %1!", $dir) );
        return undef;
    }

    return File::Spec->catfile($dir,$file);
}

sub _zip_ppm_distribution {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = {
        ppd_file    => { default => '', required => 1, strict_type => 1 },
        tarball     => { default => '', required => 1, strict_type => 1 },
        readme      => { default => '', required => 1, strict_type => 1 },
        verbose     => { default => $conf->get_conf('verbose') },
        force       => { default => $conf->get_conf('force') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $ppd_file    = $args->{ppd_file};
    my $tgz         = $args->{tarball};
    my $readme      = $args->{readme};

    ### already there ###
    ### change to the build dir ###
    #my $dir = $self->{dist}->{ppm}->{dir};
    #unless ( $dir eq cwd ) {
    #    unless (chdir $dir) {
    #        $err->trap(
    #            error => loc("Make couldn't chdir to %1! I am in %2 now", $dir, cwd()),
    #        );
    #        return 0;
    #    }
    #}

    my $uselist = {
        'Archive::Zip'  => '0.0',
    };

    if( $obj->_can_use( modules => $uselist ) ) {
        my $ppd = File::Basename::basename($ppd_file);
        my $dir = cwd();
        #my $dir = File::Basename::dirname($ppd_file);

        my $zip;
        unless( $zip = Archive::Zip->new() ) {
            $err->trap( error => loc("Could not create Archive::Zip object") );
            return undef;
        }

        my $flag;
        for my $path ( ($readme, $ppd_file, $tgz) ) {
            my $item = File::Basename::basename($path);
            unless( $zip->addFile($item) ) {
                $flag = 1;
                $err->trap( error => loc("%1 could not be added by Archive::Zip", $item) );
            }
        }

        my $archive;
        unless( $flag ) {
            my $topdir = File::Basename::basename( $dir );

            $archive = File::Spec->catfile( $dir, $topdir .'-'. $Config{archname} . '.zip' );

            if( $zip->writeToFileNamed($archive) != Archive::Zip::AZ_OK() ) {
                $err->trap( error => loc("File '%1' was not created: %2", $archive, $!) );
                $flag = 1;
            }
        }

        if( $flag ) {
            $err->trap( error => loc("Failed to create zip file for %1", $ppd_file) );
            return undef;
        }

        return $archive;

    } else {
        $err->trap( error => loc("You do not have Archive::Zip installed -- can not create .zip distribution") );
        return undef;
    }
}

sub _make_readme {
    my $dist = shift;
    my $self = $dist->parent;
    my %hash = @_;

    my $obj  = $self->_make_object();

    my $conf = $obj->configure_object;
    my $err  = $obj->error_object;

    my $tmpl = {
        ppd_file    => { default => '', required => 1, strict_type => 1 },
        verbose     => { default => $conf->get_conf('verbose') },
        force       => { default => $conf->get_conf('force') },
        makeflags   => { default => $conf->get_conf('makeflags') },
        make        => { default => $conf->get_conf('make') },
        perl        => { default => ($conf->_get_build('perl') || $^X) },
        dir         => { default => $self->status->{make}->{dir} },
        distdir     => { default => '', },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $dir         = cwd();
    my $ppd_file    = File::Basename::basename( $args->{ppd_file} );
    my $file        = File::Spec->catfile($dir, 'README.' . $Config{archname} );

    my $README;
    unless( open $README, ">$file" ) {
        $err->trap( error => loc("Could not open %1 for writing: %2", $file, $!) );
    } else {

        my $pkg = __PACKAGE__;
        my $now = scalar localtime;

        print $README <<EO_README;
To install this PPM package, run the following command in the current directory:

    ppm install $ppd_file

Created by $pkg $VERSION at $now
EO_README

        close $README;
    }

    return $file
}

1;

__END__

=pod

=head1 NAME

CPANPLUS::Dist::PPM - PPM Interface for CPANPLUS

=head1 DESCRIPTION

CPANPLUS::Dist::PPM is CPANPLUS's way to generate, install and uninstall PPM's

=head1 METHODS

=head2 new( module => MODULE_OBJECT );

takes a module object as returned by CPANPLUS::Internals::Module (and the module_tree method in CPANPLUS::Backend)
and returns a CPANPLUS::Dist::PPM object.

=head2 create ( dir => '/path/to/build/dir' );

create() requires the build directory to be passed to it. This is the directory you ran 'make test' in.
It needs it to find the appropriate blib/ to include in the PPM.

It will create the following files in a subdirectory named $module_dir under CPANPLUS_HOME/$perl_version/PPM,
which will also be present in it's return value:

$VAR1 = {
          'zip' => 'D:\\cpanplus\\5.6.1\\PPM\\Acme-Buffy-1.3\\Acme-Buffy-1.3-MSWin32-x86-multi-thread.zip',
          'ppd' => 'D:\\cpanplus\\5.6.1\\PPM\\Acme-Buffy-1.3\\Acme-Buffy-1.3.ppd',
          'tgz' => 'D:\\cpanplus\\5.6.1\\PPM\\Acme-Buffy-1.3\\Acme-Buffy-1.3.tar.gz',
          'readme' => 'D:\\cpanplus\\5.6.1\\PPM\\Acme-Buffy-1.3\\README.MSWin32-x86-multi-thread'
        };

The .zip file contains all 3 other files, as per PPM specification. To install the file, you need the .ppd
and the .tar.gz file. The readme is also supplied for convenience.

=head2 install ( ppd => '/path/to/ppd_file.ppd' );

This will actually install the module through the ppd file using PPM.

It will return 0 on failure, and 1 on success. Any errors will be available through the error object
(see CPANPLUS::Backend)

=head2 uninstall ( ppd => '/path/to/ppd_file.ppd', force => BOOL );

uninstall will read the modules ppd file and from that delete it using PPM.

The 'force' flag will unconditionally uninstall it, even if the PPM module requires it.

It will return 0 on failure, and 1 on success. Any errors will be available through the error object
(see CPANPLUS::Backend)

=head1 AUTHORS

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

=head1 ACKNOWLEDGMENTS

Thanks to Abe Timmerman who inspired the idea of CPANPLUS::Dist::PPM with his
CPAN::PPMify and contributed to the development of this module with sound advice.

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
