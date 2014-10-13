package Net::FreeDB;

use 5.006;
use strict;
use warnings;
use IO::Socket;
use Net::Cmd;
use CDDB::File;
use Carp;
use Data::Dumper;
use File::Temp;

require Exporter;
require DynaLoader;
use AutoLoader;

our @ISA = qw(Exporter DynaLoader Net::Cmd IO::Socket::INET);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Net::FreeDB ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw() ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw();

our $VERSION = '0.09';

our $ERROR;
sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.  If a constant is not found then control is passed
    # to the AUTOLOAD in AutoLoader.

    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "& not defined" if $constname eq 'constant';
    my $val = constant($constname, @_ ? $_[0] : 0);
    if ($! != 0) {
	if ($! =~ /Invalid/ || $!{EINVAL}) {
	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
	}
	else {
	    croak "Your vendor has not defined Net::FreeDB macro $constname";
	}
    }
    {
	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
	if ($] >= 5.00561) {
	    *$AUTOLOAD = sub () { $val };
	}
	else {
	    *$AUTOLOAD = sub { $val };
	}
    }
    goto &$AUTOLOAD;
}

bootstrap Net::FreeDB $VERSION;

# Preloaded methods go here.
sub new {
    my $class = shift;
    my $self = {};
    $self = {@_};
    bless($self, $class);

    $self->{HOST} = 'freedb.freedb.org' unless defined($self->{HOST});
    $self->{PORT} = '8880' unless defined($self->{PORT});

    if (!defined($self->{USER})) {
	$self->{USER} = defined($ENV{USER}) ? $ENV{USER} : 'unknown';
    }

    if (!defined($self->{HOSTNAME})) {
	$self->{HOSTNAME} = defined($ENV{HOSTNAME}) ? $ENV{HOSTNAME} : 'unknown';
    }

    my $obj = $self->SUPER::new(PeerAddr => $self->{HOST},
				PeerPort => $self->{PORT},
				Proto    => 'tcp',
				Timeout  =>
				defined($self->{TIMEOUT}) ? $self->{TIMEOUT} : 120
			       );

    return undef
      unless defined $obj;

    $obj->autoflush(1);
    $obj->debug(exists $self->{DEBUG} ? $self->{DEBUG} : undef);

    unless ($obj->response() == CMD_OK) {
	$obj->close;
	return undef;
    }

    $obj->command(
		  "cddb hello",
		  $self->{USER},
		  $self->{HOSTNAME},
		  ref($self),
		  $VERSION
		 );

    unless ($obj->response() == CMD_OK) {
	$obj->close;
	return undef;
    }

    $obj;
}

sub read {
    my $self = shift;
    my ($cat, $id);

    if (scalar(@_) == 2) {
	($cat, $id) = @_;
    } else {
	if ((scalar(@_) % 2) == 0) {
	    if ($_[0] =~ /^CATEGORY$/i || $_[0] =~ /^ID$/i) {
		my %input = @_;
		($cat, $id) = ($input{CATEGORY}, $input{ID});
	    } else {
		print "Error: Unknown input!\n";
		return undef;
	    }
	} else {
	    print "Error: Unknown input!\n";
	    return undef;
	}
    }

    # First, fetch the data, before creating any temporary files
    my $data = $self->_READ($cat, $id)? $self->_read(): undef;
    return undef unless defined $data;
    
    # Create a file for CDDB::File to use...
    my $fh = new File::Temp;
    print $fh join '', @$data;
    seek $fh, 0, 0;

    # ...and use it.
    my $cddb_file = new CDDB::File($fh->filename());
    return $cddb_file;
}

sub query {
    my $self = shift;
    $self->_QUERY(@_) ? $self->_query : undef;
}

sub sites {
    my $self = shift;
    $self->_SITES ? $self->_sites : undef;
}

