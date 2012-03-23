#!/usr/bin/env perl

use strict;
use warnings;

use Irssi;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

my $sock;

Irssi::settings_add_str('channel-socket', 'channel-socket-path', '/tmp/irssi-channel.sock');

Irssi::command_bind('channel-socket', sub {
    my ($data) = @_;

    if ($data eq 'start') {
        if ($sock) {
            Irssi::print("socket already started");
            return;
        }

        $sock = tcp_server 'unix/', Irssi::settings_get_str('channel-socket-path'), sub {
            my ($fh) = @_;

            my $h; $h = AnyEvent::Handle->new(
                fh       => $fh,
                on_error => sub {
                    undef $h;
                },
            );

            my $t; $t = AnyEvent->timer( after => 1, cb => sub { undef $h; $t });

            $h->push_read( line => sub {
                my $channel = Irssi::channel_find($_[1]);
                undef $t;

                if ($channel) {
                    Irssi::command('window goto ' . $channel->{name});
                    undef $h;
                }
                else {
                    for my $channel (Irssi::channels()) {
                        $h->push_write("$channel->{name}\n");
                    }
                    $h->on_drain(sub { undef $h });
                }
            });
        };

        Irssi::print("started socket at: " . Irssi::settings_get_str('channel-socket-path'));
    }
    elsif ($data eq 'stop') {
        undef $sock;
        Irssi::print("stopped");
    }
});

# avoid warning
{ package Irssi::Nick }

