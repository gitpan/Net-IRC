#####################################################################
#                                                                   #
#   Net::IRC -- Object-oriented Perl interface to an IRC server     #
#                                                                   #
#   Connection.pm: The basic functions for a simple IRC connection  #
#                                                                   #
#                                                                   #
#          Copyright (c) 1997 Greg Bacon & Dennis Taylor.           #
#                       All rights reserved.                        #
#                                                                   #
#      This module is free software; you can redistribute it        #
#      and/or modify it under the terms of the Perl Artistic        #
#             License, distributed with this module.                #
#                                                                   #
#####################################################################


#####################################################################
#  Here's the headers. Package vars are all defined at the bottom,  #
#       though, because they're big and long and boring. :P         #
#####################################################################

package Net::IRC::Connection;

use Net::IRC::Event;
use Net::IRC::DCC;
use IO::Socket;
use strict;               # A little anal-retention never hurt...
use vars (                # with a few exceptions...
	  '$AUTOLOAD',    #   - the name of the sub in &AUTOLOAD
	  '%_udef',       #   - the hash containing the user's global handlers
	  '%autoloaded',  #   - the hash containing names of &AUTOLOAD methods
	 );


# The names of the methods to be handled by &AUTOLOAD.
# It seems the values ought to be useful *somehow*...
my %autoloaded = (
		  'ircname'  => undef,
		  'port'     => undef,
		  'username' => undef,
		  'socket'   => undef,
		  'verbose'  => undef,
		  'parent'   => undef,
		 );

# This hash will contain any global default handlers that the user specifies.

my %_udef = ();



#####################################################################
#        Methods start here, arranged in alphabetical order.        #
#####################################################################


# This sub is the common backend to add_handler and add_global_handler
#
sub _add_generic_handler
{
    my ($self, $event, $ref, $rp, $hash_ref, $real_name) = @_;
    my $ev;
    my %define = ( "replace" => 0, "before" => 1, "after" => 2 );

    unless (@_ >= 3) {
	$self->printerr("Not enough arguments to $real_name()");
	return undef;
    }
    unless (ref($ref) eq 'CODE') {
	$self->printerr("Second argument of $real_name isn't a coderef");
	return undef;
    }

    # Translate REPLACE, BEFORE and AFTER.
    if (not defined $rp) {
	$rp = 0;
    } elsif ($rp =~ /^\D/) {
	$rp = $define{lc $rp} || 0;
    }

    foreach $ev (ref $event eq "ARRAY" ? @{$event} : $event) {
	# Translate numerics to names
	if ($ev =~ /^\d/) {
	    $ev = Net::IRC::Event->trans($ev);
	    unless ($ev) {
		$self->printerr("Unknown event type in $real_name: $ev");
		return undef;
	    }
	}

	$hash_ref->{$ev} = [ $ref, $rp ];
    }
    return 1;
}

# This sub will assign a user's custom function to a particular event which
# might be received by any Connection object.
# Takes 3 args:  the event to modify, as either a string or numeric code
#                   If passed an arrayref, the array is assumed to contain
#                   all event names which you want to set this handler for.
#                a reference to the code to be executed for the event
#    (optional)  A value indicating whether the user's code should replace
#                the built-in handler, or be called with it. Possible values:
#                   0 - Replace the built-in handlers entirely. (the default)
#                   1 - Call this handler right before the default handler.
#                   2 - Call this handler right after the default handler.
# These can also be referred to by the #define-like strings in %define.
sub add_global_handler {
    my ($self, $event, $ref, $rp) = @_;
        return $self->_add_generic_handler($event, $ref, $rp,
					   \%_udef, 'add_global_handler');
}

# This sub will assign a user's custom function to a particular event which
# this connection might receive.  Same args as above.
sub add_handler {
    my ($self, $event, $ref, $rp) = @_;
        return $self->_add_generic_handler($event, $ref, $rp,
					   $self->{_handler}, 'add_handler');
}

# Why do I even bother writing subs this simple? Sends an ADMIN command.
# Takes 1 optional arg:  the name of the server you want to query.
sub admin {
    my $self = shift;        # Thank goodness for AutoLoader, huh?

    $self->sl("ADMIN" . ($_[0] ? " $_[0]" : ""));
}

# Takes care of the methods in %autoloaded
# Sets specified attribute, or returns its value if called without args.
sub AUTOLOAD {
    my $self = @_;  ## can't modify @_ for goto &name
    my $class = ref $self;  ## die here if !ref($self) ?
    my $meth;
    
    ($meth = $AUTOLOAD) =~ s/^.*:://;  ## strip fully qualified portion

    unless (exists $autoloaded{$meth}) {
	$self->printerr("No method called \"$meth\" for $class object.");
	return;
    }
    
    eval <<EOSub;
sub $meth {
    my \$self = shift;
	
    if (\@_) {
	my \$old = \$self->{"_$meth"};
	
	\$self->{"_$meth"} = shift;
	
	return \$old;
    }
    else {
	return \$self->{"_$meth"};
    }
}
EOSub
    
    ## no reason to play this game every time
    goto &$meth;
}

# Attempts to connect to the specified IRC (server, port) with the specified
#   (nick, username, ircname). Will close current connection if already open.
sub connect {
    my $self = shift;

    if (@_) {
	my (%arg) = @_;

	$self->nick($arg{'Nick'}) if exists $arg{'Nick'};
	$self->port($arg{'Port'}) if exists $arg{'Port'};
	$self->server($arg{'Server'}) if exists $arg{'Server'};
	$self->ircname($arg{'Ircname'}) if exists $arg{'Ircname'};
	$self->username($arg{'Username'}) if exists $arg{'Username'};
    }
    
    # Lots of error-checking claptrap first...
    unless ($self->server) {
	unless ($ENV{IRCSERVER}) {
	    $self->printerr("No server address specified in connect()");
	    return undef;
	}
	$self->server( $ENV{IRCSERVER} );
    }
    unless ($self->nick) {
	$self->nick($ENV{IRCNICK} || eval { scalar getpwuid($>) }
		    || $ENV{USER} || $ENV{LOGNAME} || "WankerBot");
    }
    unless ($self->port) {
	$self->port($ENV{IRCPORT} || 6667);
    }
    unless ($self->ircname)  {
	$self->ircname($ENV{IRCNAME} || eval { (getpwuid($>))[6] }
		       || "Just Another Perl Hacker");
    }
    unless ($self->username) {
	$self->username(eval { scalar getpwuid($>) } || $ENV{USER}
			|| $ENV{LOGNAME} || "japh");
    }
    
    # Now for the socket stuff...
    if ($self->connected) {
	$self->quit("Changing servers");
    }
    
    my $sock = IO::Socket::INET->new(PeerAddr => $self->server,
				     PeerPort => $self->port,
				     Proto    => "tcp",
				    );

    if ($sock) {
	$self->socket($sock);
    } else {
	$self->printerr(sprintf "Can't open socket for %s:%s !",
			$self->server, $self->port);
	$self->error(1);
	return undef;
    }

    # Now, log in to the server...
    unless ($self->sl(sprintf("NICK %s", $self->nick)) &&
	    $self->sl(sprintf("USER %s %s %s :%s",
			      $self->username,
			      "foo.bar.com",
			      $self->server,
			      $self->ircname))) {
	$self->printerr("Couldn't send introduction to server: $!");
	$self->error(1);
	$! = "Couldn't send NICK/USER introduction to " . $self->server;
	return undef;
    }

    $self->{_connected} = 1;
}

