# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';

no_long_string();

run_tests();

__DATA__

=== TEST 1: basic
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res, " (flags: ", flags, ")")
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog: 32 (flags: 0)
--- no_error_log
[error]



=== TEST 2: add an exsitent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local ok, err = memc:add("dog", 56)
            if not ok then
                ngx.say("failed to add dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
failed to add dog: NOT_STORED
dog: 32
--- no_error_log
[error]



=== TEST 3: add a nonexistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:add("dog", 56)
            if not ok then
                ngx.say("failed to add dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog: 56
--- no_error_log
[error]



=== TEST 4: set an exsistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local ok, err = memc:set("dog", 56)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog: 56
--- no_error_log
[error]



=== TEST 5: replace an exsistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local ok, err = memc:replace("dog", 56)
            if not ok then
                ngx.say("failed to replace dog: ", err)
                return
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog: 56
--- no_error_log
[error]



=== TEST 6: replace a nonexsistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:replace("dog", 56)
            if not ok then
                ngx.say("failed to replace dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
failed to replace dog: NOT_STORED
dog not found
--- no_error_log
[error]



=== TEST 7: prepend to a nonexsistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:prepend("dog", 56)
            if not ok then
                ngx.say("failed to prepend to dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
failed to prepend to dog: NOT_STORED
dog not found
--- no_error_log
[error]



=== TEST 8: prepend to an exsistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
            end

            local ok, err = memc:prepend("dog", 56)
            if not ok then
                ngx.say("failed to prepend to dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog: 5632
--- no_error_log
[error]



=== TEST 9: append to a nonexsistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:append("dog", 56)
            if not ok then
                ngx.say("failed to append to dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
failed to append to dog: NOT_STORED
dog not found
--- no_error_log
[error]



=== TEST 10: append to an exsistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
            end

            local ok, err = memc:append("dog", 56)
            if not ok then
                ngx.say("failed to append to dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog: 3256
--- no_error_log
[error]



=== TEST 11: delete an exsistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
            end

            local ok, err = memc:delete("dog")
            if not ok then
                ngx.say("failed to delete dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)

            local res, flags, err = memc:add("dog", 772)
            if err then
                ngx.say("failed to add dog: ", err)
                return
            end

            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog not found
--- no_error_log
[error]



=== TEST 12: delete a nonexsistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:delete("dog")
            if not ok then
                ngx.say("failed to delete dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
failed to delete dog: NOT_FOUND
dog not found
--- no_error_log
[error]



=== TEST 13: delete an exsistent key with delay
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local ok, err = memc:delete("dog", 1)
            if not ok then
                ngx.say("failed to delete dog: ", err)
            end

            local ok, err = memc:add("dog", 76)
            if not ok then
                ngx.say("failed to add dog: ", err)
            end

            local ok, err = memc:replace("dog", 53)
            if not ok then
                ngx.say("failed to replace dog: ", err)
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res)
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
failed to add dog: NOT_STORED
failed to replace dog: NOT_STORED
dog not found
--- no_error_log
[error]



=== TEST 14: flags
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32, 0, 526)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res, " (flags: ", flags, ")")
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog: 32 (flags: 526)
--- no_error_log
[error]



=== TEST 15: set with exptime
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32, 1, 526)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            ngx.location.capture("/sleep");

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res, " (flags: ", flags, ")")
            memc:close()
        ';
    }

    location /sleep {
        echo_sleep 1.01;
    }
--- request
GET /t
--- response_body
dog: 32 (flags: 526)
--- no_error_log
[error]



=== TEST 16: flush with a delay
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local ok, err = memc:flush_all(2)
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res, " (flags: ", flags, ")")
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog: 32 (flags: 0)
--- no_error_log
[error]



=== TEST 17: incr an existent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local value, err = memc:incr("dog", 2)
            if not value then
                ngx.say("failed to incr dog: ", err)
                return
            end

            ngx.say("dog is now: ", value)

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res, " (flags: ", flags, ")")
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog is now: 34
dog: 34 (flags: 0)
--- no_error_log
[error]



=== TEST 18: incr a nonexistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local value, err = memc:incr("dog", 2)
            if not value then
                ngx.say("failed to incr dog: ", err)
                return
            end

            ngx.say("dog is now: ", value)

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res, " (flags: ", flags, ")")
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
failed to incr dog: NOT_FOUND
--- no_error_log
[error]



=== TEST 19: decr an existent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local value, err = memc:decr("dog", 3)
            if not value then
                ngx.say("failed to decr dog: ", err)
                return
            end

            ngx.say("dog is now: ", value)

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res, " (flags: ", flags, ")")
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
dog is now: 29
dog: 29 (flags: 0)
--- no_error_log
[error]



