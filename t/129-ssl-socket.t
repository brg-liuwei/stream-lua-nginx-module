# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua::Stream;
repeat_each(2);

plan tests => repeat_each() * (blocks() * 7);

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();

sub read_file {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $StartComRootCertificate = read_file("t/cert/startcom.crt");
our $EquifaxRootCertificate = read_file("t/cert/equifax.crt");
our $TestCertificate = read_file("t/cert/test.crt");
our $TestCertificateKey = read_file("t/cert/test.key");
our $TestCRL = read_file("t/cert/test.crl");

run_tests();

__DATA__

=== TEST 1: www.google.com
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER ipv6=off;

    content_by_lua_block {
        -- avoid flushing google in "check leak" testing mode:
        local counter = package.loaded.counter
        if not counter then
            counter = 1
        elseif counter >= 2 then
            return ngx.exit(503)
        else
            counter = counter + 1
        end
        package.loaded.counter = counter

        do
            local sock = ngx.socket.tcp()
            sock:settimeout(2000)
            local ok, err = sock:connect("www.google.com", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake()
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "GET / HTTP/1.1\r\nHost: www.google.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response_like chop
\Aconnected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 (?:200 OK|302 Found)
close: 1 nil
\z
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- no_error_log
lua ssl server name:
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 2: no SNI, no verify
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("g.sregex.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake()
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local req = "GET / HTTP/1.1\r\nHost: g.sregex.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 57 bytes.
received: HTTP/1.1 401 Unauthorized
close: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- no_error_log
lua ssl server name:
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 3: SNI, no verify
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org")
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- error_log
lua ssl server name: "iscribblet.org"
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 4: ssl session reuse
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do

        local session
        for i = 1, 2 do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            session, err = sock:sslhandshake(session, "iscribblet.org")
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end

        end -- do
        collectgarbage()
    }

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil
connected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl set session: \1:2
lua ssl save session: \1:3
lua ssl free session: \1:2
lua ssl free session: \1:1
$/

--- error_log
SSL reused session
lua ssl free session

--- log_level: debug
--- no_error_log
[error]
[alert]
--- timeout: 5



=== TEST 5: certificate does not match host name (verify)
The certificate for "blah.agentzh.org" does not contain the name "blah.agentzh.org".
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 5;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("agentzh.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "blah.agentzh.org", true)
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
            else
                ngx.say("ssl handshake: ", type(session))
            end

            local req = "GET / HTTP/1.1\r\nHost: agentzh.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- user_files eval
">>> trusted.crt
$::StartComRootCertificate"

--- stream_response
connected: 1
failed to do SSL handshake: certificate host mismatch
failed to send stream request: closed

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log
lua ssl server name: "blah.agentzh.org"
lua ssl certificate does not match host "blah.agentzh.org"
--- no_error_log
SSL reused session
[alert]
--- timeout: 5



=== TEST 6: certificate does not match host name (verify, no log socket errors)
The certificate for "blah.agentzh.org" does not contain the name "blah.agentzh.org".
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_socket_log_errors off;
    lua_ssl_verify_depth 2;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("agentzh.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "blah.agentzh.org", true)
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
            else
                ngx.say("ssl handshake: ", type(session))
            end

            local req = "GET / HTTP/1.1\r\nHost: blah.agentzh.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- user_files eval
">>> trusted.crt
$::StartComRootCertificate"

--- stream_response
connected: 1
failed to do SSL handshake: certificate host mismatch
failed to send stream request: closed

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log
lua ssl server name: "blah.agentzh.org"
--- no_error_log
lua ssl certificate does not match host
SSL reused session
[alert]
--- timeout: 5



=== TEST 7: certificate does not match host name (no verify)
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("agentzh.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "agentzh.org", false)
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/

--- error_log
lua ssl server name: "agentzh.org"
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 8: iscribblet.org: passing SSL verify
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 2;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org", true)
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- user_files eval
">>> trusted.crt
$::StartComRootCertificate"

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/

--- error_log
lua ssl server name: "iscribblet.org"
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 9: ssl verify depth not enough (with automatic error logging)
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 1;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org", true)
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
            else
                ngx.say("ssl handshake: ", type(session))
            end

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- user_files eval
">>> trusted.crt
$::StartComRootCertificate"

--- stream_response
connected: 1
failed to do SSL handshake: 20: unable to get local issuer certificate
failed to send stream request: closed

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log
lua ssl server name: "iscribblet.org"
lua ssl certificate verify error: (20: unable to get local issuer certificate)
--- no_error_log
SSL reused session
[alert]
--- timeout: 5



=== TEST 10: ssl verify depth not enough (without automatic error logging)
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 1;
    lua_socket_log_errors off;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org", true)
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
            else
                ngx.say("ssl handshake: ", type(session))
            end

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- user_files eval
">>> trusted.crt
$::StartComRootCertificate"

--- stream_response
connected: 1
failed to do SSL handshake: 20: unable to get local issuer certificate
failed to send stream request: closed

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log
lua ssl server name: "iscribblet.org"
--- no_error_log
lua ssl certificate verify error
SSL reused session
[alert]
--- timeout: 7



=== TEST 11: www.google.com  (SSL verify passes)
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 3;

    content_by_lua_block {
        -- avoid flushing google in "check leak" testing mode:
        local counter = package.loaded.counter
        if not counter then
            counter = 1
        elseif counter >= 2 then
            return ngx.exit(503)
        else
            counter = counter + 1
        end
        package.loaded.counter = counter

        do
            local sock = ngx.socket.tcp()
            sock:settimeout(2000)
            local ok, err = sock:connect("www.google.com", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "www.google.com", true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "GET / HTTP/1.1\r\nHost: www.google.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- user_files eval
">>> trusted.crt
$::EquifaxRootCertificate"

--- stream_response_like chop
\Aconnected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 (?:200 OK|302 Found)
close: 1 nil
\z
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- error_log
lua ssl server name: "www.google.com"
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 12: www.google.com  (SSL verify enabled and no corresponding trusted certificates)
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 3;

    content_by_lua_block {
        -- avoid flushing google in "check leak" testing mode:
        local counter = package.loaded.counter
        if not counter then
            counter = 1
        elseif counter >= 2 then
            return ngx.exit(503)
        else
            counter = counter + 1
        end
        package.loaded.counter = counter

        do
            local sock = ngx.socket.tcp()
            sock:settimeout(2000)
            local ok, err = sock:connect("www.google.com", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "www.google.com", true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "GET / HTTP/1.1\r\nHost: www.google.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- user_files eval
">>> trusted.crt
$::StartComRootCertificate"

--- stream_response
connected: 1
failed to do SSL handshake: 20: unable to get local issuer certificate

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log
lua ssl server name: "www.google.com"
lua ssl certificate verify error: (20: unable to get local issuer certificate)
--- no_error_log
SSL reused session
[alert]
--- timeout: 5



=== TEST 13: iscribblet.org: passing SSL verify with multiple certificates
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 2;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org", true)
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- user_files eval
">>> trusted.crt
$::EquifaxRootCertificate
$::StartComRootCertificate"

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/

--- error_log
lua ssl server name: "iscribblet.org"
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 14: default cipher
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org")
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- error_log
lua ssl server name: "iscribblet.org"
SSL: TLSv1.2, cipher: "ECDHE-RSA-RC4-SHA SSLv3
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 15: explicit cipher configuration
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_ciphers RC4-SHA;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org")
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- error_log
lua ssl server name: "iscribblet.org"
SSL: TLSv1.2, cipher: "RC4-SHA SSLv3
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 10



=== TEST 16: explicit ssl protocol configuration
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_protocols TLSv1;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org")
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- error_log
lua ssl server name: "iscribblet.org"
SSL: TLSv1, cipher: "ECDHE-RSA-RC4-SHA SSLv3
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 17: unsupported ssl protocol
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_protocols SSLv2;
    lua_socket_log_errors off;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org")
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
            else
                ngx.say("ssl handshake: ", type(session))
            end

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response
connected: 1
failed to do SSL handshake: handshake failed
failed to send stream request: closed

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log eval
[
qr/\[crit\] .*?SSL_do_handshake\(\) failed .*?unsupported protocol/,
'lua ssl server name: "iscribblet.org"',
]
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 18: iscribblet.org: passing SSL verify: keepalive (reuse the ssl session)
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 2;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do

        local session
        for i = 1, 3 do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            session, err = sock:sslhandshake(session, "iscribblet.org", true)
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))

            local ok, err = sock:setkeepalive()
            ngx.say("set keepalive: ", ok, " ", err)
        end  -- do

        end
        collectgarbage()
    }

--- config
    server_tokens off;

--- user_files eval
">>> trusted.crt
$::StartComRootCertificate"

--- stream_response
connected: 1
ssl handshake: userdata
set keepalive: 1 nil
connected: 1
ssl handshake: userdata
set keepalive: 1 nil
connected: 1
ssl handshake: userdata
set keepalive: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: \1:2
$/

--- error_log
lua tcp socket get keepalive peer: using connection
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 19: iscribblet.org: passing SSL verify: keepalive (no reusing the ssl session)
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 2;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        do

        local sessions = {}

        for i = 1, 3 do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local session, err = sock:sslhandshake(nil, "iscribblet.org", true)
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            sessions[i] = session

            ngx.say("ssl handshake: ", type(session))

            local ok, err = sock:setkeepalive()
            ngx.say("set keepalive: ", ok, " ", err)
            ngx.sleep(0.001)
        end  -- do

        end
        collectgarbage()
    }

--- user_files eval
">>> trusted.crt
$::StartComRootCertificate"

--- stream_response
connected: 1
ssl handshake: userdata
set keepalive: 1 nil
connected: 1
ssl handshake: userdata
set keepalive: 1 nil
connected: 1
ssl handshake: userdata
set keepalive: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/stream lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^stream lua ssl save session: ([0-9A-F]+):2
stream lua ssl save session: \1:3
stream lua ssl save session: \1:4
stream lua ssl free session: \1:4
stream lua ssl free session: \1:3
stream lua ssl free session: \1:2
$/

--- error_log
lua tcp socket get keepalive peer: using connection
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 20: downstream cosockets do not support ssl handshake
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/trusted.crt;
    lua_ssl_verify_depth 2;

    content_by_lua_block {
        local sock = ngx.req.socket()
        local sess, err = sock:sslhandshake()
        if not sess then
            ngx.say("failed to do ssl handshake: ", err)
        else
            ngx.say("ssl handshake: ", type(sess))
        end
    }

--- user_files eval
">>> trusted.crt
$::StartComRootCertificate"

--- stream_response
--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log
attempt to call method 'sslhandshake' (a nil value)
--- no_error_log
[alert]
--- timeout: 3



=== TEST 21: unix domain ssl cosocket (no verify)
--- stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;

        content_by_lua_block {
            local sock = assert(ngx.req.socket(true))
            local data = sock:receive()
            if data == "thunder!" then
                ngx.say("flash!")
            else
                ngx.say("boom!")
            end
            ngx.say("the end...")
        }
    }
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()
            sock:settimeout(3000)
            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake()
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "thunder!\n";
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to recieve response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 9 bytes.
received: flash!
received: the end...
close: 1 nil

--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate"

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- no_error_log
lua ssl server name:
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 22: unix domain ssl cosocket (verify)
--- stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;

        content_by_lua_block {
            local sock = assert(ngx.req.socket(true))
            local data = sock:receive()
            if data == "thunder!" then
                ngx.say("flash!")
            else
                ngx.say("boom!")
            end
            ngx.say("the end...")
        }
    }
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/test.crt;


    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()
            sock:settimeout(3000)
            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "test.com", true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "thunder!\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to recieve response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 9 bytes.
received: flash!
received: the end...
close: 1 nil

--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate"

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- error_log
lua ssl server name: "test.com"
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 23: unix domain ssl cosocket (no ssl on server)
--- stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        content_by_lua_block {
            local sock = assert(ngx.req.socket(true))
            local data = sock:receive()
            if data == "thunder!" then
                ngx.say("flash!")
            else
                ngx.say("boom!")
            end
            ngx.say("the end...")
        }
    }
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake()
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "thunder!\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to recieve response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- stream_response
connected: 1
failed to do SSL handshake: handshake failed

--- user_files eval
">>> test.crt
$::TestCertificate"

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log eval
qr/SSL_do_handshake\(\) failed .*?unknown protocol/
--- no_error_log
lua ssl server name:
SSL reused session
[alert]
--- timeout: 3



=== TEST 24: lua_ssl_crl
--- stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;

        content_by_lua_block {
            local sock = assert(ngx.req.socket(true))
            local data = sock:receive()
            if data == "thunder!" then
                ngx.say("flash!")
            else
                ngx.say("boom!")
            end
        }
    }
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_crl ../html/test.crl;
    lua_ssl_trusted_certificate ../html/test.crt;
    lua_socket_log_errors off;

    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()

            sock:settimeout(3000)

            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, "test.com", true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
            else
                ngx.say("ssl handshake: ", type(sess))
            end

            local req = "thunder!\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to recieve response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- stream_response
connected: 1
failed to do SSL handshake: 12: CRL has expired
failed to send stream request: closed

--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate
>>> test.crl
$::TestCRL"

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log
lua ssl server name: "test.com"
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 25: multiple handshake calls
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        local sock = ngx.socket.tcp()

        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            for i = 1, 2 do
                local session, err = sock:sslhandshake(nil, "iscribblet.org")
                if not session then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(session))
            end

            local req = "GET / HTTP/1.1\r\nHost: iscribblet.org\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to recieve response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response
connected: 1
ssl handshake: userdata
ssl handshake: userdata
sent stream request: 59 bytes.
received: HTTP/1.1 200 OK
close: 1 nil

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl save session: ([0-9A-F]+):3
lua ssl free session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- error_log
lua ssl server name: "iscribblet.org"
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 26: handshake timed out
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        local sock = ngx.socket.tcp()

        sock:settimeout(2000)

        do
            local ok, err = sock:connect("iscribblet.org", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(1);  -- should timeout immediately
            local session, err = sock:sslhandshake(nil, "iscribblet.org")
            if not session then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(session))
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response
connected: 1
failed to do SSL handshake: timeout

--- log_level: debug
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log
lua ssl server name: "iscribblet.org"
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 27: unix domain ssl cosocket (no gen session)
--- stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;

        content_by_lua_block {
            local sock = assert(ngx.req.socket(true))
            local data = sock:receive()
            if data == "thunder!" then
                ngx.say("flash!")
            else
                ngx.say("boom!")
            end
            ngx.say("the end...")
        }
    }
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()
            sock:settimeout(3000)
            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", sess)

            sock:close()
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response
connected: 1
ssl handshake: true