# Returns a boolean value based on the state of the object's socket.
sub connected {
    my $self = shift;
    my $sock = $self->socket;

    return ($self->{_connected} && $sock->opened);
}

# Sends a CTCP request to some hapless victim(s).
# Takes at least two args:  the type of CTCP request (case insensitive)
#                           the nick or channel of the intended recipient(s)
# Any further args are arguments to CLIENTINFO, ERRMSG, or ACTION.
sub ctcp {
    my ($self, $type, $target) = splice @_, 0, 3;
    $type = uc $type;

    unless ($target) {
	$self->printerr("Not enough arguments to ctcp()");
	return undef;
    }

    if ($type eq "PING") {
	unless ($self->sl("PRIVMSG $target :\001PING " . time . "\001")) {
	    $self->printerr("Socket error sending $type request in ctcp()");
	    return undef;
	}
    } elsif (($type eq "CLIENTINFO" or $type eq "ACTION") and @_) {
	unless ($self->sl("PRIVMSG $target :\001$type " .
			  join(" ", @_) . "\001")) {
	    $self->printerr("Socket error sending $type request in ctcp()");
	    return undef;
	}
    } elsif ($type eq "ERRMSG") {
	unless (@_) {
	    $self->printerr("Not enough arguments to $type in ctcp()");
	    return undef;
	}
	unless ($self->sl("PRIVMSG $target :\001ERRMSG " .
			  join(" ", @_) . "\001")) {
	    $self->printerr("Socket error sending $type request in ctcp()");
	    return undef;
	}
    } else {
	unless ($self->sl("PRIVMSG $target :\001$type " . 
		join(" ",@_) . "\001")) {
	    $self->printerr("Socket error sending $type request in ctcp()");
	    return undef;
	}
    }
}

# Sends replies to CTCP queries. Simple enough, right?
# Takes 2 args:  the target person or channel to send a reply to
#                the text of the reply
sub ctcp_reply {
    my $self = shift;

    $self->notice($_[0], "\001" . $_[1] . "\001");
}

