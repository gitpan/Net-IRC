#####################################################################
#                                                                   #
#   Net::IRC -- Object-oriented Perl interface to an IRC server     #
#                                                                   #
#   DCC.pm: An object for Direct Client-to-Client connections.      #
#                                                                   #
#          Copyright (c) 1997 Greg Bacon & Dennis Taylor.           #
#                       All rights reserved.                        #
#                                                                   #
#      This module is free software; you can redistribute it        #
#      and/or modify it under the terms of the Perl Artistic        #
#             License, distributed with this module.                #
#                                                                   #
#####################################################################

package Net::IRC::DCC;

use strict;


# --- #perl was here! ---
#
# The comments scattered throughout this module are excerpts from a
# log saved from one particularly surreal night on #perl. Ahh, the
# trials of being young, single, and drunk...
#
# ---------------------
#           \merlyn has offered the shower to a randon guy he met in a bar.
#  fimmtiu: Shower?
#           \petey raises an eyebrow at \merlyn
#  \merlyn: but he seems like a nice trucker guy...
#   archon: you offered to shower with a random guy?


# Methods that can be shared between the various DCC classes.
package Net::IRC::DCC::Connection;

sub bytes_in {
    return shift->{_bin};
}

sub bytes_out {
    return shift->{_bout};
}

sub socket {
    return shift->{_socket};
}

sub time {
    return time - shift->{_time};
}

sub _getline {
    my ($self, $sock) = @_;
    my ($input, $line);
    my $frag = $self->{_frag};

    if (defined $sock->recv($input, 10240)) {
	$frag .= $input;
	if (length($frag) > 0) {
	    # Tkil sez: "thanks to tchrist for pointing out that the -1
	    # keeps null fields at the end".  (tkil rewrote this part)
	    # We're returning \n's 'cause DCC's need 'em
	    my @lines = split /(\n)/, $frag, -1;
	    $self->{_frag} = (@lines > 1 ? pop @lines : '');
	    return (@lines);
	}
	else {
	    # um, if we can read, i say we should read more than 0
	    # besides, recv isn't returning undef on closed
	    # sockets.  getting rid of this connection...
	    $self->{_parent}->handler(Net::IRC::Event->new('dcc_close',
							   $self->{_nick},
							   $self->{_socket},
							   $self->{_type}));
	    $self->{_parent}->parent->removefh($sock);
	    return undef;
	}
    } else {
	# Error, lets scrap this connection
	$self->{_parent}->handler(Net::IRC::Event->new('dcc_close',
						       $self->{_nick},
						       $self->{_socket},
						       $self->{_type}));
	$self->{_parent}->parent->removefh($sock);
	return undef;
    }
}

sub DESTROY {
    my $self = shift;
    
    $self->{_parent}->handler(Net::IRC::Event->new('dcc_close',
						   $self->{_nick},
						   $self->{_socket},
						   $self->{_type}));
}

sub peer {
    return ( $_[0]->{_nick}, "DCC " . $_[0]->{_type} );
}

# -- #perl was here! --
#     orev: hehe...
# Silmaril: to, not with.
#   archon: heheh
# tmtowtdi: \merlyn will be hacked to death by a psycho
#   archon: yeah, but with is much more amusing


# Connection handling GETs
package Net::IRC::DCC::GET;

use IO::Socket;

@Net::IRC::DCC::GET::ISA = qw(Net::IRC::DCC::Connection);

sub new {

    my ($class, $container, $nick, $address, $port, $size, $filename) = @_;
    
    my ($sock, $fh);

    # get the address into a dotted quad
    $address = inet_ntoa(pack("N",$address));

    $fh = new IO::File ">$filename";

    unless(defined $fh) {
        $container->printerr("Can't open $filename for writing: $!");
        $sock = new IO::Socket::INET( Proto    => "tcp",
				      PeerAddr => "$address:$port" ) and
        $sock->close();
        return undef;
    }

    binmode $fh;
    $fh->autoflush(1);

    $sock = new IO::Socket::INET( Proto    => "tcp",
				  PeerAddr => "$address:$port" );

    if (defined $sock) {
	$container->handler(Net::IRC::Event->new('dcc_open',
						 $nick,
						 $sock,
						 'get',
						 'get', $sock));
	
    } else {
        $container->printerr("Can't connect to $address: $!");
        $fh->close();
        return undef;
    }
    
    $sock->autoflush(1);

    my $self = {
        _bin        =>  0,      # Bytes we've recieved thus far
        _bout       =>  0,      # Bytes we've sent
        _connected  =>  1,
        _fh         =>  $fh,    # FileHandle we will be writing to.
        _filename   =>  $filename,
	_frag       =>  '',
	_nick       =>  $nick,  # Nick of person on other end
        _parent     =>  $container,
        _size       =>  $size,  # Expected size of file
        _socket     =>  $sock,  # Socket we're reading from
        _time       =>  time, 
	_type       =>  'GET',
        };

    bless $self, $class;

    return $self;
}

