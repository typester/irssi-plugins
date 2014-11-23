use strict;
use warnings;

use Glib;

use Irssi;
use AnyEvent::HTTP;
use JSON;

use HTTP::Request::Common;

our $VERSION = '0.1';

our %IRSSI = (
    name        => 'hilight2pushbullet',
    description => 'notify hilight message to Pushbullet',
    authors     => 'Daisuke Murase',
);

sub sig_printtext {
    my ($dest, $text, $stripped) = @_;

    if ( $dest->{level} & MSGLEVEL_HILIGHT ) {
        my $token = Irssi::settings_get_str('pushbullet_token') or return;
        my $msg  = sprintf('%s %s', $dest->{target}, $stripped);

        my $channel = Irssi::settings_get_str('pushbullet_channel_tag');

        my $req = POST 'https://api.pushbullet.com/v2/pushes',
            'Content-Type' => 'application/json',
            'Authorization' => 'Bearer ' . $token,
            Content => to_json({
                type => 'note',
                title => $msg,
                ($channel) ? (channel_tag => $channel) : (),
            });
        my %headers = map { $_ => $req->header($_), } $req->headers->header_field_names;

        my $r;
        $r = http_post $req->uri, $req->content, headers => \%headers, sub { undef $r };
    }
}

Irssi::signal_add('print text' => \&sig_printtext);
Irssi::settings_add_str('pushbullet', 'pushbullet_token', '');
Irssi::settings_add_str('pushbullet', 'pushbullet_channel_tag', '');
