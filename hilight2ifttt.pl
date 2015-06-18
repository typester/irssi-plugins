use strict;
use warnings;

use Glib;

use Irssi;
use AnyEvent::HTTP;
use JSON;

use HTTP::Request::Common;

our $VERSION = '0.1';

our %IRSSI = (
    name        => 'hilight2itfff',
    description => 'notify hilight message to IF',
    authors     => 'Daisuke Murase',
);

sub sig_printtext {
    my ($dest, $text, $stripped) = @_;

    if ( $dest->{level} & MSGLEVEL_HILIGHT ) {
        my $token = Irssi::settings_get_str('ifttt_secret_key') or return;
        my $msg  = sprintf('%s %s', $dest->{target}, $stripped);

        my $event = Irssi::settings_get_str('ifttt_event_name');

        my $req = POST 'https://maker.ifttt.com/trigger/' . $event . '/with/key/' . $token, [
            value1 => $msg,
        ];
        my %headers = map { $_ => $req->header($_), } $req->headers->header_field_names;

        my $r;
        $r = http_post $req->uri, $req->content, headers => \%headers, sub { undef $r };
    }
}

Irssi::signal_add('print text' => \&sig_printtext);
Irssi::settings_add_str('ifttt', 'ifttt_event_name', '');
Irssi::settings_add_str('ifttt', 'ifttt_secret_key', '');
