#####################################################################
#                                                                   #
#   Net::IRC -- Object-oriented Perl interface to an IRC server     #
#                                                                   #
#      Event.pm: The basic data type for any IRC occurrence.        #
#                                                                   #
#          Copyright (c) 1997 Greg Bacon & Dennis Taylor.           #
#                       All rights reserved.                        #
#                                                                   #
#      This module is free software; you can redistribute it        #
#      and/or modify it under the terms of the Perl Artistic        #
#             License, distributed with this module.                #
#                                                                   #
#####################################################################


package Net::IRC::Event;

use strict;
my %_names;


# Sets or returns an argument list for this event.
# Takes any number of args:  the arguments for the event.
sub args {
    my $self = shift;
    
    $self->{'args'} = [ @_ ] if @_;
    return @{$self->{'args'}};
}

# Sets or returns the format string for this event.
# Takes 1 optional arg:  the new value for this event's "format" field.
sub format {
    my $self = shift;

    $self->{'format'} = $_[0] if @_;
    return $self->{'format'};
}

# Sets or returns the originator of this event
# Takes 1 optional arg:  the new value for this event's "from" field.
sub from {
    my $self = shift;
    
    if (@_) {
	my @part = split /[\@!]/, $_[0], 3;

	$self->nick(defined $part[0] ? $part[0] : '');
	$self->user(defined $part[1] ? $part[1] : '');
	$self->host(defined $part[2] ? $part[2] : '');
	defined $self->user ?
	    $self->userhost($self->user . '@' . $self->host) :
	    $self->userhost($self->host);
	$self->{'from'} = $_[0];
    }
    return $self->{'from'};
}

# Sets or returns the hostname of this event's initiator
# Takes 1 optional arg:  the new value for this event's "host" field.
sub host {
    my $self = shift;

    $self->{'host'} = $_[0] if @_;
    return $self->{'host'};
}

