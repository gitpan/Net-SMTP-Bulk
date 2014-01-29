package Net::SMTP::Bulk::AnyEvent;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

use MIME::Base64;



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

    bless($self, $class||'Net::SMTP::AnyEvent');

    $self->{new}=\%new;
    $self->{encode} =  ( ($new{Encode}||'') eq '1' ) ? 'utf8':'';
    $self->{debug} = (($new{Debug}||0) >= 1) ? int($new{Debug}):0;
    $self->{debug_path} = $new{DebugPath}||'debug_[HOST]_[THREAD].txt';
    $self->{func} = $new{Callbacks};
    $self->{defaults}={
                       threads=>$new{Threads}||2,
                       port=>$new{Port}||25,
                       timeout=>$new{Timeout}||30,
                       secure=>$new{Secure}||0
                       };
    
    
    $self->{cv} = AnyEvent->condvar;
    
    if (exists($new{Hosts})) {
       $self->_PREPARE($new{Hosts});
    } else {
       $self->_PREPARE([\%new]);
    }

    return $self;
}




sub auth {
    my $self=shift;
    my $type=shift;
    my $user=shift;
    my $pass=shift;
    my $k=shift||$self->{last}[0];
    
    
    #if ( !exists($self->{auth}{ $k->[0] }{ $k->[1] }[0]) ) {
        
    
    
     $self->{auth}{ $k->[0] }{ $k->[1] }=[$type,$user,$pass];
    
 # print "GOTHERE($self->{last}[0][0]){ $k->[0] }{ $k->[1] }\n";
    if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'HEADER' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 1 ) {
                $self->_AUTH($k);
    }
    
    #}
    
}


sub mail {
    my $self=shift;
    my $user=shift;
    my $k=shift||$self->{last}[0];


    $self->{queue}{ $k->[0] }{ $k->[1] }[$self->{queue_size}{ $k->[0] }{ $k->[1] }]{mail}=$user;
    # $self->{data}{ $k->[0] }{ $k->[1] }{mail}=$user;
    #if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'MAIL' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 0 ) {
    #            $self->_MAIL($k);
    #} elsif ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'END' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 0 ) {
    #            $self->_MAIL($k);
    #}
    
}


sub to {
    my $self=shift;
    my $user=shift;
    my $k=shift||$self->{last}[0];

    

    $self->{queue}{ $k->[0] }{ $k->[1] }[$self->{queue_size}{ $k->[0] }{ $k->[1] }]{to}=$user;
    #$self->{data}{ $k->[0] }{ $k->[1] }{to}=$user;
    #if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'TO' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 0 ) {
    #            $self->_TO($k);
    #}  
}

sub data {
    my $self=shift;
    my $k=shift||$self->{last}[0];
    
    $self->{queue}{ $k->[0] }{ $k->[1] }[$self->{queue_size}{ $k->[0] }{ $k->[1] }]{data}='';
    #$self->{data}{ $k->[0] }{ $k->[1] }{data}='';
    #if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'DATA' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 0 ) {
    #            $self->_DATA($k);
    #}  
}


sub datasend {
    my $self=shift;
    my $data=shift;
    my $k=shift||$self->{last}[0];
    
    $self->{queue}{ $k->[0] }{ $k->[1] }[$self->{queue_size}{ $k->[0] }{ $k->[1] }]{data}.=$data;
    #$self->{data}{ $k->[0] }{ $k->[1] }{data}.=$data;
}

sub dataend {
    my $self=shift;
    my $k=shift||$self->{last}[0];
        $self->{queue_size}{ $k->[0] }{ $k->[1] }++;
      #  print "PQ($self->{queue_size}{ $k->[0] }{ $k->[1] })\n";
    #if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'DATA' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 0 ) {
    #            $self->_DATAEND($k);
    #} 
    
    $self->_NEXT();
    # $self->_BULK();
}


sub quit {
    my $self=shift;
    
    
    foreach my $h ( keys(%{ $self->{threads} })  ) {
        foreach my $t ( 0..$self->{threads}{ $h } ) {
#print "QSS($#{$self->{queue}{ $h }{ $t }})\n";
             if ( $#{$self->{queue}{ $h }{ $t }} >= 0 ) {
     
            $self->{cv}->begin;
            $self->_CONNECT([$h,$t]);
      
            }
        }
    }
    #$self->_BULK();
     $self->{cv}->recv;
}



