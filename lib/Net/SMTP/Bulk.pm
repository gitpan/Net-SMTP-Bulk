package Net::SMTP::Bulk;

use 5.006;
use strict;
use warnings FATAL => 'all';

#use Encode;
#use Coro;
#use Coro::Handle;
#use AnyEvent::Socket;


=head1 NAME

Net::SMTP::Bulk - NonBlocking batch SMTP using Net::SMTP interface

=head1 VERSION

Version 0.17

=cut

our $VERSION = '0.17';


=head1 SYNOPSIS

This is a rewrite of Net::SMTP using AnyEvent and Coro as a backbone. It supports AUTH and SSL (no STARTTLS support yet). This module can be used as a drop in replacement for Net::SMTP. At this point this module is EXPIREMENTAL, so use at your own risk. Functionality can change at any time.

    use Net::SMTP::Bulk;

    my $smtp = Net::SMTP::Bulk->new($server, %options);

    
See Net::SMTP for syntax.
    
=head1 SUBROUTINES/METHODS

=head2 new($server,%options)

=head2 new(%options)

Options:
Host - Hostname or IP address

Mode - Options of AnyEvent or Coro (default: Coro but switches to AnyEvent if Coro is not installed)

Port - The port to which to connect to on the server (default: 25)

Hello - The domain name you wish to connect to (default: [same as server])

Debug - Debug information (Coro: off: 0, on: 1, AnyEvent: 0-10 depending on level) (default: 0 [disabled]) OPTIONAL

DebugPath - Set to default Debug Path. use [HOST] and [THREAD] for deeper control of output OPTIONAL

Secure - If you wish to use a secure connection. (0 - None, 1 - SSL [no verify]) OPTIONAL [Requires Net::SSLeay]

Threads - How many concurrent connections per host (default: 2) OPTIONAL

Encode - Encode socket( 1: utf8 )

Callbacks - You can supply callback functions on certain conditions, these conditions include:

connect_pass,connect_fail,auth_pass,auth_fail,reconnect_pass,reconnect_fail,pass,fail,hang

The callback must return 1 it to follow proper proceedures. You can overwrite the defaults by supplying a different return.

1 - Default

101 - Remove Thread permanently

102 - Remove thread temporarily and reconnect at end of batch

103 - Remove thread temporarily and restart at end of batch (If your using an SMTP server with short timeout, it is suggested to use this over reconnect)

104 - Remove Thread temporarily

202 - Reconnect now

203 - Restart now

=head2 new(%options, Hosts=>[\%options2,\%options3])

You can supply multiple hosts in an array.


=head2 auth( [ MECHANISM,] USERNAME, PASSWORD  )

*Requires Authen::SASL

=head2 mail( ADDRESS )

=head2 to( ADDRESS )

=head2 data()

=head2 datasend( DATA )

=head2 dataend( DATA )

=head2 reconnect(  )

=head2 quit(  )

=cut

sub new {
    my $class=shift;
    my %new=@_;
    my $self={};

    if (($new{Mode}||'') eq 'AnyEvent') {
        require Net::SMTP::Bulk::AnyEvent;    
        $self=Net::SMTP::Bulk::AnyEvent->new(@_);    
    } else {
        if (eval { require Net::SMTP::Bulk::Coro; 1 }) {
            $self=Net::SMTP::Bulk::Coro->new(@_);
        } else {
            require Net::SMTP::Bulk::AnyEvent; 
            $self=Net::SMTP::Bulk::AnyEvent->new(@_);
        }
    
        
    }
    
    

    return $self;
}


#########################################################################


=head1 AUTHOR

KnowZero

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-smtp-bulk at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-SMTP-Bulk>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::SMTP::Bulk


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-SMTP-Bulk>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-SMTP-Bulk>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-SMTP-Bulk>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-SMTP-Bulk/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 KnowZero.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.


=cut

1; # End of Net::SMTP::Bulk
