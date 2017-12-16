package OpenKore::Plugins::Ignore;

use strict;

use Plugins;
use Globals;
use Utils;
use Misc;
use Log;
use AI;
use Time::HiRes qw( time );

our $recent = {};
our $ignore = {};

Plugins::register( 'ignore', 'ignore messages', \&Unload, \&Unload );

my $hooks = Plugins::addHooks(    #
	[ 'packet_pre/public_chat'     => \&onPublicChat ],
	[ 'packet_pre/private_message' => \&onPrivateMessage ],
	[ 'spread_pm'                  => \&onSpreadPM ],
	[ 'Commands::run/post'         => \&onCommandsRunPost ],
);

sub Unload {
	Plugins::delHooks( $hooks );
	Log::message( "ignore unloaded.\n" );
}

sub onCommandsRunPost {
	my ( undef, $args ) = @_;

	return if $args->{switch} ne 'ignore';
	return if $args->{args} !~ /^test (.*)/;

	handle_message( 'test', 'self', "$1" );
}

sub onSpreadPM {
	my ( undef, $param ) = @_;
	return if $param->{privMsg} !~ /^test (.*)$/;
	$param->{return} = handle_message( 'private', $param->{privMsgUser}, "$1" );
	$param->{privMsg} = '' if $param->{return};
	return $param->{return};
}

sub onPrivateMessage {
	my ( undef, $param ) = @_;
	$param->{return} = handle_message( 'private', $param->{privMsgUser}, $param->{privMsg} );
	$param->{privMsg} = '' if $param->{return};
	return $param->{return};
}

sub onPublicChat {
	my ( undef, $param ) = @_;
	my ( $from, $msg )   = $param->{message} =~ /^([^:]+?)\s*:\s*(.*)$/os;
	$param->{return} = handle_message( 'public', $from, $msg );
	$param->{message} = '' if $param->{return};
	return $param->{return};
}

sub handle_message {
	my ( $type, $from, $msg ) = @_;

	if ( $msg eq 'Congratulation on Ragnarok 12th anniversary!' || $msg eq 'Enjoy the 12th anniversary event in Comodo island!' ) {
		Log::debug( "[ignore] ignored: $msg\n", 'ignore' );
		return 1;
	}

	return if $from =~ /bearr/i;

	Log::debug( "[ignore] message: $msg\n", 'ignore' );

	my $now = time;
	push @{ $recent->{$from} ||= [] }, { time => $now, msg => $msg };
	@{ $recent->{$from} } = grep { $_->{time} > $now - 7 } @{ $recent->{$from} };
	$msg = join '', map { $_->{msg} } @{ $recent->{$from} };

	# NOTE: "V" is converted to "W" before these tokens are looked at.
	my $tokens = [ qw(
		cgold 4shop eabcde seagm goldnba z=golds mmook goldcentral
		gridgold irozenyshop mmook buyrozeny gameygg zenyragial goldceo
		fkgold ggatm thepowerlevel wgolds helper coupon coupons org com
		bonus usd www web skype wechat
	) ];

	# Convert inverted space/underscore.
	$msg =~ tr/ _/_ / if $msg =~ /^_.*_$/o;

	# Eat question marks.
	$msg =~ s/[?]//gos;

	# Strip }and{
	$msg =~ s/\Q}and{\E//gos;

	# <    => C
	# [    => C
	# (    => C
	# 0    => O
	# ()   => O
	# /\/\ => M
	# rn   => m
	# /Y\  => M
	$msg =~ s/[l|]V[l|]/M/gios;
	$msg =~ s/!Y!/M/gios;
	$msg =~ s/\/\\\/\\/M/gios;
	$msg =~ s/\(\)|0/O/gios;
	$msg =~ s/<|\[|\(/C/gios;
	$msg =~ s/rn/m/gios;

	$msg =~ s/[`~\[\]_\/]//gios;

	$msg =~ s/V/W/gios;
	$msg =~ s/[3W][.,:;]?W+/ www /gios;

	# Eat punctuation. This seems risky, but let's give it a try. The
	# regexes below could just match whitespace, since the punctuation is
	# already gone.
	$msg =~ s/["'.,:;#@*+-]+//gos;

	@$tokens = reverse sort { length $a <=> length $b } @$tokens;
	foreach ( @$tokens ) {
		my $pat = join '[\s.,:;#@-]*', split //;
		$msg =~ s{$pat}{ $_ }gis;
	}

	my $pat = '\b(?:' . join( '|', @$tokens ) . '|[\dO]*\s*usd?|(?:[uas]|rm|eur)\$?[\dO]+|[\dO]+[m$]|safe|zeny|quick|skype|gift)\b|[-\s]+\d+$';
	my @matches = grep {$_} $msg =~ /($pat)/gi;

	# Check for MMOOK, who seems to be pretty aggressive, and is unlikely to get matched in normal conversation.
	my @aggressives = $msg =~ /(m.*m.*o.*o.*k)/gi;
	push @matches, @aggressives;

	Log::debug( "[ignore] modify:  $msg\n", 'ignore' );
	Log::debug( "[ignore] pattern: $pat\n", 'ignore' );
	Log::debug( "[ignore] matches: " . @matches . ": " . join( ' ', map {"[$_]"} @matches ) . "\n", 'ignore' );

	return if @matches < 3;

	# The server only ignores a certain number of characters.
	# Silently ignore offenders that the server isn't ignoring for us.
	if ( !$ignore->{$from} || timeOut( $ignore->{$from} ) ) {
		Log::warning( "[ignore] Auto-ignoring character [$from] due to offensive $type message.\n" );
		$messageSender->sendIgnore( $from );
	}

	$ignore->{$from} = { time => time, timeout => 60 };

	Log::debug( "[ignore] ignored: $msg\n", 'ignore' );

	return 1;
}

1;