local fakes = require("fakes")

local UI_MANAGER = "/Script/Permafrost.UI_ManagerComponent"
local LEDGER = "/Game/Permafrost/Blueprints/Components/BPC_UserInterfaceManager.BPC_UserInterfaceManager_C"
    .. ":UpdateOnLedgerTabToggled"
local WORLD_MAP = "/Script/Permafrost.Widget_WorldMap"
local CONFIRM = WORLD_MAP .. ":HandleFastTravelConfirmationConfirmed"
local CANCEL = WORLD_MAP .. ":HandleFastTravelConfirmationCancelled"
local PRESS = "/Game/Permafrost/UI/Journal/Map/UW_Journal_WorldMap.UW_Journal_WorldMap_C:OnMouseButtonDown"
local TICK = PRESS:gsub(":OnMouseButtonDown$", ":Tick")
local CREATE = PRESS:gsub(":OnMouseButtonDown$", ":CreateMapMarker")
local INPUT_LIB = "/Script/Engine.Default__KismetInputLibrary"
local MAP_TAB = require("ftm.fast_travel.logic").MAP_TAB

local function vec(x, y, z)
    return { X = x, Y = y, Z = z }
end

-- A fake TMap of the map markers: ForEach gives each key and value as a RemoteUnrealParam, and
-- Find gives the value of a key as a RemoteUnrealParam and throws for a missing key, as in UE4SS.
-- `find` = "throws" makes each Find throw (a UE4SS build without it), "nil" makes it give no value.
local function markers(byName, find)
    return {
        walks = 0,
        Find = function(_, key)
            if find == "throws" then error("no Find") end
            if find == "nil" then return fakes.param(nil) end
            local marker = byName[key]
            if marker == nil then error("key not found") end
            return fakes.param(marker)
        end,
        ForEach = function(self, fn)
            self.walks = self.walks + 1
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

-- The top overlay of a map, with the bed icon in it already.
local function overlays(map)
    map.Markers_Overlay_MovingTargets = {
        HasChild = function()
            return true
        end,
    }
    return map
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
            name = "BP_RespawnPointTemplate_C_1",
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
        w.map = overlays(fakes.object({
            class = "UW_Journal_WorldMap_C",
            MapMarkers = markers({ BP_RespawnPointTemplate_C_1 = w.icon }),
            ["World Map Manager"] = w.manager,
            GetOwningPlayer = function()
                return w.pc
            end,
            HandleFastTravelDestinationSelectionChanged = spy.new(function() end),
        }))
        w.ledger = fakes.object({ Panel_Map = w.map })
        w.pc.UIManagerComp = fakes.object({ CloseLedger = w.pc.UIManagerComp.CloseLedger, LedgerMenu = w.ledger })
        w.ui = fakes.object({ class = "BPC_UserInterfaceManager_C", LedgerMenu = w.ledger })
        return w
    end

    -- A second map widget in the ledger, as after the game makes the map again.
    local function newMap()
        local map = overlays(fakes.object({
            class = "UW_Journal_WorldMap_C",
            MapMarkers = markers({ BP_RespawnPointTemplate_C_1 = world.icon }),
            GetOwningPlayer = function()
                return world.pc
            end,
            HandleFastTravelDestinationSelectionChanged = spy.new(function() end),
        }))
        world.ledger.Panel_Map = map
        return map
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

    -- One frame of the map's Tick, 50 ms after the one before (the clock is fake).
    local realClock, clockNow = os.clock, 0
    local function tick()
        clockNow = clockNow + 0.05
        local hook = env.hooks[TICK]
        if hook then hook(fakes.param(world.ledger.Panel_Map), fakes.param({}), fakes.param(0.05)) end
    end

    before_each(function()
        clockNow = 1000
        os.clock = function()
            return clockNow
        end
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
        os.clock = realClock
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

        it("traces that the pressed map is the map of the ledger", function()
            press("RightMouseButton")
            assert.are.equal(1, lines("map press: the ledger map is the same"))
        end)

        it("traces a pressed map that is not the map of the ledger", function()
            local pressed = world.map
            newMap()
            env.hooks[PRESS](fakes.param(pressed), fakes.param({}), fakes.param({ button = "RightMouseButton" }))
            assert.are.equal(1, lines("map press: the ledger map is different"))
        end)

        it("traces nothing at a press without verbose", function()
            ctx.config.verbose = false
            press("RightMouseButton")
            assert.are.equal(0, lines("map press:"))
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

        it("does nothing when the bed claim is gone", function()
            world.pc.PlayerState.BedRespawnPoint = nil
            world.pc.PlayerState.BedRespawnLocation = vec(0, 0, 0)
            world.icon.TargetLocation = vec(0, 0, 0)
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

        it("on a ledger close, on the map of the UI manager, not on the map of the press", function()
            local pressed = world.map
            local current = newMap()
            tab(0)
            assert.are.equal(1, #pressed.HandleFastTravelDestinationSelectionChanged.calls)
            assert.spy(current.HandleFastTravelDestinationSelectionChanged).was.called(1)
        end)

        it("on a ledger close with no valid map, with no error", function()
            world.ledger.Panel_Map.destroyed = true
            tab(0)
            assert.are.equal(1, #windowCalls())
            assert.are.equal(1, lines("bed pending cleared %(ledger%)"))
            assert.are.equal(0, lines("WARN"))
        end)
    end)

    describe("the selection hook", function()
        local SELECTION = WORLD_MAP .. ":HandleFastTravelDestinationSelectionChanged"

        local function select(has, name)
            env.hooks[SELECTION](
                fakes.param(world.map),
                fakes.param({
                    bHasSelectedDestination = has,
                    DestinationName = {
                        ToString = function()
                            return name
                        end,
                    },
                })
            )
        end

        it("traces each selection change with the destination name", function()
            select(true, "Old Mill")
            select(false, "")
            assert.are.equal(1, lines("selection changed: true 'Old Mill'"))
            assert.are.equal(1, lines("selection changed: false ''"))
        end)

        it("traces nothing without verbose", function()
            ctx.config.verbose = false
            select(true, "Old Mill")
            assert.are.equal(0, lines("selection changed"))
        end)

        it("warns once and keeps the rest when the hook cannot register", function()
            env.failHook = ":HandleFastTravelDestinationSelectionChanged"
            install()
            assert.are.equal(1, lines("WARN bed selection hook failed"))
        end)
    end)

    describe("the golden look", function()
        local GOLD = require("ftm.bed_travel.logic").iconColor(false, true)
        local SELECTION = WORLD_MAP .. ":HandleFastTravelDestinationSelectionChanged"

        local function select(has, name)
            env.hooks[SELECTION](
                fakes.param(world.map),
                fakes.param({
                    bHasSelectedDestination = has,
                    DestinationName = {
                        ToString = function()
                            return name
                        end,
                    },
                })
            )
        end

        local function lastColor()
            local calls = world.icon.SetIconColor.calls
            return calls[#calls].vals[2]
        end

        before_each(function()
            tab(MAP_TAB)
            tick()
            press()
            tick()
        end)

        it("is on after a press on the bed icon, also with the mouse on the icon", function()
            assert.are.same(GOLD, lastColor())
            world.icon.hovered = false
            tick()
            assert.are.same(GOLD, lastColor())
        end)

        it("stays on for the mod's own bed selection", function()
            select(true, "Bed")
            tick()
            assert.are.same(GOLD, lastColor())
        end)

        it("goes off at a cancel", function()
            env.hooks[CANCEL](fakes.param(world.map))
            tick()
            assert.are_not.same(GOLD, lastColor())
        end)

        it("goes off at a click on a fast-travel icon", function()
            select(true, "Church")
            tick()
            assert.are_not.same(GOLD, lastColor())
        end)

        it("goes off when the game collapses the window", function()
            select(false, "")
            tick()
            assert.are_not.same(GOLD, lastColor())
        end)

        it("goes off at a confirm of a fast-travel point", function()
            world.manager.selected = true
            confirm()
            tick()
            assert.are_not.same(GOLD, lastColor())
        end)

        it("is off at the next map-tab open after a ledger close", function()
            tab(0)
            tab(MAP_TAB)
            tick()
            assert.are_not.same(GOLD, lastColor())
        end)
    end)

    describe("the bed icon lookup", function()
        it("finds the bed icon by its key and walks no marker", function()
            tab(MAP_TAB)
            tick()
            assert.spy(world.icon.SetIconColor).was.called(1)
            assert.are.equal(0, world.map.MapMarkers.walks)
        end)

        for _, mode in ipairs({ "throws", "nil" }) do
            it("walks the markers when Find " .. (mode == "nil" and "gives nothing" or "throws"), function()
                world.map.MapMarkers = markers({ BP_RespawnPointTemplate_C_1 = world.icon }, mode)
                tab(MAP_TAB)
                tick()
                assert.spy(world.icon.SetIconColor).was.called(1)
                assert.are.equal(1, world.map.MapMarkers.walks)
                assert.are.equal(0, lines("WARN"))
            end)
        end

        describe("a new marker", function()
            local function created(name)
                env.hooks[CREATE](
                    fakes.param(world.map),
                    fakes.param({
                        UniqueName = {
                            ToString = function()
                                return name
                            end,
                        },
                    })
                )
            end

            local function moves()
                return world.map.Markers_Overlay_MovingTargets.moved or 0
            end

            before_each(function()
                local top = world.map.Markers_Overlay_MovingTargets
                top.HasChild = function()
                    return false
                end
                top.AddChildToOverlay = function(self)
                    self.moved = (self.moved or 0) + 1
                    return { SetHorizontalAlignment = function() end, SetVerticalAlignment = function() end }
                end
                tab(MAP_TAB)
            end)

            it("does nothing before the key of the bed marker is known", function()
                created("BP_RespawnPointTemplate_C_1")
                assert.are.equal(0, moves())
            end)

            it("moves only the bed marker, in the frame that makes it", function()
                tick()
                local before = moves()
                created("Other")
                assert.are.equal(before, moves())
                created("BP_RespawnPointTemplate_C_1")
                assert.are.equal(before + 1, moves())
            end)
        end)

        describe("while the respawn point actor is streamed out", function()
            before_each(function()
                world.pc.PlayerState.BedRespawnPoint = nil
                world.icon.TargetLocation = vec(1, 2, 3)
            end)

            it("finds the marker at the bed location", function()
                world.map.MapMarkers = markers({
                    Other = fakes.object({ TargetLocation = vec(900, 900, 900) }),
                    BP_RespawnPointTemplate_C_1 = world.icon,
                })
                tab(MAP_TAB)
                tick()
                assert.spy(world.icon.SetIconColor).was.called(1)
                assert.are.equal(1, world.map.MapMarkers.walks)
            end)

            it("takes the bed marker and not the player marker that stands at the bed", function()
                local player = fakes.object({
                    TargetLocation = vec(1, 2, 3),
                    IsHovered = function()
                        return false
                    end,
                    SetIconColor = spy.new(function() end),
                })
                world.map.MapMarkers = markers({ LocalPlayer = player, BP_RespawnPointTemplate_C_1 = world.icon })
                tab(MAP_TAB)
                tick()
                assert.spy(world.icon.SetIconColor).was.called(1)
                assert.spy(player.SetIconColor).was.not_called()
            end)

            it("takes no player marker when the bed marker is gone", function()
                local player = fakes.object({
                    TargetLocation = vec(1, 2, 3),
                    IsHovered = function()
                        return false
                    end,
                    SetIconColor = spy.new(function() end),
                })
                world.map.MapMarkers = markers({ LocalPlayer = player })
                tab(MAP_TAB)
                tick()
                assert.spy(player.SetIconColor).was.not_called()
            end)

            it("walks once and then uses the key", function()
                tab(MAP_TAB)
                tick()
                tick()
                assert.are.equal(1, world.map.MapMarkers.walks)
            end)

            it("does not take the marker of an old key away from the bed", function()
                tab(MAP_TAB)
                tick()
                world.pc.PlayerState.BedRespawnLocation = vec(500, 500, 500)
                tick()
                assert.spy(world.icon.SetIconColor).was.called(1)
            end)

            it("skips a marker that cannot be read and keeps the hover", function()
                local broken = setmetatable({}, {
                    __index = function()
                        error("freed")
                    end,
                })
                world.map.MapMarkers = markers({ Broken = broken, BP_RespawnPointTemplate_C_1 = world.icon })
                tab(MAP_TAB)
                tick()
                assert.spy(world.icon.SetIconColor).was.called(1)
                assert.are.equal(0, lines("WARN"))
            end)

            it("logs the lookup by location again after a level change", function()
                tab(MAP_TAB)
                tick()
                env.loadMap.pre[1]()
                tab(MAP_TAB)
                tick()
                assert.are.equal(2, lines("bed marker by location"))
            end)

            it("logs the lookup by location once", function()
                tab(MAP_TAB)
                tick()
                tick()
                assert.are.equal(1, lines("bed marker by location"))
            end)

            it("logs the change back to the actor reference", function()
                tab(MAP_TAB)
                tick()
                world.pc.PlayerState.BedRespawnPoint = world.point
                tick()
                assert.are.equal(1, lines("bed marker by actor"))
            end)

            it("opens the window and travels to the bed location", function()
                tab(MAP_TAB)
                press()
                assert.are.equal(1, #windowCalls())
                confirm()
                assert.spy(world.pc.TeleportToLocation).was.called_with(world.pc, vec(1, 2, 3))
            end)
        end)
    end)

    describe("the hover", function()
        it("registers the map Tick hook at the first map tab, once, and runs no async poll", function()
            assert.is_nil(env.hooks[TICK])
            tab(MAP_TAB)
            tab(0)
            tab(MAP_TAB)
            assert.is_function(env.hooks[TICK])
            assert.are.equal(1, lines("map tick hook armed"))
            assert.spy(env.spy.LoopAsync).was.not_called()
        end)

        it("sets the bed icon tint from the map of the Tick and does not search", function()
            tab(MAP_TAB)
            tick()
            assert.spy(env.spy.FindFirstOf).was.not_called()
            assert.spy(world.icon.SetIconColor).was.called(1)
        end)

        it("follows a new map widget at the next Tick", function()
            tab(MAP_TAB)
            tick()
            local icon = world.icon
            world.icon = fakes.object({
                IsHovered = spy.new(function()
                    return false
                end),
                SetIconColor = spy.new(function() end),
            })
            newMap()
            tick()
            assert.spy(world.icon.SetIconColor).was.called(1)
            assert.spy(icon.SetIconColor).was.called(1)
        end)

        it("resets the hover at a ledger close with no object call, and sets the tint at the next open", function()
            tab(MAP_TAB)
            tick()
            tab(0)
            assert.spy(world.icon.SetIconColor).was.called(1)
            assert.are.equal(1, lines("bed hover end: 1 ticks, 1 checks"))
            tab(MAP_TAB)
            tick()
            assert.spy(world.icon.SetIconColor).was.called(2)
        end)

        it("resets the hover at a map load with no object call", function()
            tab(MAP_TAB)
            tick()
            env.loadMap.pre[1]()
            assert.spy(world.icon.SetIconColor).was.called(1)
            assert.are.equal(1, lines("bed hover end"))
        end)

        it("registers no quit hook: there is no async work to stop", function()
            assert.is_nil(env.hooks["/Script/Engine.KismetSystemLibrary:QuitGame"])
            assert.is_nil(env.hooks["/Script/Engine.GameplayStatics:OpenLevel"])
        end)

        it("closes the bed window at a map load, so a later confirm does not travel", function()
            tab(MAP_TAB)
            tick()
            press()
            env.loadMap.pre[1]()
            confirm()
            assert.spy(world.pc.TeleportToLocation).was.not_called()
        end)

        it("resets at a map load through the post hook when the game has no pre hook", function()
            _G.RegisterLoadMapPreHook = nil
            install()
            env.watchers[UI_MANAGER](world.ui)
            assert.are.equal(1, #env.loadMap.post)
            tab(MAP_TAB)
            tick()
            env.loadMap.post[1]()
            assert.are.equal(1, lines("bed hover end"))
        end)
    end)
end)