sub reconnect {
       my $self=shift;
    my $k=shift||$self->{last}[0];
    
    
    $self->{fh}{ $k->[0] }{ $k->[1] }->destroy if defined($self->{fh}{ $k->[0] }{ $k->[1] });
    #$self->{cv}->end;
    #delete($self->{auth}{ $k->[0] }{ $k->[1] });
    #$self->{cv}->begin;
            $self->_CONNECT($k);
    
}



sub _PREPARE {
    my $self=shift;
    my $hosts=shift;
    $self->{order}=[];
    $self->{open_threads}=0;
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
        $self->{threads}{ $new{Host} }=($new{Threads}||$self->{defaults}{threads}) - 1;
        $self->{open_threads}+=$self->{threads}{ $new{Host} };
        
       
        foreach my $t ( 0..$self->{threads}{ $new{Host} } ) {
            if ($self->{debug} == 2) {
                my $path=''.$self->{debug_path};
                $path=~s/\[HOST\]/$new{Host}/gs;
                $path=~s/\[THREAD\]/$t/gs;
                open( $self->{debug_fh}{ $new{Host}.':'.$t } , '>>'.$path );
                binmode( $self->{debug_fh}{ $new{Host}.':'.$t } , ':utf8' );
            }

            
            $self->{auth}{ $new{Host} }{$t}=[0,''];
            $self->{queue}{ $new{Host} }{$t}=[];
            $self->{queue_size}{ $new{Host} }{$t}=0;    
            push(@{$self->{order}}, [$new{Host},$t,1] );
            
            #$self->_CONNECT([$new{Host},$t]);

        }
        
        
=head2        
        foreach my $t ( 0..$self->{threads}{ $new{Host} } ) {
            $self->_HELO([$new{Host},$t]);
        }
        foreach my $t ( 0..$self->{threads}{ $new{Host} } ) {
            $self->_READ([$new{Host},$t]);
            $self->_HEADER([$new{Host},$t]);
        }
=cut
    
    }
}


sub _CONNECT {
    my $self=shift;
    my $k=shift;
    
            my %extra;
         
            if ( $self->{secure}{ $k->[0] } == 1 ) {
                %extra=(
                    tls      => "connect",
                    tls_ctx  => { verify => 0, verify_peername => "smtp" }
                );
            } elsif ( $self->{secure}{ $k->[0] } == 2 ) {
                %extra=(
                    tls      => "connect",
                    tls_ctx  => { verify => 1, verify_peername => "smtp" }
                );
            }
 
     $self->_DEBUG($k,"Connecting to $self->{host}{ $k->[0] } on port $self->{port}{ $k->[0] }") if $self->{debug} >= 1;
     
     $self->{fh}{ $k->[0] }{ $k->[1] } = new AnyEvent::Handle(
      connect  => [$self->{host}{ $k->[0] }, $self->{port}{ $k->[0] }],
      on_read=>sub { $self->_READ($k); },
      on_error=>sub {
        
        my $r=$self->_FUNC('fail',$self,$k,0,[$self->{on_queue}{ $k->[0] }{ $k->[1] }]);
       
        $self->reconnect($k->[0],$k->[1]);
        
        },
      %extra
      );
               
                
                
}

sub _FUNC {
    my $self=shift;
    no strict;
    my $func=shift;
    return &{$self->{func}{$func}}(@_) if exists($self->{func}{$func});
    return 1;
}

sub _BULK {
    my $self=shift;
    
    
    
}

sub _NEXT {
    my $self=shift;
    my $k=shift;
    
    my @next;
    
    while (!exists($next[0])) {
        $self->{last}[1]++;
        
        if (exists($self->{order}[ $self->{last}[1] ])) {
           # if ($self->{order}[ $self->{last}[1] ][2]==1) {
                @next=( $self->{order}[ $self->{last}[1] ], $self->{last}[1] );
              
           # }
        } else {
         
            
           
              @next=($self->{order}[0],0);    
        }
           #print "NEXT(@next)\n";
 
        
    }
    
    
    $self->{last}=\@next;
}

###########################


sub _HELO {
    my $self=shift;
    my $k=shift;
    
    $self->_WRITE($k,'EHLO '.$self->{helo}{ $k->[0] });
}

