# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks() + 6);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_package_cpath "$pwd/lib/?.so;;";
    lua_shared_dict hashmemcached 1m;
};

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_MEMCACHED_BACKUP_PORT} ||= 11212;

no_long_string();

run_tests();

__DATA__

=== TEST 1: basic (set, get, flush_all)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"
            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT, 2},
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_BACKUP_PORT, 1}
            }, 'hashmemcached')

            -- always flush_all at first
            local result = hmemc:flush_all()
            local serv, res, ok, err
            for serv, res in pairs(result) do
                ok, err = unpack(res)
                if not ok then
                    ngx.say("failed to flush ", serv, ", ", err)
                    return
                end
            end

            ngx.say("set")

            keys = {'dog', 'puppy', 'cat', 'kitten'}
            values = {32, "I am a little dog", 64, "I am a \nlittle cat\n"}
            local i, key
            for i, key in ipairs(keys) do
                local ok, err = hmemc:set(key, values[i])
                if not ok then
                    ngx.say("failed to set ", key, ": ", err)
                else
                    ngx.say(key, " is stored in ", hmemc:which_server())
                end
            end
            
            ngx.say("\nget")

            for i, key in ipairs(keys) do
                local res, flags, err = hmemc:get(key)
                if err then
                    ngx.say("failed to get ", key, ": ", err)
                elseif not res then
                    ngx.say(key, " not found")
                else
                    ngx.say(key, ": ", res, " (flags: ", flags, ")")
                end
            end

            local result = hmemc:flush_all()
            local serv, res, ok, err
            for serv, res in pairs(result) do
                ok, err = unpack(res)
                if not ok then
                    ngx.say("failed to flush ", serv, ", ", err)
                    return
                end
            end

            ngx.say("\nget after flush")

            -- get (404)
            for i, key in ipairs(keys) do
                local res, flags, err = hmemc:get(key)
                if err then
                    ngx.say("failed to get ", key, ": ", err)
                elseif not res then
                    ngx.say(key, " not found")
                else
                    ngx.say(key, ": ", res, " (flags: ", flags, ")")
                end
            end

            hmemc:close()
        }
    }
--- request
GET /t
--- response_body
set
dog is stored in 127.0.0.1:11211
puppy is stored in 127.0.0.1:11212
cat is stored in 127.0.0.1:11212
kitten is stored in 127.0.0.1:11211

get
dog: 32 (flags: 0)
puppy: I am a little dog (flags: 0)
cat: 64 (flags: 0)
kitten: I am a 
little cat
 (flags: 0)

get after flush
dog not found
puppy not found
cat not found
kitten not found
--- no_error_log
[error]


=== TEST 2: multi get, gets
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"
            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT, 2},
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_BACKUP_PORT, 1}
            }, 'hashmemcached')

            local result = hmemc:flush_all()
            local serv, res, ok, err
            for serv, res in pairs(result) do
                ok, err = unpack(res)
                if not ok then
                    ngx.say("failed to flush ", serv, ", ", err)
                    return
                end
            end
            
            keys = {'dog', 'puppy', 'cat', 'kitten'}
            values = {32, "I am a little dog", 64, "I am a \nlittle cat\n"}
            local i, key
            for i, key in ipairs(keys) do
                local ok, err = hmemc:set(key, values[i])
                if not ok then
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            ngx.say("get")

            keys[#keys+1] = 'blah'
            local results = hmemc:get(keys)
            for i, key in ipairs(keys) do
                ngx.print(key, ": ")
                if results[key] then
                    ngx.say(table.concat(results[key], ", "))
                else
                    ngx.say("not found")
                end
            end

            ngx.say("\ngets")

            local results = hmemc:gets(keys)
            for i, key in ipairs(keys) do
                ngx.print(key, ": ")
                if results[key] then
                    ngx.say(table.concat(results[key], ", "))
                else
                    ngx.say("not found")
                end
            end

            hmemc:close()
        }
    }
--- request
GET /t
--- response_body_like chop
^get
dog: 32, 0
puppy: I am a little dog, 0
cat: 64, 0
kitten: I am a 
little cat
, 0
blah: not found

gets
dog: 32, 0, \d+
puppy: I am a little dog, 0, \d+
cat: 64, 0, \d+
kitten: I am a 
little cat
, 0, \d+
blah: not found$
--- no_error_log
[error]


