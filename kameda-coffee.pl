use strict;
use warnings;
use Encode;

eval q[use Irssi; 1]; die $@ if $@;

our $VERSION = '0.1';
our %IRSSI   = (
    name => 'kameda-coffee',
);

sub sig_public {
    my ($server, $msg, $nick, $address, $target) = @_;

    my $target_nick    = 'kame';
    my $target_channel = '#coffee';
    return unless $nick eq $target_nick and $target eq $target_channel;

    my $match;
    {
        use utf8;
        my $m = decode_utf8 $msg;

        if ($m =~ /珈琲[い淹]れ[たる]/) {
            $match++;
        }
    }

    if ($match) {
        $server->command("MSG $target $target_nick: ほしい！");
    }
}

Irssi::signal_add('message public' => \&sig_public);
