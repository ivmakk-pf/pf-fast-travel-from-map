local fakes = require("fakes")

local UI_MANAGER = "/Script/Permafrost.UI_ManagerComponent"
local LEDGER = "/Game/Permafrost/Blueprints/Components/BPC_UserInterfaceManager.BPC_UserInterfaceManager_C"
    .. ":UpdateOnLedgerTabToggled"
local WORLD_MAP = "/Script/Permafrost.Widget_WorldMap"
local CONFIRM = WORLD_MAP .. ":HandleFastTravelConfirmationConfirmed"
local CANCEL = WORLD_MAP .. ":HandleFastTravelConfirmationCancelled"
local PRESS = "/Game/Permafrost/UI/Journal/Map/UW_Journal_WorldMap.UW_Journal_WorldMap_C:OnMouseButtonDown"
local INPUT_LIB = "/Script/Engine.Default__KismetInputLibrary"
local MAP_TAB = require("ftm.fast_travel.logic").MAP_TAB

local function vec(x, y, z)
    return { X = x, Y = y, Z = z }
end

-- A fake TMap of the map markers: ForEach gives each key and value as a RemoteUnrealParam.
local function markers(byName)
    return {
        ForEach = function(_, fn)
            for name, marker in pairs(byName) do
                fn(
                    fakes.param({
                        ToString = function()
                            return name
                        end,
                    }),
                    fakes.param(marker)
                )
            end
        end,
    }
end

