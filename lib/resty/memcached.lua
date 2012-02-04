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
    if not line then
        return nil, err
    end

    if line == 'END' then
        return nil, nil
    end

    local flags, len = match(line, [[^VALUE %S+ (%d+) (%d+)]])
    if not flags then
        return nil, "bad response: " .. line
    end

    -- print("size: ", size, ", flags: ", len)

    local data, err = sock:receive(len)
    if not data then
        return nil, nil, err
    end

    return data, flags
end


function set(self, ...)
    return _store(self, "set", ...)
end


function add(self, ...)
    return _store(self, "add", ...)
end


function replace(self, ...)
    return _store(self, "replace", ...)
end


function append(self, ...)
    return _store(self, "append", ...)
end


function prepend(self, ...)
    return _store(self, "prepend", ...)
end


function _store(self, cmd, key, value, exptime, flags)
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

    local request = table.concat({cmd, " ", escape_uri(key), " ", flags, " ",
                             exptime, " ", string.len(value), "\r\n", value,
                             "\r\n"}, "")

    local bytes, err = sock:send(request)
    if not bytes then
        return nil, err
    end

    local data, err = sock:receive()
    if not data then
        return nil, err
    end

    if data == "STORED" then
        return 1
    end

    return nil, data
end


function delete(self, key, time)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    key = escape_uri(key)

    local request
    if time then
        request = table.concat({"delete ", key, " ", time, "\r\n"}, "")
    else
        request = "delete " .. key .. "\r\n"
    end

    local bytes, err = sock:send(request)
    if not bytes then
        return nil, err
    end

    local res, err = sock:receive()
    if not res then
        return nil, err
    end

    if res ~= 'DELETED' then
        return nil, res
    end

    return 1
end


function set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end


function flush_all(self, time)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local request
    if time then
        request = "flush_all " .. time .. "\r\n"
    else
        request = "flush_all\r\n"
    end

    local bytes, err = sock:send(request)
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

    return 1
end


function _incr_decr(self, cmd, key, value)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local request = table.concat({cmd, " ", escape_uri(key), " ", value, "\r\n"}, "")

    local bytes, err = sock:send(request)
    if not bytes then
        return nil, err
    end

    local line, err = sock:receive()
    if not line then
        return nil, err
    end

    if not match(line, '^%d+$') then
        return nil, line
    end

    return line
end


function incr(self, key, value)
    return _incr_decr(self, "incr", key, value)
end


function decr(self, key, value)
    return _incr_decr(self, "decr", key, value)
end


function stats(self, args)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local request
    if args then
        request = "stats " .. args .. "\r\n"
    else
        request = "stats\r\n"
    end

    local bytes, err = sock:send(request)
    if not bytes then
        return nil, err
    end

    local lines = {}
    while true do
        local line, err = sock:receive()
        if not line then
            return nil, err
        end

        if line == 'END' then
            return lines, nil
        end

        if not match(line, "ERROR") then
            table.insert(lines, line)
        else
            return nil, line
        end
    end

    -- cannot reach here...
    return lines
end


function version(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local bytes, err = sock:send("version\r\n")
    if not bytes then
        return nil, err
    end

    local line, err = sock:receive()
    if not line then
        return nil, err
    end

    local ver = match(line, "^VERSION (.+)$")
    if not ver then
        return nil, ver
    end

    return ver
end


function quit(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local bytes, err = sock:send("quit\r\n")
    if not bytes then
        return nil, err
    end

    return 1
end


function close(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:close()
end


-- to prevent use of casual module global variables
getmetatable(resty.memcached).__newindex = function (table, key, val)
    error('attempt to write to undeclared variable "' .. key .. '": '
            .. debug.traceback())
end

