
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

unless ($] >= 5.004) {
    print <<"ZOT";
               *** REALLY BIG FAT FATAL ERROR ***

    Net::IRC requires Perl version 5.004 or higher. Please complain
    to your system administrator until sie installs it. Sorry...

ZOT

    exit 1;
}

WriteMakefile(
	      'NAME'  => 'Net::IRC',
	      'PM'    =>  {
		  'IRC.pm'        => '$(INST_LIBDIR)/IRC.pm',
		  'Connection.pm' => '$(INST_LIBDIR)/IRC/Connection.pm',
		  'Event.pm'      => '$(INST_LIBDIR)/IRC/Event.pm',
		  'DCC.pm'        => '$(INST_LIBDIR)/IRC/DCC.pm',
	      },
              'PREREQ_PM' => {
                  'IO::Select'    => 0,
                  'Carp'          => 0,
                  'Socket'        => 0,
                  'IO::File'      => 0,
                  'IO::Socket'    => 0,
                  'Sys::Hostname' => 0,
              },
	      'VERSION_FROM' => 'IRC.pm', # finds $VERSION
              'dist' => { 'COMPRESS' => 'gzip --best' },
);
