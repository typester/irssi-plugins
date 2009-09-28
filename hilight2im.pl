use strict;
use warnings;

use Glib;

use Irssi;
use AnyEvent::HTTP;

use HTTP::Request::Common;

our $VERSION = '0.1';

our %IRSSI = (
    name        => 'hilight2im',
    description => 'notify hilight message to IM via im.kayac.com api',
    authors     => 'Daisuke Murase',
);

sub sig_printtext {
    my ($dest, $text, $stripped) = @_;

    if ( $dest->{level} & MSGLEVEL_HILIGHT ) {
        my $user = Irssi::settings_get_str('im_kayac_com_username') or return;
        my $msg  = sprintf('[irssi] %s %s', $dest->{target}, $stripped);

        my $req = POST "http://im.kayac.com/api/post/$user", [ message => $msg ];
        my %headers = map { $_ => $req->header($_), } $req->headers->header_field_names;

        my $r;
        $r = http_post $req->uri, $req->content, headers => \%headers, sub { undef $r };
    }
}

Irssi::signal_add('print text' => \&sig_printtext);
Irssi::settings_add_str('im_kayac_com', 'im_kayac_com_username', '');