sub getdiscid {
    my $self = shift;
	my ($driveNo, $id);
	if (ref($self) ne 'Net::FreeDB') {
		$driveNo = $self;
	} else {
		$driveNo = shift;
	}
	$id = discid($driveNo);
    if ($id eq "UNDEF" || $id eq '') {
	$ERROR = "Drive Error: no disc found\n";
	return undef;
    }
    return $id;
}

sub getdiscdata {
    my $self = shift;
    my ($driveNo, $data);
	if (ref($self) ne 'Net::FreeDB') {
		$driveNo = $self;
	} else {
		$driveNo = shift;
	}
	$data = discinfo($driveNo);
    if (!$data) {
	$ERROR = "Drive Error: no disc found\n";
	return undef;
    }
    return $data;
}

sub lscat {
    my $self = shift;
    $self->_LSCAT();
}
sub quit {
    my $self = shift;
    $self->_QUIT();
}

sub DESTROY {
    my $self = shift;
    $self = {};
}

sub _read {
    my $self = shift;
    my $data = $self->read_until_dot or
      return undef;
    return $data;
}

sub _query {
    my $self = shift;
    my $data = $self->message();
	my $code = $self->code();
	my @returns;
	if ($code == 210 || $code == 211) {


		my $data = $self->read_until_dot
			or return undef;
		foreach my $i (@{$data}) {
			next if $i =~ /^\.$/;
			$i =~
				/([^\s]+)\s([^\s]+)\s([^\/|\:|\-]+)\s[\/|\|:|\-]\s?(.*)\s?/;
			push @returns, {GENRE =>$1,DISCID =>$2,ARTIST=>$3,ALBUM=>$4};
		}
	} else {
		#we got a single; parse it, hash it and return it
    	$data =~ /([^\s]+)\s([^\s]+)\s([^\/|\:|\-]+)\s[\/|\:|\-]\s?(.*)\s?/;
		push @returns, {GENRE=>$1,DISCID=>$2,ARTIST=>$3,ALBUM=>$4};
	}
	return @returns;
}

sub _sites {
    my $self = shift;
    my $data = $self->read_until_dot
		or return undef;
    my @sites;
    foreach (@$data) {
	s/([^\s]+)\s([^\s]+).*/$1 $2/;
	push(@sites, $_);
    }
    return \@sites;
}

sub _READ      { shift->command('CDDB READ',@_)->response == CMD_OK }
sub _SITES     { shift->command('SITES',@_)->response == CMD_OK }
sub _LSCAT     { shift->command('CDDB LSCAT')->response == CMD_OK }
sub _QUERY     { shift->command('CDDB QUERY',@_)->response == CMD_OK }
sub _QUIT      { shift->command('QUIT')->response == CMD_OK }

sub _WRITE     { shift->command('CDDB WRITE',@_)->response == CMD_OK }
sub _WHOM      { shift->command('CDDB WHOM')->response == CMD_OK }
sub _UPDATE    { shift->command('CDDB UPDATE')->response == CMD_OK }
sub _VER       { shift->command('CDDB VER')->response == CMD_OK }
sub _STAT      { shift->command('CDDB STAT')->response == CMD_OK }
sub _PROTO     { shift->command('CDDB PROTO')->response == CMD_OK }
sub _MOTD      { shift->command('CDDB MOTD')->response == CMD_OK }
sub _LOG       { shift->command('CDDB LOG',@_)->response == CMD_OK }
sub _HELP      { shift->command('CDDB HELP')->response == CMD_OK }
sub _DISCID    { shift->command('DISCID',@_)->response == CMD_OK }


1;
__END__


=head1 NAME

Net::FreeDB - Perl interface to freedb server(s)

=head1 SYNOPSIS

    use Net::FreeDB;
$freedb = Net::FreeDB->new();
$discdata = $freedb->getdiscdata('/dev/cdrom');
my $cddb_file_object = $freedb->read('rock', $discdata->{ID});
print $cddb_file_object->id;