# -- #perl was here! --
#  \merlyn: we were both ogling a bartender named arley
#  \merlyn: I mean carle
#  \merlyn: carly
# Silmaril: man merlyn
# Silmaril: you should have offered HER the shower.
#   \petey: all three of them?

sub parse {
    my ($self) = shift;

    foreach my $line ($self->_getline($_[0])) {
    
	unless( $self->{_fh}->write($line, length($line)) ) {
	    $self->{_parent}->printerr("Error writing to " . 
				       $self->{_filename} . ": $!");
	    $self->{_fh}->close;
	    $self->{_parent}->parent->removeconn($self);
	    return;
	}
	
	$self->{_bin} += length($line);
	
	# confirm the packet we've just recieved
	unless ( $self->{_socket}->send( pack("N", $self->{_bin}) ) ) {
	    $self->{_parent}->printerr("Error writing to socket: $!");
	    $self->{_fh}->close;
	    $self->{_parent}->parent->removeconn($self);
	    return;
	}
	
	$self->{_bout} += 4;
	
	# If we close the socket, the select loop gets screwy because
	# it won't remove its reference to the socket.  weird.
	if ( $self->{_size} && $self->{_size} <= $self->{_bin} ) {
	    $self->{_parent}->parent->removeconn($self);
	    $self->{_fh}->close;
	}
    }
} 

# -- #perl was here! --
#  \merlyn: I can't type... she created a numbner of very good drinks
#  \merlyn: She's still at work
#           \petey resists mentioning that there's "No manual entry
#           for merlyn."
# Silmaril: Haven't you ever seen swingers?
#  \merlyn: she's off tomorrow... will meet me at the bar at 9:30
# Silmaril: AWWWWwwww yeeeaAAHH.
#   archon: waka chica waka chica


# Connection handling SENDs
package Net::IRC::DCC::SEND;
@Net::IRC::DCC::SEND::ISA = qw(Net::IRC::DCC::Connection);

use IO::File;
use IO::Socket;
use Sys::Hostname;

sub new {

    my ($class, $container, $nick, $filename, $blocksize) = @_;
    my ($size, $port, $fh, $sock, $select);

    $blocksize ||= 1024;

    $fh = new IO::File $filename;

    unless (defined $fh) {
        $container->printerr("Couldn't open $filename for read: $!");
        return undef;
    }

    binmode $fh;
    $fh->seek(0, SEEK_END);
    $size = $fh->tell;
    $fh->seek(0, SEEK_SET);

    $sock = new IO::Socket::INET( Proto     => "tcp",
				  LocalPort => &Socket::INADDR_ANY(),
                                  Listen    => 1);

    if (defined $sock) {
	$container->handler(Net::IRC::Event->new('dcc_open',
						 $nick,
						 $sock,
						 'send',
						 'send', $sock));
	
    } else {
        $container->printerr("Couldn't open socket: $!");
        $fh->close;
        return undef;
    }    

    $container->ctcp('DCC SEND', $nick, $filename, 
                     unpack("N",inet_aton(hostname())),
		     $sock->sockport(), $size);

    $sock->autoflush(1);

    my $self = {
        _bin        =>  0,         # Bytes we've recieved thus far
        _blocksize  =>  $blocksize,       
        _bout       =>  0,         # Bytes we've sent
        _fh         =>  $fh,       # FileHandle we will be reading from.
        _filename   =>  $filename,
	_frag       =>  '',
	_nick       =>  $nick,
        _parent     =>  $container,
        _size       =>  $size,     # Size of file
        _socket     =>  $sock,     # Socket we're writing to
        _time       =>  time, 
	_type       =>  'SEND',
    };

    bless $self, $class;
    
    $sock = Net::IRC::DCC::Accept->new($sock, $self);

    unless (defined $sock) {
        $container->printerr("Error in accept: $!");
        $fh->close;
        return undef;
    }

    return $self;
}

