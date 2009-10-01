use strict;
use warnings;

use Irssi;

use AnyEvent;
use AnyEvent::HTTPD;
use JSON::XS;
use MIME::Base64;

our $state = {};

Irssi::settings_add_str('webapi', 'webapi_bind', '0.0.0.0');
Irssi::settings_add_int('webapi', 'webapi_port', 4423);
Irssi::settings_add_str('webapi', 'webapi_docroot', '/');
Irssi::settings_add_int('webapi', 'webapi_maxlogs', 100);
Irssi::settings_add_bool('webapi', 'webapi_use_auth', 0);
Irssi::settings_add_str('webapi', 'webapi_auth_username', '');
Irssi::settings_add_str('webapi', 'webapi_auth_password', '');

Irssi::signal_add( "message $_" => bind_signal("irssi_$_") )
    for qw/public private own_public own_private join part quit kick nick own_nick invite topic/;
Irssi::signal_add( "message irc $_" => bind_signal("irssi_irc_$_") )
    for qw/op_public own_wall own_action action own_notice notice own_ctcp ctcp/;
Irssi::signal_add( 'print text' => bind_signal('irssi_print_text') );

Irssi::command_bind( webapi_start => sub {
    if ($state->{_httpd}) {
        Irssi::print('web api already started');
        return;
    }

    my $httpd = $state->{_httpd} = AnyEvent::HTTPD->new(
        host => Irssi::settings_get_str('webapi_bind'),
        port => Irssi::settings_get_int('webapi_port'),
    );

    $httpd->reg_cb(
        error => sub {
            Irssi::print("[web api] $_[1]");
        },
        '' => sub {
            my ($httpd, $req) = @_;

            my $require_authentication = 0;
            if (Irssi::settings_get_bool('webapi_use_auth')) {
                if (my ($auth) = ($req->headers->{authorization} || '') =~ /Basic (.*)/) {
                    my ($username, $password) = split ':', decode_base64($auth);

                    $require_authentication++
                        unless $username eq Irssi::settings_get_str('webapi_auth_username')
                           and $password eq Irssi::settings_get_str('webapi_auth_password');
                }
                else {
                    $require_authentication++;
                }
            }

            if ($require_authentication) {
                $req->respond([
                    401, 'Authorization Required',
                    { 'WWW-Authenticate' => 'Basic realm="Authorization Required"',
                      'Content-Type'     => 'text/html',
                    },
                    '<h1>401 Authorization Required</h1>',
                ]);
            }
            else {
                handle_request($req);
            }
        },
    );

    my $root = doc_root();
    Irssi::print(qq[web api started at http://$httpd->{host}:$httpd->{port}$root]);
});

Irssi::command_bind( webapi_stop => sub {
    if (!$state->{_httpd}) {
        Irssi::print('web api is not running');
        return;
    }

    delete $state->{_httpd};
    $state = {};
    Irssi::print('web api stopped');
});

sub bind_signal {
    my $sub = __PACKAGE__->can(shift);

    our $state;
    return sub {
        return unless $state->{_httpd};
        $sub->(@_) if $sub;
    };
}

sub doc_root {
    my $root = Irssi::settings_get_str('webapi_docroot') || '/';
    $root =~ s!(^(/+)?|(/+)?$)!/!g;
    $root;
}

sub handle_request {
    my ($req) = @_;

    my $root = doc_root();
    (my $path = $req->url) =~ s/^$root//;

    my $paths = {
        'servers'  => \&handle_servers,
        'channels' => \&handle_channels,
        'queries'  => \&handle_queries,
        'messages' => \&handle_messages,
        'nicks'    => \&handle_nicks,
        'replies'  => \&handle_replies,
        'post'     => \&handle_post,
    };

    my $json = $state->{_json} ||= JSON::XS->new;

    if (my $code = $paths->{$path}) {
        my $res = $code->($req);
        $req->respond({ content => ['application/json', $json->encode($res) ]});
    }
    else {
        $req->respond(
            [   404, 'Not Found',
                { 'Content-Type' => 'text/html', },
                '<h1>404 Not Found</h1>'
            ]
        );
    }
}

sub handle_servers {
    my ($req) = @_;

    [map +{
        tag       => $_->{tag},
        nick      => $_->{nick},
        connected => $_->{connected},
        $_->{real_address} ? (address => $_->{real_address}) : (),
    }, Irssi::servers()];
}

sub handle_channels {
    my ($req) = @_;

    my @channels;
    if (my $server_tag = $req->parm('server')) {
        my $server = Irssi::server_find_tag($server_tag);
        unless ($server) {
            return { error => qq[no such server tag:"$server_tag"] };
        }

        @channels = $server->channels;
    }
    else {
        @channels = Irssi::channels();
    }

    [map channel_hash($_), @channels];
}

sub handle_queries {
    my ($req) = @_;

    my @queries;
    if (my $server_tag = $req->parm('server')) {
        my $server = Irssi::server_find_tag($server_tag);
        unless ($server) {
            return { error => qq[no such server tag:"$server_tag"] };
        }

        @queries = $server->queries();
    }
    else {
        @queries = Irssi::queries();
    }

    [map query_hash($_), @queries];
}

sub handle_messages {
    my ($req) = @_;

    if (my $server_tag = $req->parm('server')) {
        my $server = Irssi::server_find_tag($server_tag);
        unless ($server) {
            return { error => qq[no such server tag:"$server_tag"] };
        }

        my $target = $req->parm('target')
            or return { error => 'target parameter is required' };

        my $channel = $server->channel_find($target) || $server->query_find($target)
            or return { error => qq[no such target: "$target"] };

        $state->{unread_count}{ $server_tag }{ $target } = 0;
        return $state->{messages}{ $server_tag }{ $target } ||= [];
    }

    return { error => qq[parameters are missing] };
}

sub handle_nicks {
    my ($req) = @_;

    if (my $server_tag = $req->parm('server')) {
        my $server = Irssi::server_find_tag($server_tag);
        unless ($server) {
            return { error => qq[no such server tag:"$server_tag"] };
        }

        my $target = $req->parm('target')
            or return { error => 'channel parameter is required' };

        my $channel = $server->channel_find($target) || $server->query_find($target)
            or return { error => qq[no such target: "$target"] };

        if ($channel->{type} eq 'QUERY') {
            return [{ nick => $channel->{name} }];
        }
        else {
            return [map nick_hash($_), $channel->nicks];
        }
    }

    return { error => qq[parameters are missing] };
}

sub handle_replies {
    my ($req) = @_;
    return $state->{replies} ||= [];
}

sub handle_post {
    my ($req) = @_;

    return { error => qq[method "@{[ $req->method ]}" does not allowed] }
        unless $req->method eq 'POST';

    my $server_tag = $req->vars->{server}
        or return { error => qq[server parameter required] };

    my $server = Irssi::server_find_tag($server_tag)
        or return { error => qq[server "$server_tag" does not exists] };

    my $target = $req->vars->{target}
        or return { error => qq[channel parameter required] };

    my $message = $req->vars->{message}
        or return { error => qq[message parameter required] };

    if ($message =~ m!^/me (.+)!) {
        $server->command("ACTION $target $1");
    }
    else {
        $server->command("MSG $target $message");
    }

    return { result => 'sent' };
}

sub nick_hash {
    my ($nick) = @_;

    return {
        nick     => $nick->{nick},
        op       => $nick->{op},
        voice    => $nick->{voice},
        halfop   => $nick->{halfop},
    };
}

sub channel_hash {
    my ($channel) = @_;

    return {
        name   => $channel->{name},
        topic  => $channel->{topic},
        server => $channel->{server}{tag},
        unread => $state->{unread_count}{ $channel->{server}{tag} }{ $channel->{name} }
            || 0,
    };
}

sub query_hash {
    my ($query) = @_;

    return {
        name   => $query->{name},
        server => $query->{server_tag},
        unread => $state->{unread_count}{ $query->{server_tag} }{ $query->{name} } || 0,
    };
}

sub server_hash {
    my ($server) = @_;
    $server = Irssi::server_find_tag($server) unless ref $server;
    return unless $server;

    return {
        tag       => $server->{tag},
        nick      => $server->{nick},
        connected => $server->{connected},
        $server->{real_address} ? (address => $server->{real_address}) : (),
    };
}

sub add_message {
    my ($server, $channel_name, $nick_name, $type, $message, %extra) = @_;

    my $channel = $server->channel_find($channel_name)
        || $server->query_find($channel_name);

    my $nick = $channel->{type} eq 'CHANNEL' ? $channel->nick_find($nick_name) : undef;

    my $log = $state->{messages}{ $server->{tag} }{ $channel->{name} } ||= [];
    push @$log, $state->{last_message} = {
        time    => time,
        nick    => $nick_name,
        type    => $type,
        is_own  => $server->{nick} eq $nick_name,
        $nick ? (
            is_op     => $nick->{op},
            is_voice  => $nick->{voice},
            is_halfop => $nick->{halfop},
        ): (),
        message => $message,
        %extra,
    };
    $state->{last_channel} = $channel;

    if (@$log > Irssi::settings_get_int('webapi_maxlogs')) {
        shift @$log;
    }

    if ($type =~ /(public|private|notice|action)/) {
        $state->{unread_count}{ $server->{tag} }{ $channel->{name} }++;
    }
}

sub irssi_public {
    my ($server, $msg, $nick, $address, $target) = @_;
    add_message( $server, $target, $nick, public => $msg );
}

sub irssi_own_public {
    my ($server, $msg, $target) = @_;
    add_message( $server, $target, $server->{nick}, public => $msg );
}

sub irssi_private {
    # "message private", SERVER_REC, char *msg, char *nick, char *address
    my ($server, $msg, $nick, $address) = @_;
    add_message( $server, $nick, $nick, private => $msg );
}

sub irssi_own_private {
    # "message own_private", SERVER_REC, char *msg, char *target, char *orig_target
    my ($server, $msg, $target, $orig_target) = @_;
    add_message( $server, $target, $server->{nick}, private => $msg );
}

sub irssi_join {
    # "message join", SERVER_REC, char *channel, char *nick, char *address
    my ($server, $channel, $nick, $address) = @_;
    add_message( $server, $channel, $nick, join => undef );
}

sub irssi_part {
    # "message part", SERVER_REC, char *channel, char *nick, char *address, char *reason
    my ($server, $channel, $nick, $address, $reason) = @_;
    add_message( $server, $channel, $nick, part => $reason );
}

sub irssi_kick {
    # "message kick", SERVER_REC, char *channel, char *nick, char *kicker, char *address, char *reason
    my ($server, $channel, $nick, $kicker, $address, $reason) = @_;
    add_message( $server, $channel, $nick, kick => $reason, kicker => $kicker );
}

sub irssi_topic {
    # "message topic", SERVER_REC, char *channel, char *topic, char *nick, char *address
    my ($server, $channel, $topic, $nick, $address) = @_;
    add_message( $server, $channel, $nick, topic => $topic );
}

sub irssi_irc_action {
    # "message irc action", SERVER_REC, char *msg, char *nick, char *address, char *target
    my ($server, $msg, $nick, $address, $target) = @_;
    add_message( $server, $target, $nick, action => $msg );
}

sub irssi_irc_own_action {
    # "message irc own_action", SERVER_REC, char *msg, char *target
    my ($server, $msg, $target) = @_;
    add_message( $server, $target, $server->{nick}, action => $msg );
}

sub irssi_irc_notice {
    # "message irc notice", SERVER_REC, char *msg, char *nick, char *address, char *target
    my ($server, $msg, $nick, $address, $target) = @_;
    add_message( $server, $target, $nick, notice => $msg );
}

sub irssi_irc_own_notice {
    # "message irc own_notice", SERVER_REC, char *msg, char *target
    my ($server, $msg, $target) = @_;
    add_message( $server, $target, $server->{nick}, notice => $msg );
}

sub irssi_print_text {
    my ($dest, $text, $stripped) = @_;
    return unless $dest->{level} & MSGLEVEL_HILIGHT;

    return if $state->{last_channel}{server}{tag} ne $dest->{server}{tag};
    return if $state->{last_channel}{name} ne $dest->{target};

    my $log = $state->{replies} ||= [];
    push @$log, {
        %{ $state->{last_message} },
        server  => $dest->{server}{tag},
        channel => $dest->{target},
    };
}

# avoid warning
{ package Irssi::Nick }
