local fakes = require("fakes")

local FEATURE_MODULES = { "ftm.fast_travel.feature", "ftm.bed_travel.feature", "ftm.ledger_tab" }

-- Loads Scripts/main.lua with this config and stub feature modules. Returns the fake env and the
-- context that the features got.
local function loadMain(config, installs)
    installs = installs or {}
    local env = fakes.install()
    local got = {}
    package.loaded["ftm.core.config_file"] = {
        load = function()
            return config
        end,
    }
    for _, name in ipairs(FEATURE_MODULES) do
        package.loaded[name] = {
            install = function(ctx)
                got.ctx = ctx
                got[name] = true
                if installs[name] then installs[name](ctx) end
            end,
        }
    end
    dofile("Scripts/main.lua")
    return env, got
end

local function lines(env, pattern)
    local found = {}
    for _, line in ipairs(env.printed) do
        if line:find(pattern) then found[#found + 1] = line end
    end
    return found
end

local ON = { fast_travel = true, bed_travel = true, verbose = false }

describe("main", function()
    after_each(function()
        fakes.restore()
        package.loaded["ftm.core.config_file"] = nil
        for _, name in ipairs(FEATURE_MODULES) do
            package.loaded[name] = nil
        end
    end)

    describe("the load line", function()
        it("shows both features on", function()
            local env, got = loadMain(ON)
            assert.is_true(got["ftm.fast_travel.feature"] and got["ftm.bed_travel.feature"])
            assert.are.equal(
                1,
                #lines(env, "^%[FastTravelFromMap%] v%d+%.%d+%.%d+ loaded %(fast travel on, bed travel on%)\n$")
            )
        end)

        it("shows a feature off by its switch, and does not install it", function()
            local env, got = loadMain({ fast_travel = false, bed_travel = true, verbose = false })
            assert.is_nil(got["ftm.fast_travel.feature"])
            assert.are.equal(1, #lines(env, "loaded %(fast travel off, bed travel on%)"))
        end)

        it("shows the bed travel off by its switch", function()
            local env, got = loadMain({ fast_travel = true, bed_travel = false, verbose = false })
            assert.is_nil(got["ftm.bed_travel.feature"])
            assert.are.equal(1, #lines(env, "loaded %(fast travel on, bed travel off%)"))
        end)

        it("shows a feature off with one warning when its install throws, and keeps the other", function()
            local env = loadMain(ON, {
                ["ftm.bed_travel.feature"] = function()
                    error("no class")
                end,
            })
            assert.are.equal(1, #lines(env, "loaded %(fast travel on, bed travel off%)"))
            assert.are.equal(1, #lines(env, "WARN bed travel not installed %(a game change%?%): .*no class"))
        end)
    end)

    describe("the context", function()
        local env, ctx
        before_each(function()
            local got
            env, got = loadMain(ON)
            ctx = got.ctx
        end)

        it("hook registers the callback and keeps its ids", function()
            assert.is_true(ctx.hook("k", "/Script/X.Y:F", function() end))
            assert.are.same({ 1, 2 }, ctx.hooks["/Script/X.Y:F"])
            assert.is_function(env.hooks["/Script/X.Y:F"])
        end)

        it("hook runs the callback in a guard", function()
            ctx.hook("k", "/Script/X.Y:F", function()
                error("boom")
            end)
            env.hooks["/Script/X.Y:F"]()
            env.hooks["/Script/X.Y:F"]()
            assert.are.equal(1, #lines(env, "WARN k: .*boom"))
        end)

        it("hook logs one warning and gives false when the registration fails", function()
            env.failHook = ":F"
            assert.is_false(ctx.hook("k", "/Script/X.Y:F", function() end))
            assert.is_false(ctx.hook("k", "/Script/X.Y:F", function() end))
            assert.are.equal(1, #lines(env, "WARN k hook failed %(a game change%?%): .*No UFunction"))
            assert.is_nil(ctx.hooks["/Script/X.Y:F"])
        end)

        it("hook with required throws when the registration fails, and logs nothing", function()
            env.failHook = ":F"
            assert.has_error(function()
                ctx.hook("k", "/Script/X.Y:F", function() end, { required = true })
            end)
            assert.are.equal(0, #lines(env, "WARN"))
        end)

        it("guard logs a repeated error once, with its key", function()
            local fn = ctx.guard("key", function()
                error("bad")
            end)
            fn()
            fn()
            assert.are.equal(1, #lines(env, "WARN key: .*bad"))
        end)

        it("trace logs only with verbose on", function()
            ctx.trace("quiet")
            assert.are.equal(0, #lines(env, "quiet"))
            fakes.restore()
            local got
            env, got = loadMain({ fast_travel = true, bed_travel = true, verbose = true })
            got.ctx.trace("loud")
            assert.are.equal(1, #lines(env, "^%[FastTravelFromMap%] loud\n$"))
        end)

        it("try gives the value, or nil when the function throws", function()
            assert.are.equal(
                3,
                ctx.try(function()
                    return 3
                end)
            )
            assert.is_nil(ctx.try(function()
                error("x")
            end))
        end)

        it("valid is true only for a live object", function()
            local o = fakes.object()
            assert.is_true(ctx.valid(o))
            o.destroyed = true
            assert.is_false(ctx.valid(o))
            assert.is_false(ctx.valid(nil))
            assert.is_false(ctx.valid({
                IsValid = function()
                    error("stale")
                end,
            }))
        end)
    end)
end)
