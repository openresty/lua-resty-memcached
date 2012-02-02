Description
===========

This Lua library is a memcached client driver for the ngx_lua nginx module:

http://wiki.nginx.org/HttpLuaNginxModule

This Lua library takes advantage of ngx_lua's cosocket API, which ensures
100% nonblocking behavior.

Note that at least ngx_lua 0.5.0rc1 is required.

Synopsis
========

    lua_package_path "/path/to/lua-resty-memcached/lib/?.lua;;"

    server {
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

                local res, err = memc:get("dog")
                if err then
                    ngx.say("failed to get dog: ", err)
                    return
                end

                if not res then
                    ngx.say("dog not found")
                    return
                end

                ngx.say("dog: ", res)

                -- put it into the connection pool of size 100,
                -- with 0 idle timeout
                memc:setkeepalive(0, 100)
            ';
        }
    }