--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate"

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- no_error_log
lua ssl server name:
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 28: unix domain ssl cosocket (gen session, true)
--- stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;

        content_by_lua_block {
            local sock = assert(ngx.req.socket(true))
            local data = sock:receive()
            if data == "thunder!" then
                ngx.say("flash!")
            else
                ngx.say("boom!")
            end
            ngx.say("the end...")
        }
    }
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()
            sock:settimeout(3000)
            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            sock:close()
        end  -- do
        collectgarbage()
    }

--- stream_response
connected: 1
ssl handshake: userdata

--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate"

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- no_error_log
lua ssl server name:
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 29: unix domain ssl cosocket (keepalive)
--- stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;

        content_by_lua_block {
            local sock = assert(ngx.req.socket(true))
            local data = sock:receive()
            if data == "thunder!" then
                ngx.say("flash!")
            else
                ngx.say("boom!")
            end
        }
    }
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;

    content_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(3000)
        for i = 1, 2 do
            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", sess)

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end
        end  -- do
        collectgarbage()
    }

--- config
    server_tokens off;

--- stream_response
connected: 1
ssl handshake: true
connected: 1
ssl handshake: true

--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate"

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- no_error_log
lua ssl server name:
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 30: unix domain ssl cosocket (verify cert but no host name check, passed)
--- stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;

        content_by_lua_block {
            local sock = assert(ngx.req.socket(true))
            local data = sock:receive()
            if data == "thunder!" then
                ngx.say("flash!")
            else
                ngx.say("boom!")
            end
            ngx.say("the end...")
        }
    }
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../html/test.crt;


    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()
            sock:settimeout(3000)
            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, nil, true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "thunder!\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to recieve response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- stream_response