=head1 DESCRIPTION

  Net::FreeDB was inspired by Net::CDDB.  And in-fact
    was designed as a replacement in-part by Net::CDDB's
    author Jeremy D. Zawodny.  Net::FreeDB allows an
    oop interface to the freedb server(s) as well as
    some basic cdrom functionality like determining
    disc ids, track offsets, etc.

=head2 METHODS

=over

=item new(HOST => $h, PORT => $p, USER => $u, HOSTNAME => $hn, TIMEOUT => $to)

     Constructor:
        Creates a new Net::FreeDB object.

     Parameters:
          Set to username or user-string you'd like to be logged as.

        HOSTNAME: (optional)
          Set to the hostname you'd like to be known as.

        TIMEOUT: (optional)
          Set to the number of seconds to timeout on freedb server.


    new() creates and returns a new Net::FreeDB object that is connected
    to either the given host or freedb.freedb.org as default.

=item read($cat, $id)

  Parameters:

    read($$) takes 2 parameters, the first being a category name.
    This can be any string either that you make up yourself or
    that you believe the disc to be. The second is the disc id. This
    may be generated for the current cd in your drive by calling getdiscid()

  NOTE:
    Using an incorrect category will result in either no return or an
    incorrect return. Please check the CDDB::File documentation for
	information on this module.


  read() requests a freedb record for the given information and returns a
    CDDB::File object.

=item query($id, $num_trks, $trk_offset1, $trk_offset2, $trk_offset3...)

  Parameters:

    query($$$...) takes:
  1: a discid
  2: the number of tracks
  3: first track offset
  4: second track offset... etc.

    Query expects $num_trks number of extra params after the first two.

    query() returns an array of hashes. The hashes looks like:

	{
		GENRE  => 'newage',
		DISCID => 'discid',
		ARTIST => 'artist',
		ALBUM  => 'title'
	}

	NOTE: query() can return 'inexact' matches and/or 'multiple exact'
	matches. The returned array is the given returned match(es).

=item sites()

  Parameters:
    None

    sites() returns an array reference of urls that can be used as 
    a new HOST.

=item getdiscid($device)

  Parameters:
    getdiscid($) takes the device you want to use.
    Basically this means '/dev/cdrom' or whatever on linux machines
    but it's an array index in the number of cdrom drives on windows
    machines starting at 0. (Sorry, I may change this at a later time).
    So, if you have only 1 cdrom drive then getdiscid(0) would work fine.

  getdiscid() returns the discid of the current disc in the given drive.

    NOTE: See BUGS

=item getdiscdata($device)

  Parameters:
    getdiscdata($) takes the device you want to use. See getdiscid()
    for full description.

  getdiscdata() returns a hash of the given disc data as you would
  require for a call to query. The returns hash look like:

   {
     ID => 'd00b3d10',
     NUM_TRKS => '3',
     TRACKS => [
                 '150',
                 '18082',
                 '29172'
               ],
     SECONDS => '2879'
   }

   NOTE: A different return type/design may be developed.

=back

=head1 BUGS

        The current version of getdiscid() and getdiscdata()
        on the Windows platform takes ANY string in a single
        cdrom configuration and works fine.  That is if you
        only have 1 cdrom drive; you can pass in ANY string
        and it will still scan that cdrom drive and return
        the correct data.  If you have more then 1 cdrom drive
        giving the correct drive number will return in an
        accurate return.

=head1 AUTHOR
	David Shultz E<lt>dshultz@cpan.orgE<gt>
	Peter Pentchev E<lt>roam@ringlet.netE<gt>

=head1 CREDITS
	Jeremy D. Zawodny E<lt>jzawodn@users.sourceforge.netE<gt>
	Pete Jordon E<lt>ramtops@users.sourceforge.netE<gt>

=head1 COPYRIGHT
	Copyright (c) 2002 David Shultz.
	Copyright (c) 2005, 2006 Peter Pentchev.
	All rights reserved.
	This program is free software; you can redistribute it
	and/or modify if under the same terms as Perl itself.

=cut