=== TEST 3: add, set, incr, decr, replace, append, prepend, delete
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"
            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT, 2},
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_BACKUP_PORT, 1}
            }, 'hashmemcached')

            local result = hmemc:flush_all()
            local serv, res, ok, err
            for serv, res in pairs(result) do
                ok, err = unpack(res)
                if not ok then
                    ngx.say("failed to flush ", serv, ", ", err)
                    return
                end
            end
            -- add
            local ok, err = hmemc:add("dog", 32)
            if not ok then
                ngx.say("failed to add dog: ", err)
            end

            local res, flags, err = hmemc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end
            if not res then
                ngx.say("dog not found")
                return
            end
            ngx.say("dog: ", res)

            -- set
            local ok, err = hmemc:set("dog", 33)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            local res, flags, err = hmemc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end
            if not res then
                ngx.say("dog not found")
                return
            end
            ngx.say("dog: ", res)

            -- incr
            local value, err = hmemc:incr("dog", 2)
            if not value then
                ngx.say("failed to incr dog: ", err)
                return
            end

            ngx.say("dog: ", value)

            --decr
            local value, err = hmemc:decr("dog", 3)
            if not value then
                ngx.say("failed to decr dog: ", err)
                return
            end

            ngx.say("dog: ", value)
            -- replace
            local ok, err = hmemc:replace("dog", 56)
            if not ok then
                ngx.say("failed to replace dog: ", err)
                return
            end

            local res, flags, err = hmemc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end
            if not res then
                ngx.say("dog not found")
                return
            end
            ngx.say("dog: ", res)

            -- append
            local ok, err = hmemc:append("dog", 78)
            if not ok then
                ngx.say("failed to append to dog: ", err)
            end

            local res, flags, err = hmemc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end
            if not res then
                ngx.say("dog not found")
                return
            end
            ngx.say("dog: ", res)

            -- prepend
            local ok, err = hmemc:prepend("dog", 34)
            if not ok then
                ngx.say("failed to prepend to dog: ", err)
            end

            local res, flags, err = hmemc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end
            if not res then
                ngx.say("dog not found")
                return
            end
            ngx.say("dog: ", res)

            -- delete            
            local ok, err = hmemc:delete("dog")
            if not ok then
                ngx.say("failed to delete dog: ", err)
            end

            local res, flags, err = hmemc:get("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end
            if not res then
                ngx.say("dog not found")
                return
            end
            ngx.say("dog: ", res)

            hmemc:close()
        }
    }
--- request
GET /t
--- response_body
dog: 32
dog: 33
dog: 35
dog: 32
dog: 56
dog: 5678
dog: 345678
dog not found
--- no_error_log
[error]


=== TEST 4: incr, decr, replace, append, prepend, delete on a nonexistent key
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"
            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT, 2},
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_BACKUP_PORT, 1}
            }, 'hashmemcached')

            local result = hmemc:flush_all()
            local serv, res, ok, err
            for serv, res in pairs(result) do
                ok, err = unpack(res)
                if not ok then
                    ngx.say("failed to flush all: ", err)
                    return
                end
            end

            -- incr
            local value, err = hmemc:incr("dog", 2)
            if not value then
                ngx.say("failed to incr dog: ", err)
            end

            --decr
            local value, err = hmemc:decr("dog", 3)
            if not value then
                ngx.say("failed to decr dog: ", err)
            end

            -- replace
            local ok, err = hmemc:replace("dog", 56)
            if not ok then
                ngx.say("failed to replace dog: ", err)
            end

            -- append
            local ok, err = hmemc:append("dog", 78)
            if not ok then
                ngx.say("failed to append to dog: ", err)
            end

            -- prepend
            local ok, err = hmemc:prepend("dog", 34)
            if not ok then
                ngx.say("failed to prepend to dog: ", err)
            end

            -- delete            
            local ok, err = hmemc:delete("dog")
            if not ok then
                ngx.say("failed to delete dog: ", err)
            end

            hmemc:close()
        }
    }
--- request
GET /t
--- response_body
failed to incr dog: NOT_FOUND
failed to decr dog: NOT_FOUND
failed to replace dog: NOT_STORED
failed to append to dog: NOT_STORED
failed to prepend to dog: NOT_STORED
failed to delete dog: NOT_FOUND
--- no_error_log
[error]


