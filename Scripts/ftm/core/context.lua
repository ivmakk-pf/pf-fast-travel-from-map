-- The helpers that all features of FastTravelFromMap share: the log, the warnings, the guards,
-- and the hook registration. Its own file, so the specs of a feature can make a real context.
local M = {}

---@class FtmContext
---@field config table<string, any> the validated settings of config.lua
---@field log fun(message: string)
---@field warnOnce fun(key: string, message: string)
---@field trace fun(message: string) logs only when `verbose` is on
---@field try fun(fn: fun(): any): any the result of fn, nil when it errors (a stale object, a changed game)
---@field valid fun(obj: any): boolean
---@field guard fun(key: string, fn: function): fun(...) fn in a pcall that logs each distinct error once
---@field hook fun(key: string, path: string, fn: function, opts: { required: boolean? }?): boolean registers fn in a guard; a failure logs one warning, or throws when required
---@field hooks table<string, integer[]> the pre and post ids of each registered hook path

---@param fn fun(): any
---@return any
local function try(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function valid(obj)
    return obj ~= nil and try(function()
        return obj:IsValid()
    end) == true
end

---@param mod string the tag of each log line
---@return FtmContext ctx with an empty config: the caller sets ctx.config after the config load
function M.new(mod)
    local ctx = { config = {}, try = try, valid = valid, hooks = {} } ---@type FtmContext
    local warned = {}

    function ctx.log(message)
        print("[" .. mod .. "] " .. message .. "\n")
    end

    function ctx.warnOnce(key, message)
        if warned[key] then return end
        warned[key] = true
        ctx.log("WARN " .. message)
    end

    -- Not named "debug": that would hide the Lua debug library.
    function ctx.trace(message)
        if ctx.config.verbose then ctx.log(message) end
    end

    function ctx.guard(key, fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then ctx.warnOnce(key, key .. ": " .. tostring(err)) end
        end
    end

    function ctx.hook(key, path, fn, opts)
        local ok, pre, post = pcall(RegisterHook, path, ctx.guard(key, fn))
        if not ok then
            if opts and opts.required then error(key .. " hook failed: " .. tostring(pre)) end
            ctx.warnOnce(key .. " hook", key .. " hook failed (a game change?): " .. tostring(pre))
            return false
        end
        ctx.hooks[path] = { pre, post }
        return true
    end

    return ctx
end

return M
