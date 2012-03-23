#!/usr/bin/env perl

use strict;
use warnings;

use Irssi;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

my ($getsock, $setsock);

Irssi::settings_add_str('channel-socket', 'channel-get-socket-path', '/tmp/irssi-channels.sock');
Irssi::settings_add_str('channel-socket', 'channel-set-socket-path', '/tmp/irssi-set-channel.sock');

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

            for my $channel (Irssi::channels()) {
                $h->push_write("$channel->{name}\n") if $h;
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
                Irssi::command('window goto ' . $_[1]);
                undef $h;
            });
        };

        Irssi::print("started socket at: " . Irssi::settings_get_str('channel-socket-path'));
    }
    elsif ($data eq 'stop') {
        undef $setsock;
        undef $getsock;
        Irssi::print("stopped");
    }
});

# avoid warning
{ package Irssi::Nick }

