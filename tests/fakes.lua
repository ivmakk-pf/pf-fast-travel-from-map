-- Fake UE4SS globals and fake UObjects for the specs, on luassert spies. A spec calls
-- fakes.install() in before_each and fakes.restore() in after_each, and loads the module under
-- test fresh (package.loaded[name] = nil), so each test starts with new state.
-- The behavior copies what the game runs showed: a Blueprint hook gets only its first callback,
-- and a NotifyOnNewObject callback gets an object that is not set up yet.
local spy = require("luassert.spy")

local M = {}

local NAMES = {
    "RegisterHook",
    "NotifyOnNewObject",
    "ExecuteInGameThread",
    "LoopAsync",
    "StaticFindObject",
    "FindFirstOf",
    "FName",
    "FText",
    "print",
}
local saved = nil
local nextAddress = 0x1000

---@class FakeEnv
---@field hooks table<string, function> the callback of each registered hook path
---@field watchers table<string, function> the callback of each watched class path
---@field loops function[] the active LoopAsync callbacks
---@field printed string[] each print line
---@field objects table<string, any> what StaticFindObject finds, by path
---@field firstOf table<string, any> what FindFirstOf finds, by class name
---@field failHook string? RegisterHook throws for a path with this suffix (a test can set it later)
---@field failWatch boolean? NotifyOnNewObject throws while it is true
---@field spy table<string, any> the fake of each global, for assert.spy(env.spy.RegisterHook)
---@field tick fun() runs each active loop once

---@param opts { failHook: string? }? failHook: RegisterHook throws for a path with this suffix
---@return FakeEnv
function M.install(opts)
    opts = opts or {}
    saved = {}
    for _, name in ipairs(NAMES) do
        saved[name] = rawget(_G, name)
    end
    local env = { hooks = {}, watchers = {}, loops = {}, printed = {}, objects = {}, firstOf = {} }
    env.failHook = opts.failHook
    local ids = 0

    -- The globals go in through a loop with a variable key, so LuaLS keeps the UE4SS types of
    -- these names (a literal `_G.X = spy` or `rawset(_G, "X", spy)` would change them).
    ---@type table<string, any>
    local globals = {
        RegisterHook = spy.new(function(path, fn)
            if env.failHook and path:sub(-#env.failHook) == env.failHook then
                error("No UFunction with the specified name was found: " .. path)
            end
            env.hooks[path] = fn
            ids = ids + 2
            return ids - 1, ids
        end),
        NotifyOnNewObject = spy.new(function(class, fn)
            if env.failWatch then error("watch failed: " .. class) end
            env.watchers[class] = fn
        end),
        ExecuteInGameThread = spy.new(function(fn)
            fn()
        end),
        LoopAsync = spy.new(function(_, fn)
            env.loops[#env.loops + 1] = fn
        end),
        StaticFindObject = spy.new(function(path)
            return env.objects[path]
        end),
        FindFirstOf = spy.new(function(class)
            return env.firstOf[class]
        end),
        FName = function(s)
            return s
        end,
        FText = function(s)
            return s
        end,
        print = spy.new(function(s)
            env.printed[#env.printed + 1] = s
        end),
    }
    for _, name in ipairs(NAMES) do
        _G[name] = globals[name]
    end
    env.spy = globals

    function env.tick()
        local active = {}
        for _, fn in ipairs(env.loops) do
            if fn() ~= true then active[#active + 1] = fn end
        end
        env.loops = active
    end
    return env
end

function M.restore()
    if not saved then return end
    for _, name in ipairs(NAMES) do
        _G[name] = saved[name]
    end
    saved = nil
end

local function fname(s)
    return {
        ToString = function()
            return s
        end,
    }
end

-- A fake UObject: IsValid (false after `destroyed = true`), GetAddress, GetClass():GetFName(),
-- and GetFName() of `class` and `name`. Other fields of props become its properties and methods.
---@param props table?
---@return any
function M.object(props)
    local o = props or {}
    nextAddress = nextAddress + 0x10
    local address = nextAddress
    o.IsValid = function(self)
        return not self.destroyed
    end
    o.GetAddress = function()
        return address
    end
    o.GetClass = function(self)
        return {
            GetFName = function()
                return fname(self.class)
            end,
        }
    end
    o.GetFName = function(self)
        return fname(self.name)
    end
    return o
end

-- A fake RemoteUnrealParam of a hook callback.
---@param value any
---@return any
function M.param(value)
    local p = { value = value }
    function p:get()
        return self.value
    end
    function p:set(v)
        self.value = v
    end
    return p
end

return M
