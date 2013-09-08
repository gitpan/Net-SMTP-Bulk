package Net::SMTP::Bulk;

use 5.006;
use strict;
use warnings FATAL => 'all';
use Coro;
use Coro::Handle;
use AnyEvent::Socket;


=head1 NAME

Net::SMTP::Bulk - NonBlocking batch SMTP using Net::SMTP interface

=head1 VERSION

Version 0.04

=cut

our $VERSION = '0.04';


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
Port - The port to which to connect to on the server (default: 25)
Hello - The domain name you wish to connect to (default: [same as server])
Debug - Debug information (off: 0, on: 1) (default: 0 [disabled]) OPTIONAL
Secure - If you wish to use a secure connection. (0 - None, 1 - SSL [no verify]) OPTIONAL [Requires Net::SSLeay]
Threads - How many concurrent connections per host (default: 2) OPTIONAL

Callbacks - You can supply callback functions on certain conditions, these conditions include:

connect_pass,connect_fail,auth_pass,auth_fail,reconnect_pass,reconnect_fail,pass,fail,hang

The callback must return 1 it to follow proper proceedures. You can overwrite the defaults by supplying a different return.

1 - Default
101 - Remove Thread
102 - Reconnect

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

    if ($#_ % 2 == 0) {
        $new{Host}=shift;
    }

    $new{Threads}||=2;
    $new{Threads}--;
    
    bless($self, $class||'Net::SMTP::Bulk');
 

    $self->{debug} = (($new{Debug}||0) == 1) ? 1:0;
    $self->{func} = $new{Callbacks};
    $self->{defaults}={
                       threads=>$new{Threads},
                       port=>$new{Port}||25,
                       timeout=>$new{Timeout}||30,
                       secure=>$new{Secure}||0
                       };
    
    
    if (exists($new{Hosts})) {
       $self->_PREPARE($new{Hosts});
    } else {
       $self->_PREPARE([\%new]);
    }


    return $self;
}

sub mail {
    my $self=shift;
    my $str=shift;
    my $k=shift||$self->{last}[0];
    $str=~s/\n$//s;
    push( @{$self->{queue}{ $k->[0] }{ $k->[1] }}, ['MAIL',250,'MAIL FROM: '.$str] );
    
}

sub to {
    my $self=shift;
    my $str=shift;
    my $k=shift||$self->{last}[0];
    $str=~s/\n$//s;
    push( @{$self->{queue}{ $k->[0] }{ $k->[1] }}, ['TO',250,'RCPT TO: '.$str] );
}

sub data {
    my $self=shift;
    my $k=shift||$self->{last}[0];
    
    push( @{$self->{queue}{ $k->[0] }{ $k->[1] }}, ['DATA',354,'DATA'] );
    $self->{data}{ $k->[0] }{ $k->[1] }='';
}

sub datasend {
    my $self=shift;
    my $str=shift;
    my $k=shift||$self->{last}[0];
    $str=~s/\n$//s;
    $self->{data}{ $k->[0] }{ $k->[1] }.=$str."\n";
}

sub dataend {
    my $self=shift;
    my $k=shift||$self->{last}[0];
    
    push( @{$self->{queue}{ $k->[0] }{ $k->[1] }}, ['DATAEND',250,$self->{data}{ $k->[0] }{ $k->[1] }."\r\n."] );
    
    $self->{queue_size}=$#{$self->{queue}{ $k->[0] }{ $k->[1] }} if $self->{queue_size} < $#{$self->{queue}{ $k->[0] }{ $k->[1] }};
    

    
    $self->_BULK() if $self->{last}[1] == $#{ $self->{order} };
    
    $self->_NEXT();
}

