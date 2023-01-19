-- Copyright (C) Yichun Zhang (agentzh), CloudFlare Inc.


local escape_uri = ngx.escape_uri
local unescape_uri = ngx.unescape_uri
local match = string.match
local tcp = ngx.socket.tcp
local strlen = string.len
local concat = table.concat
local tab_insert = table.insert
local setmetatable = setmetatable
local type = type
local tab_clear = require "table.clear"

local cmd_tab = {}

local _M = {
    _VERSION = '0.17'
}


local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok or type(new_tab) ~= "function" then
    new_tab = function (narr, nrec) return {} end
end

local function _read_reply(sock, len)
    local line, err
    if len == nil then
        line, err = sock:receive()
    else
        line, err = sock:receive(len)
    end
    if not line then
        if err == "timeout" then
            sock:close()
        end
        return nil, err
    end
    return line, nil
end

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

    local memc = setmetatable({
        sock = sock,
        escape_key = escape_key,
        unescape_key = unescape_key,
    }, mt)

    return memc
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
    tab_clear(cmd_tab)
    tab_insert(cmd_tab, "get")

    for i = 1, nkeys do
        tab_insert(cmd_tab, " ")
        tab_insert(cmd_tab, escape_key(keys[i]))
    end
    tab_insert(cmd_tab, "\r\n")

    -- print("multi get cmd: ", cmd_tab)

    local bytes, err = sock:send(cmd_tab)
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
    local line, err = _read_reply(sock)
    if err then
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
    local data, err = _read_reply(sock, len)
    if err then
        return nil, nil, err
    end

    local _, err = _read_reply(sock, 7) -- discard the trailing "\r\nEND\r\n"
    if err then
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

    local reqs = rawget(self, "_reqs")
    if reqs then
        local readers = rawget(self, "_readers")
        tab_insert(reqs, "get ")
        tab_insert(reqs, self.escape_key(key))
        tab_insert(reqs, "\r\n")
        tab_insert(readers, _get_reply)
        return 1
    end

    tab_clear(cmd_tab)
    tab_insert(cmd_tab, "get ")
    tab_insert(cmd_tab, self.escape_key(key))
    tab_insert(cmd_tab, "\r\n")
    local bytes, err = sock:send(cmd_tab)
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
    tab_clear(cmd_tab)
    tab_insert(cmd_tab, "gets")
    for i = 1, nkeys do
        tab_insert(cmd_tab, " ")
        tab_insert(cmd_tab, escape_key(keys[i]))
    end
    tab_insert(cmd_tab, "\r\n")

    -- print("multi get cmd: ", cmd_tab)

    local bytes, err = sock:send(cmd_tab)
    if not bytes then
        return nil, err
    end

    local unescape_key = self.unescape_key
    local results = {}

    while true do
        local line, err = _read_reply(sock)
        if err then
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

        local data, err = _read_reply(sock, len)
        if err then
            return nil, err
        end

        results[unescape_key(key)] = {data, flags, cas_uniq}
        data, err = _read_reply(sock, 2) -- discard the trailing CRLF
        if err then
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

    tab_clear(cmd_tab)
    tab_insert(cmd_tab, "gets ")
    tab_insert(cmd_tab, self.escape_key(key))
    tab_insert(cmd_tab, "\r\n")
    local bytes, err = sock:send(cmd_tab)
    if not bytes then
        return nil, nil, nil, err
    end

    local line, err = _read_reply(sock)
    if err then
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

    local data, err = _read_reply(sock, len)
    if not data then
        return nil, nil, nil, err
    end

    line, err = _read_reply(sock, 7) -- discard the trailing "\r\nEND\r\n"
    if not line then
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
    local data, err = _read_reply(sock)
    if err then
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

    local reqs = rawget(self, "_reqs")
    if reqs then
        local readers = rawget(self, "_readers")
        tab_insert(reqs, cmd)
        tab_insert(reqs, " ")
        tab_insert(reqs, self.escape_key(key))
        tab_insert(reqs, " ")
        tab_insert(reqs, flags)
        tab_insert(reqs, " ")
        tab_insert(reqs, exptime)
        tab_insert(reqs, " ")
        tab_insert(reqs, strlen(value))
        tab_insert(reqs, "\r\n")
        tab_insert(reqs, value)
        tab_insert(reqs, "\r\n")

        tab_insert(readers, _store_reply)
        return 1
    end

    tab_clear(cmd_tab)
    tab_insert(cmd_tab, cmd)
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, self.escape_key(key))
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, flags)
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, exptime)
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, strlen(value))
    tab_insert(cmd_tab, "\r\n")
    tab_insert(cmd_tab, value)
    tab_insert(cmd_tab, "\r\n")

    local bytes, err = sock:send(cmd_tab)
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

    tab_clear(cmd_tab)
    tab_insert(cmd_tab, "cas ")
    tab_insert(cmd_tab, self.escape_key(key))
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, flags)
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, exptime)
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, strlen(value))
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, cas_uniq)
    tab_insert(cmd_tab, "\r\n")
    tab_insert(cmd_tab, value)
    tab_insert(cmd_tab, "\r\n")

    -- local cjson = require "cjson"
    -- print("request: ", cjson.encode(cmd_tab))

    local bytes, err = sock:send(cmd_tab)
    if not bytes then
        return nil, err
    end

    local line, err = _read_reply(sock)
    if err then
        return nil, err
    end

    -- print("response: [", line, "]")

    if line == "STORED" then
        return 1
    end

    return nil, line
