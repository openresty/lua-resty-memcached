# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (2 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
};


no_long_string();
no_diff();

run_tests();

__DATA__

=== TEST 1: basic
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local key = "dog&cat&rabbit"
         	local memcached = require "resty.memcached"
			local memc = memcached:new()
            memc:set_timeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set(key, "value", 5)
            if not ok then
                ngx.say("failed to set ", key, ": ", err)
                return
            end

            local ok, err = memc:touch(key, 120) --120sec
            if not ok then
                ngx.say("failed to touch ", key, ": ", err)
                return
            end

            ngx.say(ok)
        ';
    }
--- request
	GET /t
--- response_body
1


=== TEST 2: not exists
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local key = "dog&cat&rabbit"
         	local memcached = require "resty.memcached"
			local memc = memcached:new()
            memc:set_timeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:touch(key, 120) --120sec
            if not ok then
                ngx.say("failed to touch ", key, ": ", err)
                return
            end

            ngx.say(ok)
        ';
    }
--- request
 GET /t
--- response_body
failed to touch dog&cat&rabbit: NOT_FOUND