sub _AUTH {
    my $self=shift;
    my $k=shift;
    
    if ($self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'AUTH' ) {
        
        if ($self->{auth}{ $k->[0] }{ $k->[1] }[0] eq 'LOGIN') {
            
            if ( $self->{status_text}{ $k->[0] }{ $k->[1] } eq 'VXNlcm5hbWU6' ) {
                my $temp=MIME::Base64::encode_base64($self->{auth}{ $k->[0] }{ $k->[1] }[1]);
                $temp=~s/[\r\n]//gs;
                $self->_WRITE($k,$temp);
                
            } elsif ( $self->{status_text}{ $k->[0] }{ $k->[1] } eq  'UGFzc3dvcmQ6' ) {
                my $temp=MIME::Base64::encode_base64($self->{auth}{ $k->[0] }{ $k->[1] }[2]);
                $temp=~s/[\r\n]//gs;
                $self->_WRITE($k,$temp);  
            }
            
            
            
        }
    } else {
        $self->{stage}{ $k->[0] }{ $k->[1] }=['AUTH',0];
        $self->_WRITE($k,'AUTH '.$self->{auth}{ $k->[0] }{ $k->[1] }[0]);
        $self->{stage}{ $k->[0] }{ $k->[1] }=['AUTH',1];
        
    }
    
}

sub _MAIL {
    my $self=shift;
    my $k=shift;
    
    $self->{queue_size}{ $k->[0] }{ $k->[1] }--;
    $self->{on_queue}{ $k->[0] }{ $k->[1] }=shift(@{ $self->{queue}{ $k->[0] }{ $k->[1] } });
    #print "QUEUES($#{$self->{queue}{ $k->[0] }{ $k->[1] }})\n";
    
    if ( $self->{queue_size}{ $k->[0] }{ $k->[1] } == -1 ) {
        
      $self->{cv}->end;
      $self->_WRITE($k,'QUIT');
      $self->{stage}{ $k->[0] }{ $k->[1] }=['END',0];
    } else {
    
    
    $self->{stage}{ $k->[0] }{ $k->[1] }=['MAIL',1];
    #$self->_WRITE($k,'MAIL FROM: '.$self->{data}{ $k->[0] }{ $k->[1] }{mail});
    $self->_WRITE($k,'MAIL FROM: '.$self->{on_queue}{ $k->[0] }{ $k->[1] }{mail});
    $self->{stage}{ $k->[0] }{ $k->[1] }=['MAIL',2];
    }
}

sub _TO {
    my $self=shift;
    my $k=shift;
    $self->{stage}{ $k->[0] }{ $k->[1] }=['TO',1];
    #$self->_WRITE($k,'RCPT TO: '.$self->{data}{ $k->[0] }{ $k->[1] }{to});
    $self->_WRITE($k,'RCPT TO: '.$self->{on_queue}{ $k->[0] }{ $k->[1] }{to});
   
    $self->{stage}{ $k->[0] }{ $k->[1] }=['TO',2];
}

sub _DATA {
    my $self=shift;
    my $k=shift;
    $self->{stage}{ $k->[0] }{ $k->[1] }=['DATA',1];
    $self->_WRITE($k,'DATA');
    $self->{stage}{ $k->[0] }{ $k->[1] }=['DATA',2];
}

sub _DATAEND {
    my $self=shift;
    my $k=shift;
    $self->{stage}{ $k->[0] }{ $k->[1] }=['DATAEND',1];
    #$self->_WRITE($k,$self->{data}{ $k->[0] }{ $k->[1] }{data}."\r\n.");
    $self->_WRITE($k,$self->{on_queue}{ $k->[0] }{ $k->[1] }{data}."\r\n.");
    
    $self->{stage}{ $k->[0] }{ $k->[1] }=['DATAEND',2];
    $self->{data}{ $k->[0] }{ $k->[1] }={};
      #$self->{cv}->end;
}

sub _HEADER {
    my $self=shift;
    my $k=shift;
    my $line=shift;
    
    $line=~m/^((\d{3})[ \-](\w+?)(?: (.*?)|)[\r\n]*?)$/is;

    my $status = lc($2);
    my $head = lc($3);
    
    $self->{header}{ $k->[0] }{ $k->[1] }{$head}=[split/ /,($4||'')];
}


###########################


