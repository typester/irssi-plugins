#!/usr/bin/env perl

use strict;
use warnings;

use Irssi ();

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

my ($getsock, $setsock);

Irssi::settings_add_str('channel-socket', 'channel-get-socket-path', '/tmp/irssi-channels.sock');
Irssi::settings_add_str('channel-socket', 'channel-set-socket-path', '/tmp/irssi-set-channel.sock');
Irssi::settings_add_bool('channel-socket', 'channel-socket-autostart', 0);

Irssi::command_bind('channel-socket', sub {
    my ($data) = @_;

    if ($data eq 'start') {
        if ($getsock || $setsock) {
            Irssi::print("socket already started");
            return;
        }

        $getsock = tcp_server 'unix/', Irssi::settings_get_str('channel-get-socket-path'), sub {
            my ($fh) = @_;

            my $h; $h = AnyEvent::Handle->new(
                fh       => $fh,
                on_error => sub {
                    undef $h;
                },
            );

            my @window_params_list;
            my $max_length = 0;

            for my $window (Irssi::windows()) {
                my $name       = $window->{active} ? $window->{active}{name}        : $window->{name};
                my $server_tag = $window->{active} ? $window->{active}{server}{tag} : '';
                my $length     = length $name;

                push @window_params_list, {
                    name       => $name,
                    server_tag => $server_tag,
                    length     => length $name,
                };

                $max_length = $length if $max_length < $length;
            }

            for my $params (@window_params_list) {
                my $padding = $params->{server_tag} ? ' ' x ($max_length - $params->{length} + 1) : '';
                $h->push_write("${$params}{name}$padding${$params}{server_tag}\n") if $h;
            }

            $h->on_drain(sub { undef $h }) if $h;
        };

        $setsock = tcp_server 'unix/', Irssi::settings_get_str('channel-set-socket-path'), sub {
            my ($fh) = @_;

            my $h; $h = AnyEvent::Handle->new(
                fh => $fh,
                on_error => sub { undef $h },
            );

            $h->push_read( line => sub {
                my $window_name = (split ' ', $_[1])[0];
                Irssi::command('window goto ' . $window_name);
                undef $h;
            });
        };

        Irssi::print('started socket at:');
        Irssi::print('  read socket: ' . Irssi::settings_get_str('channel-get-socket-path'));
        Irssi::print('  write socket: ' . Irssi::settings_get_str('channel-set-socket-path'));
    }
    elsif ($data eq 'stop') {
        undef $setsock;
        undef $getsock;
        Irssi::print("stopped");
    }
});

if (Irssi::settings_get_str('channel-socket-autostart')) {
    Irssi::command('channel-socket start');
}

# avoid warning
{ package Irssi::Nick }

