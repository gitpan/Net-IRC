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

$VERSION = "0.45";


#####################################################################
#        Methods start here, arranged in alphabetical order.        #
#####################################################################

# Adds a Connection to the connections list and sets changed.
sub addconn {
    my ($self,$conn) = @_;

    push(@{$self->{_conn}}, $conn) if defined $conn;
    $self->changed;

    return $conn;
}

# Simple enough for ya? This lets the select loop know that it needs to
# rebuild the list of active filehandles. No args.
sub changed {
    $_[0]->{_changed} = 1;
}

# Prints an error message when a socket gets closed on us.
# Takes at least 1 arg:  the object whose socket is in question
#            (optional)  an error message to print.
sub closed {
    my ($self, $obj, $err) = @_;
    my (@peer);
    
    $err ||= $!;   # Err can be $! if it's not yet set.
    
    if (@peer = $obj->peer) {

	# This is a bit of an ugly hack. Suggestions welcome.
	until ($obj->can("printerr")) {  $obj = $obj->{_parent};  }
	
	$obj->printerr($peer[1] . " to " . $peer[0] . " closed" .
		       ($err ? ": $err." : "."));
    } else {

	$obj->{_parent}->printerr("Connection closed" . ($err ? ": $err." : "."))
	    if $obj->{_parent};
    }
}

# Returns or sets the debugger level for this Net::IRC object.
# Takes 1 optional arg:  the new debugger level.
sub debug {
    my $self = shift;

    if (@_) { $self->{_debug} = $_[0] }
    else    { return $self->{_debug}  }
}