# -- #perl was here! --
#  fimmtiu: So a total stranger is using your shower?
#  \merlyn: yes... a total stranger is using my hotel shower
#           Stupid coulda sworn \merlyn was married...
#   \petey: and you have a date.
#  fimmtiu: merlyn isn't married.
#   \petey: not a bad combo......
#  \merlyn: perhaps a adate
#  \merlyn: not maerried
#  \merlyn: not even sober. --)

sub parse {
    my ($self, $sock) = @_;
    my $size = ($self->_getline($sock))[0];
    my $buf;

    # i don't know how useful this is, but let's stay consistent
    $self->{_bin} += 4;

    unless (defined $size) {
	# Dang! The other end unexpectedly canceled.
        $self->{_parent}->printerr(($self->peer)[1] . " connection to " .
				   ($self->peer)[0] . " lost.");
	$self->{_parent}->parent->removefh($sock);
	return undef;
    }
    
    $size = unpack("N", $size);
    
    if ($size == $self->{_size}) {
        # they've acknowledged the whole file,  we outtie
        $self->{_fh}->close;
        $self->{_parent}->parent->removeconn($self);
        return;
    } 

    # we're still waiting for acknowledgement, 
    # better not send any more
    return if $size < $self->{_bout};

    unless (defined $self->{_fh}->read($buf,$self->{_blocksize})) {
        $self->{_fh}->close;
        $self->{_parent}->parent->removeconn($self);
        return;
    }

    unless($self->{_socket}->send($buf)) {
        $self->{_fh}->close;
        $self->{_parent}->parent->removeconn($self);
    }

    $self->{_bout} += length($buf);

    return 1;
}

# -- #perl was here! --
#  fimmtiu: Man, merlyn, you must be drunk to type like that. :)
#  \merlyn: too many longislands.
#  \merlyn: she made them strong
#   archon: it's a plot
#  \merlyn: not even a good amoun tof coke
#   archon: she's in league with the guy in your shower
#   archon: she gets you drunk and he takes your wallet!


# handles CHAT connections
package Net::IRC::DCC::CHAT;
@Net::IRC::DCC::CHAT::ISA = qw(Net::IRC::DCC::Connection);

use IO::Socket;
use Sys::Hostname;

sub new {

    my ($class, $container, $type, $nick, $address, $port) = @_;
    my ($sock, $self);

    if ($type) {
        # we're initiating

        $sock = new IO::Socket::INET( Proto     => "tcp",
				      LocalPort => &Socket::INADDR_ANY(),
                                      Listen    => 1);
	
        unless (defined $sock) {
            $container->printerr("Couldn't open socket: $!");
            print("Couldn't open socket: $!");
            return undef;
        }

	$sock->autoflush(1);

        $container->ctcp('DCC CHAT', $nick, 'chat',  
                         unpack("N",inet_aton(hostname)), $sock->sockport());

	$self = {
	    _bin        =>  0,      # Bytes we've recieved thus far
	    _bout       =>  0,      # Bytes we've sent
	    _connected  =>  1,
	    _frag       =>  '',
	    _nick       =>  $nick,  # Nick of the client on the other end
	    _parent     =>  $container,
	    _socket     =>  $sock,  # Socket we're reading from
	    _time       =>  time,
	    _type       =>  'CHAT',
	};
	
	bless $self, $class;
	
        $sock = Net::IRC::DCC::Accept->new($sock, $self);

	if (defined $sock) {
	    $container->handler(Net::IRC::Event->new('dcc_open',
						     $nick,
						     $sock->socket,
						     'chat',
						     'chat', $sock->socket));
	    
	} else {
	    $container->printerr("Error in DCC CHAT connect: $!");
	    return undef;
	}
	
    } else {      # we're connecting

        $address = inet_ntoa(pack("N",$address));
        $sock = new IO::Socket::INET( Proto    => "tcp",
				      PeerAddr => "$address:$port");
	$sock->autoflush(1);

        if (defined $sock) {
	    my $ev = Net::IRC::Event->new('dcc_open',
					  $nick,
					  $sock,
					  'chat',
					  'chat', $sock);
	} else {
	    $container->printerr("Error in connect: $!");
	    return undef;
	}

	$self = {
	    _bin        =>  0,      # Bytes we've recieved thus far
	    _bout       =>  0,      # Bytes we've sent
	    _connected  =>  1,
	    _nick       =>  $nick,  # Nick of the client on the other end
	    _parent     =>  $container,
	    _socket     =>  $sock,  # Socket we're reading from
	    _time       =>  time,
	    _type       =>  'CHAT',
	};
	
	bless $self, $class;
	
	$self->{_parent}->parent->addfh($self->socket,
					$self->can('parse'), 'rw', $self);
    }

    return $self;
}

