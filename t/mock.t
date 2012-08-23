# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (4 * blocks() + 1);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

no_long_string();

run_tests();

__DATA__

=== TEST 1: fail to flush
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:set_timeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 1921);
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            ngx.say("flush: ", ok);

            memc:close()
        ';
    }
--- request
GET /t
--- tcp_listen: 1921
--- tcp_query_len: 11
--- tcp_query eval
"flush_all\r\n"
--- tcp_reply eval
"SOME ERROR\r\n"
--- response_body
failed to flush all: SOME ERROR
--- no_error_log
[error]