# Goes through one iteration of the main event loop. Useful for integrating
# other event-based systems (Tk, etc.) with Net::IRC.
# Takes no args.
sub do_one_loop {
    my $self = shift;
    
    # -- #perl was here! --
    #  ChipDude: Pudge:  Do not become the enemy.
    #    ^Pudge: give in to the dark side, you knob.
    
    my ($conn, $sock, $time, $nexttimer, $timeout);
    my $select = $self->{_ioselect};
    
    if ($self->{_changed}) {
	$select->remove($select->handles);
	$self->{_connhash} = {};
	foreach $conn ( @{$self->{_conn}} ) {
	    $select->add( $conn->socket )
		if $conn->socket->opened;
	    $self->{_connhash}->{$conn->socket} = $conn;
	    $self->{_fraghash}->{$conn->socket} = '';
	}
	$self->{_changed} = 0;
    }
    
    # Check the queue for scheduled events to run.
    
    $time = time;              # no use calling time() all the time.
    $nexttimer = 0;
    foreach $sock ($self->queue) {     # we can reuse $sock, too. Woo!
	if ($self->{_queue}->{$sock}->[0] <= $time) {
	    $self->{_queue}->{$sock}->[1]->
		(@{$self->{_queue}->{$sock}}[2..$#{$self->{_queue}->{$sock}}]);
	    delete $self->{_queue}->{$sock};
	} else {
	    $nexttimer = $self->{_queue}->{$sock}->[0] 
		if ($self->{_queue}->{$sock}->[0] < $nexttimer
		    or not $nexttimer);
	}
    }
    # Block until input arrives... I regret the use of an extraneous
    # variable here, but it's pretty ooogly otherwise, as $conn would
    # change contexts.
    
    $timeout = $nexttimer ? $nexttimer - $time : $self->{_timeout};
    foreach $sock ($select->can_read($timeout)) {
	my ($line, $input);
	
	# -- #perl was here! --
	#   Tkil2: hm.... any joy if you add a 'defined' to the test? like
	#          if (defined $sock...
	# fimmtiu: Much joy now.
	#   archon rejoices

	if ($self->{_connhash}->{$sock}->{_nonblock}) {
	    $self->{_connhash}->{$sock}->parse();
	    next;
	}
	
	my $frag = $self->{_fraghash}->{$sock};
	if (defined $sock->recv($input, 10240)) {
	    $frag .= $input;
	    if (length($frag) > 0) {
		# Tkil sez: "thanks to tchrist for pointing out that the -1
		# keeps null fields at the end".  (tkil rewrote this part)
		# We're returning \n's 'cause DCC's need 'em
		my @lines = split /(\n)/, $frag, -1;
		$frag = (@lines > 1 ? pop @lines : '');
		foreach $line (@lines) {
		    $self->{_connhash}->{$sock}->parse($line);
		}
	    } else {
		# um, if we can read, i say we should read more than 0
		# besides, recv isn't returning undef on closed
		# sockets.  getting rid of this connection...
		$self->closed($self->{_connhash}->{$sock});
		$self->removeconn($self->{_connhash}->{$sock});
	    }
	} else {
	    # Error, lets scrap this Connection
	    $self->closed($self->{_connhash}->{$sock});
	    $self->removeconn($self->{_connhash}->{$sock});
	}
	
	$self->{_fraghash}->{$sock} = $frag;
    }
}

# Ye Olde Contructor Methode. You know the drill.
# Takes absolutely no args whatsoever.
sub new {
    my $proto = shift;

    my $self = {
	        '_conn'     => [],
		'_connhash' => {},
		'_debug'    =>  0,
		'_fraghash' => {},
		'_ioselect' => IO::Select->new(),
		'_queue'    => {},
		'_qid'      => 'a',
		'_timeout'  =>  1,
	    };

    bless $self, $proto;

    # -- #perl was here! --
    # *** Notice -- Received KILL message for [Gump]. From TrueCynic Path: *.
    # concentric.net[irc@ircd.concentric.net]!irc.best.net!usr10.primenet.com
    # !TrueCynic (Clone, Forrest! Clone!)
    
    return $self;
}

# Creates and returns a new Connection object.
# Any args here get passed to Connection->connect().
sub newconn {
    my $self = shift;
    my $conn = Net::IRC::Connection->new($self, @_);

    push @{$self->{_conn}}, $conn;
    $self->changed;
    return $conn unless $conn->error;
    return undef;
}

# Returns a list of listrefs to event scheduled to be run.
# Takes the args passed to it by Connection->schedule()... see it for details.
sub queue {
    my $self = shift;

    if (@_) {
	$self->{_qid} = 'a' if $self->{_qid} eq 'zzzzzzzz';
	$self->{_queue}->{$self->{_qid}++} = [ @_ ];

    } else {

	return keys %{$self->{_queue}};
    }
}

# Removes a given Connection and sets changed.
# Takes 1 arg:  a Connection (or DCC or whatever) to remove.
sub removeconn {
    my ($self, $conn) = @_;
    
    @{$self->{_conn}} = grep { $_ != $conn } @{$self->{_conn}};
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
	$self->do_one_loop();
    }
}

# Sets or returns the current timeout, in seconds, for the select loop.
# Takes 1 optional arg:  the new value for the timeout, in seconds.
# Fractional timeout values are just fine, as per the core select().
sub timeout {
    my $self = shift;

    if (@_) { $self->{_timeout} = $_[0] }
    return $self->{_timeout};
}

1;


__END__


=head1 NAME

Net::IRC - Perl interface to the Internet Relay Chat protocol

=head1 SYNOPSIS

    use Net::IRC;

    $irc = new Net::IRC;
    $conn = $irc->newconn(Nick    => 'some_nick',
                          Server  => 'some.irc.server.com',
	                  Port    =>  6667,
			  Ircname => 'Some witty comment.');
    $irc->start;

=head1 DESCRIPTION

Welcome to Net::IRC, a work in progress. First intended to be a quick tool
for writing an IRC script in Perl, Net::IRC has grown into a comprehensive
Perl implementation of the IRC protocol (RFC 1459), supported and developed by
several members of the EFnet IRC channel #perl.

There are 4 component modules which make up Net::IRC:

=over

=item *

Net::IRC

The wrapper for everything else, containing methods to generate
Connection objects (see below) and a connection manager which does an event
loop, reads available data from all currently open connections, and passes
it off to the appropriate parser in a separate package.

=item *

Net::IRC::Connection

The big time sink on this project. Each Connection instance is a
single connection to an IRC server. The module itself contains methods for
every single IRC command available to users (Net::IRC isn't designed for
writing servers, for obvious reasons), methods to set, retrieve, and call
handler functions which the user can set (more on this later), and too many
cute comments. Hey, what can I say, we were bored.

=item *

Net::IRC::Event

Kind of a struct-like object for storing info about things that the
IRC server tells you (server responses, channel talk, joins and parts, et
cetera). It records who initiated the event, who it affects, the event
type, and any other arguments provided for that event. Incidentally, the
only argument passed to a handler function.

=item *

Net::IRC::DCC

The analogous object to Connection.pm for connecting, sending and
retrieving with the DCC protocol. Invoked from
C<Connection-E<gt>new_{send,get,chat}> in the same way that
C<IRC-E<gt>newconn> invokes C<Connection-E<gt>new>. This will make more
sense later, we promise.

=back

The central concept that Net::IRC is built around is that of handlers
(or hooks, or callbacks, or whatever the heck you wanna call them). We
tried to make it a completely event-driven model, a la Tk -- for every
conceivable type of event that your client might see on IRC, you can give
your program a custom subroutine to call. But wait, there's more! There are
3 levels of handler precedence:

=over

=item *

Default handlers

Considering that they're hardwired into Net::IRC, these won't do
much more than the bare minimum needed to keep the client listening on the
server, with an option to print (nicely formatted, of course) what it hears
to whatever filehandles you specify (STDOUT by default). These get called
only when the user hasn't defined any of his own handlers for this event.

=item *

User-definable global handlers

The user can set up his own subroutines to replace the default
actions for I<every> IRC connection managed by your program. These only get
invoked if the user hasn't set up a per-connection handler for the same
event.

=item *

User-definable per-connection handlers

Simple: this tells a single connection what to do if it gets an event of
this type. Supersedes global handlers if any are defined for this event.

=back

And even better, you can choose to call your custom handlers before
or after the default handlers instead of replacing them, if you wish. In
short, it's not perfect, but it's about as good as you can get and still be
documentable, given the sometimes horrendous complexity of the IRC protocol.


=head1 GETTING STARTED

=head2 Initialization

To start a Net::IRC script, you need two things: a Net::IRC object, and a
Net::IRC::Connection object. The Connection object does the dirty work of
connecting to the server; the IRC object handles the input and output for it.
To that end, say something like this:

    use Net::IRC;

    $irc = new Net::IRC;

    $conn = $irc->newconn(Nick    => 'some_nick',
                          Server  => 'some.irc.server.com');

...or something similar. Acceptable parameters to newconn() are:

=over

=item *

Nick

The nickname you'll be known by on IRC, often limited to a maximum of 9
letters. Acceptable characters for a nickname are C<[\w{}[]\`^|-]>. If
you don't specify a nick, it defaults to your username.

=item *

Server

The IRC server to connect to. There are dozens of them across several
widely-used IRC networks, but the oldest and most popular is EFNet (Eris
Free Net), home to #perl. See http://www.irchelp.org/ for lists of
popular servers, or ask a friend.

=item *

Port

The port to connect to this server on. By custom, the default is 6667.

=item *

Username

On systems not running identd, you can set the username for your user@host
to anything you wish. Note that some IRC servers won't allow connections from
clients which don't run identd.

=item *

Ircname

A short (maybe 50 or 60 chars) piece of text, originally intended to display
your real name, which people often use for pithy quotes and URLs. Defaults to
the contents of your GECOS field.

=back

=head2 Handlers

Once that's over and done with, you need to set up some handlers if you want
your bot to do anything more than sit on a connection and waste resources.
Handlers are references to subroutines which get called when a specific event
occurs. Here's a sample handler sub:

    # What to do when the bot successfully connects.
    sub on_connect {
        my $self = shift;

        $self->print("Joining #IRC.pm...");
        $self->join("#IRC.pm");
        $self->privmsg("#IRC.pm", "Hi there.");
    }

The arguments to a handler function are always the same:

=over

=item $_[0]:

The Connection object that's calling it.

=item $_[1]:

An Event object (see below) that describes what the handler is responding to.

=back

Got it? If not, see the examples in the irctest script that came with this
distribution. Anyhow, once you've defined your handler subroutines, you need
to add them to the list of handlers as either a global handler (affects all
Connection objects) or a local handler (affects only a single Connection). To
do so, say something along these lines:

    $self->add_global_handler('376', \&on_connect);     # global
    $self->add_handler('msg', \&on_msg);                # local

376, incidentally, is the server number for "end of MOTD", which is an event
that the server sends to you after you're connected. See Event.pm for a list
of all possible numeric codes. The 'msg' event gets called whenever someone
else on IRC sends your client a private message. For a big list of possible
events, see the B<Event List> section in the documentation for
Net::IRC::Event.

=head2 Getting Connected

When you've set up all your handlers, the following command will put your
program in an infinite loop, grabbing input from all open connections and
passing it off to the proper handlers:

    $irc->start;

Note that new connections can be added and old ones dropped from within your
handlers even after you call this. Just don't expect any code below the call
to C<start()> to ever get executed.

If you're tying Net::IRC into another event-based module, such as perl/Tk,
there's a nifty C<do_one_loop()> method provided for your convenience. Calling
C<$irc-E<gt>do_one_loop()> runs through the IRC.pm event loop once, reads from
all ready filehandles, and dispatches their events, then returns control to
your program. Currently, performance on this is a little slow, but we're
working on it.

=head1 METHOD DESCRIPTIONS

This section contains only the methods in IRC.pm itself. Lists of the
methods in Net::IRC::Connection, Net::IRC::Event, or Net::IRC::DCC are in
their respective modules' documentation; just C<perldoc Net::IRC::Connection>
(or Event or DCC or whatever) to read them. Functions take no arguments
unless otherwise specified in their description.

By the way, expect Net::IRC to use Autoloader sometime in the future, once
it becomes a little more stable.

=over

=item *

addconn()

Adds the specified socket or filehandle to the list of readable connections
and notifies C<do_one_loop()>.

Takes 1 arg:

=over

=item 0.

a socket or filehandle to add to the select loop

=back

=item *

changed()

Sets a flag which tells C<do_one_loop()> that the current list of readable
connections needs to be rebuilt. It's not likely that many users will need
this... just use C<addconn()> and C<removeconn()> instead.

=item *

debug()

This doesn't yet even pretend to be functional. It may be in the future; wait
and see.

=item *

do_one_loop()

C<select()>s on all open sockets and passes any information it finds to the
appropriate C<parse()> method in a separate package for handling. Also
responsible for executing scheduled events from
C<Net::IRC::Connection-E<gt>schedule()> on time.

=item *

new()

A fairly vanilla constructor which creates and returns a new Net::IRC object.

=item *

newconn()

Creates and returns a new Connection object. All arguments are passed straight
to C<Net::IRC::Connection-E<gt>new()>; examples of common arguments can be
found in the B<Synopsis> or B<Getting Started> sections.

=item *

removeconn()

Removes the specified socket or filehandle from the list of readable
filehandles and notifies C<do_one_loop()> of the change.

Takes 1 arg:

=over

=item 0.

a socket or filehandle to remove from the select loop

=back

=item *

start()

Starts an infinite event loop which repeatedly calls C<do_one_loop()> to
read new events from all open connections and pass them off to any
applicable handlers.

=back

=head1 AUTHORS

=over

=item *

Conceived and initially developed by Greg Bacon (gbacon@adtran.com)
and Dennis Taylor (corbeau@execpc.com).

=item *

Ideas and large amounts of code donated by Nat "King" Torkington
(gnat@frii.com).

=item *

Currently being hacked on, hacked up, and worked over by the members of the
Net::IRC developers mailing list. For details, see
http://www.execpc.com/~corbeau/irc/list.html .

=back

=head1 URL

The following identical pages contain up-to-date source and information
about the Net::IRC project:

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

    