sub auth {
    my $self=shift;
    my $user;
    my $pass;
    my $k;
    my $mech;
    
    if ($#_ == 3 or $#_ == 2 and ref($_[2]) ne 'ARRAY') {
        $mech=shift;
    }
    
    $user=shift||'';
    $pass=shift||'';
    $k=shift||$self->{last}[0];
    
    require MIME::Base64;
    require Authen::SASL;
    
    if ($self->{auth}{ $k->[0] }{ $k->[1] }[0] == 1) {
        #already authenticated
    } else {   
    
    $mech ||= uc(join(' ',(@{$self->{header}{$k->[0]}{$k->[1]}{auth}})));
    $self->{objects}{$k->[0]}{$k->[1]}{sasl} = Authen::SASL->new(
      mechanism => $mech,
      callback  => {
        user     => $user,
        pass     => $pass,
        authname => $user,
      }
    ) if (!exists($self->{objects}{$k->[0]}{$k->[1]}{sasl}));
        $self->{objects}{ $k->[0] }{ $k->[1] }{sasl_client} = $self->{objects}{ $k->[0] }{ $k->[1] }{sasl}->client_new("smtp", $self->{host}{$k->[0]},1);

    
        $self->_WRITE($k,'AUTH '.$self->{objects}{ $k->[0] }{ $k->[1] }{sasl_client}->mechanism);
        $self->_READ($k);
        if (my $str = $self->{objects}{ $k->[0] }{ $k->[1] }{sasl_client}->client_start) {
        $self->_WRITE($k,MIME::Base64::encode_base64($str, ''));
        }

        do {
               my $msg=MIME::Base64::decode_base64($self->{buffer}{ $k->[0] }{ $k->[1] });

          
               $self->_WRITE($k,
               MIME::Base64::encode_base64($self->{objects}{$k->[0]}{$k->[1]}{sasl_client}->client_step($msg),'')
                 );
            $self->_READ($k);
        } while($self->{status_code}{ $k->[0] }{ $k->[1] } == 334);
        
        if ($self->{status_code}{ $k->[0] }{ $k->[1] } == 235) {
            $self->{auth}{ $k->[0] }{ $k->[1] }=[1,$mech];
            my $r=$self->_FUNC('auth_pass',$self,$k,0,$self->{queue}{ $k->[0] }{ $k->[1] });
            
            if ($r != 1) {
                $self->_FUNC_CALLBACK($k,0,$r);
            }
            return 1;
            
        } else {

            #AUTH FAILED
            my $r=$self->_FUNC('auth_fail',$self,$k,0,$self->{queue}{ $k->[0] }{ $k->[1] });
            
            if ($r == 1) {
                $self->_FUNC_CALLBACK($k,0,101); #remove thread
            } else {
                $self->_FUNC_CALLBACK($k,0,$r);    
            }
            
            return 0;
        }
        
        
    }


    
}

sub quit {
    my $self=shift;
    
    $self->_BULK();
}


sub reconnect{
    my $self=shift;
    my $k=shift||$self->{last}[0];
    
    
    $self->{fh}{ $k->[0] }{ $k->[1] }->close() if defined($self->{fh}{ $k->[0] }{ $k->[1] });
    
    $self->_CONNECT($k);
    if ( $self->{auth}{ $k->[0] }{ $k->[1] }[0] == 1 ) {
        $self->{auth}{ $k->[0] }{ $k->[1] }[0]=0;
        my $auth=$self->auth($self->{auth}{ $k->[0] }{ $k->[1] }[1],'','',$k);
        
        $self->{order}[ $self->{last}[1] ][2]=2;
        
        
        return 1 if $auth == 1;
    }
    return 0;
}

#########################################################################

sub _BULK {
    my $self=shift;

    foreach my $q ( 0..$self->{queue_size} ) {
        
        foreach my $k (@{$self->{order}}) {
            if ($k->[2] == 1 and exists($self->{queue}{ $k->[0] }{ $k->[1] }[$q])) {
                $self->_WRITE($k,$self->{queue}{ $k->[0] }{ $k->[1] }[$q][2]);
            }
 
        }

        foreach my $k (@{$self->{order}}) {
            if ($k->[2] == 1 and exists($self->{queue}{ $k->[0] }{ $k->[1] }[$q])) {
                $self->_READ($k);
                
                if ($self->{status_code}{ $k->[0] }{ $k->[1] } == $self->{queue}{ $k->[0] }{ $k->[1] }[$q][1] ) {
                    #GOOD
                    no strict;
                    my $r=$self->_FUNC('pass',$self,$k,$q,$self->{queue}{ $k->[0] }{ $k->[1] });
                    
                    if ($r != 1) {
                        $self->_FUNC_CALLBACK($k,$q,$r);
                    }
                    
                } else {
                    #BAD
                    if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == -1 ) {
                        
                        my $r=$self->_FUNC('hang',$self,$k,$q,$self->{queue}{ $k->[0] }{ $k->[1] });
                        
                        if ($r == 1) {
                            #reconnect
                            $self->_FUNC_CALLBACK($k,$q,102);
 
                        } else {
                            $self->_FUNC_CALLBACK($k,$q,$r);
                        }
                        
                    } else {
                        #error
                        my $r=$self->_FUNC('fail',$self,$k,$q,$self->{queue}{ $k->[0] }{ $k->[1] });
                        
                        if ($r != 1) {
                            $self->_FUNC_CALLBACK($k,$q,$r);
                        }
                        
                        
                        
                    }
                    
                }
   
            }
        }
    
        
    }
    foreach my $order (0..$#{$self->{order}}) {
        my $k=$self->{order}[$order];
        $self->{order}[ $order ][2]=1 if $self->{order}[ $order ][2] == 2;
        $self->{queue}{ $k->[0] }{ $k->[1] }=[];
    }
    
}