describe("bed_travel", function()
    local env, ctx, world

    local function lines(pattern)
        local n = 0
        for _, line in ipairs(env.printed) do
            if line:find(pattern) then n = n + 1 end
        end
        return n
    end

    -- The game objects of one test: the map, the player, the bed, its icon, and the manager.
    local function newWorld()
        local w = {}
        w.point = fakes.object({
            name = "BP_Bed_1",
            K2_GetActorLocation = function()
                return vec(7, 8, 9)
            end,
        })
        w.icon = fakes.object({
            hovered = true,
            IsHovered = function(self)
                return self.hovered
            end,
            SetIconColor = spy.new(function() end),
        })
        w.manager = fakes.object({
            selected = false,
            HasSelectedFastTravelDestination = function(self)
                return self.selected
            end,
            ClearSelectedFastTravelDestination = spy.new(function(self)
                self.selected = false
            end),
        })
        w.pc = {
            PlayerState = { BedRespawnPoint = w.point, BedRespawnLocation = vec(1, 2, 3) },
            UIManagerComp = { CloseLedger = spy.new(function() end) },
            TeleportToLocation = spy.new(function() end),
        }
        w.map = fakes.object({
            class = "UW_Journal_WorldMap_C",
            MapMarkers = markers({ BP_Bed_1 = w.icon }),
            ["World Map Manager"] = w.manager,
            GetOwningPlayer = function()
                return w.pc
            end,
            HandleFastTravelDestinationSelectionChanged = spy.new(function() end),
        })
        w.ui = fakes.object({ class = "BPC_UserInterfaceManager_C" })
        return w
    end

    local function install()
        package.loaded["ftm.bed_travel.feature"] = nil
        package.loaded["ftm.ledger_tab"] = nil
        package.loaded["ftm.bed_travel.hover"] = nil
        require("ftm.bed_travel.feature").install(ctx)
    end

    local function tab(value)
        env.hooks[LEDGER](fakes.param(world.ui), fakes.param(value))
    end

    local function press(button)
        env.hooks[PRESS](fakes.param(world.map), fakes.param({}), fakes.param({ button = button or "LeftMouseButton" }))
    end

    local function confirm()
        env.hooks[CONFIRM](fakes.param(world.map))
    end

    local function windowCalls()
        return world.map.HandleFastTravelDestinationSelectionChanged.calls
    end

    before_each(function()
        env = fakes.install()
        env.objects[INPUT_LIB] = fakes.object({
            PointerEvent_GetEffectingButton = function(_, event)
                return {
                    KeyName = {
                        ToString = function()
                            return event.button
                        end,
                    },
                }
            end,
        })
        ctx = require("ftm.core.context").new("T")
        ctx.config = { verbose = true }
        world = newWorld()
        install()
        env.watchers[UI_MANAGER](world.ui)
    end)
    after_each(function()
        fakes.restore()
    end)

    describe("install", function()
        it("fails without the input library", function()
            env.objects[INPUT_LIB] = nil
            assert.has_error(install)
        end)

        it("fails when the confirm hook cannot register", function()
            env.failHook = ":HandleFastTravelConfirmationConfirmed"
            assert.has_error(install)
        end)

        it("fails when the cancel hook cannot register", function()
            env.failHook = ":HandleFastTravelConfirmationCancelled"
            assert.has_error(install)
        end)

        it("registers the map press hook at the first map tab, once", function()
            assert.is_nil(env.hooks[PRESS])
            tab(MAP_TAB)
            tab(0)
            tab(MAP_TAB)
            assert.is_function(env.hooks[PRESS])
            assert.are.equal(1, lines("map press hook armed"))
        end)

        it("warns once and keeps the rest when the map press hook cannot register", function()
            env.failHook = ":OnMouseButtonDown"
            tab(MAP_TAB)
            tab(0)
            tab(MAP_TAB)
            assert.is_nil(env.hooks[PRESS])
            assert.are.equal(1, lines("WARN bed press hook failed"))
        end)
    end)

    describe("a press on the map", function()
        before_each(function()
            tab(MAP_TAB)
        end)

        it("opens the window with the bed for a left press on the hovered bed icon", function()
            press()
            assert.are.equal(1, #windowCalls())
            assert.are.same({ bHasSelectedDestination = true, DestinationName = "Bed" }, windowCalls()[1].vals[2])
            assert.are.equal(1, lines("bed window opened"))
        end)

        it("clears a fast-travel selection first", function()
            world.manager.selected = true
            press()
            assert.spy(world.manager.ClearSelectedFastTravelDestination).was.called(1)
            assert.are.equal(1, #windowCalls())
        end)

        it("does nothing for a right press", function()
            press("RightMouseButton")
            assert.are.equal(0, #windowCalls())
        end)

        it("does nothing for a press off the bed icon", function()
            world.icon.hovered = false
            press()
            assert.are.equal(0, #windowCalls())
        end)

        it("does nothing with no claimed bed", function()
            world.pc.PlayerState.BedRespawnPoint = nil
            press()
            assert.are.equal(0, #windowCalls())
        end)

        it("warns once when the mouse button cannot be read", function()
            env.objects[INPUT_LIB].PointerEvent_GetEffectingButton = function()
                error("changed")
            end
            press()
            press()
            assert.are.equal(0, #windowCalls())
            assert.are.equal(1, lines("WARN cannot read the mouse button"))
        end)
    end)

    describe("the confirm", function()
        before_each(function()
            tab(MAP_TAB)
        end)

        it("closes the ledger and travels to the claimed bed location", function()
            press()
            confirm()
            assert.spy(world.pc.UIManagerComp.CloseLedger).was.called(1)
            assert.spy(world.pc.TeleportToLocation).was.called_with(world.pc, vec(1, 2, 3))
            assert.are.equal(1, lines("bed travel to %(1,2,3%)"))
        end)

        it("travels to the respawn point when the bed location is zero", function()
            world.pc.PlayerState.BedRespawnLocation = vec(0, 0, 0)
            press()
            confirm()
            assert.spy(world.pc.TeleportToLocation).was.called_with(world.pc, vec(7, 8, 9))
        end)

        it("does not travel when both locations are zero", function()
            world.pc.PlayerState.BedRespawnLocation = vec(0, 0, 0)
            world.point.K2_GetActorLocation = function()
                return vec(0, 0, 0)
            end
            press()
            confirm()
            assert.spy(world.pc.TeleportToLocation).was.not_called()
            assert.are.equal(1, lines("no bed target"))
        end)

        it("leaves a fast-travel selection to the game and closes the bed window", function()
            press()
            world.manager.selected = true
            confirm()
            assert.spy(world.pc.TeleportToLocation).was.not_called()
            world.manager.selected = false
            confirm()
            assert.spy(world.pc.TeleportToLocation).was.not_called()
            assert.are.equal(1, lines("bed pending cleared %(fast travel%)"))
        end)

        it("does nothing without a bed window", function()
            confirm()
            assert.spy(world.pc.TeleportToLocation).was.not_called()
        end)
    end)

    describe("the window closes", function()
        before_each(function()
            tab(MAP_TAB)
            press()
        end)

        it("on a cancel", function()
            env.hooks[CANCEL](fakes.param(world.map))
            confirm()
            assert.spy(world.pc.TeleportToLocation).was.not_called()
            assert.are.equal(1, lines("bed pending cleared %(cancel%)"))
        end)

        it("on a ledger close, and the mod collapses the bed window", function()
            tab(0)
            assert.are.same({ bHasSelectedDestination = false, DestinationName = "" }, windowCalls()[2].vals[2])
            confirm()
            assert.spy(world.pc.TeleportToLocation).was.not_called()
            assert.are.equal(1, lines("bed pending cleared %(ledger%)"))
        end)
    end)

    describe("the hover", function()
        it("finds the map at the first turn and tints the bed icon", function()
            world.icon.hovered = false
            env.firstOf["UW_Journal_WorldMap_C"] = world.map
            tab(MAP_TAB)
            env.tick()
            assert.spy(env.spy.FindFirstOf).was.called(1)
            assert.spy(world.icon.SetIconColor).was.called(1)
        end)

        it("uses the map of the last press and does not search", function()
            tab(MAP_TAB)
            press()
            tab(MAP_TAB)
            env.tick()
            assert.spy(env.spy.FindFirstOf).was.not_called()
            assert.spy(world.icon.SetIconColor).was.called(1)
        end)

        it("stops on a ledger close and sets the icon back to white", function()
            env.firstOf["UW_Journal_WorldMap_C"] = world.map
            tab(MAP_TAB)
            env.tick()
            tab(0)
            env.tick()
            assert.are.equal(0, #env.loops)
            assert.spy(world.icon.SetIconColor).was.called(2)
        end)
    end)
end)
