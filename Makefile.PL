
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

if ($] < 5) {
    my $years = (localtime)[5] - 91;
    print <<"ARGH";
               *** REALLY BIG FAT FATAL ERROR ***
  Holy antiquities, Batman! You're using a version of Perl that's
  over $years years old! Sheesh. Please download and install Perl 5.004
  or better from http://www.perl.com ...Net::IRC won't even consider
  running on this old lemon.

ARGH

    exit 1;
}

unless ($] >= 5.004) {
    print <<"ZOT";
               *** REALLY BIG FAT FATAL ERROR ***
  Net::IRC requires Perl version 5.004 or higher. Please complain
    to your system administrator until he installs it. Sorry...
  
ZOT
    
    exit 1;
}

WriteMakefile(
	      'NAME'  => 'Net::IRC',
	      'PM'    =>  {
		  'IRC.pm'        => '${INST_LIBDIR}/IRC.pm',
		  'Connection.pm' => '${INST_LIBDIR}/IRC/Connection.pm',
		  'Event.pm'      => '${INST_LIBDIR}/IRC/Event.pm',
		  'DCC.pm'        => '${INST_LIBDIR}/IRC/DCC.pm',
	      },
	      'VERSION_FROM' => 'IRC.pm', # finds $VERSION
              'dist' => { 'COMPRESS' => 'gzip --best' },
);