sub _FUNC {
    my $self=shift;
    no strict;
    my $func=shift;
    return &{$self->{func}{$func}}(@_) if exists($self->{func}{$func});
    return 0;
}

sub _FUNC_CALLBACK {
    my $self=shift;
    my $k=shift;
    my $q=shift;
    my $r=shift;
    
    if ($r == 101) {
        #remove thread
        $self->{order}[ $self->{last}[1] ][2]=0;
        $self->{last}=[ $self->{order}[ $self->{last}[1] ], $self->{last}[1] ];
        $self->_DEBUG($k,'++REMOVE THREAD++') if $self->{debug} == 1;
    } elsif ($r == 102) {
        #reconnect
        $self->_DEBUG($k,'++RECONNECT++') if $self->{debug} == 1;
        my $reconnect=$self->reconnect($k);
        if ($reconnect == 1) {
            my $r2=$self->_FUNC('reconnect_pass',$self,$k,$q,$self->{queue}{ $k->[0] }{ $k->[1] });
        } else {
            my $r2=$self->_FUNC('reconnect_fail',$self,$k,$q,$self->{queue}{ $k->[0] }{ $k->[1] });
                                
            if ($r2 == 1) {
                $self->_FUNC_CALLBACK($k,0,101); #remove thread
            } else {
                $self->_FUNC_CALLBACK($k,0,$r2);
            }
                                
        }
    }
    
    
}

sub _PREPARE {
    my $self=shift;
    my $hosts=shift;
    
    foreach my $i ( 0..$#{$hosts} ) {
   
        my %new=( %{$hosts->[$i]} );
        $self->{host}{ $new{Host} }||=$new{Host};
        $self->{last}=[[$new{Host},0],0] if $i == 0; 
        if ($self->{host}{ $new{Host} }=~s/\:(\d+?)$//is) {
            $self->{port}{ $new{Host} }=$1;  
        }
    
        $self->{secure}{ $new{Host} }=$new{Secure}||$self->{defaults}{secure};
        $self->{port}{ $new{Host} }||=$new{Port}||$self->{defaults}{port};
        $self->{helo}{ $new{Host} }=$new{Hello}||$self->{host}{ $new{Host} };
        $self->{timeout}{ $new{Host} }=$new{Timeout}||$self->{defaults}{timeout};
        $self->{threads}{ $new{Host} }=$new{Threads}||$self->{defaults}{threads};
        $self->{queue_size}=-1;
       
        foreach my $t ( 0..$self->{threads}{ $new{Host} } ) {
            $self->{auth}{ $new{Host} }{$t}=[0,''];
            $self->{queue}{ $new{Host} }{$t}=[];
            
            push(@{$self->{order}}, [$new{Host},$t,1] );
            
            $self->_CONNECT([$new{Host},$t]);

            
        }
    
    }
}

sub _CONNECT {
    my $self=shift;
    my $k=shift;
    
    my $cb=Coro::rouse_cb;
    my $g=tcp_connect($self->{host}{ $k->[0] }, $self->{port}{ $k->[0] },
        #Coro::rouse_cb
        sub{
            my $sock=$_[0];
            $self->_SECURE($k,$sock) if ($self->{secure}{ $k->[0] } == 1 or $self->{secure}{ $k->[0] } == 2);
            $cb->($sock);

        }   
    );
   
    $self->{fh}{ $k->[0] }{ $k->[1] }=unblock +(Coro::rouse_wait)[0];
    


            $self->_READ($k);
            
            if ($self->{status_code}{ $k->[0] }{ $k->[1] } == 220) {
                my $r=$self->_FUNC('connect_pass',$self,$k,0,$self->{queue}{ $k->[0] }{ $k->[1] });
                
                if ($r != 1) {
                    $self->_FUNC_CALLBACK($k,0,$r);
                }
                
            } else {
                #FAIL TO CONNECT
                my $r=$self->_FUNC('connect_fail',$self,$k,0,$self->{queue}{ $k->[0] }{ $k->[1] });
                
                if ($r == 1) {
                    $self->_FUNC_CALLBACK($k,0,101); #remove thread
                } else {
                    $self->_FUNC_CALLBACK($k,0,$r);
                }
                
                
            }
            
            $self->_WRITE($k,'EHLO '.$self->{helo}{ $k->[0] });

            $self->_READ($k);
            $self->_HEADER($k);
    
    
}