=== TEST 5: set, gets, cas, cas
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"
            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT, 2},
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_BACKUP_PORT, 1}
            }, 'hashmemcached')

            local result = hmemc:flush_all()
            local serv, res, ok, err
            for serv, res in pairs(result) do
                ok, err = unpack(res)
                if not ok then
                    ngx.say("failed to flush ", serv, ", ", err)
                    return
                end
            end

            -- set
            local ok, err = hmemc:set("dog", 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end

            -- gets
            local res, flags, cas_uniq, err = hmemc:gets("dog")
            if err then
                ngx.say("failed to get dog: ", err)
                return
            end
            if not res then
                ngx.say("dog not found")
                return
            end
            ngx.say("dog: ", res, " (flags: ", flags, ", cas_uniq: ", cas_uniq, ")")

            -- cas
            local ok, err = hmemc:cas("dog", "hello world", cas_uniq, 0, 78)
            if not ok then
                ngx.say("failed to cas: ", err)
                return
            end
            ngx.say("cas succeeded")

            -- cas again
            local ok, err = hmemc:cas("dog", 56, cas_uniq, 0, 56)
            if not ok then
                ngx.say("failed to cas: ", err)
                return
            end
            ngx.say("second cas succeeded")

            hmemc:close()
        }
    }
--- request
GET /t
--- response_body_like chop
^dog: 32 \(flags: 0, cas_uniq: \d+\)
cas succeeded
failed to cas: EXISTS$
--- no_error_log
[error]



=== TEST 6: one of the servers is down
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"

            ngx.shared['hashmemcached']:flush_all()

            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT},
                {'127.0.0.1', 1921}
            }, 'hashmemcached')

            local result = hmemc:flush_all()
            local serv, res, ok, err
            for serv, res in pairs(result) do
                ok, err = unpack(res)
                if not ok then
                    ngx.say("failed to flush ", serv, ", ", err)
                end
            end

            -- bird is hashed to 127.0.0.1:1921
            -- set
            local ok, err = hmemc:set("bird", 32)
            if not ok then
                ngx.say("failed to set bird: ", err)
            end

            -- set again
            local ok, err = hmemc:set("bird", 33)
            if not ok then
                ngx.say("failed to set bird: ", err)
            end

            -- set finally successfully
            local ok, err = hmemc:set("bird", 34)
            if not ok then
                ngx.say("failed to set bird: ", err)
                return
            end

            -- get
            local res, flags, err = hmemc:get("bird")
            if err then
                ngx.say("failed to get bird: ", err)
                return
            end
            if not res then
                ngx.say("bird not found")
                return
            end
            ngx.say("bird: ", res)

            hmemc:close()
        }
    }
--- request
GET /t
--- response_body
failed to flush 127.0.0.1:1921, connection refused
failed to set bird: connection refused
failed to set bird: connection refused
bird: 34
--- error_log
127.0.0.1:1921 failed the first time
127.0.0.1:1921 failed 2 times
127.0.0.1:1921 is turned down after 3 failure(s)


=== TEST 7: one of the servers is marked down previously 
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"

            ngx.shared['hashmemcached']:flush_all()

            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT},
                {'127.0.0.1', 1921}
            }, 'hashmemcached')

            local result = hmemc:flush_all()
            local serv, res, ok, err
            for serv, res in pairs(result) do
                ok, err = unpack(res)
                if not ok then
                    ngx.say("failed to flush ", serv, ", ", err)
                end
            end

            -- set 3 times
            for i = 1, 3 do
                local ok, err = hmemc:set("bird", i)
                if not ok then
                    ngx.say("failed to set bird ", i, " time(s): ", err)
                end
            end

            hmemc:close()

            -- 127.0.0.1:1921 is turned down now

            -- a new client
            local hmemc2, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT},
                {'127.0.0.1', 1921}
            }, "hashmemcached")

            -- get
            local res, flags, err = hmemc2:get("bird")
            if err then
                ngx.say("failed to get bird: ", err)
                return
            end
            if not res then
                ngx.say("bird not found")
                return
            end
            ngx.say("bird: ", res)

            hmemc2:close()
        }
    }
--- request
GET /t
--- response_body
failed to flush 127.0.0.1:1921, connection refused
failed to set bird 1 time(s): connection refused
failed to set bird 2 time(s): connection refused
bird: 3
--- error_log
127.0.0.1:1921 is turned down after 3 failure(s)