end

local function _delete_reply(sock)
    local res, err = _read_reply(sock)
    if err then
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

    local reqs = rawget(self, "_reqs")
    if reqs then
        local readers = rawget(self, "_readers")
        tab_insert(reqs, "delete ")
        tab_insert(reqs, key)
        tab_insert(reqs, "\r\n")
        tab_insert(readers, _delete_reply)
        return 1
    end

    tab_clear(cmd_tab)
    tab_insert(cmd_tab, "delete ")
    tab_insert(cmd_tab, key)
    tab_insert(cmd_tab, "\r\n")
    local bytes, err = sock:send(cmd_tab)
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

    tab_clear(cmd_tab)
    if time then
        tab_insert(cmd_tab, "flush_all ")
        tab_insert(cmd_tab, time)
        tab_insert(cmd_tab, "\r\n")
    else
        tab_clear(cmd_tab)
        tab_insert(cmd_tab, "flush_all\r\n")
    end

    local bytes, err = sock:send(cmd_tab)
    if not bytes then
        return nil, err
    end

    local res, err = _read_reply(sock)
    if err then
        return nil, err
    end

    if res ~= 'OK' then
        return nil, res
    end

    return 1
end

local function _incr_decr_reply(sock)
    local line, err = _read_reply(sock)
    if err then
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

    local reqs = rawget(self, "_reqs")
    local readers = rawget(self, "_readers")
    if reqs then
        tab_insert(reqs, cmd)
        tab_insert(reqs, " ")
        tab_insert(reqs, self.escape_key(key))
        tab_insert(reqs, " ")
        tab_insert(reqs, value)
        tab_insert(reqs, "\r\n")
        tab_insert(readers, _incr_decr_reply)
        return 1
    end

    tab_clear(cmd_tab)
    tab_insert(cmd_tab, cmd)
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, self.escape_key(key))
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, value)
    tab_insert(cmd_tab, "\r\n")

    local bytes, err = sock:send(cmd_tab)
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
        local line, err = _read_reply(sock)
        if err then
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

    local reqs = rawget(self, "_reqs")
    local readers = rawget(self, "_readers")
    if reqs then
        if args then
            tab_insert(reqs, "stats ")
            tab_insert(reqs, args)
            tab_insert(reqs, "\r\n")
        else
            tab_insert(reqs, "stats\r\n")
        end
        tab_insert(readers, _stats_reply)
        return 1
    end

    local bytes, err
    if args then
        tab_clear(cmd_tab)
        tab_insert(cmd_tab, "stats ")
        tab_insert(cmd_tab, args)
        tab_insert(cmd_tab, "\r\n")
        bytes, err = sock:send(cmd_tab)
    else
        bytes, err = sock:send("stats\r\n")
    end
    if not bytes then
        return nil, err
    end

    return _stats_reply(sock)
end

local function _version_reply(sock)
    local line, err = _read_reply(sock)
    if err then
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
    local line, err = _read_reply(sock)
    if err then
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

    local reqs = rawget(self, "_reqs")
    if reqs then
        local readers = rawget(self, "_readers")
        tab_insert(reqs, "verbosity ")
        tab_insert(reqs, level)
        tab_insert(reqs, "\r\n")
        tab_insert(readers, _verbosity_reply)
        return 1
    end

    tab_clear(cmd_tab)
    tab_insert(cmd_tab, "verbosity ")
    tab_insert(cmd_tab, level)
    tab_insert(cmd_tab, "\r\n")
    local bytes, err = sock:send(cmd_tab)
    if not bytes then
        return nil, err
    end

    return _verbosity_reply(sock)
end

local function _touch_reply(sock)
    local line, err = _read_reply(sock)
    if err then
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

    local reqs = rawget(self, "_reqs")
    local readers = rawget(self, "_readers")
    if reqs then
        tab_insert(reqs, "touch ")
        tab_insert(reqs, self.escape_key(key))
        tab_insert(reqs, " ")
        tab_insert(reqs, exptime)
        tab_insert(reqs, "\r\n")
        tab_insert(readers, _touch_reply)
        return 1
    end

    tab_clear(cmd_tab)
    tab_insert(cmd_tab, "touch ")
    tab_insert(cmd_tab, self.escape_key(key))
    tab_insert(cmd_tab, " ")
    tab_insert(cmd_tab, exptime)
    tab_insert(cmd_tab, "\r\n")
    local bytes, err = sock:send(cmd_tab)
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
        return "bad n arg: number expected, but got " .. type(n)
    end
    self._reqs = new_tab(n or 20, 0)
    self._readers = new_tab(n or 4, 0)
    return nil
end


function _M.cancel_pipeline(self)
    self._reqs = nil
    self._readers = nil
end


function _M.commit_pipeline(self)
    local reqs = rawget(self, "_reqs")
    local readers = rawget(self, "_readers")
    self._reqs = nil
    self._readers = nil
    if not reqs or not readers then
        return nil, "no pipeline"
    end
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    if #readers == 0 then
        return nil, "no more cmds"
    end
    local bytes, err = sock:send(reqs)
    if not bytes then
        return nil, err
    end

    local results = {}
    for i, reader in ipairs(readers) do
        results[i] = { reader(sock) }
    end

    return results, nil
end

return _M