# Constructor method for Net::IRC::Event objects.
# Takes at least 4 args:  the type of event
#                         the person or server that initiated the event
#                         the recipient(s) of the event, as arrayref or scalar
#                         the name of the format string for the event
#            (optional)   any number of arguments provided by the event
sub new {
    my $class = shift;

    # -- #perl was here! --
    #   \mjd: Under the spreading foreach loop, the lexical variable stands.
    #   \mjd: The my is a mighty keyword, with abcessed anal glands. (*)
    #   \mjd: Apologies to Mr. Longfellow.
    #
    #    * it's a very long story -- ask kjj sometime.

    my $self = { 'type'   =>  $_[0],
		 'from'   =>  $_[1],
		 'to'     =>  ref($_[2]) eq 'ARRAY'  ?  $_[2]  :  [ $_[2] ],
		 'format' =>  $_[3],
		 'args'   =>  [ @_[4..$#_] ],
	       };
    
    bless $self, $class;
    
    # OO bigots can bite me. I just saved 5 unnecessary sub calls in an
    # often-called routine, and that's more important than dogma.
    if ($self->{'type'} !~ /\D/) {
	$self->{'type'} = $self->trans($self->{'type'});
    } else {
	$self->{'type'} = lc $self->{'type'};
    }

    #  ChipDude: "Beware the method call, my son!  The subs that grab, the
    #             args that shift!"
    #      \mjd: That's pretty good.
    
    $self->from($self->{'from'});   # sets nick, user, and host
    
    return $self;
}

# Sets or returns the nick of this event's initiator
# Takes 1 optional arg:  the new value for this event's "nick" field.
sub nick {
    my $self = shift;

    $self->{'nick'} = $_[0] if @_;
    return $self->{'nick'};
}

# Sets or returns the recipient list for this event
# Takes any number of args:  this event's list of recipients.
sub to {
    my $self = shift;
    
    $self->{'to'} = [ @_ ] if @_;
    return @{$self->{'to'}};
}

# Simple sub for translating server numerics to their appropriate names.
# Take one arg:  the number to be translated.
sub trans {
    shift if (ref($_[0]) || $_[0]) =~ /^Net::IRC/;
    my $ev = shift;
    
    return (exists $_names{$ev} ? $_names{$ev} : undef);
}

# Sets or returns the type of this event
# Takes 1 optional arg:  the new value for this event's "type" field.
sub type {
    my $self = shift;
    
    $self->{'type'} = $_[0] if @_;
    return $self->{'type'};
}

# Sets or returns the username of this event's initiator
# Takes 1 optional arg:  the new value for this event's "user" field.
sub user {
    my $self = shift;

    $self->{'user'} = $_[0] if @_;
    return $self->{'user'};
}

# Just $self->user plus '@' plus $self->host, for convenience.
sub userhost {
    my $self = shift;
    
    $self->{'userhost'} = $_[0] if @_;
    return $self->{'userhost'};
}

%_names = (
	   # suck!  these aren't treated as strings --
	   # 001 ne 1 for the purpose of hash keying, apparently.
	   '001' => "welcome",
	   '002' => "yourhost",
	   '003' => "created",
	   '004' => "myinfo",
	   
	   200 => "tracelink",
	   201 => "traceconnecting",
	   202 => "tracehandshake",
	   203 => "traceunknown",
	   204 => "traceoperator",
	   205 => "traceuser",
	   206 => "traceserver",
	   208 => "tracenewtype",
	   209 => "traceclass",
	   211 => "statslinkinfo",
	   212 => "statscommands",
	   213 => "statscline",
	   214 => "statsnline",
	   215 => "statsiline",
	   216 => "statskline",
	   217 => "statsqline",
	   218 => "statsyline",
	   219 => "endofstats",
	   221 => "umodeis",
	   231 => "serviceinfo",
	   232 => "endofservices",
	   233 => "service",
	   234 => "servlist",
	   235 => "servlistend",
	   241 => "statslline",
	   242 => "statsuptime",
	   243 => "statsoline",
	   244 => "statshline",
	   251 => "luserclient",
	   252 => "luserop",
	   253 => "luserunknown",
	   254 => "luserchannels",
	   255 => "luserme",
	   256 => "adminme",
	   257 => "adminloc1",
	   258 => "adminloc2",
	   259 => "adminemail",
	   261 => "tracelog",
	   262 => "endoftrace",  # 1997-11-24 -- archon
	   265 => "n_local",     # 1997-10-16 -- tkil
	   266 => "n_global",    # 1997-10-16 -- tkil
	   
	   300 => "none",
	   301 => "away",
	   302 => "userhost",
	   303 => "ison",
	   305 => "unaway",
	   306 => "nowaway",
	   311 => "whoisuser",
	   312 => "whoisserver",
	   313 => "whoisoperator",
	   314 => "whowasuser",
	   315 => "endofwho",
	   316 => "whoischanop",
	   317 => "whoisidle",
	   318 => "endofwhois",
	   319 => "whoischannels",
	   321 => "liststart",
	   322 => "list",
	   323 => "listend",
	   324 => "channelmodeis",
	   329 => "channelcreate",  # 1997-11-24 -- archon
	   331 => "notopic",
	   332 => "topic",
	   333 => "topicinfo",      # 1997-11-24 -- archon
	   341 => "inviting",
	   342 => "summoning",
	   351 => "version",
	   352 => "whoreply",
	   353 => "namreply",
	   361 => "killdone",
	   362 => "closing",
	   363 => "closeend",
	   364 => "links",
	   365 => "endoflinks",
	   366 => "endofnames",
	   367 => "banlist",
	   368 => "endofbanlist",
	   369 => "endofwhowas",
	   371 => "info",
	   372 => "motd",
	   373 => "infostart",
	   374 => "endofinfo",
	   375 => "motdstart",
	   376 => "endofmotd",
	   377 => "motd2",        # 1997-10-16 -- tkil
	   381 => "youreoper",
	   382 => "rehashing",
	   384 => "myportis",
	   391 => "time",
	   392 => "usersstart",
	   393 => "users",
	   394 => "endofusers",
	   395 => "nousers",
	   
	   401 => "nosuchnick",
	   402 => "nosuchserver",
	   403 => "nosuchchannel",
	   404 => "cannotsendtochan",
	   405 => "toomanychannels",
	   406 => "wasnosuchnick",
	   407 => "toomanytargets",
	   409 => "noorigin",
	   411 => "norecipient",
	   412 => "notexttosend",
	   413 => "notoplevel",
	   414 => "wildtoplevel",
	   421 => "unknowncommand",
	   422 => "nomotd",
	   423 => "noadmininfo",
	   424 => "fileerror",
	   431 => "nonicknamegiven",
	   432 => "erroneusnickname", # Thiss iz how its speld in thee RFC.
	   433 => "nicknameinuse",
	   436 => "nickcollision",
	   441 => "usernotinchannel",
	   442 => "notonchannel",
	   443 => "useronchannel",
	   444 => "nologin",
	   445 => "summondisabled",
	   446 => "usersdisabled",
	   451 => "notregistered",
	   461 => "needmoreparams",
	   462 => "alreadyregistered",
	   463 => "nopermforhost",
	   464 => "passwdmismatch",
	   465 => "yourebannedcreep", # I love this one...
	   466 => "youwillbebanned",
	   467 => "keyset",
	   471 => "channelisfull",
	   472 => "unknownmode",
	   473 => "inviteonlychan",
	   474 => "bannedfromchan",
	   475 => "badchannelkey",
	   476 => "badchanmask",
	   481 => "noprivileges",
	   482 => "chanoprivsneeded",
	   483 => "cantkillserver",
	   491 => "nooperhost",
	   492 => "noservicehost",
	   
	   501 => "umodeunknownflag",
	   502 => "usersdontmatch",
	  );


1;


__END__

=head1 NAME

Net::IRC::Event - A class for passing event data between subroutines

=head1 SYNOPSIS

Hard hat area: This section under construction. Watch for falling referents.

=head1 DESCRIPTION

This documentation is a subset of the main Net::IRC documentation. If
you haven't already, please "perldoc Net::IRC" before continuing.

Net::IRC::Event defines a standard interface to the salient information for
just about any event your client may witness on IRC. It's about as close as
we can get in Perl to a struct, with a few extra nifty features thrown in.

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

