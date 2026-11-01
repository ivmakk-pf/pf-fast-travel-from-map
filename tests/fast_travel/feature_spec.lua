local fakes = require("fakes")

local UI_MANAGER = "/Script/Permafrost.UI_ManagerComponent"
local HOOK = "/Game/Permafrost/Blueprints/Components/BPC_UserInterfaceManager.BPC_UserInterfaceManager_C"
    .. ":UpdateOnLedgerTabToggled"
local MAP_TAB = require("ftm.fast_travel.logic").MAP_TAB

describe("fast_travel", function()
    local env, ui

    before_each(function()
        env = fakes.install()
        package.loaded["ftm.ledger_tab"] = nil
        package.loaded["ftm.fast_travel.feature"] = nil
        local ctx = require("ftm.core.context").new("T")
        ctx.config = { verbose = true }
        require("ftm.fast_travel.feature").install(ctx)
        ui = fakes.object({ class = "BPC_UserInterfaceManager_C", AddWorldMapContext = spy.new(function() end) })
        env.watchers[UI_MANAGER](ui)
    end)
    after_each(function()
        fakes.restore()
    end)

    local function openTab(tab, manager)
        env.hooks[HOOK](fakes.param(manager or ui), fakes.param(tab))
    end

    it("adds the fast-travel map context when the map tab opens", function()
        openTab(MAP_TAB)
        assert.spy(ui.AddWorldMapContext).was.called(1)
        assert.spy(ui.AddWorldMapContext).was.called_with(ui, { TagName = "WorldMap.Context.FastTravel" })
        assert.are.same({ "[T] context added\n" }, { env.printed[#env.printed] })
    end)

    it("adds nothing for another tab or a closed ledger", function()
        openTab(1)
        openTab(0)
        assert.spy(ui.AddWorldMapContext).was.not_called()
    end)

    it("adds nothing for an invalid UI manager", function()
        ui.destroyed = true
        openTab(MAP_TAB)
        assert.spy(ui.AddWorldMapContext).was.not_called()
    end)
end)
