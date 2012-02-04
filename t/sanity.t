# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
};

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

