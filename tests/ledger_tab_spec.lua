local fakes = require("fakes")

local UI_MANAGER = "/Script/Permafrost.UI_ManagerComponent"
local HOOK = "/Game/Permafrost/Blueprints/Components/BPC_UserInterfaceManager.BPC_UserInterfaceManager_C"
    .. ":UpdateOnLedgerTabToggled"

describe("ledger_tab", function()
    local env, ctx, ledger

    before_each(function()
        env = fakes.install()
        package.loaded["ftm.ledger_tab"] = nil
        ledger = require("ftm.ledger_tab")
        ctx = require("ftm.core.context").new("T")
    end)
    after_each(function()
        fakes.restore()
    end)

    local function uiManager(class)
        return fakes.object({ class = class or "BPC_UserInterfaceManager_C" })
    end

    local function lines(pattern)
        local n = 0
        for _, line in ipairs(env.printed) do
            if line:find(pattern) then n = n + 1 end
        end
        return n
    end

    it("watches the native UI manager class once, for all listeners", function()
        ledger.listen(ctx, "a", function() end)
        ledger.listen(ctx, "b", function() end)
        assert.spy(env.spy.NotifyOnNewObject).was.called(1)
        assert.spy(env.spy.NotifyOnNewObject).was.called_with(UI_MANAGER, match._)
    end)

    it("throws and keeps no listener when the watch fails, and tries the watch again at the next call", function()
        local calls = { a = 0, b = 0 }
        env.failWatch = true
        assert.has_error(function()
            ledger.listen(ctx, "a", function()
                calls.a = calls.a + 1
            end)
        end)
        env.failWatch = false
        ledger.listen(ctx, "b", function()
            calls.b = calls.b + 1
        end)
        assert.spy(env.spy.NotifyOnNewObject).was.called(2)
        local ui = uiManager()
        env.watchers[UI_MANAGER](ui)
        env.hooks[HOOK](fakes.param(ui), fakes.param(4))
        assert.are.same({ a = 0, b = 1 }, calls)
    end)

    it("registers the ledger tab hook once for the Blueprint UI manager", function()
        ledger.listen(ctx, "a", function() end)
        env.watchers[UI_MANAGER](uiManager())
        env.watchers[UI_MANAGER](uiManager())
        assert.spy(env.spy.RegisterHook).was.called(1)
        assert.is_function(env.hooks[HOOK])
    end)

    it("warns once and registers nothing for another UI manager class", function()
        ledger.listen(ctx, "a", function() end)
        env.watchers[UI_MANAGER](uiManager("Other_C"))
        env.watchers[UI_MANAGER](uiManager("Other_C"))
        assert.spy(env.spy.RegisterHook).was.not_called()
        assert.are.equal(1, lines("WARN unknown UI manager class Other_C"))
    end)

    it("ignores an invalid UI manager", function()
        ledger.listen(ctx, "a", function() end)
        local ui = uiManager()
        ui.destroyed = true
        env.watchers[UI_MANAGER](ui)
        assert.spy(env.spy.RegisterHook).was.not_called()
    end)

    it("calls each listener with the UI manager and the tab value", function()
        local seen = {}
        ledger.listen(ctx, "a", function(ui, tab)
            seen[#seen + 1] = { "a", ui, tab }
        end)
        ledger.listen(ctx, "b", function(ui, tab)
            seen[#seen + 1] = { "b", ui, tab }
        end)
        local ui = uiManager()
        env.watchers[UI_MANAGER](ui)
        env.hooks[HOOK](fakes.param(ui), fakes.param(4))
        assert.are.same({ { "a", ui, 4 }, { "b", ui, 4 } }, seen)
    end)

    it("keeps calling the other listener when one throws, and warns once with its key", function()
        local calls = 0
        ledger.listen(ctx, "bad", function()
            error("broken")
        end)
        ledger.listen(ctx, "good", function()
            calls = calls + 1
        end)
        env.watchers[UI_MANAGER](uiManager())
        env.hooks[HOOK](fakes.param(uiManager()), fakes.param(4))
        env.hooks[HOOK](fakes.param(uiManager()), fakes.param(0))
        assert.are.equal(2, calls)
        assert.are.equal(1, lines("WARN bad: .*broken"))
    end)

    it("logs the armed hook with verbose on", function()
        ctx.config = { verbose = true }
        ledger.listen(ctx, "a", function() end)
        env.watchers[UI_MANAGER](uiManager())
        assert.are.equal(1, lines("ledger tab hook armed"))
    end)

    it("warns once when the hook registration fails", function()
        env.failHook = ":UpdateOnLedgerTabToggled"
        ledger.listen(ctx, "a", function() end)
        env.watchers[UI_MANAGER](uiManager())
        assert.are.equal(1, lines("WARN ledger tab hook failed"))
    end)
end)
