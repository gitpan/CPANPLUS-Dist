# $File: //member/autrijus/CPANPLUS-Dist/lib/CPANPLUS/Dist.pm $ $Author: autrijus $
# $Revision: #5 $ $Change: 10593 $ $DateTime: 2004/05/11 13:17:45 $

package CPANPLUS::Dist;

use strict;
use Data::Dumper;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Check qw[check];

BEGIN {
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( CPANPLUS::Internals );
    $VERSION    =   '0.00_03';
}

my $Class = 'CPANPLUS::Backend';

sub new {
    my $self = shift;
    my %hash = @_;

    my $tmpl = {
        format  => { required => 1 },
        module  => { required => 1, allow => sub { UNIVERSAL::isa( pop(), 'CPANPLUS::Internals::Module' ) } },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $mod = $args->{module};

    my $class = {
                #rpm         => 'CPANPLUS::Dist::RPM',
                ppm         => 'CPANPLUS::Dist::PPM',
                #deb         => 'CPANPLUS::Dist::Deb',
                ports       => 'CPANPLUS::Dist::Ports',
                par         => 'CPANPLUS::Dist::PAR',
                #build       => 'CPANPLUS::Dist::Build', # Module::Build
                #makemaker   => 'CPANPLUS::Dist::MakeMaker',
            }->{ lc $args->{format} } or return undef;

    $mod->_make_object->_can_use( modules => { $class => 0.0 } ) or return undef;

    return bless { parent => $mod }, $class;
}

### accessors ###
for my $key (qw[parent] ) {
    no strict 'refs';
    *{__PACKAGE__."::$key"} = sub {
        my $self = shift;
        $self->{$key} = $_[0] if @_;
        return $self->{$key};
    }
}

1;
__END__

=head1 NAME

CPANPLUS::Dist - Interface to package managers for CPANPLUS

=head1 SYNOPSIS

In the default CPANPLUS Shell:

    # install Acme::Bleach with FreeBSD ports
    CPAN Terminal> install --format=ports Acme::Bleach

    # build and test only, do not install
    CPAN Terminal> test --format=ppm Acme::Bleach

    # set default format to PAR and save the setting
    CPAN Terminal> s format par
    CPAN Terminal> s save

In your programs:

    use CPANPLUS::Dist;

    my $dist = CPANPLUS::Dist->new( 
                            format  => 'PPM', 
                            module  => 'Acme::Bleach' 
                        );
    $dist->create;
    $dist->install;
    $dist->uninstall;    

=head1 NOTES

Please note that this module is B<HIGHLY EXPERIMENTAL>.

Its API is subject to change during the CPANPLUS 0.05x development.
This version only works with CPANPLUS 0.043 and B<NOTHING ELSE>.

=head1 DESCRIPTION

CPANPLUS::Dist works as a gateway for the underlying subclasses, 
providing proper inheritance and reference to C<CPANPLUS::Module>-
and C<CPANPLUS::Backend>-objects.

Users probably don't ever need to know about this class. This 
document is aimed at explaining the API to programmers who want to
create their own CPANPLUS::Dist::* module.

=head2 The API

The way this works for the user should be quite simple. We'll walk
through the steps of installing the module Acme::Bleach as a PPM.

    my $cb      = CPANPLUS::Backend->new;
    my $modobj  = $cb->module_tree->{'Acme::Bleach'};
    my $dist    = $modobj->dist( format => 'PPM' );

    print $dist->install ? "worked" : "didnt";

=head2 The Implementation

Calling a method on a module-object just serves a wrapper for the
corresponding C<CPANPLUS::Backend> method (C<dist()> in this case)

It will accept the following options:

=over 4

=item modules

array ref of modules to be distified

=item format

what type of dist to make of them

=item perl    

with what perl to execute any possible scripts (default is $^X)

=item makeflags

options that need passing to C<make>

=back

Backend will now call C<< CPANPLUS::Dist->new() >> and create a new (empty)
dist object. By the C<format> option it will know what class to inherit
from (in our previous example, C<CPANPLUS::Dist::PPM>);
It will also populate the dist object with one key, namely C<parent>,
which is the module object we were supposed to make a dist of.

If, in your own Dist::* modules you need ever access to the parent
module object, you can do simply:
    my $modobj = $dist->parent

And along the same way, if you ever need to have a CPANPLUS::Backend,
you can do:
    my $cb = $modobj->_make_object

which will give you a copy of the object that parented this module
object.

=head1 METHODS

Below are a list of methods that must be supported by your subclass.

=head2 create

Now, back in C<< CPANPLUS::Backend->dist() >>, we will have an (almost) 
empty C<CPANPLUS::Dist> object, with proper inheritance and a link to
it's parent. We then call it's C<create> method to make a package of 
the given module object.

Again, things like package name, version numbers, authors etc can all
be retrieved via the parent module object.

We also have a standard place of creating these packages, which is
under C<$CPANHOME/$PERLVERSION/dist/$FORMAT/>. Of course this 
information all comes out of C<Config.pm> and C<CPANPLUS::Config>, so 
here's the way it's done in C<CPANPLUS::Dist::PPM> (with some creative
formatting):

    File::Spec->catdir(
        $conf->_get_build('base'),
        $obj->_perl_version( perl => $args->{perl} )
        $conf->_get_build('distdir'),
        'PPM',
        File::Basename::basename( $parent->status->make_dir )
     );

and it should return a value which is at least true, but preferably has
a bit more information (like what files were created, or where the
package ended up), and stores these in itself as well, for later
querying.

Should it go wrong, undef should be returned, so Backend can handle
the error properly. Again, I refer to C<CPANPLUS::Dist::PPM> and 
C<CPANPLUS::Dist::Ports> as good examples on how to code this up.

=head2 install

Now, when the user does $dist->install, the C<install> method from
your C<Dist::*> package is called, and should then do the necessary
steps for installing the package. Ideally, it shouldn't need any
arguments since all this was taken care of at C<create> time.

=head2 uninstall

Finally, we'd also like to be able to uninstall the package, but
in all fairness, this will probably most likely be done with the 
package manager of choice. ie, rather C<rpm -e package> than 
C<< $dist->uninstall >>.

So all that needs to be implemented are those 3 method calls and
C<CPANPLUS> will Do The Right Thing.

=head1 AUTHORS

Copyright (c) 2001, 2002, 2003, 2004 by Jos Boumans E<lt>kane@cpan.orgE<gt>,
Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>.  All rights reserved.

=head1 COPYRIGHT

This library is free software; you may redistribute and/or modify it
under the same terms as Perl itself.    

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