sub _READ {
    my $self=shift;
    my $k=shift;
    
    $self->{fh}{ $k->[0] }{ $k->[1] }->push_read (line => sub {
        
        $self->{handle}{ $k->[0] }{ $k->[1] }=shift;
        $self->{buffer}{ $k->[0] }{ $k->[1] }=shift;
        $self->_DEBUG($k,$self->{buffer}{ $k->[0] }{ $k->[1] }) if $self->{debug} >= 1;
            
        if ($self->{buffer}{ $k->[0] }{ $k->[1] }=~m/^(\d+?)[ \-](.*?)$/is) {
            $self->{status_code}{ $k->[0] }{ $k->[1] }=$1;
            $self->{status_text}{ $k->[0] }{ $k->[1] }=$2;


            if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'DATAEND' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 2 ) {
                #$self->{cv}->end;
                #$self->{open_threads}--;
                #if ($self->{open_threads} == -1) {
                  #  $self->{cv} = AnyEvent->condvar;
                #    $self->{open_threads}=3;
                #}
                
                
                #print "THREADS($self->{open_threads})\n";
                $self->{stage}{ $k->[0] }{ $k->[1] }=['MAIL',0];
            }
            
            if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 220 ) {
                $self->{stage}{ $k->[0] }{ $k->[1] }=['HELO',0];
                my $r=$self->_FUNC('connect_pass',$self,$k,0,$self->{queue}{ $k->[0] }{ $k->[1] });
               
                $self->_HELO($k);
                $self->{stage}{ $k->[0] }{ $k->[1] }=['HELO',1];
            } elsif ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 221 ) {
                $self->{fh}{ $k->[0] }{ $k->[1] }->destroy;
            } elsif ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and !exists($self->{header}{ $k->[0] }{ $k->[1] }{'ok'}) ) {
                $self->{stage}{ $k->[0] }{ $k->[1] }=['HEADER',0];
                $self->_HEADER($k,$self->{buffer}{ $k->[0] }{ $k->[1] });
        
                if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and exists($self->{header}{ $k->[0] }{ $k->[1] }{'ok'}) ) {
                     $self->{stage}{ $k->[0] }{ $k->[1] }=['HEADER',1]; 
                    
                    if ( $self->{status_code}{ $k->[0] }{ $k->[1] } == 250 and exists($self->{auth}{ $k->[0] }{ $k->[1] }) ) {
                        $self->_AUTH($k);
                    } else {
                         $self->{stage}{ $k->[0] }{ $k->[1] }=['MAIL',0];
                    }
                }
               
               
            } elsif ($self->{status_code}{ $k->[0] }{ $k->[1] } == 334 and $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'AUTH' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 1 ) {
                 $self->_AUTH($k);
            } elsif ($self->{status_code}{ $k->[0] }{ $k->[1] } == 235 and $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'AUTH' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 1 ) {
                 $self->{stage}{ $k->[0] }{ $k->[1] }=['MAIL',0];
            }
            
            
            if (  $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'MAIL' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 0 ) {
                $self->_MAIL($k);
                
            } elsif ( $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'MAIL' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 2  ) {
                
                if ($self->{status_code}{ $k->[0] }{ $k->[1] } == 250) {
                    $self->{stage}{ $k->[0] }{ $k->[1] }=['TO',0];
                    $self->_TO($k);
                    
                }
                
                
            } elsif ( $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'TO' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 2  ) {
                
                if ($self->{status_code}{ $k->[0] }{ $k->[1] } == 250) {
                    $self->{stage}{ $k->[0] }{ $k->[1] }=['DATA',0];
                    $self->_DATA($k);
                    
                }
                
                
            } elsif ( $self->{stage}{ $k->[0] }{ $k->[1] }[0] eq 'DATA' and $self->{stage}{ $k->[0] }{ $k->[1] }[1] == 2  ) {
                
                if ($self->{status_code}{ $k->[0] }{ $k->[1] } == 354) {
                    $self->{stage}{ $k->[0] }{ $k->[1] }=['DATAEND',0];
                    $self->_DATAEND($k);
                    
                }
                
                
            }
            

            
            

        }
        
    });
    
}

sub _WRITE {
   my $self=shift;
   my $k=shift;
    my $str=shift;
    $str=~s/[\r\n]+?$//s;
   $self->_DEBUG($k,'>>'.$str) if $self->{debug} >= 1;
   $self->{handle}{ $k->[0] }{ $k->[1] }->push_write( ($self->{encode} ne '') ? Encode::encode($self->{encode}=>$str."\r\n"):$str."\r\n" );
}

sub _DEBUG {
    my $self=shift;
    my $k=shift;
    my $str=shift||'';
    if ($self->{debug} == 1) {
        print '['.$k->[0].':'.$k->[1].'] '.$str."\n";
    } else {
        print { $self->{debug_fh}{ $k->[0].':'.$k->[1] }  } '['.$k->[0].':'.$k->[1].'] '.$str."\n";
    }
}

1;