connected: 1
ssl handshake: userdata
sent stream request: 9 bytes.
received: flash!
received: the end...
close: 1 nil

--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate"

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+):2
lua ssl free session: ([0-9A-F]+):1
$/
--- error_log
--- no_error_log
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 31: unix domain ssl cosocket (verify cert but no host name check, NOT passed)
--- stream_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;

        content_by_lua_block {
            local sock = assert(ngx.req.socket(true))
            local data = sock:receive()
            if data == "thunder!" then
                ngx.say("flash!")
            else
                ngx.say("boom!")
            end
        }
    }
--- stream_server_config
    lua_resolver $TEST_NGINX_RESOLVER;
    #lua_ssl_trusted_certificate ../html/test.crt;


    content_by_lua_block {
        do
            local sock = ngx.socket.tcp()
            sock:settimeout(3000)
            local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake(nil, nil, true)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "thunder"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send stream request: ", err)
                return
            end

            ngx.say("sent stream request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to recieve response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
        collectgarbage()
    }

--- stream_response
connected: 1
failed to do SSL handshake: 18: self signed certificate

--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate"

--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+:\d+/
--- grep_error_log_out
--- error_log
lua ssl certificate verify error: (18: self signed certificate)
--- no_error_log
SSL reused session
[alert]
--- timeout: 5
