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

$Net::IRC::DCC::nextport = 5555;


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

    my ($class, $container, $address, $port, $size, $filename) = @_;
    
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

    unless(defined $sock) {
        $container->printerr("Can't connect to $address: $!");
        $fh->close();
        return undef;
    }

    $sock->autoflush(1);

    my $self = {
        _bin        =>  0,      # Bytes we've recieved thus far
        _bout       =>  0,      # Bytes we've sent
        _fh         =>  $fh,    # FileHandle we will be writing to.
        _filename   =>  $filename,
        _size       =>  $size,  # Expected size of file
        _socket     =>  $sock,  # Socket we're reading from
        _time       =>  time, 
        _connected  =>  1,
        _parent     =>  $container
    };

    bless $self, $class;

    return $self;
}

# -- #perl was here! --
#  \merlyn: we were both ogling a bartender named arley
#  \merlyn: I mean carle
#  \merlyn: carly
# Silmaril: man merlyn
# Silmaril: you shouold have offered HER the shower.
#   \petey: all three of them?

sub parse {
    my ($self, $line) = @_;

    unless( $self->{_fh}->write($line, length($line)) ) {
        $self->{_parent}->printerr("Error writing to " . 
             $self->{_filename} . ": $!");
        $self->{_fh}->close;
        $self->{_parent}->parent->remove_conn($self);
        return;
    }

    $self->{_bin} += length($line);

    # confirm the packet we've just recieved
    unless ( $self->{_socket}->send( pack("N", $self->{_bin}) ) ) {
        $self->{_parent}->printerr("Error writing to socket: $!");
        $self->{_fh}->close;
        $self->{_parent}->parent->remove_conn($self);
        return;
    }

    $self->{_bout} += 4;

    # If we close the socket, the select loop gets screwy because
    # it won't remove its reference to the socket.  weird.
    if ( $self->{_size} && $self->{_size} == $self->{_bin} ) {
        $self->{_parent}->parent->remove_conn($self);
        $self->{_fh}->close;
    }

    1;
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

    $blocksize = 1024 unless $blocksize;

    $fh = new IO::File $filename;

    unless (defined $fh) {
        $container->printerr("Couldn't open $filename for read: $!");
        return undef;
    }

    binmode $fh;
    $fh->seek(0, SEEK_END);
    $size = $fh->tell;
    $fh->seek(0, SEEK_SET);

    $port = $Net::IRC::DCC::nextport++;

    $sock = new IO::Socket::INET( Proto     => "tcp",
				  LocalPort => $port,
                                  Listen    => 1);

    unless (defined $sock) {
        $container->printerr("Couldn't open socket: $!");
        $fh->close;
        return undef;
    }

    $container->ctcp('DCC SEND', $nick, $filename, 
                     unpack("N",inet_aton(hostname())), $port, $size);

    # this accept() blocks.  if they don't connect, the client is hung
    # what's the fix?
    $sock = $sock->accept;

    unless (defined $sock) {
        $container->printerr("Error in accept: $!");
        $fh->close;
        return undef;
    }

    $sock->autoflush(1);

    # ok, to get the ball rolling, we send them the first packet.
    # the rest will get sent from parse()
    my $buf;
    return undef unless defined $fh->read($buf,$blocksize);
    return undef unless defined $sock->send($buf);


    my $self = {
        _bin        =>  0,         # Bytes we've recieved thus far
        _blocksize  =>  $blocksize,       
        _bout       =>  0,         # Bytes we've sent
        _fh         =>  $fh,       # FileHandle we will be reading from.
        _filename   =>  $filename,
        _parent     =>  $container,
        _size       =>  $size,     # Size of file
        _socket     =>  $sock,     # Socket we're writing to
        _time       =>  time, 
    };

    bless $self, $class;

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
    my ($self, $size) = @_;
    my  $buf;

    # i don't know how useful this is, but let's stay consistent
    $self->{_bin} += 4;

    $size = unpack("N", $size);

    if ($size == $self->{_size}) {
        # they've acknowledged the whole file,  we outtie
        $self->{_fh}->close;
        $self->{_parent}->parent->remove_conn($self);
        return;
    } 

    # we're still waiting for acknowledgement, 
    # better not send any more
    return if $size < $self->{_bout};

    unless (defined $self->{_fh}->read($buf,$self->{_blocksize})) {
        $self->{_fh}->close;
        $self->{_parent}->parent->remove_conn($self);
        return;
    }

    unless($self->{_socket}->send($buf)) {
        $self->{_fh}->close;
        $self->{_parent}->parent->remove_conn($self);
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

    my $sock;

    if ($type) {
        # we're initiating

        $port = $Net::IRC::DCC::nextport++;
        $sock = new IO::Socket::INET( Proto     => "tcp",
				      LocalPort => $port,
                                      Listen    => 1);

        unless (defined $sock) {
            $container->printerr("Couldn't open socket: $!");
            print("Couldn't open socket: $!");
            return undef;
        }

        $container->ctcp('DCC CHAT', $nick, 'chat',  
                         unpack("N",inet_aton(hostname)), $port);

        # this will block, leaving the client in a bad position
        $sock = $sock->accept;

        unless (defined $sock) {
            $container->printerr("Error in connect: $!");
            return undef;
        }

    } else {      # we're connecting

        $address = inet_ntoa(pack("N",$address));
        $sock = new IO::Socket::INET( Proto    => "tcp",
				      PeerAddr => "$address:$port");

        unless (defined $sock) {
            $container->printerr("Error in connect: $!");
            return undef;
        }
    }

    $sock->autoflush(1);

    my $self = {
        _bin        =>  0,      # Bytes we've recieved thus far
        _bout       =>  0,      # Bytes we've sent
        _socket     =>  $sock,  # Socket we're reading from
        _time       =>  time,
	_nick       =>  $nick,  # Nick of the client on the other end
        _connected  =>  1,
        _parent     =>  $container
    };

    bless $self, $class;

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
    my ($self, $line) = @_;

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


1;