sub _NEXT {
    my $self=shift;
    my $k=shift;
    
    my @next;
    
    while (!exists($next[0])) {
        $self->{last}[1]++;
        if (exists($self->{order}[ $self->{last}[1] ]) and $self->{order}[ $self->{last}[1] ][2]==1) {
            @next=( $self->{order}[ $self->{last}[1] ], $self->{last}[1] );
        } else {
            @next=($self->{order}[0],0);    
        }
        
    }
    
    
    $self->{last}=\@next;
}

sub _SECURE {
    my $self=shift;
    my $k=shift;
    my $sock=shift;
    
    require IO::Socket::SSL;
    
    my $sel = IO::Select->new($sock); # wait until it connected
    if ($sel->can_write) {
        $self->_DEBUG($k,'IO::Socket::INET connected') if $self->{debug} == 1;
    }
    
    my %extra;
    if ($self->{secure}{ $k->[0] } == 1) {
        $extra{SSL_verify_mode}=Net::SSLeay::VERIFY_NONE(),
    }
    
    

    IO::Socket::SSL->start_SSL($sock, %extra, SSL_startHandshake => 0);

    while (1) {
        if ($sock->connect_SSL) { # will not block
            $self->_DEBUG($k,'IO::Socket::SSL connected') if $self->{debug} == 1;
            last;
        }
        else { # handshake still incomplete
            $self->_DEBUG($k,'IO::Socket::SSL not connected yet') if $self->{debug} == 1;
            if ( IO::Socket::SSL->want_read() ) {
                $sel->can_read;
            }
            elsif ( IO::Socket::SSL->want_write()) {
                $sel->can_write;
            }
            else {
               $self->_DEBUG($k,'IO::Socket::SSL unknown error: '. $IO::Socket::SSL::SSL_ERROR) if $self->{debug} == 1;
               #SSL ERROR
            }
        }
    }
    
}

sub _HEADER {
    my $self=shift;
    my $k=shift;
    
    my $fh= $self->{fh}{ $k->[0] }{ $k->[1] };
  my $nb_fh = $fh->fh;
  my $buf = \$fh->rbuf;

  while () {
        # now use buffer contents, modifying
        # if necessary to reflect the removed data

        last if $$buf ne ""; # we have leftover data

        # read another buffer full of data
        $fh->readable or die "end of file";
        sysread $nb_fh, $$buf, 8192;
    }

    foreach my $line (split/[\r\n]+/,$$buf) {
        $line=~m/^((\d{3})[ \-](\w+?)(?: (.*?)|)[\r\n]*?)$/is;
        $self->_DEBUG($k,$1) if $self->{debug}==1;
        my $status = lc($2);
        my $head = lc($3);
        $self->{header}{ $k->[0] }{ $k->[1] }{$head}=[split/ /,($4||'')];
    }
    $fh->rbuf='';
}

sub _READ {
    my $self=shift;
    my $k=shift;
    
    my $str;
    my $waitcount=0;
    do {
    $str=$self->{fh}{ $k->[0] }{ $k->[1] }->readline();
    $waitcount++;
    Coro::AnyEvent::sleep 1 if $waitcount % 2 == 0;
    $str='' if $waitcount >= 5;
    } while(!defined($str));
    
    
    
    if (defined($str) and $str=~m/^((\d{3}).(.*?))[\r\n]+?$/) {
        $self->_DEBUG($k,$1) if $self->{debug}==1;
        $self->{buffer}{ $k->[0] }{ $k->[1] }=$1;
        $self->{status_code}{ $k->[0] }{ $k->[1] }=$2;
        $self->{status_text}{ $k->[0] }{ $k->[1] }=$3;
    } else {
        $self->{buffer}{ $k->[0] }{ $k->[1] }='';
        $self->{status_code}{ $k->[0] }{ $k->[1] }=-1;
        $self->{status_text}{ $k->[0] }{ $k->[1] }='';
    }
   
}

sub _WRITE {
    my $self=shift;
    my $k=shift;
    my $str=shift;
    $str=~s/[\r\n]+?$//s;
    $self->_DEBUG($k,'>>'.$str) if $self->{debug}==1;
    $self->{fh}{ $k->[0] }{ $k->[1] }->print($str."\r\n");
}

sub _DEBUG {
    my $self=shift;
    my $k=shift;
    print '['.$k->[0].':'.$k->[1].'] '.shift."\n";
}

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