=== TEST 8: fail_timeout, max_fails
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"

            ngx.shared['hashmemcached']:flush_all()

            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT},
                {'127.0.0.1', 1921}
            }, 'hashmemcached', {fail_timeout=0.5, max_fails=1})
            
            hmemc:flush_all()

            -- 127.0.0.1:1921 is marked down because max_fails=1

            hmemc:close()

            ngx.sleep(0.6)
            -- 127.0.0.1:1921 is removed from blacklist now

            -- must use a new client here
            local hmemc2, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT},
                {'127.0.0.1', 1921}
            }, "hashmemcached", {fail_timeout=0.5, max_fails=4})

            local res, flags, err = hmemc2:get("bird")
            if err then
                ngx.say("failed to get bird: ", err)
            elseif not res then
                ngx.say("bird not found")
            else
                ngx.say("bird: ", res, " (flags: ", flags, ")")
            end

            ngx.say('sleep...')
            ngx.sleep(0.7)
            -- 127.0.0.1:1921's bad record is evicted now

            for i = 1,5 do
                local res, flags, err = hmemc2:get("bird")
                if err then
                    ngx.say("failed to get ", "bird: ", err)
                elseif not res then
                    ngx.say("bird not found")
                else
                    ngx.say("bird: ", res, " (flags: ", flags, ")")
                end
            end

            hmemc2:close()
        }
    }
--- request
GET /t
--- response_body
failed to get bird: connection refused
sleep...
failed to get bird: connection refused
failed to get bird: connection refused
failed to get bird: connection refused
failed to get bird: connection refused
bird not found
--- error_log
127.0.0.1:1921 is turned down after 1 failure(s)
127.0.0.1:1921 is turned down after 4 failure(s)


=== TEST 9: mock memcached emulating read timeout
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"

            ngx.shared['hashmemcached']:flush_all()

            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT}
            })

            hmemc:flush_all()

            hmemc:close()

            local hmemc2, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT},
                {'127.0.0.1', 1921}
            }, nil, {max_fails=1})

            hmemc2:set_timeout(100) -- 0.1 sec

            -- get twice
            for i = 1, 2 do
                local data, flags, err = hmemc2:get("bird")
                if err then
                    ngx.say("failed to get bird: ", err)
                elseif not data then
                    ngx.say("bird not found")
                else
                    ngx.say("bird: ", data, " (flags: ", flags, ")")
                end
            end

            hmemc2:close()
        }
    }
--- request
GET /t
--- tcp_listen: 1921
--- tcp_query_len: 10
--- tcp_query eval
"get bird\r\n"
--- tcp_reply eval
"VALUE bird 0 11\r\nI am a bird\r\nEND\r\n"
--- tcp_reply_delay: 150ms
--- response_body
failed to get bird: timeout
bird not found
--- error_log
127.0.0.1:1921 is turned down after 1 failure(s)


=== TEST 10: mock memcached emulating remote closed
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"

            ngx.shared['hashmemcached']:flush_all()

            local hmemc, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT}
            })

            hmemc:flush_all()

            local ok, err = hmemc:set('bird', 'a good bird')
            if not ok then
                ngx.say("failed to set bird: ", err)
                return
            end

            hmemc:close()


            local hmemc2, err = hashmemcached.new({
                {'127.0.0.1', $TEST_NGINX_MEMCACHED_PORT},
                {'127.0.0.1', 1921}
            }, nil, {max_fails=1})

            -- get twice
            for i = 1, 2 do
                local data, flags, err = hmemc2:get("bird")
                if err then
                    ngx.say("failed to get bird: ", err)
                elseif not data then
                    ngx.say("bird not found")
                else
                    ngx.say("bird: ", data, " (flags: ", flags, ")")
                end
            end

            hmemc2:close()
        }
    }
--- request
GET /t
--- tcp_listen: 1921
--- tcp_query_len: 10
--- tcp_query eval
"get bird\r\n"
--- tcp_shutdown: 1
--- response_body
failed to get bird: closed
bird: a good bird (flags: 0)
--- error_log
127.0.0.1:1921 is turned down after 1 failure(s)


=== TEST 11: no available memcaced server in the cluster
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hashmemcached = require "resty.hashmemcached"
            local hmemc, err = hashmemcached.new({}, 'hashmemcached')

            -- always flush_all at first
            local result = hmemc:flush_all()
            local serv, res, ok, err
            for serv, res in pairs(result) do
                ok, err = unpack(res)
                if not ok then
                    ngx.say("failed to flush ", serv, ", ", err)
                    return
                end
            end

            local ok, err = hmemc:set('dog', 32)
            if not ok then
                ngx.say("failed to set dog: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
failed to set dog: no available memcached server
