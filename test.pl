# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
use Data::Dumper;
BEGIN { plan tests => ($ENV{HAVE_INTERNET} ? 10 : 1) };
use Net::FreeDB;
ok(1); # If we made it this far, we're ok.

#########################

if ($ENV{HAVE_INTERNET}) {
#########################
ok($cddb = new Net::FreeDB('USER' => 'win32usr'));

#########################
ok($cddb->read('newage', '940a070c'));

#########################
ok($cddb->query('940a070c 12 150 8285 32097 51042 71992 86235 100345 105935 120932 139472 158810 171795 2567'));

#########################
ok($cddb->query('860aec0b 11 150 19539 34753 52608 69426 86636 112972 130586 151446 172365 191628 2798') > 1);

#########################
ok($cddb->sites());

#########################
ok($cddb->lscat());

#########################
my $id;
if ($^O =~ /MSWin32/) {
	$id = $cddb->getdiscid(0);
} elsif ($^O =~ /freebsd/) {
	$id = $cddb->getdiscid('/dev/acd0');
} else {
	$id = $cddb->getdiscid('/dev/cdrom');
}
ok($id);

#########################
$id = undef;
if ($^O =~ /MSWin32/) {
	$id = Net::FreeDB::getdiscid(0);
} elsif ($^O =~ /freebsd/) {
	$id = Net::FreeDB::getdiscid('/dev/acd0');
} else { $id = Net::FreeDB::getdiscid('/dev/cdrom');
}
ok($id);

#########################
$id = undef;
if ($^O =~ /MSWin32/) {
	$id = Net::FreeDB::getdiscdata(0);
} elsif ($^O =~ /freebsd/) {
	$id = Net::FreeDB::getdiscdata('/dev/acd0');
} else {
	$id = Net::FreeDB::getdiscdata('/dev/cdrom');
}

ok($id->{NUM_TRKS});
}