# -- #perl was here! --
#  \merlyn: tahtd be coole
#           KTurner bought the camel today, so somebody can afford one
#           more drink... ;)
# tmtowtdi: I've heard of things like this...
#  \merlyn: as an experience. that is.
#   archon: i can think of cooler things (;
#  \merlyn: I don't realiy have that mch in my wallet.

sub parse {
    my ($self, $sock) = @_;
    my $line = ($self->_getline($sock))[0];
    return unless defined $line;
    
    $self->{_bin} += length($line);

    return undef if $line eq "\n";
    my $ev = Net::IRC::Event->new('chat',
				  $self->{_nick},
				  $self->{_socket},
				  'chat',
				  $line);
    
    $self->{_bout} += length($line);
    $self->{_parent}->handler($ev);
}

# -- #perl was here! --
#  \merlyn: this girl carly at the bar is aBABE
#   archon: are you sure? you don't sound like you're in a condition to
#           judge such things (;
# *** Stupid has set the topic on channel #perl to \merlyn is shit-faced
#     with a trucker in the shower.
# tmtowtdi: uh, yeah...
#  \merlyn: good topic


# Sockets waiting for accept() use this to shoehorn into the select loop.
package Net::IRC::DCC::Accept;

@Net::IRC::DCC::Accept::ISA = qw(Net::IRC::DCC::Connection);

sub new {
    my ($class, $sock, $parent) = @_;
    my ($self);

    $self = {
	     _nonblock =>  1,
	     _socket   =>  $sock,
	     _parent   =>  $parent,
	     _type     =>  'accept',
            };
    
    bless $self, $class;

    # Tkil's gonna love this one. :-)   But what the hell... it's safe to
    # assume that the only thing initiating DCCs will be Connections, right?
    $self->{_parent}->{_parent}->parent->addconn($self);
    return $self;
}

sub parse {
    my ($self) = shift;
    my ($sock);
    
    $sock = $self->{_socket}->accept;
    $self->{_parent}->{_socket} = $sock;

    if ($self->{_parent}->{_type} eq 'SEND') {
	# ok, to get the ball rolling, we send them the first packet.
	my $buf;
	unless (defined $self->{_parent}->{_fh}->
		read($buf, $self->{_parent}->{_blocksize})) {
	    return undef;
	}
	return undef unless defined $sock->send($buf);
    }
    
    $self->{_parent}->{_parent}->parent->addconn($self->{_parent});
    $self->{_parent}->{_parent}->parent->removeconn($self);
}



1;


__END__

=head1 NAME

Net::IRC::DCC - Object-oriented interface to a single DCC connection

=head1 SYNOPSIS

Hard hat area: This section under construction.

=head1 DESCRIPTION

This documentation is a subset of the main Net::IRC documentation. If
you haven't already, please "perldoc Net::IRC" before continuing.

Net::IRC::DCC defines a few subclasses that handle DCC CHAT, GET, and SEND
requests for inter-client communication. DCC objects are created by
C<Connection-E<gt>new_{chat,get,send}()> in much the same way that
C<IRC-E<gt>newconn()> creates a new connection object.

B<NOTE:> DCC CHAT and SEND currently block on the accept() call when setting up
a new connection. This will probably change in the near future, but bear it in
mind for the time being if you expect to use these heavily.

=head1 METHOD DESCRIPTIONS

This section is under construction, but hopefully will be finally written up
by the next release. Please see the C<irctest> script and the source for
details about this module.

=head1 AUTHORS

Conceived and initially developed by Greg Bacon (gbacon@adtran.com) and
Dennis Taylor (corbeau@execpc.com).

Ideas and large amounts of code donated by Nat "King" Torkington (gnat@frii.com).

Currently being hacked on, hacked up, and worked over by the members of the
Net::IRC developers mailing list. For details, see
http://www.execpc.com/~corbeau/irc/list.html .

=head1 URL

The following identical pages contain up-to-date source and information about
the Net::IRC project:

=over

=item *

http://www.execpc.com/~corbeau/irc/

=item *

http://betterbox.net/fimmtiu/irc/

=back

=head1 SEE ALSO

=over

=item *

perl(1).

=item *

RFC 1459: The Internet Relay Chat Protocol

=item *

http://www.irchelp.org/, home of fine IRC resources.

=back

=cut
