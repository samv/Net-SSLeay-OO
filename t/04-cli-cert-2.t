#!/usr/bin/perl
#
#  t/04-cli-cert.t - Test client certificates - based on an example
#                    program from Net::SSLeay
#
# Copyright (C) 2009  NZ Registry Services
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the Artistic License 2.0 or later.  You should
# have received a copy of the Artistic License the file COPYING.txt.
# If not, see <http://www.perlfoundation.org/artistic_license_2_0>

use strict;
use warnings;
use FindBin qw($Bin);

our $TC;
our $DEBUG = $ENV{DEBUG_SSL};

sub ok($$) {
	if ( !$_[0] ) {
		print "not ";
	}
	print "ok " . ( ++$TC ) . ( $_[1] ? " - $_[1]" : "" ) . "\n";
	return !!$_[0];
}

sub diag {
	if ($DEBUG) {
		print map {"# $_\n"} map { split "\n", $_ } @_;
	}
}

$ENV{RND_SEED} = '1234567890123456789012345678901234567890';

use Net::SSLeay::OO;
use Net::SSLeay::OO::Constants qw(VERIFY_PEER FILETYPE_PEM VERIFY_FAIL_IF_NO_PEER_CERT);
use Net::SSLeay::OO::X509;
use Net::SSLeay::OO::X509::Context;

my $cert_dir = "$Bin/certs";

my $ctx = Net::SSLeay::OO::Context->new;
$ctx->set_default_passwd_cb( sub {"secr1t"} );
$ctx->load_verify_locations( '', $cert_dir );

pipe RS, WC or die "pipe 1 ($!)";
pipe RC, WS or die "pipe 2 ($!)";
select WC;
$| = 1;
select WS;
$| = 1;
select STDOUT;
$| = 1;
pipe R2, W2 or die "pipe 3 ($!)";

ok( $ctx, "Set up Context OK" );

my $child_pid = fork;
defined($child_pid) or die $!;
unless ($child_pid) {
	diag("child - using server cert");
	$ctx->use_certificate_chain_file("$cert_dir/server-cert.pem");
	$ctx->use_PrivateKey_file( "$cert_dir/server-key.pem", FILETYPE_PEM,);

	# we get one event for each certificate check
	$ctx->set_verify( VERIFY_PEER | VERIFY_FAIL_IF_NO_PEER_CERT );

	my $ssl = Net::SSLeay::OO::SSL->new( ctx => $ctx );

	$ssl->set_rfd( fileno(RS) );
	$ssl->set_wfd( fileno(WS) );

	ok( !$ssl->get_session, "No session before accept" );
	diag("child - accept");
	$ssl->accept;
	ok( $ssl->get_session, "Set up session OK" );
	my $peer_cert = $ssl->get_peer_certificate;
	ok( $peer_cert, "Got a peer certificate OK" );

	my $name = $peer_cert->get_subject_name;
	ok( $name, "got Client cert name");

	ok( $name && $name->cn eq "Test Client", "extracted CN OK" )
		or diag("CN is '".$name->cn."'");

	my @found_altnames = $peer_cert->get_subjectAltNames;
	ok( @found_altnames, "Found altnames" );

	my $cipher = $ssl->get_cipher;
	ok( $cipher, "Got a cipher ($cipher)" );


	my $got = $ssl->read;
	ok( $got, "Read some data via SSL" );
	my $wrote = $ssl->write($got);
	ok( ( $wrote == length $got ), "Wrote data back via SSL" );

	undef($ssl);    # Tear down connection
	undef($ctx);

	close WS;
	close RS;
	ok( 1, "Server shut down OK" );
	print W2 "$TC\n";
	close W2;
	exit;
}
close W2;

#sleep 1;		    # Give server time to get its act together

# set up a client certificate
diag("client - use certificate");
$ctx->use_certificate_chain_file("$cert_dir/client-cert.pem");
$ctx->use_PrivateKey_file( "$cert_dir/client-key.pem", FILETYPE_PEM );

my $ssl = Net::SSLeay::OO::SSL->new( ctx => $ctx );
$ssl->set_rfd( fileno(RC) );
$ssl->set_wfd( fileno(WC) );
diag("client - connect");
alarm(5);    # timeout if something goes wrong
$ssl->connect;

#print "$$: Cipher `" . $ssl->get_cipher . "'\n";
#print "$$: server cert: " . $ssl->dump_peer_certificate;

# Exchange data

my $secret_message = "ping from pid $$";
$ssl->write( $secret_message . "\n" );
my $got_back = $ssl->read;
chomp($got_back);

$TC = <R2>;
chomp($TC);
ok( ( $got_back eq $secret_message ), "SSL round-trip" )
	or diag( "got: $got_back", "sent: $secret_message" );

undef($ssl);    # Tear down connection
undef($ctx);
close WC;
close RC;

print "1..$TC\n";

# Local Variables:
# mode:cperl
# indent-tabs-mode: t
# cperl-continued-statement-offset: 8
# cperl-brace-offset: 0
# cperl-close-paren-offset: 0
# cperl-continued-brace-offset: 0
# cperl-continued-statement-offset: 8
# cperl-extra-newline-before-brace: nil
# cperl-indent-level: 8
# cperl-indent-parens-as-block: t
# cperl-indent-wrt-brace: nil
# cperl-label-offset: -8
# cperl-merge-trailing-else: t
# End:
# vim: filetype=perl:noexpandtab:ts=3:sw=3
