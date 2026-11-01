-- Bed travel: a left click on the player's claimed bed on the normal map (M) opens the game's
-- fast-travel confirmation window with the bed as the target, and its confirm calls the game's
-- own teleport (TeleportToLocation: the screen fade, the world streaming, the move).
-- Runs on the local machine: every hook is a UI hook of the player who clicks.
local logic = require("ftm.bed_travel.logic")
local isMapTab = require("ftm.fast_travel.logic").isMapTab
local ledgerTab = require("ftm.ledger_tab")
local hover = require("ftm.bed_travel.hover")

local M = {}

local MAP_BP = "/Game/Permafrost/UI/Journal/Map/UW_Journal_WorldMap.UW_Journal_WorldMap_C"
local WORLD_MAP = "/Script/Permafrost.Widget_WorldMap"
local INPUT_LIB = "/Script/Engine.Default__KismetInputLibrary"
local LEFT_BUTTON = "LeftMouseButton"
local MAP_CLASS = "UW_Journal_WorldMap_C"
local BED_NAME = "Bed" -- the target name in the confirmation window
-- Without these hooks the bed travel cannot work, so a failed registration fails the install.
local REQUIRED = { required = true }

local ctx = nil ---@type FtmContext
local inputLib = nil ---@type any
-- pending: the confirmation window shows the bed. map: the map widget of the last press or hover.
local state = { pending = false, map = nil, mapHooked = false } ---@type { pending: boolean, map: UUW_Journal_WorldMap_C?, mapHooked: boolean }

-- Shows the game's confirmation window with the bed, or collapses it.
local function showWindow(map, show)
    map:HandleFastTravelDestinationSelectionChanged({
        bHasSelectedDestination = show,
        DestinationName = FText(show and BED_NAME or ""),
    })
end

-- The claimed respawn point of the local player, nil without a claimed bed.
---@return any
local function bedPoint(pc)
    local point = ctx.try(function()
        return pc.PlayerState.BedRespawnPoint
    end)
    if ctx.valid(point) then return point end
    return nil
end

-- The bed icon: the map marker whose key is the name of the respawn point actor. Nil when there
-- is no claimed bed or no valid icon (yet).
---@param map UUW_Journal_WorldMap_C
---@return UMapMarkerWidgetBase?
local function bedIcon(map)
    local point = bedPoint(map:GetOwningPlayer())
    if point == nil then return nil end
    local bedName = point:GetFName():ToString()
    local found = nil
    local markers = map.MapMarkers ---@type any
    markers:ForEach(function(key, value)
        if key:get():ToString() == bedName then found = value:get() end
    end)
    if found ~= nil and ctx.valid(found) then return found end
    return nil
end

---@return string? button the key name of the pressed mouse button, nil when it cannot be read
local function pressedButton(mouseEvent)
    return ctx.try(function()
        return inputLib:PointerEvent_GetEffectingButton(mouseEvent:get()).KeyName:ToString()
    end)
end

-- Runs after the Blueprint body of the map's OnMouseButtonDown.
local function bedTravelOnMapPress(self, _, mouseEvent)
    local map = self:get() ---@type UUW_Journal_WorldMap_C
    if not ctx.valid(map) then return end
    state.map = map
    local button = pressedButton(mouseEvent)
    if button == nil then
        ctx.warnOnce("bed button", "cannot read the mouse button (a game change?); the bed travel does nothing")
        return
    end
    local icon = button == LEFT_BUTTON and bedIcon(map) or nil
    if not logic.press(icon ~= nil and icon:IsHovered() == true, button == LEFT_BUTTON) then return end
    local manager = map["World Map Manager"]
    if ctx.valid(manager) and manager:HasSelectedFastTravelDestination() then
        manager:ClearSelectedFastTravelDestination()
    end
    showWindow(map, true)
    state.pending = true
    ctx.trace("bed window opened")
end

---@return Vec3?
local function plainVec(v)
    return ctx.try(function()
        return { X = v.X, Y = v.Y, Z = v.Z }
    end)
end

---@param map UUW_Journal_WorldMap_C
local function travelToBed(map)
    local pc = map:GetOwningPlayer() ---@type any
    local point = bedPoint(pc)
    local bedLocation = plainVec(ctx.try(function()
        return pc.PlayerState.BedRespawnLocation
    end))
    local pointLocation = point and plainVec(ctx.try(function()
        return point:K2_GetActorLocation()
    end))
    local goal = point and logic.target(bedLocation, pointLocation)
    if not goal then
        ctx.trace("no bed target")
        return
    end
    pc.UIManagerComp:CloseLedger()
    pc:TeleportToLocation(goal)
    ctx.trace(string.format("bed travel to (%.0f,%.0f,%.0f)", goal.X, goal.Y, goal.Z))
end

-- Runs before the native body of the window's confirm. With no fast-travel selection, the body
-- only collapses the window, so the bed travel runs here.
local function bedTravelOnConfirm(self)
    local map = self:get() ---@type UUW_Journal_WorldMap_C
    if not ctx.valid(map) then return end
    local manager = ctx.try(function()
        return map["World Map Manager"]
    end)
    local selected = ctx.valid(manager) and manager:HasSelectedFastTravelDestination() == true
    local action = logic.onConfirm(state.pending, selected)
    if action == "none" then return end
    if action == "vanilla" and state.pending then ctx.trace("bed pending cleared (fast travel)") end
    state.pending = false
    if action == "bed" then travelToBed(map) end
end

-- Runs before the native body of the window's cancel, which collapses the window.
local function bedTravelOnCancel()
    if not state.pending then return end
    state.pending = false
    ctx.trace("bed pending cleared (cancel)")
end

-- The map widget class is loaded at the first map-tab open, so its hook registers then, once.
-- A drag of the map does not close the bed window: the game's fast-travel window stays open too.
local function armMapHooks()
    if state.mapHooked then return end
    state.mapHooked = true
    if ctx.hook("bed press", MAP_BP .. ":OnMouseButtonDown", bedTravelOnMapPress) then
        ctx.trace("map press hook armed")
    end
end

-- The bed icon for the hover poll. One FindFirstOf for each map-tab open, at the first turn, only
-- without a cached map.
---@param turn integer
---@return UMapMarkerWidgetBase?
local function hoverIcon(turn)
    if turn == 1 and not ctx.valid(state.map) then
        state.map = FindFirstOf(MAP_CLASS) --[[@as UUW_Journal_WorldMap_C?]]
    end
    local map = state.map
    if map == nil or not ctx.valid(map) then return nil end
    return bedIcon(map)
end

---@param tab integer
local function bedTravelOnLedgerTab(_, tab)
    local action = logic.onLedgerTab(isMapTab(tab), state.pending)
    if action == "map" then
        armMapHooks()
        hover.start(ctx, hoverIcon)
        return
    end
    hover.stop()
    if action ~= "clear" then return end
    state.pending = false
    if ctx.valid(state.map) then showWindow(state.map, false) end
    ctx.trace("bed pending cleared (ledger)")
end

---@param context FtmContext
function M.install(context)
    ctx = context
    inputLib = StaticFindObject(INPUT_LIB)
    if not ctx.valid(inputLib) then error("no " .. INPUT_LIB) end
    ctx.hook("bed confirm", WORLD_MAP .. ":HandleFastTravelConfirmationConfirmed", bedTravelOnConfirm, REQUIRED)
    ctx.hook("bed cancel", WORLD_MAP .. ":HandleFastTravelConfirmationCancelled", bedTravelOnCancel, REQUIRED)
    ledgerTab.listen(ctx, "bed ledger tab", bedTravelOnLedgerTab)
end

return M
