use strict;
use warnings;

use Glib;
use POE qw/
    Loop::Glib
    Session::Irssi;
    Component::Client::HTTPDeferred
    /;

use URI::Template;
use HTTP::Request::Common;

our %IRSSI = (
    name    => 'outputz',
    authors => 'typester@cpan.org',
);

Irssi::settings_add_str('outputz', 'outputz_key', '');
Irssi::settings_add_str('outputz', 'outputz_uri', 'irc://{server}:{port}/{channel}');

POE::Session::Irssi->create(
    irssi_signals => {
        map {
            +"message $_" => sub {
                my ($kernel, $session, $args) = @_[KERNEL, SESSION, ARG1];
                my ($server, $msg, $target)   = @$args;

                my $key = Irssi::settings_get_str('outputz_key');
                my $uri = Irssi::settings_get_str('outputz_uri');
                return unless $key and $uri;

                my $template = URI::Template->new($uri);
                $uri = $template->process(
                    channel    => $target,
                    server     => $server->{address},
                    port       => $server->{port},
                    nick       => $server->{nick},
                    server_tag => $server->{tag},
                );

                my $ua = POE::Component::Client::HTTPDeferred->new;
                my $d  = $ua->request(
                    POST 'http://outputz.com/api/post',
                    [ key => $key, uri => $uri, size => length($msg), ],
                );

                $d->addErrback(sub { Irssi::print('outputz error: ' . shift->status_line) });
                $d->addBoth(sub { $ua->shutdown });
            },
        } qw/own_public own_private/,
    },
);