# Dequotes CTCP messages according to ctcp.spec. Nothing special.
# Then it breaks them into their component parts in a flexible, ircII-
# compatible manner. This is not quite as trivial. Oh, well.
# Takes 1 arg:  the line to be dequoted.
sub dequote {
    my $line = shift;
    my ($order, @chunks) = (0, ());    # CHUNG! CHUNG! CHUNG!
    
    # Filter misplaced \001s before processing... (Thanks, Tom!)
    substr($line, rindex($line, "\001"), 1) = '\\a'
      unless ($line =~ tr/\001//) % 2 == 0;
    
    # Thanks to Abigail (abigail@fnx.com) for this clever bit.
    if (index($line, "\cP") >= 0) {    # dequote low-level \n, \r, ^P, and \0.
        my (%h) = (n => "\n", r => "\r", 0 => "\0", "\cP" => "\cP");
        $line =~ s/\cP([\n\r\0\cP])/$h{$1}/g;
    }
    $line =~ s/\\([^\\a])/$1/g;  # dequote unnecessarily quoted characters.
    
    # -- #perl was here! --
    #     roy7: Chip Chip he's our man!
    #  fimmtiu: If he can't do it, Larry can!
    # ChipDude: I thank you!  No applause, just throw RAM chips!
    
    # If true, it's in odd order... ctcp commands start with first chunk.
    $order = 1 if index($line, "\001") == 0;
    @chunks = map { s/\\\\/\\/g; $_ } (split /\cA/, $line);

    return ($order, @chunks);
}

# Standard destructor method for the GC routines. (HAHAHAH! DIE! DIE! DIE!)
sub DESTROY {
    my $self = shift;
    $self->handler("destroy", "nobody will ever use this");
    $self->quit();
    # anything else?
}

# Tells IRC.pm if there was an error opening this connection. It's just
# for sane error passing.
# Takes 1 optional arg:  the new value for $self->{'iserror'}
sub error {
    my $self = shift;

    $self->{'iserror'} = $_[0] if @_;
    return $self->{'iserror'};
}

# Lets the user set or retrieve a format for a message of any sort.
# Takes at least 1 arg:  the event whose format you're inquiring about
#           (optional)   the new format to use for this event
sub format {
    my ($self, $ev) = splice @_, 0, 2;
    
    unless ($ev) {
        $self->printerr("Not enough arguments to format()");
	return undef;
    }
    
    if (@_) {
        $self->{'_format'}->{$ev} = $_[0];
    } else {
        return ($self->{'_format'}->{$ev} ||
                $self->{'_format'}->{'default'});
    }
}

# Calls the appropriate handler function for a specified event.
# BEWARE: The data structure for the handlers is shockingly ugly. I bet this
#         will be totally incomprehensible to me 10 minutes after I write it.
# Takes 2 args:  the name of the event to handle
#                the arguments to the handler function
sub handler {
    my ($self, $event) = splice @_, 0, 2;

    # Get name of event.
    my $ev;
    if (ref $event) {
	$ev = $event->type;
    } elsif (defined $event) {
	$ev = $event;
	$event = Net::IRC::Event->new($event, '', '', '');
    } else {
	$self->printerr("Not enough arguments to handler()");
	return undef;
    }

    # -- #perl was here! --
    #   <\lembit> tainted code...oh-oh..tainted code...sometimes I know I've
    #             got to (boink boink) run away...
    # <Excession> \lembit I'd ease up on the caffiene if I were you
    
    my $handler = undef;
    if (exists $self->{_handler}->{$ev}) {
	$handler = $self->{_handler}->{$ev};
    } elsif (exists $_udef{$ev}) {
	$handler = $_udef{$ev};
    } else {
	return $self->_default($event, @_);
    }
    
    my ($code, $rp) = @{$handler};
    
    # If we have args left, try to call the handler.
    if ($rp == 0) {                      # REPLACE
	&$code($self, $event, @_);
    } elsif ($rp == 1) {                 # BEFORE
	&$code($self, $event, @_);
	$self->_default($event, @_);
    } elsif ($rp == 2) {                 # AFTER
	$self->_default($event, @_);
	&$code($self, $event, @_);
    } else {
	$self->printerr("Bad parameter passed to handler(): rp=$rp");
	return undef;
    }
    return 1;
}

# Lets a user set hostmasks to discard certain messages from, or (if called
# with only 1 arg), show a list of currently ignored hostmasks of that type.
# Takes 2 args:  type of ignore (public, msg, ctcp, etc)
#    (optional)  [mask(s) to be added to list of specified type]
sub ignore {
    my $self = shift;

    unless (@_) {
	$self->printerr("Not enough arguments to ignore()");
	return undef;
    }
    if (@_ == 1) {
	if (exists $self->{_ignore}->{$_[0]}) {
	    return @{ $self->{_ignore}->{$_[0]} };
	} else {
	    return ();
	}
    } elsif (@_ > 1) {     # code defensively, remember...
	my $type = shift;

	# I moved this part further down as an Obsessive Efficiency
	# Initiative. It shouldn't be a problem if I do _parse right...
	# ... but those are famous last words, eh?
	unless (grep {$_ eq $type}
		qw(public msg ctcp notice channel nick other all)) {

	    $self->printerr("$type isn't a valid type to ignore()");
	    return undef;
	}

	if ( exists $self->{_ignore}->{$type} )  {
	    push @{$self->{_ignore}->{$type}}, @_;
	} else  {
	    $self->{_ignore}->{$type} = [ @_ ];
	}
    }
}

# Yet Another Ridiculously Simple Sub. Sends an INFO command.
# Takes 1 optional arg: the name of the server to query.
sub info {
    my $self = shift;
    
    $self->sl("INFO" . ($_[0] ? " $_[0]" : ""));
}

# Invites someone to an invite-only channel. Whoop.
# Takes 2 args:  the nick of the person to invite
#                the channel to invite them to.
# I hate the syntax of this command... always seemed like a protocol flaw.
sub invite {
    my $self = shift;

    unless (@_ > 1) {
	$self->printerr("Not enough arguments to invite()");
    }
    
    $self->sl("INVITE $_[0] $_[1]");
}

# Checks if a particular nickname is in use.
# Takes at least 1 arg:  nickname(s) to look up.
sub ison {
    my $self = shift;

    unless (@_) {
	$self->printerr('Not enough args to ison().');
	return undef;
    }

    $self->sl("ISON " . join(" ", @_));
}

# Joins a channel on the current server if connected, eh?.
# Corresponds to /JOIN command.
# Takes 2 args:  name of channel to join
#                optional channel password, for +k channels
sub join {
    my $self = shift;
    
    unless ( $self->connected ) {
	$self->printerr("Can't join() -- not connected to a server");
	return undef;
    }

    # -- #perl was here! --
    # *** careful is Starch@ncb.mb.ca (The WebMaster)
    # *** careful is on IRC via server irc.total.net (Montreal Hub &
    #        Client Server)
    # careful: well, it's hard to buy more books now too cause where the
    #          heck do you put them all? i have to move and my puter room is
    #          almost 400 square feet, it's the largest allowed in my basement
    #          without calling it a room and pay taxes, hehe

    unless (@_) {
	$self->printerr("Not enough arguments to join()");
	return undef;
    }

    #  \petey: paying taxes by the room?
    #          \petey boggles
    # careful: that's what they do for finished basements and stuff
    # careful: need an emergency exit and stuff
    #   jjohn: GOOD GOD! ARE THEY HEATHENS IN CANADA? DO THEY EAT THEIR
    #          OWN YOUNG?
    
    return $self->sl("JOIN $_[0]" . ($_[1] ? " $_[1]" : ""));

    # \petey: "On the 'net nobody knows you're Canadian, eh?"
    #  jjohn: shut up, eh?
}

# Opens a righteous can of whoop-ass on any luser foolish enough to ask a
# CGI question in #perl. Eat flaming death, web wankers!
# Takes at least 2 args:  the channel to kick the bastard from
#                         the nick of the bastard in question
#             (optional)  a parting comment to the departing bastard
sub kick {
    my $self = shift;

    unless (@_ > 1) {
	$self->printerr("Not enough arguments to kick()");
	return undef;
    }
    return $self->sl("KICK $_[0] $_[1]" . ($_[2] ? " :$_[2]" : ""));
}

# Gets a list of all the servers that are linked to another visible server.
# Takes 2 optional args:  it's a bitch to describe, and I'm too tired right
#                         now, so read the RFC.
sub links {
    my ($self) = (shift, undef);

    $self->sl("LINKS" . (scalar(@_) ? " " . join(" ", @_[0,1]) : ""));
}


# Requests a list of channels on the server, or a quick snapshot of the current
# channel (the server returns channel name, # of users, and topic for each).
sub list {
    my $self = shift;

    $self->sl("LIST " . join(",", @_));
}

# Sends a request for some server/user stats.
# Takes 1 optional arg: the name of a server to request the info from.
sub lusers {
    my $self = shift;
    
    $self->sl("LUSERS" . ($_[0] ? " $_[0]" : ""));
}

# Gets and/or sets the max line length.  The value previous to the sub
# call will be returned.
# Takes 1 (optional) arg: the maximum line length (in bytes)
sub maxlinelen {
    my $self = shift;

    my $ret = $self->{_maxlinelen};

    $self->{_maxlinelen} = shift if @_;

    return $ret;
}

# Sends an action to the channel/nick you specify. It's truly amazing how
# many IRCers have no idea that /me's are actually sent via CTCP.
# Takes 2 args:  the channel or nick to bother with your witticism
#                the action to send (e.g., "weed-whacks billn's hand off.")
sub me {
    my $self = shift;

    $self->ctcp("ACTION", $_[0], $_[1]);
}

# Change channel and user modes (this one is easy... the handler is a bitch.)
# Takes at least 2 args:  the target of the command (channel or nick)
#                         the mode string (i.e., "-boo+i")
#             (optional)  operands of the mode string (nicks, hostmasks, etc.)
sub mode {
    my $self = shift;

    unless (@_ > 1) {
	$self->printerr("Not enough arguments to mode()");
	return undef;
    }
    $self->sl("MODE $_[0] $_[1] " . join(" ", @_[2..$#_]));
}

# Sends a MOTD command to a server.
# Takes 1 optional arg:  the server to query (defaults to current server)
sub motd {
    my $self = shift;

    $self->sl("MOTD" . ($_[0] ? " $_[0]" : ""));
}

# Requests the list of users for a particular channel (or the entire net, if
# you're a masochist).
# Takes 1 or more optional args:  name(s) of channel(s) to list the users from.
sub names {
    my $self = shift;

    $self->sl("NAMES " . join(",", @_));
    
}   # Was this the easiest sub in the world, or what?

# Creates a new IRC object and assigns some default attributes.
sub new {
    my $proto = shift;

    # -- #perl was here! --
    # <\merlyn> just don't use ref($this) || $this;
    # <\merlyn> tchrist's abomination.
    # <\merlyn> lame lame lame.  frowned upon by any OO programmer I've seen.
    # <tchrist> randal disagrees, but i don't care.
    # <tchrist> Randal isn't being flexible/imaginative.
    # <ChipDude> fimm: WRT "ref ($proto) || $proto", I'm against. Class
    #            methods and object methods are distinct.

    # my $class = ref($proto) || $proto;             # Man, am I confused...
    
    my $self = {                # obvious defaults go here, rest are user-set
		_port       => 6667,
		# Evals are for non-UNIX machines, just to make sure.
		_username   => eval { scalar getpwuid($>) } || $ENV{USER}
		|| $ENV{LOGNAME} || "japh",
		_ircname    => $ENV{IRCNAME} || eval { (getpwuid($>))[6] }
		|| "Just Another Perl Hacker",
		_nick       => $ENV{IRCNICK} || eval { scalar getpwuid($>) }
		|| $ENV{USER} || $ENV{LOGNAME} || "WankerBot",  # heheh...
		_ignore     => {},
		_errout     => [ \*STDERR ],
		_output     => [ \*STDOUT ],
		_handler    => {},
		_verbose    =>  0,       # Is this an OK default?
		_parent     =>  shift,
		_frag       =>  '',
		_connected  =>  0,
		_maxlinelen =>  510,     # The RFC says we shouldn't exceed this.
		_format     => {
		    'default' => "[%f:%t]  %m  <%d>",
		}
	      };
    
    bless $self, $proto;
    # do any necessary initialization here
    $self->connect(@_) if @_;
    
    return $self;
}

# Creates and returns a DCC CHAT object, analogous to IRC.pm's newconn().
# Takes at least 1 arg:   An Event object for the DCC CHAT request.
#                    OR   A list or listref of args to be passed to new(),
#                         consisting of:
#                           - A boolean value indicating whether or not
#                             you're initiating the CHAT connection.
#                           - The nick of the chattee
#                           - The address to connect to
#                           - The port to connect on
sub new_chat {
    my $self = shift;
    my ($init, $nick, $address, $port);

    if (ref($_[0]) =~ /Event/) {
	# If it's from an Event object, we can't be initiating, right?
	($init, undef, undef, undef, $address, $port) = (0, $_[0]->args);
	$nick = $_[0]->nick;

    } elsif (ref($_[0]) eq "ARRAY") {
	($init, $nick, $address, $port) = @{$_[0]};
    } else {
	($init, $nick, $address, $port) = @_;
    }

    # -- #perl was here! --
    #          gnat snorts.
    #    gnat: no fucking microsoft products, thanks :)
    #  ^Pudge: what about non-fucking MS products?  i hear MS Bob is a virgin.
    
    Net::IRC::DCC::CHAT->new($self, $init, $nick, $address, $port);
}

# Creates and returns a DCC GET object, analogous to IRC.pm's newconn().
# Takes at least 1 arg:   An Event object for the DCC SEND request.
#                    OR   A list or listref of args to be passed to new(),
#                         consisting of:
#                           - The nick of the file's sender
#                           - The name of the file to receive
#                           - The address to connect to
#                           - The port to connect on
#                           - The size of the incoming file
sub new_get {
    my $self = shift;
    my ($nick, $name, $address, $port, $size);

    if (ref($_[0]) =~ /Event/) {
	(undef, undef, $name, $address, $port, $size) = $_[0]->args;
	$nick = $_[0]->nick;
    } elsif (ref($_[0]) eq "ARRAY") {
	($nick, $name, $address, $port, $size) = @{$_[0]};
    } else {
	($nick, $name, $address, $port, $size) = @_;
    }

    my $dcc = Net::IRC::DCC::GET->new($self, $nick, $address,
				      $port, $size, $name);

    $self->parent->addconn($dcc) if $dcc;
    return $dcc;
}

# Creates and returns a DCC SEND object, analogous to IRC.pm's newconn().
# Takes at least 2 args:  The nickname of the person to send to
#                         The name of the file to send
#             (optional)  The blocksize for the connection (default 1k)
sub new_send {
    my $self = shift;
    my ($nick, $filename, $blocksize);
    
    if (ref($_[0]) eq "ARRAY") {
	($nick, $filename, $blocksize) = @{$_[0]};
    } else {
	($nick, $filename, $blocksize) = @_;
    }

    Net::IRC::DCC::SEND->new($self, $nick, $filename, $blocksize);
}

# Selects nick for this object or returns currently set nick.
# No default; must be set by user.
# If changed while the object is already connected to a server, it will
# automatically try to change nicks.
# Takes 1 arg:  the nick. (I bet you could have figured that out...)
sub nick {
    my $self = shift;

    if (@_)  {
	$self->{'_nick'} = shift;
	if ($self->connected) {
	    return $self->sl("NICK " . $self->{'_nick'});
	}
    }
    else
      {  return $self->{'_nick'}  }
}

# Sends a notice to a channel or person.
# Takes 2 args:  the target of the message (channel or nick)
#                the text of the message to send
# The message will be chunked if it is longer than the _maxlinelen 
# attribute, but it doesn't try to protect against flooding.  If you
# give it too much info, the IRC server will kick you off!
sub notice {
    my ($self, $to) = splice @_, 0, 2;
    
    unless (@_) {
	$self->printerr("Not enough arguments to notice()");
	return undef;
    }

    my ($buf, $length, $line) = (join("", @_), $self->{_maxlinelen});

    while($buf) {
        ($line, $buf) = unpack("a$length a*", $buf);
        $self->sl("NOTICE $to :$line");
    }
}

# Makes you an IRCop, if you supply the right username and password.
# Takes 2 args:  Operator's username
#                Operator's password
sub oper {
    my $self = shift;

    unless (@_ > 1) {
	$self->printerr("Not enough arguments to oper()");
	return undef;
    }
    
    $self->sl("OPER $_[0] $_[1]");
}

# This function splits apart a raw server line into its component parts
# (message, target, message type, CTCP data, etc...) and passes it to the
# appropriate handler. Takes no args, really.
sub parse {
    my ($self) = shift;
    my ($from, $type, $message, @stuff, $itype, $ev, @lines, $line);
    
    # Read newly arriving data from $self->socket
    # -- #perl was here! --
    #   Tkil2: hm.... any joy if you add a 'defined' to the test? like
    #          if (defined $sock...
    # fimmtiu: Much joy now.
    #   archon rejoices

    if (defined $self->socket->recv($line, 10240) and
	(length($self->{_frag}) + length($line)) > 0)  {
	# grab any remnant from the last go and split into lines
	my $chunk = $self->{_frag} . $line;
	@lines = split /\n/, $chunk;
	
	# if the last line was incomplete, pop it off the chunk and
	# stick it back into the frag holder.
	$self->{_frag} = (substr($chunk, -1) ne "\n" ? pop @lines : '');

    } else {
	
	# um, if we can read, i say we should read more than 0
	# besides, recv isn't returning undef on closed
	# sockets.  getting rid of this connection...
	$self->handler(Net::IRC::Event->new( "disconnect",
					     $self->server,
					     '',
					     'error',
					     'Connection reset by peer'));
	$self->parent->removeconn($self);
	return undef;
    }
    
    foreach $line (@lines) {

	# Clean the lint filter every 2 weeks...
	$line =~ s/[\012\015]+$//;
	next unless $line;

	# Like the RFC says: "respond as quickly as possible..."
	if ($line =~ /^PING/) {
	    $ev = (Net::IRC::Event->new( "ping",
					 $self->server,
					 $self->nick,
					 "serverping",   # FIXME?
					 substr($line, 5)
					 ));
	    
	# Had to move this up front to avoid a particularly pernicious bug.
	} elsif ($line =~ /^NOTICE/) {
	    $ev = Net::IRC::Event->new( "other",
					$self->server,
					'',
					'server',
					$line );
	    
    
	# Spurious backslashes are for the benefit of cperl-mode, of course.
	# Assumptions:  all hostnames have periods in them
	#               all non-numeric message types begin with a letter
	} elsif ($line =~ /^:?
		 ([][}{\w\\\`^|\-]+?      # The nick (valid nickname chars)
		  !                       # The nick-username separator
		  .+?                     # The username
		  \@)?                    # Umm, duh...
		 [^.]+?\.                 # Everything up to the first period
		 \S+?                     # The hostname
		 \s+                      # Space between mask and message type
		 [A-Za-z]                 # First char of message type
		 [^\s:]+?                 # The rest of the message type
		 /x)                      # That ought to do it for now...
	{
	    $line = substr $line, 1 if $line =~ /^:/;
	    ($from, $line) = split ":", $line, 2;
	    ($from, $type, @stuff) = split /\s+/, $from;
	    $type = lc $type;
	    
	    # This should be fairly intuitive... (cperl-mode sucks, though)
	    if (defined $line and index($line, "\001") >= 0) {
		$itype = "ctcp";
		unless ($type eq "notice") {
		    $type = (($stuff[0] =~ tr/\#\&//) ? "public" : "msg");
		}
	    } elsif ($type eq "privmsg") {
		$itype = $type = (($stuff[0] =~ tr/\#\&//) ? "public" : "msg");
	    } elsif ($type eq "notice") {
		$itype = "notice";
	    } elsif ($type eq "join" or $type eq "part" or
		     $type eq "mode" or $type eq "topic" or
		     $type eq "kick") {
		$itype = "channel";
	    } elsif ($type eq "nick") {
		$itype = "nick";
	    } else {
		$itype = "other";
	    }
	    
	    # This goes through the list of ignored addresses for this message
	    # type and drops out of the sub if it's from an ignored hostmask.
	    
	    study $from;    # This needs to be benchmarked for speed later.
	    foreach ( $self->ignore($itype), $self->ignore("all") ) {
		$_ = quotemeta; s/\\\*/.*/g;
		return 1 if $from =~ /$_/;
	    }
	    
	    # It used to look a lot worse. Here was the original version...
	    # the optimization above was proposed by Silmaril, for which I am
	    # eternally grateful. (Mine still looks cooler, though. :)
	    
	    # return if grep { $_ = join('.*', split(/\\\*/,
	    #                  quotemeta($_)));  /$from/ }
	    # ($self->ignore($type), $self->ignore("all"));
	    
	    # Add $line to @stuff for the handlers
	    push @stuff, $line if defined $line;
	    
	    # Now ship it off to the appropriate handler and forget about it.
	    if ( $itype eq "ctcp" ) {       # it's got CTCP in it!
		$self->parse_ctcp($type, $from, $stuff[0], $line);
		return 1;
		
	    }  elsif ($type eq "public" or $type eq "msg"   or
		      $type eq "notice" or $type eq "mode"  or
		      $type eq "join"   or $type eq "part"  or
		      $type eq "topic"  or $type eq "invite" ) {
		
		$ev = Net::IRC::Event->new( $type,
					    $from,
					    shift(@stuff),
					    $type,
					    @stuff,
					    );
	    } elsif ($type eq "quit" or $type eq "nick") {
		
		$ev = Net::IRC::Event->new( $type,
					    $from,
					    $from,
					    $type,
					    @stuff,
					    );
	    } elsif ($type eq "kick") {
		
		$ev = Net::IRC::Event->new( $type,
					    $from,
					    $stuff[1],
					    $type,
					    @stuff[0,2..$#stuff],
					    );
		
	    } elsif ($type eq "kill") {
		$ev = Net::IRC::Event->new($type,
					   $from,
					   '',
					   $type,
					   $line);   # Ahh, what the hell.
	    } else {
		$self->printerr("Unknown event type: $type");
	    }
	}

	# -- #perl was here! --
	# *** orwant (orwant@media.mit.edu) has joined channel #perl
	# orwant: Howdy howdy.
	# orwant: Just came back from my cartooning class.
	# orwant: I'm working on a strip for TPJ.
        #    njt: it's happy bouncy clown jon from clownland!  say 'hi' to
	#         the kiddies, jon!
	#         orwant splits open njt like a wet bag of groceries and
	#         dances on his sticky bones.
	#    njt: excuse me, ladies, but I've got to go eviscerate myself with
	#         a leaky biro.  don't wait up.

	elsif ($line =~ /^:?       # Here's Ye Olde Numeric Handler!
	       .+?                 # the servername (can't assume RFC hostname)
	       \s+?                # Some spaces here...
	       \d+?                # The actual number
	       \b/x                # Some other crap, whatever...
	       ) {
	    $ev = $self->parse_num($line);
	    
	} elsif (index($line, $self->nick . " MODE") == 1) {
	    $ev = Net::IRC::Event->new( 'umode',
					$self->server,
					$self->nick,
					'server',
					substr($line, index($line,':',1) + 1));
	    
	} elsif ($line =~ /^ERROR/) {
	    if ($line =~ /^ERROR :Closing link/) {      # is this compatible?
		$ev = Net::IRC::Event->new( "disconnect",
					    $self->server,
					    '',
					    'error',
					    ($line =~ /(.*)/));
	    } else {
		$ev = Net::IRC::Event->new( "error",
					    $self->server,
					    '',
					    'error',
					    (split /:/, $line, 2)[1]);
	    }
	}
	
	if ($ev) {
	    $self->handler($ev);
	} else {
	    # If it gets down to here, it's some exception I forgot about. :P
	    $self->printerr("Funky parse case: $line\n");
	}
    }
}

# The backend that parse() sends CTCP requests off to. Pay no attention
# to the camel behind the curtain.
# Takes 4 arguments:  the type of message
#                     who it's from
#                     the first bit of stuff
#                     the line from the server.
sub parse_ctcp {
    my ($self, $type, $from, $stuff, $line) = @_;
	
    my ($one, $two) = (undef, undef);
    my ($odd, @foo) = (&dequote($line));

    while (($one, $two) = (splice @foo, 0, 2)) {
	
	($one, $two) = ($two, $one) if $odd;
	
	my ($ctype) = $one =~ /^(\w+)\b/;
	my $prefix = undef;
	if ($type eq 'notice') {
	    $prefix = 'cr';
	} elsif ($type eq 'public' or
		 $type eq 'msg'   ) {
	    $prefix = 'c';
	} else {
	    $self->printerr("Unknown CTCP type: $type");
	    return undef;
	}
	
	if ($prefix) {
	    my $handler = $prefix . $ctype;   # unit. value prob with $ctype

	    # -- #perl was here! --
	    # fimmtiu: Words cannot describe my joy. Sil, you kick ass.
	    # fimmtiu: I was passing the wrong arg to Event::new()
	    
	    $self->handler(Net::IRC::Event->new($handler, $from, $stuff,
						$handler, (split /\s/, $one)));
	}

	# This next line is very likely broken somehow. Sigh.
	$self->handler(Net::IRC::Event->new($type, $from, $stuff, $type, $two))
	    if ($two);
    }
    return 1;
}

# Does special-case parsing for numeric events. Separate from the rest of
# parse() for clarity reasons (I can hear Tkil gasping in shock now. :-).
# Takes 1 arg:  the raw server line
sub parse_num {
    my ($self, $line) = @_;

    my ($from, $type, @stuff) = split /\s+/, $line;
    $from = substr $from, 1 if $from =~ /^:/;

    return Net::IRC::Event->new( $type,
				 $from,
				 '',
				 'server',
				 @stuff );
}

# Helps you flee those hard-to-stand channels.
# Takes at least one arg:  name(s) of channel(s) to leave.
sub part {
    my $self = shift;
    
    unless (@_) {
	$self->printerr("No arguments provided to part()");
	return undef;
    }
    $self->sl("PART " . join(",", @_));    # "A must!!!"
}

# Tells what's on the other end of a connection. Returns a 2-element list
# consisting of the name on the other end and the type of connection.
# Takes no args.
sub peer {
    my $self = shift;

    return ($self->server(), "IRC connection");
}

# Prints stuff to the appropriate spot, formatted as per $self->format().
# Takes at least 2 args:  a boolean value indicating whether it's an error
#                         the message to be printed
#            (optional)   up to 10 custom things to be printed
sub _pr {
    my ($self, $err, $event, @custom) = @_;
    my $line;
    
    return 1 unless defined $event;
    if (ref $event eq "Net::IRC::Event") {
	$line = $self->format($event->type);
	
	# Thanks to Abigail (abigail@fnx.com) for the idea for this clever bit.
	# I'm sure it can be made more efficient, though. Any suggestions?
	# I'm too tired right now to think of 'em myself. :)
	
	my (%h) = ( 'f' => $event->from,
		    'n' => $event->nick,
		    'u' => $event->user,
		    'h' => $event->host,
		    'c' => $event->type,
		    'm' => ($event->args)[-1],
		    '0' => $custom[0],
		    '1' => $custom[1],
		    '2' => $custom[2],
		    '3' => $custom[3],
		    '4' => $custom[4],
		    '5' => $custom[5],
		    '6' => $custom[6],
		    '7' => $custom[7],
		    '8' => $custom[8],
		    '9' => $custom[9],
		    's' => $self->server,
		    't' => join(",", ($event->to())),
		    'd' => scalar localtime,
		    'D' => time,
		    '%' => '%',
		   );
	
	$line =~ s/\%([0-9uhdcmnst%])/$h{$1}/g;
    } else {
	$line = $event;
    }
    
    foreach my $fh (@{$self->{($err ? '_errout' : '_output')}}) {
	if (ref $fh eq "GLOB") {
	    print $fh $line, "\n";
	} else {
	    $fh->print($line, "\n");
	}
    }
}

# Prints a message to the defined error filehandle(s).
# Takes at least 1 arg:  the Event object to print
#           (optional)   up to 10 custom fields to pass to the formatter
sub printerr {
    my $self = shift;

    $self->_pr(1, @_);
}

# Prints a message to the defined output filehandle(s).
# Takes at least 1 arg:  the Event object to print
#           (optional)   up to 10 custom fields to pass to the formatter
sub print {
        my $self = shift;

	$self->_pr(0, @_);
}

# Sends a message to a channel or person.
# Takes 2 args:  the target of the message (channel or nick)
#                the text of the message to send
# Don't use this for sending CTCPs... that's what the ctcp() function is for.
# The message will be chunked if it is longer than the _maxlinelen 
# attribute, but it doesn't try to protect against flooding.  If you
# give it too much info, the IRC server will kick you off!
sub privmsg {
    my ($self, $to) = splice @_, 0, 2;

    unless (@_) {
	$self->printerr("Not enough arguments to privmsg()");
	return undef;
    }
    
    my $buf = join "", @_;
    my $length = $self->{_maxlinelen} - 11 - length($to);
    my $line;
    
    if (ref($to) =~ /^IO::Socket/) {
        while($buf) {
	    ($line, $buf) = unpack("a$length a*", $buf);
	    $to->send($line . "\015\012");
       	} 
    } else {
	while($buf) {
	    ($line, $buf) = unpack("a$length a*", $buf);
	    $self->sl("PRIVMSG $to :$line");
	}
    }
}


# Closes connection to IRC server.  (Corresponding function for /QUIT)
# Takes 1 optional arg:  parting message, defaults to "Leaving" by custom.
sub quit {
    my $self = shift;

    # Do any user-defined stuff before leaving
    $self->handler("selfquit");

    # -- #perl was here! --
    # <fimmtiu> Should an $irc->quit method return an error if the instance
    #           isn't connected, or die silently?
    # <Stupid> fimm:  Go quietly into the night.
    unless ( $self->connected ) {  return 1  }
    
    # Why bother checking for sl() errors now, after all?  :)
    $self->sl("QUIT :" . (scalar(@_) ? $_[0] : "Leaving"));
    $self->socket->close;
    $self->{_connected} = undef;
    return 1;
}

# Schedules an event to be executed after some length of time.
# Takes at least 2 args:  the number of seconds to wait until it's executed
#                         a coderef to execute when time's up
# Any extra args are passed as arguments to the user's coderef.
sub schedule {
    my ($self, $time, $code) = splice @_, 0, 3;
    my $parent = $self->parent;
    
    unless ($code) {
	$self->printerr('Not enough arguments to Connection->schedule()');
	return undef;
    }

    $time = time + int $time;
    $parent->queue($time, $code, $self, @_);
}

# Lets J. Random IRCop connect one IRC server to another. How uninteresting.
# Takes at least 1 arg:  the name of the server to connect your server with
#            (optional)  the port to connect them on (default 6667)
#            (optional)  the server to connect to arg #1. Used mainly by
#                          servers to communicate with each other.
sub sconnect {
    my $self = shift;

    unless (@_) {
	$self->printerr("Not enough arguments to sconnect()");
	return undef;
    }
    $self->sl("CONNECT " . join(" ", @_));
}

# Sets/changes the IRC server which this instance should connect to.
# Takes 1 arg:  the name of the server (see below for possible syntaxes)
#                                       ((syntaxen? syntaxi? syntaces?))
sub server {
    my ($self) = shift;
    
    if (@_)  {
	# cases like "irc.server.com:6668"
	if (index($_[0], ':') > 0) {
	    my ($serv, $port) = split /:/, $_[0];
	    if ($port =~ /\D/) {
		$self->printerr("$port is not a valid port number in server()");
		return undef;
	    }
	    $self->{_server} = $serv;
	    $self->port($port);

	    # cases like ":6668"  (buried treasure!)
	} elsif (index($_[0], ':') == 0 and $_[0] =~ /^:(\d+)/) {
	    $self->port($1);

	    # cases like "irc.server.com"
	} else {
	    $self->{_server} = shift;
	}
	# Is this behavior OK? It follows IRC client custom...
	return $self->connect if ($self->connected);
    }
    else
      {  return $self->{_server};  }
}

# Lets the user tell Net::IRC where his error messages should be going.
# Takes 1 arg:  the new list of output filehandles.
# The list can be in @_ or passed as an array ref; the fhs can be passed as
# \*GLOBS (as per perlsyn) or IO::* objects.
sub seterr {
    my ($self, $arg) = shift;
    
    unless (@_) {
        $self->printerr("Not enough arguments to seterr()");
	return undef;
    }
    
    $self->{'errout'} = [];
    while (@_) {
        $arg = shift;
        
        unless (ref $arg) {
            push @{$self->{'_errout'}}, $arg;
        } elsif (ref $arg eq "ARRAY") {
            $self->{'_errout'} = $arg;
        } else {
	    $self->printerr("seterr() only accepts array references or lists");
	    return undef;
	}
    }
}

# Lets the user tell Net::IRC where his output should be going.
# Takes 1 arg:  the new list of output filehandles.
# The list can be in @_ or passed as an array ref; the fhs can be passed as
# \*GLOBS (as per perlsyn) or IO::* objects.
sub setout {
    my ($self, $arg) = shift;
    
    unless (@_) {
        $self->printerr("Not enough arguments to setout()");
	return undef;
    }
    
    $self->{'_output'} = [];
    while (@_) {
        $arg = shift;
        
        unless (ref $arg) {
	    push @{$self->{'_output'}}, $arg;
	} elsif (ref $arg eq "ARRAY") {
	    $self->{'_output'} = $arg;
	} else {
            $self->printerr("setout() only accepts array references or lists");
	    return undef;
	}
    }
}

# Sends a raw IRC line to the server.
# Corresponds to the internal sirc function of the same name.
# Takes 1 arg:  string to send to server. (duh. :)
sub sl {
    my $self = shift;

    unless (@_) {
	$self->printerr("Not enough arguments to sl()");
	return undef;
    }
    
    # RFC compliance can be kinda nice... ;)
    my $rv = $self->{_socket}->send("$_[0]\015\012");
    unless ($rv) {
	$self->handler("sockerror");
	return undef;
    }
    return $rv;
    
    # discards any extra arguments silently... is that bad? Should it join()?
}

# Tells any server that you're an oper on to disconnect from the IRC network.
# Takes at least 1 arg:  the name of the server to disconnect
#            (optional)  a comment about why it was disconnected
sub squit {
    my $self = shift;

    unless (@_) {
	$self->printerr("Not enough arguments to squit()");
	return undef;
    }
    
    $self->sl("SQUIT $_[0]" . ($_[1] ? " :$_[1]" : ""));
}

# Gets various server statistics for the specified host.
# Takes at least 1 arg: the type of stats to request [chiklmouy]
#            (optional) the server to request from (default is current server)
sub stats {
    my $self = shift;

    unless (@_) {
	$self->printerr("Not enough arguments passed to stats()");
	return undef;
    }

    $self->sl("STATS $_[0]" . ($_[1] ? " $_[1]" : ""));
}

# Requests timestamp from specified server. Easy enough, right?
# Takes 1 optional arg:  a server name/mask to query
sub time {
    my ($self, $serv) = (shift, undef);

    $self->sl("TIME" . ($_[0] ? " $_[0]" : ""));
}

# Sends request for current topic, or changes it to something else lame.
# Takes at least 1 arg:  the channel whose topic you want to screw around with
#            (optional)  the new topic you want to impress everyone with
sub topic {
    my $self = shift;

    unless (@_) {
	$self->printerr("Not enough arguments to topic()");
	return undef;
    }
    
    # Can you tell I've been reading the Nethack source too much? :)
    $self->sl("TOPIC $_[0]" . ($_[1] ? " :$_[1]" : ""));
}

# Sends a trace request to the server. Whoop.
# Take 1 optional arg:  the server or nickname to trace.
sub trace {
    my $self = shift;

    $self->sl("TRACE" . ($_[0] ? " $_[0]" : ""));
}

# Requests userhost info from the server.
# Takes at least 1 arg: nickname(s) to look up.
sub userhost {
    my $self = shift;
    
    unless (@_) {
	$self->printerr('Not enough args to userhost().');
	return undef;
    }
    
    $self->sl("USERHOST " . join (" ", @_));
}

# Sends a users request to the server, which may or may not listen to you.
# Take 1 optional arg:  the server to query.
sub users {
    my $self = shift;

    $self->sl("USERS" . ($_[0] ? " $_[0]" : ""));
}

# Asks the IRC server what version and revision of ircd it's running. Whoop.
# Takes 1 optional arg:  the server name/glob. (default is current server)
sub version {
    my $self = shift;

    $self->sl("VERSION" . ($_[0] ? " $_[0]" : ""));
}

# Sends a message to all opers on the network. Hypothetically.
# Takes 1 arg:  the text to send.
sub wallops {
    my $self = shift;

    unless ($_[0]) {
	$self->printerr("Not enough args to wallops(): No text to send!");
	return undef;
    }

    $self->sl("WALLOPS :" . join("", @_));
}

# Asks the server about stuff, you know. Whatever. Pass the Fritos, dude.
# Takes 2 optional args:  the bit of stuff to ask about
#                         an "o" (nobody ever uses this...)
sub who {
    my $self = shift;

    # Obfuscation!
    $self->sl( "WHO" . ($_[0] ? " $_[0]" : "") . ($_[1] ? " $_[1]" : ""));
}

# If you've gotten this far, you probably already know what this does.
# Takes at least 1 arg:  nickmasks or channels to /whois
sub whois {
    my $self = shift;

    unless (@_) {
	$self->printerr("Not enough arguments to whois()");
	return undef;
    }
    return $self->sl("WHOIS " . join(",", @_));
}

# Same as above, in the past tense.
# Takes at least 1 arg:  nick to do the /whowas on
#            (optional)  max number of hits to display
#            (optional)  server or servermask to query
sub whowas {
    my $self = shift;

    unless (@_) {
	$self->printerr("Not enough arguments to whowas()");
	return undef;
    }
    return $self->sl("WHOWAS $_[0]" . ($_[1] ? " $_[1]" : "") .
		     (($_[1] && $_[2]) ? " $_[2]" : ""));
}


# This sub executes the default action for an event with no user-defined
# handlers. It's all in one sub so that we don't have to make a ton of
# separate anonymous subs stuffed in a hash. (ouch)
sub _default {
    my ($self, $event) = @_;
    my $verbose = $self->verbose;

    # Users should only see this if the programmer (me) fucked up.
    unless ($event) {
	$self->printerr("You EEEEEDIOT!!! Not enough args to _default()!");
	return undef;
    }
    
    # Reply to PING from server as quickly as possible.
    if ($event->type eq "ping") {
	$self->sl("PONG " . (join ' ', $event->args));
	
    } elsif ($event->type eq "disconnect") {
	$self->socket->close;
	$self->parent->changed;
    }

    return 1;
}



##############################################################################
#                           THAT'S ALL, FOLKS...                             #
#                                                                            #
#  <fimmtiu>  OK, once you've passed the point where caffeine no longer has  #
#             any discernible effect on any part of your body but your       #
#             bladder, it's time to sleep.                                   #
#  <fimmtiu>  'Night, all.                                                   #
#    <regex>  Night, fimm                                                    #
#                                                                            #
##############################################################################
1;


__END__

=head1 NAME

Net::IRC::Connection - Object-oriented interface to a single IRC connection

=head1 SYNOPSIS

Hard hat area: This section under construction. Watch for falling referents.

=head1 DESCRIPTION

This documentation is a subset of the main Net::IRC documentation. If
you haven't already, please "perldoc Net::IRC" before continuing.

Net::IRC::Connection defines a class whose instances are individual
connections to a single IRC server. Several Net::IRC::Connection objects may
be handled simultaneously by one Net::IRC object.

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

