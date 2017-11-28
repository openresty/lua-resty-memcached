-- Dependency
local memcached = require "resty.memcached"
local resty_chash = require "resty.chash"

local _M = {
    _VERSION = '0.01'
}

-- Global private methods
local function Set (list)
  local set = {}
  for _, l in ipairs(list) do set[l] = true end
  return set
end

-- Global private variables:
local log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO

local key_methods = Set{
    'get', 'gets',
    'set', 'add', 'replace', 'append', 'prepend',
    'cas',
    'delete',
    'incr', 'decr',
    'touch'
}

-- Class implemented by closure
function _M.new(cluster, shm, opts)
    local self = {}

    -- Private variables:
    local client, err = memcached:new(opts)
    if not client then
        return client, err
    end

    local max_fails = 3
    local fail_timeout = 10
    if opts then
        if opts.max_fails then
            max_fails = opts.max_fails
        end
        if opts.fail_timeout then
            fail_timeout = opts.fail_timeout
        end
    end

    local dict = ngx.shared[shm or 'hashmemcached']
    local serv_id -- current node (string in format 'ip:port')
    local chash_up
    local servers = {}

    -- Private methods:
    local function init_chash()
        local nodes = {}
        for i, node in ipairs(cluster) do
            local ip, port, weight = unpack(node)
            local id = ip..':'..port
            servers[id] = {ip, port}
            nodes[id] = weight or 1
        end
        local keys = dict:get_keys()
        for i, k in ipairs(keys) do
            local v = dict:get(k)
            -- 0 means this node is down
            if v == 0 then
                nodes[k] = nil
            end
        end
        chash_up = resty_chash:new(nodes)
    end

    local function down()
        -- if a node fails max_fails times in fail_timeout seconds
        -- then this node is considered unavailable in the duration of fail_timeout
        local fails = dict:get(serv_id)
        if fails then
            if fails > 0 then
                fails = fails + 1
                -- two requests may increase the same value
                fails = dict:incr(serv_id, 1)
                log(INFO, "hashmemcached: ", serv_id, " failed ", fails, " times")
            else
                -- in case this node is already marked down by another client
                chash_up:delete(serv_id)
            end
        else
            fails = 1
            log(INFO, "hashmemcached: ", serv_id, " failed the first time")
            dict:set(serv_id, 1, fail_timeout)
        end
        if fails >= max_fails then
            dict:set(serv_id, 0, fail_timeout)
            log(ERR, "hashmemcached: ", serv_id, " is turned down after ", fails, " failure(s)")
            chash_up:delete(serv_id)
        end
        serv_id = nil
    end

    local function connect(id)
        -- is connected already
        if serv_id then
            if serv_id == id then return 1 end
            -- ignore error
            client:set_keepalive()
        end
        serv_id = id
        server = servers[id]
        local ok, err = client:connect(unpack(server))
        if not ok then
            down()
        end
        return ok, err
    end

    local function call(method)
        return function(self, key, ...)
            if type(key) == "table" then
                -- get or gets multi keys
                local servs = {}
                -- use empty table as default value
                setmetatable(servs, { __index = function(t, k) t[k]={};return t[k] end })
                for i, k in pairs(key) do
                    local id = chash_up:find(k)
                    if not id then
                        assert(next(servs)==nil) -- servs must be empty
                        return nil, 'no available memcached server'
                    end
                    table.insert(servs[id], k)
                end

                local results = {}
                for id, keys in pairs(servs) do
                    local ok, err = connect(id)
                    if ok then
                        local data, err = client[method](client, keys, ...)
                        if data then
                            -- data is a table
                            for k, v in pairs(data) do
                                -- v is a table too
                                -- merge result
                                results[k] = v
                            end
                        else
                            for i, k in ipairs(keys) do
                                results[k] = {nil, err}
                            end
                            if client.failed then
                                down()
                            end
                        end
                    else
                        for i, k in ipairs(keys) do
                            results[k] = {nil, err}
                        end
                    end
                end
                return results
            else
                -- single key
                local id = chash_up:find(key)
                local res1, res2, res3, res4
                local ok, err
                if id then
                    ok, err = connect(id)
                    if ok then
                        -- at most 4 return values
                        res1, res2, res3, res4 = client[method](client, key, ...)
                        if client.failed then
                            down()
                        end
                    end
                else
                    err = 'no available memcached server'
                end
                if method == 'get' then
                    return res1, res2, err or res3
                elseif method == 'gets' then
                    return res1, res2, res3, err or res4
                else
                    return res1, err or res2
                end
            end
        end
    end


    -- Public methods:
    function self.which_server()
        return serv_id
    end

    -- override flush_all
    function self.flush_all(self, time)
        local ok, err
        local results = {}
        for id, serv in pairs(servers) do
            ok, err = connect(id)
            if ok then
                results[id] = {client:flush_all(time)}
            else
                results[id] = {nil, err}
            end
        end
        return results
    end

    -- Apply some private methods
    init_chash()

    local mt = {}
    mt.__index = function(t, k)
        -- intercept these methods
        if key_methods[k] then
            return call(k)
        else
            if k=='connect' or k=='close' or k=='quit' or k=='set_keepalive' then
                serv_id = nil
            end
            return client[k]
        end
    end
    setmetatable(self, mt)
    return self
end

return _M