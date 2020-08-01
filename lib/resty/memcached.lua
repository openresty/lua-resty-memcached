-- Copyright (C) Yichun Zhang (agentzh), CloudFlare Inc.


local escape_uri = ngx.escape_uri
local unescape_uri = ngx.unescape_uri
local match = string.match
local tcp = ngx.socket.tcp
local strlen = string.len
local concat = table.concat
local setmetatable = setmetatable
local type = type


local _M = {
    _VERSION = '0.16'
}


local mt = { __index = _M }


function _M.new(self, opts)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end

    local escape_key = escape_uri
    local unescape_key = unescape_uri

    if opts then
       local key_transform = opts.key_transform

       if key_transform then
          escape_key = key_transform[1]
          unescape_key = key_transform[2]
          if not escape_key or not unescape_key then
             return nil, "expecting key_transform = { escape, unescape } table"
          end
       end
    end

    return setmetatable({
        sock = sock,
        escape_key = escape_key,
        unescape_key = unescape_key,
    }, mt)
end


local function set_timeouts(self, connect, send, read)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    sock:settimeouts(connect, send, read)
    return 1
end
_M.set_timeouts = set_timeouts

function _M.set_timeout(self, timeout)
    return set_timeouts(self, timeout, timeout, timeout)
end


function _M.connect(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:connect(...)
end


function _M.sslhandshake(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:sslhandshake(...)
end


local function _multi_get(self, keys)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local nkeys = #keys

    if nkeys == 0 then
        return {}, nil
    end

    local escape_key = self.escape_key
    local cmd = {"get"}
    local n = 1

    for i = 1, nkeys do
        cmd[n + 1] = " "
        cmd[n + 2] = escape_key(keys[i])
        n = n + 2
    end
    cmd[n + 1] = "\r\n"

    -- print("multi get cmd: ", cmd)

    local bytes, err = sock:send(cmd)
    if not bytes then
        return nil, err
    end

    local unescape_key = self.unescape_key
    local results = {}

    while true do
        local line, err = sock:receive()
        if not line then
            if err == "timeout" then
                sock:close()
            end
            return nil, err
        end

        if line == 'END' then
            break
        end

        local key, flags, len = match(line, '^VALUE (%S+) (%d+) (%d+)$')
        -- print("key: ", key, "len: ", len, ", flags: ", flags)

        if not key then
            return nil, line
        end

        local data, err = sock:receive(len)
        if not data then
            if err == "timeout" then
                sock:close()
            end
            return nil, err
        end

        results[unescape_key(key)] = {data, flags}

        data, err = sock:receive(2) -- discard the trailing CRLF
        if not data then
            if err == "timeout" then
                sock:close()
            end
            return nil, err
        end
    end

    return results
end

local function _get_reply(sock)
    local line, err = sock:receive()
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, nil, err
    end

    if line == 'END' then
        return nil, nil, nil
    end

    local flags, len = match(line, '^VALUE %S+ (%d+) (%d+)$')
    if not flags then
        return nil, nil, line
    end

    -- print("len: ", len, ", flags: ", flags)

    local data, err = sock:receive(len)
    if not data then
        if err == "timeout" then
            sock:close()
        end
        return nil, nil, err
    end

    line, err = sock:receive(7) -- discard the trailing "\r\nEND\r\n"
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, nil, err
    end

    return data, flags
end

function _M.get(self, key)
    if type(key) == "table" then
        return _multi_get(self, key)
    end

    local sock = self.sock
    if not sock then
        return nil, nil, "not initialized"
    end

    local req = "get " .. self.escape_key(key) .. "\r\n"
    local reqs = rawget(self, "_reqs")
    if reqs then
        reqs[1][#reqs[1] + 1] = req
        reqs[2][#reqs[2] + 1] = _get_reply
        return 1
    end

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, nil, err
    end

    return _get_reply(sock)
end


local function _multi_gets(self, keys)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local nkeys = #keys

    if nkeys == 0 then
        return {}, nil
    end

    local escape_key = self.escape_key
    local cmd = {"gets"}
    local n = 1
    for i = 1, nkeys do
        cmd[n + 1] = " "
        cmd[n + 2] = escape_key(keys[i])
        n = n + 2
    end
    cmd[n + 1] = "\r\n"

    -- print("multi get cmd: ", cmd)

    local bytes, err = sock:send(cmd)
    if not bytes then
        return nil, err
    end

    local unescape_key = self.unescape_key
    local results = {}

    while true do
        local line, err = sock:receive()
        if not line then
            if err == "timeout" then
                sock:close()
            end
            return nil, err
        end

        if line == 'END' then
            break
        end

        local key, flags, len, cas_uniq =
                match(line, '^VALUE (%S+) (%d+) (%d+) (%d+)$')

        -- print("key: ", key, "len: ", len, ", flags: ", flags)

        if not key then
            return nil, line
        end

        local data, err = sock:receive(len)
        if not data then
            if err == "timeout" then
                sock:close()
            end
            return nil, err
        end

        results[unescape_key(key)] = {data, flags, cas_uniq}

        data, err = sock:receive(2) -- discard the trailing CRLF
        if not data then
            if err == "timeout" then
                sock:close()
            end
            return nil, err
        end
    end

    return results
end


function _M.gets(self, key)
    if type(key) == "table" then
        return _multi_gets(self, key)
    end

    local sock = self.sock
    if not sock then
        return nil, nil, nil, "not initialized"
    end

    local bytes, err = sock:send("gets " .. self.escape_key(key) .. "\r\n")
    if not bytes then
        return nil, nil, nil, err
    end

    local line, err = sock:receive()
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, nil, nil, err
    end

    if line == 'END' then
        return nil, nil, nil, nil
    end

    local flags, len, cas_uniq = match(line, '^VALUE %S+ (%d+) (%d+) (%d+)$')
    if not flags then
        return nil, nil, nil, line
    end

    -- print("len: ", len, ", flags: ", flags)

    local data, err = sock:receive(len)
    if not data then
        if err == "timeout" then
            sock:close()
        end
        return nil, nil, nil, err
    end

    line, err = sock:receive(7) -- discard the trailing "\r\nEND\r\n"
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, nil, nil, err
    end

    return data, flags, cas_uniq
end


local function _expand_table(value)
    local segs = {}
    local nelems = #value
    local nsegs = 0
    for i = 1, nelems do
        local seg = value[i]
        nsegs = nsegs + 1
        if type(seg) == "table" then
            segs[nsegs] = _expand_table(seg)
        else
            segs[nsegs] = seg
        end
    end
    return concat(segs)
end

local function _store_reply(sock)
    local data, err = sock:receive()
    if not data then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    if data == "STORED" then
        return 1
    end

    return nil, data
end

local function _store(self, cmd, key, value, exptime, flags)
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

    if type(value) == "table" then
        value = _expand_table(value)
    end

    local req = cmd .. " " .. self.escape_key(key) .. " " .. flags .. " "
                .. exptime .. " " .. strlen(value) .. "\r\n" .. value
                .. "\r\n"
    local reqs = rawget(self, "_reqs")
    if reqs then
        reqs[1][#reqs[1] + 1] = req
        reqs[2][#reqs[2] + 1] = _store_reply
        return 1
    end
    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return _store_reply(sock)
end


function _M.set(self, ...)
    return _store(self, "set", ...)
end


function _M.add(self, ...)
    return _store(self, "add", ...)
end


function _M.replace(self, ...)
    return _store(self, "replace", ...)
end


function _M.append(self, ...)
    return _store(self, "append", ...)
end


function _M.prepend(self, ...)
    return _store(self, "prepend", ...)
end


function _M.cas(self, key, value, cas_uniq, exptime, flags)
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

    local req = "cas " .. self.escape_key(key) .. " " .. flags .. " "
                .. exptime .. " " .. strlen(value) .. " " .. cas_uniq
                .. "\r\n" .. value .. "\r\n"

    -- local cjson = require "cjson"
    -- print("request: ", cjson.encode(req))

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    local line, err = sock:receive()
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    -- print("response: [", line, "]")

    if line == "STORED" then
        return 1
    end

    return nil, line
end

local function _delete_reply(sock)
    local res, err = sock:receive()
    if not res then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    if res ~= 'DELETED' then
        return nil, res
    end

    return 1
end

function _M.delete(self, key)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    key = self.escape_key(key)

    local req = "delete " .. key .. "\r\n"
    local reqs = rawget(self, "_reqs")
    if reqs then
        reqs[1][#reqs[1] + 1] = req
        reqs[2][#reqs[2] + 1] = _delete_reply
        return 1
    end

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return _delete_reply(sock)
end


function _M.set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end


function _M.get_reused_times(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:getreusedtimes()
end


function _M.flush_all(self, time)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local req
    if time then
        req = "flush_all " .. time .. "\r\n"
    else
        req = "flush_all\r\n"
    end

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    local res, err = sock:receive()
    if not res then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    if res ~= 'OK' then
        return nil, res
    end

    return 1
end

local function _incr_decr_reply(sock) 
    local line, err = sock:receive()
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    if not match(line, '^%d+$') then
        return nil, line
    end

    return line
end

local function _incr_decr(self, cmd, key, value)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local req = cmd .. " " .. self.escape_key(key) .. " " .. value .. "\r\n"
    local reqs = rawget(self, "_reqs")
    if reqs then
        reqs[1][#reqs[1] + 1] = req
        reqs[2][#reqs[2] + 1] = _incr_decr_reply
        return 1
    end

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return _incr_decr_reply(sock)
end


function _M.incr(self, key, value)
    return _incr_decr(self, "incr", key, value)
end


function _M.decr(self, key, value)
    return _incr_decr(self, "decr", key, value)
end


local function _stats_reply(sock)
    local lines = {}
    local n = 0
    while true do
        local line, err = sock:receive()
        if not line then
            if err == "timeout" then
                sock:close()
            end
            return nil, err
        end

        if line == 'END' then
            return lines, nil
        end

        if not match(line, "ERROR") then
            n = n + 1
            lines[n] = line
        else
            return nil, line
        end
    end

    -- cannot reach here...
    return lines
end

function _M.stats(self, args)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local req
    if args then
        req = "stats " .. args .. "\r\n"
    else
        req = "stats\r\n"
    end

    local reqs = rawget(self, "_reqs")
    if reqs then
        reqs[1][#reqs[1] + 1] = req
        reqs[2][#reqs[2] + 1] = _stats_reply
        return 1
    end

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return _stats_reply(sock)
end

local function _version_reply(sock)
    local line, err = sock:receive()
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    local ver = match(line, "^VERSION (.+)$")
    if not ver then
        return nil, ver
    end

    return ver
end

function _M.version(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local bytes, err = sock:send("version\r\n")
    if not bytes then
        return nil, err
    end

    return _version_reply(sock)
end

function _M.quit(self)
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

local function _verbosity_reply(sock)
    local line, err = sock:receive()
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    if line ~= 'OK' then
        return nil, line
    end

    return 1
end

function _M.verbosity(self, level)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local req = "verbosity " .. level .. "\r\n"
    local reqs = rawget(self, "_reqs")
    if reqs then
        reqs[1][#reqs[1] + 1] = req
        reqs[2][#reqs[2] + 1] = _verbosity_reply
        return 1
    end

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return _verbosity_reply(sock)
end

local function _touch_reply(sock)
    local line, err = sock:receive()
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end

    -- moxi server from couchbase returned stored after touching
    if line == "TOUCHED" or line =="STORED" then
        return 1
    end
    return nil, line
end

function _M.touch(self, key, exptime)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local req = "touch " .. self.escape_key(key) .. " ".. exptime .. "\r\n"
    local reqs = rawget(self, "_reqs")
    if reqs then
        reqs[1][#reqs[1] + 1] = req
        reqs[2][#reqs[2] + 1] = _touch_reply
        return 1
    end

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, err
    end

    return _touch_reply(sock)
end

function _M.close(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:close()
end


function _M.init_pipeline(self, n)
    if self._reqs then 
        return "already init pipeline"
    end

    if n and type(n) ~= 'number' then
        return "buffer size is number type"
    end
    self._reqs = {
        table.new(n or 4, 0),
        table.new(n or 4, 0),
    }
    return nil
end


function _M.cancel_pipeline(self)
    self._reqs = nil
end


function _M.commit_pipeline(self)
    local reqs = rawget(self, "_reqs")
    if not reqs then
        return nil, "no pipeline"
    end
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    if #self._reqs[1] == 0 then
        return nil, "no more cmds"
    end
    local bytes, err = sock:send(table.concat(reqs[1]))
    if not bytes then
        return nil, err
    end

    local results = {}
    for i=1,#reqs[2] do
        results[i] = { reqs[2][i](sock) }
    end
    self._reqs = nil
    return results, nil
end

return _M
