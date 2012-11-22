use strict;
use warnings;
use Encode;

eval q[use Irssi; 1]; die $@ if $@;

our $VERSION = '0.1';
our %IRSSI   = (
    name => 'try',
);

# SERVER_REC, char *msg, char *target
sub sig_own_public {
    my ($server, $msg, $target) = @_;

    use utf8;
    $msg = decode_utf8 $msg;

    $msg =~ s/つらい/STFUAWSC!/g;

    Irssi::signal_continue(encode_utf8 $msg, $target);
}

Irssi::signal_add('message own_public' => \&sig_own_public);
