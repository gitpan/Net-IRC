#####################################################################
#                                                                   #
#   Net::IRC -- Object-oriented Perl interface to an IRC server     #
#                                                                   #
#   IRC.pm: A nifty little wrapper that makes your life easier.     #
#                                                                   #
#          Copyright (c) 1997 Greg Bacon & Dennis Taylor.           #
#                       All rights reserved.                        #
#                                                                   #
#      This module is free software; you can redistribute it        #
#      and/or modify it under the terms of the Perl Artistic        #
#             License, distributed with this module.                #
#                                                                   #
#####################################################################


package Net::IRC;

use 5.004;             # needs IO::* and $coderef->(@args) syntax 
use Net::IRC::Connection;
use IO::Select;
use strict;
use vars qw($VERSION
	    $DEBUG_PARSER
	    $DEBUG_SELECT
	    $DEBUG_ALLIN
	    $DEBUG_SENDLINE
	    $DEBUG_EVENTS
	    $DEBUG_HANDLERS
	    $DEBUG_ALLOUT
	    $DEBUG_TOOMUCH);

# the script that rolls Net::IRC into a tar.gz'd distribution replaces this
# with the actual version number. Nifty, huh? Not really. :)

$VERSION = "0.41";

$DEBUG_PARSER   = 0x0100;
$DEBUG_SELECT   = 0x0200;
$DEBUG_ALLIN    = 0xff00;
$DEBUG_SENDLINE = 0x0001;
$DEBUG_EVENTS   = 0x0002;
$DEBUG_HANDLERS = 0x0004;
$DEBUG_ALLOUT   = 0x00ff;
$DEBUG_TOOMUCH  = 0xffff;

# Anyone have any more categories to recommend? Note that I haven't
# actually included the debugging code in there yet... that's for
# the next time I get unlazy and unbusy at the same time.  :-)


#####################################################################
#        Methods start here, arranged in alphabetical order.        #
#####################################################################

# Adds a Connection to the connections list and sets changed.
sub addconn {
    my ($self,$conn) = @_;

    push(@{$self->{'conn'}}, $conn) if defined $conn;
    $self->changed;

    return $conn;
}

# Simple enough for ya? This lets the select loop know that it needs to
# rebuild the list of active filehandles. No args.
sub changed {
    $_[0]->{'changed'} = 1;
}

# Prints an error message when a socket gets closed on us.
# Takes at least 1 arg:  the object whose socket is in question
#            (optional)  an error message to print.
sub closed {
    my ($self, $obj, $err) = @_;

    if (ref($obj) eq 'Net::IRC::Connection') {

	$obj->printerr("Connection to " . $obj->server . " closed" .
		       ($! ? ": $!." : "."));
    } else {

	$obj->{_parent}->printerr("Connection closed" . ($! ? ": $!." : "."))
	    if $obj->{_parent};
    }
}

# Returns or sets the debugger level for this Net::IRC object.
# Takes 1 optional arg:  the new debugger level.
sub debug {
    my $self = shift;

    if (@_) { $self->{'debug'} = $_[0] }
    else    { return $self->{'debug'}  }
}

# Returns or sets the contained IO::Select object for this Net::IRC object.
# Takes 1 optional arg:  the new IO::Select object.
sub ioselect {
    my $self = shift;

    if (@_) { $self->{'io_select'} = $_[0] }
    else    { return $self->{'io_select'}  }
}

# Ye Olde Contructor Methode. You know the drill.
# Takes absolutely no args whatsoever.
sub new {
    my $proto = shift;

    my $self = {
	        'conn'     => [],
		'connhash' => {},
		'debug'    =>  0,
		'fraghash' => {},
	       };

    bless $self, $proto;
    $self->ioselect(IO::Select->new());

    # -- #perl was here! --
    # *** Notice -- Received KILL message for [Gump]. From TrueCynic Path: *.
    # concentric.net[irc@ircd.concentric.net]!irc.best.net!usr10.primenet.com
    # !TrueCynic (Clone, forrest! Clone!)
    
    return $self;
}

# Creates and returns a new Connection object.
# Any args here get passed to Connection->connect().
sub newconn {
    my $self = shift;
    my $conn = Net::IRC::Connection->new($self, @_);

    push @{$self->{'conn'}}, $conn;
    $self->changed;
    return $conn unless $conn->error;
    return undef;
}

# Removes a given Connection and sets changed.
# sub removeconn looks bad, but it'd be consistant with {add,new}conn..
sub remove_conn {
    my ($self, $conn) = @_;
    
    @{$self->{'conn'}} = grep { $_ != $conn } @{$self->{'conn'}};
    $self->changed;
}

# Begin the main loop. Wheee. Hope you remembered to set up your handlers
# first... (takes no args, of course)
sub start {
    my $self = shift;

    # -- #perl was here! --
    #  ChipDude: Pudge:  Do not become the enemy.
    #    ^Pudge: give in to the dark side, you knob.
    
    while (1) {
	my ($conn, $sock);
	my $select = $self->ioselect;
	
	if ($self->{'changed'}) {
	    $select->remove($select->handles);
	    $self->{'connhash'} = {};
	    foreach $conn ( @{$self->{'conn'}} ) {
		$select->add( $conn->socket )
		    if $conn->socket->opened;
		$self->{'connhash'}->{$conn->socket} = $conn;
		$self->{'fraghash'}->{$conn->socket} = '';
	    }
	    $self->{'changed'} = 0;
	}
	
	# Block until input arrives... I regret the use of an extraneous
	# variable here, but it's pretty ooogly otherwise, as $conn would
	# change contexts.
	
	foreach $sock ($select->can_read(undef)) {
	    my ($line, $input);
	    
	    # -- #perl was here! --
	    #   Tkil2: hm.... any joy if you add a 'defined' to the test? like
	    #          if (defined $sock...
	    # fimmtiu: Much joy now.
	    #   archon rejoices
	    
	    my $frag = $self->{'fraghash'}->{$sock};
	    if (defined $sock->recv($input, 10240)) {
		$frag .= $input;
		if (length($frag) > 0) {
		    # Tkil sez: "thanks to tchrist for pointing out that the -1
		    # keeps null fields at the end".  (tkil rewrote this part)
		    # We're returning \n's 'cause DCC's need 'em
		    my @lines = split /(\n)/, $frag, -1;
		    $frag = (@lines > 1 ? pop @lines : '');
		    foreach $line (@lines) {
			$self->{'connhash'}->{$sock}->parse($line);
		    }
		} else {
		    # um, if we can read, i say we should read more than 0
		    # besides, recv isn't returning undef on closed
		    # sockets.  getting rid of this connection...
		    $self->closed($self->{'connhash'}->{$sock}, $!);
		    $self->remove_conn($self->{'connhash'}->{$sock});
		}
	    } else {
		# Error, lets scrap this Connection
		$self->closed($self->{'connhash'}->{$sock}, $!);
		$self->remove_conn($self->{'connhash'}->{$sock});
	    }
	    
	    $self->{'fraghash'}->{$sock} = $frag;
	}
    }
}


1;