=== TEST 20: decr a nonexistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local value, err = memc:decr("dog", 2)
            if not value then
                ngx.say("failed to decr dog: ", err)
                return
            end

            ngx.say("dog is now: ", value)

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res, " (flags: ", flags, ")")
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
failed to decr dog: NOT_FOUND
--- no_error_log
[error]



=== TEST 21: general stats
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local lines, err = memc:stats()
            if not lines then
                ngx.say("failed to stats: ", err)
                return
            end

            ngx.say("stats:\\n", table.concat(lines, "\\n"))

            memc:close()
        ';
    }
--- request
GET /t
--- response_body_like chop
^stats:
STAT pid \d+
(?:STAT [^\n]+\n)*$
--- no_error_log
[error]



=== TEST 22: stats items
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local lines, err = memc:stats("items")
            if not lines then
                ngx.say("failed to stats items: ", err)
                return
            end

            ngx.say("stats:\\n", table.concat(lines, "\\n"))

            memc:close()
        ';
    }
--- request
GET /t
--- response_body_like chop
^stats:
(?:STAT items:[^\n]+\n)*$
--- no_error_log
[error]



=== TEST 23: stats sizes
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local lines, err = memc:stats("sizes")
            if not lines then
                ngx.say("failed to stats sizes: ", err)
                return
            end

            ngx.say("stats:\\n", table.concat(lines, "\\n"))

            memc:close()
        ';
    }
--- request
GET /t
--- response_body_like chop
^stats:
(?:\d+ \d+\n)*$
--- no_error_log
[error]



=== TEST 24: version
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ver, err = memc:version()
            if not ver then
                ngx.say("failed to get version: ", err)
                return
            end

            ngx.say("version: ", ver)

            memc:close()
        ';
    }
--- request
GET /t
--- response_body_like chop
^version: \d+(?:\.\d+)*$
--- no_error_log
[error]



=== TEST 25: quit
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:quit()
            if not ok then
                ngx.say("failed to quit: ", err)
                return
            end

            local ver, err = memc:version()
            if not ver then
                ngx.say("failed to get version: ", err)
                return
            end

            local ok, err = memc:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end

            ngx.say("closed successfully")
        ';
    }
--- request
GET /t
--- response_body_like chop
^failed to get version: \S.*$
--- no_error_log
[error]



=== TEST 26: verbosity
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:verbosity(2)
            if not ok then
                ngx.say("failed to quit: ", err)
                return
            end

            ngx.say("successfully set verbosity to level 2")

            local ver, err = memc:version()
            if not ver then
                ngx.say("failed to get version: ", err)
                return
            end

            local ok, err = memc:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body
successfully set verbosity to level 2
--- no_error_log
[error]



=== TEST 27: multi get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local ok, err = memc:set("cat", "hello\\nworld\\n")
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local results, err = memc:get({"dog", "blah", "cat"})
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not results then
                ngx.say("results empty")
                return
            end

            ngx.say("dog: ", results.dog and table.concat(results.dog, " ") or "not found")
            ngx.say("cat: ", results.cat and table.concat(results.cat, " ") or "not found")
            ngx.say("blah: ", results.blah and table.concat(results.blah, " ") or "not found")

            local ok, err = memc:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body
dog: 32 0
cat: hello
world
 0
blah: not found
--- no_error_log
[error]



=== TEST 28: multi get (special chars in keys)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(1000) -- 1 sec

            local ok, err = memc:connect("127.0.0.1", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:set("dog A", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local ok, err = memc:set("cat B", "hello\\nworld\\n")
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local results, err = memc:get({"dog A", "blah", "cat B"})
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not results then
                ngx.say("results empty")
                return
            end

            ngx.say("dog A: ", results["dog A"] and table.concat(results["dog A"], " ") or "not found")
            ngx.say("cat B: ", results["cat B"] and table.concat(results["cat B"], " ") or "not found")
            ngx.say("blah: ", results.blah and table.concat(results.blah, " ") or "not found")

            local ok, err = memc:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body
dog A: 32 0
cat B: hello
world
 0
blah: not found
--- no_error_log
[error]



=== TEST 29: connect timeout
--- http_config eval: $::HttpConfig
--- config
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc = memcached:new()

            memc:settimeout(100) -- 100 ms

            local ok, err = memc:connect("www.taobao.com", 11211)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = memc:flush_all()
            if not ok then
                ngx.say("failed to flush all: ", err)
                return
            end

            local ok, err = memc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local res, flags, err = memc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end

            if not res then
                ngx.say("dog not found")
                return
            end

            ngx.say("dog: ", res, " (flags: ", flags, ")")
            memc:close()
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- no_error_log
[error]

