Description
===========

This Lua library is a memcached client driver for the ngx_lua nginx module:

http://wiki.nginx.org/HttpLuaNginxModule

This Lua library takes advantage of ngx_lua's cosocket API, which ensures
100% nonblocking behavior.

Note that at least ngx_lua 0.5.0rc1 or ngx_openresty 1.0.11.1 is required.

Synopsis
========

    lua_package_path "/path/to/lua-resty-memcached/lib/?.lua;;"

    server {
        location /t {
            content_by_lua '
                local memcached = require "resty.memcached"
                local memc = memcached:new()

                memc:settimeout(1000) -- 1 sec

                -- or connect to a unix domain socket file listened
                -- by a memcached server:
                --     local ok, err = memc:connect("unix:/path/to/memc.sock")

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

                -- or just close the connection right away:
                -- local ok, err = memc:close()
                -- if not ok then
                --     ngx.say("failed to close: ", err)
                --     return
                -- end
            ';
        }
    }

Methods
=======

The `key` argument provided in the following methods will be automatically escaped according to the URI escaping rules before sending to the memcached server.

new
---
`syntax: memc = memcached:new()`

Creates a memcached object. Returns `nil` on error.

connect
-------
`syntax: ok, err = memc:connect(host, port)`
`syntax: ok, err = memc:connect("unix:/path/to/unix.sock")`

Connects to the remote host and port that the memcached server is listening to or a local unix domain socket file listened by the memcached server.

set
---
`syntax: ok, err = memc:set(key, value, exptime, flags)`

Inserts an entry into memcached unconditionally. If the key already exists, overrides it.

The `exptime` parameter is optional, defaults to `0`.

The `flags` parameter is optional, defaults to `0`.

settimeout
----------
`syntax: memc:settimeout(time)`

Sets the timeout protection for subsequent operations, including the `connect` method.

setkeepalive
------------
`syntax: memc:setkeepalive(max_idle_timeout, pool_size)`

Keeps the current memcached connection alive and put it into the ngx_lua cosocket connection pool.

You can specify the max idle timeout when the connection is in the pool and the maximal size of the pool every nginx worker process.

close
-----
`syntax: ok, err = memc:close()`

Closes the current memcached connection and returns the status.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.


add
---
`syntax: ok, err = memc:add(key, value, exptime, flags)`

Inserts an entry into memcached if and only if the key does not exist.

The `exptime` parameter is optional, defaults to `0`.

The `flags` parameter is optional, defaults to `0`.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.

replace
-------
`syntax: ok, err = memc:replace(key, value, exptime, flags)`

Inserts an entry into memcached if and only if the key does exist.

The `exptime` parameter is optional, defaults to `0`.

The `flags` parameter is optional, defaults to `0`.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.

append
------
`syntax: ok, err = memc:append(key, value, exptime, flags)`

Appends the value to an entry with the same key that already exists in memcached.

The `exptime` parameter is optional, defaults to `0`.

The `flags` parameter is optional, defaults to `0`.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.

prepend
-------
`syntax: ok, err = memc:prepend(key, value, exptime, flags)`

Prepends the value to an entry with the same key that already exists in memcached.

The `exptime` parameter is optional, defaults to `0`.

The `flags` parameter is optional, defaults to `0`.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.

get
---
`syntax: value, flags, err = memc:get(key)`

Get a single entry in the memcached server via a key.

If the entry is found and no error happens, value and flags will be returned accordingly.

In case of errors or entry absence, `nil` values will be turned for `value` and `flags` and a 3rd (string) value will also be returned for describing the error.

