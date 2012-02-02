-- vim:set ft= ts=4 sw=4 et
-- Copyright (C) 2012 Zhang "agentzh" Yichun (章亦春)

module("resty.memcached", package.seeall)


local mt = { __index = resty.memcached }

local sub = string.sub
local escape_uri = ngx.escape_uri
local match = string.match
local tcp = ngx.socket.tcp


function new(self)
    return setmetatable({ sock = tcp() }, mt)
end


function settimeout(self, timeout)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(timeout)
end


function connect(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:connect(...)
end


function get(self, key)
    local cmd = "get " .. escape_uri(key) .. "\r\n"
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local bytes, err = sock:send(cmd)
    if not bytes then
        return nil, err
    end

    local line, err = sock:receive()
    if line == 'END' then
        return nil, nil
    end

    local flags, len = match(line, [[^VALUE %S+ (%d+) (%d+)]])
    if not flags then
        return nil, "bad response: " .. line
    end

    print("size: ", size, ", flags: ", len)

    local data, err = sock:receive(len)
    if not data then
        return nil, err
    end

    return data
end


function set(self, key, value, exptime, flags)
    if not exptime then
        exptime = 0
    end

    if not flags then
        flags = 0
    end

    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local cmd = table.concat({"set ", escape_uri(key), " ", flags, " ",
                             exptime, " ", string.len(value), "\r\n", value,
                             "\r\n"}, "")

    local bytes, err = sock:send(cmd)
    if not bytes then
        return nil, err
    end

    local data, err = sock:receive()
    if sub(data, 1, 6) == "STORED" then
        return true
    end

    return false, err
end


function set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end


function flush_all(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local bytes, err = sock:send("flush_all\r\n")
    if not bytes then
        return nil, err
    end

    local res, err = sock:receive()
    if not res then
        return nil, err
    end

    if res ~= 'OK' then
        return nil, res
    end

    return true
end


function close(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:close()
end

