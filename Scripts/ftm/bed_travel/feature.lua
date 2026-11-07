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
local BED_NAME = "Bed" -- the target name in the confirmation window
-- Without these hooks the bed travel cannot work, so a failed registration fails the install.
local REQUIRED = { required = true }

local ctx = nil ---@type FtmContext
local inputLib = nil ---@type any
-- pending: the confirmation window shows the bed. markerKey: the map key of the bed marker, a plain
-- string. The feature keeps no widget between calls: the game can free a widget while IsValid still
-- reads true, so each call gets the map again.
local state = { pending = false, mapHooked = false } ---@type { pending: boolean, mapHooked: boolean, markerKey: string?, byLocation: boolean? }

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

---@return Vec3?
local function plainVec(v)
    return ctx.try(function()
        return { X = v.X, Y = v.Y, Z = v.Z }
    end)
end

-- The claimed bed location of the local player. It stays set while the respawn point actor is
-- streamed out, and it is zero only without a claimed bed.
---@return Vec3?
local function bedLocation(pc)
    return plainVec(ctx.try(function()
        return pc.PlayerState.BedRespawnLocation
    end))
end

-- Verbose only: one line at each change of the way that the lookup finds the bed marker.
---@param byLocation boolean
local function traceLookup(byLocation)
    if state.byLocation == byLocation then return end
    state.byLocation = byLocation
    ctx.trace(byLocation and "bed marker by location (no actor reference)" or "bed marker by actor")
end

-- True when the marker stands at the bed location. The walk reads each marker, so one that cannot
-- be read counts as a miss and does not end the walk.
---@param location Vec3?
---@return boolean
local function atBed(marker, location)
    return ctx.try(function()
        return logic.sameSpot(plainVec(marker.TargetLocation), location)
    end) == true
end

-- The bed icon: the map marker whose key is the name of the respawn point actor. After a travel
-- the actor can be streamed out, so PlayerState.BedRespawnPoint is empty while the marker stays on
-- the map. Then the marker must stand at the bed location: a claim made while the old actor was
-- streamed out leaves the old marker on the map. Nil when there is no claimed bed or no valid icon
-- (yet). The second result is 1 for a lookup by key, or the count of markers walked.
---@param map UUW_Journal_WorldMap_C
---@return UMapMarkerWidgetBase?, integer
local function bedIcon(map)
    local pc = map:GetOwningPlayer()
    local point = bedPoint(pc)
    local location = nil ---@type Vec3?
    if point ~= nil then
        state.markerKey = point:GetFName():ToString()
    else
        location = bedLocation(pc)
        if logic.target(location, nil) == nil then return nil, 0 end
    end
    local bedName = state.markerKey
    local markers = map.MapMarkers ---@type any
    -- The map keys each marker by its UniqueName, the FName of the bed point. Find throws for a
    -- missing key and may be missing in a UE4SS build: the walk below is the fallback.
    local ok, byKey = false, nil
    if bedName ~= nil then
        ok, byKey = pcall(function()
            return markers:Find(FName(bedName)):get()
        end)
    end
    if ok and byKey ~= nil and ctx.valid(byKey) and (point ~= nil or atBed(byKey, location)) then
        traceLookup(point == nil)
        return byKey, 1
    end
    local found, count = nil, 0
    markers:ForEach(function(key, value)
        count = count + 1
        local name = key:get():ToString()
        local marker = value:get()
        if point ~= nil then
            if name == bedName then found = marker end
        elseif logic.isBedMarkerKey(name) and atBed(marker, location) then
            found = marker
            state.markerKey = name
        end
    end)
    if found ~= nil and ctx.valid(found) then
        traceLookup(point == nil)
        return found, count
    end
    return nil, count
end

-- The map widget in the ledger of the UI manager, read in this call. Nil at each invalid step.
---@return UUW_Journal_WorldMap_C?
local function mapOf(ui)
    if not ctx.valid(ui) then return nil end
    local ledger = ui.LedgerMenu
    if not ctx.valid(ledger) then return nil end
    local map = ledger.Panel_Map
    if not ctx.valid(map) then return nil end
    return map
end

---@return string? button the key name of the pressed mouse button, nil when it cannot be read
local function pressedButton(mouseEvent)
    return ctx.try(function()
        return inputLib:PointerEvent_GetEffectingButton(mouseEvent:get()).KeyName:ToString()
    end)
end

-- Verbose only: is the pressed map the map that the ledger-close cleanup reads from the ledger?
-- Both are read in this call, so the probe keeps no state.
---@param map UUW_Journal_WorldMap_C
local function traceMapIdentity(map)
    if not ctx.config.verbose then return end
    local same = ctx.try(function()
        local ledgerMap = mapOf(map:GetOwningPlayer().UIManagerComp)
        return ledgerMap ~= nil and ledgerMap:GetAddress() == map:GetAddress()
    end)
    ctx.trace("map press: the ledger map is " .. (same and "the same" or "different"))
end

-- Runs before the native body of the map's HandleFastTravelDestinationSelectionChanged. The game
-- calls it at a click on a fast-travel icon and at a cancel, and the mod at its own bed window: any
-- destination that is not the bed ends the golden look.
local function bedTravelOnSelection(_, data)
    local value = data:get()
    local name = ctx.try(function()
        return value.DestinationName:ToString()
    end)
    if not logic.isBedSelection(value.bHasSelectedDestination, name, BED_NAME) then hover.select(false) end
    if not ctx.config.verbose then return end
    ctx.trace(string.format("selection changed: %s '%s'", tostring(value.bHasSelectedDestination), tostring(name)))
end

-- Runs after the Blueprint body of the map's OnMouseButtonDown.
local function bedTravelOnMapPress(self, _, mouseEvent)
    local map = self:get() ---@type UUW_Journal_WorldMap_C
    if not ctx.valid(map) then return end
    traceMapIdentity(map)
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
    hover.select(true)
    ctx.trace("bed window opened")
end

---@param map UUW_Journal_WorldMap_C
local function travelToBed(map)
    local pc = map:GetOwningPlayer() ---@type any
    local point = bedPoint(pc)
    local pointLocation = point and plainVec(ctx.try(function()
        return point:K2_GetActorLocation()
    end))
    local goal = logic.target(bedLocation(pc), pointLocation)
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
    hover.select(false)
    if action == "bed" then travelToBed(map) end
end

-- Runs before the native body of the window's cancel, which collapses the window.
local function bedTravelOnCancel()
    if not state.pending then return end
    state.pending = false
    hover.select(false)
    ctx.trace("bed pending cleared (cancel)")
end

-- Runs after the Blueprint body of the map's CreateMapMarker. The game makes every marker again at
-- a change of the map contexts, so this runs once for each marker: only a read of the key, until
-- the bed marker comes. The first check of the hover sets the key, usually before the game makes
-- the markers. Without a key, or when the markers come first, the hover check moves the bed icon,
-- with one blink.
local function bedTravelOnMarkerCreated(self, data)
    if state.markerKey == nil then return end
    local name = ctx.try(function()
        return data:get().UniqueName:ToString()
    end)
    if name == state.markerKey then hover.onBedMarkerCreated(self:get(), bedIcon) end
end

-- Runs after the Blueprint body of the map's Tick: each frame while the map shows, on the game
-- thread. The hover reads only this map and the objects under it, in this call.
local function bedTravelOnMapTick(self)
    hover.onTick(self, bedIcon, os.clock())
end

-- The map widget class is loaded at the first map-tab open, so its hooks register then, once.
-- A drag of the map does not close the bed window: the game's fast-travel window stays open too.
local function armMapHooks()
    if state.mapHooked then return end
    state.mapHooked = true
    if ctx.hook("bed press", MAP_BP .. ":OnMouseButtonDown", bedTravelOnMapPress) then
        ctx.trace("map press hook armed")
    end
    if ctx.hook("bed hover", MAP_BP .. ":Tick", bedTravelOnMapTick) then ctx.trace("map tick hook armed") end
    ctx.hook("bed marker", MAP_BP .. ":CreateMapMarker", bedTravelOnMarkerCreated)
end

---@param tab integer
local function bedTravelOnLedgerTab(ui, tab)
    local action = logic.onLedgerTab(isMapTab(tab), state.pending)
    if action == "map" then
        armMapHooks()
        return
    end
    hover.reset()
    if action ~= "clear" then return end
    state.pending = false
    local map = mapOf(ui)
    if map ~= nil then showWindow(map, false) end
    ctx.trace("bed pending cleared (ledger)")
end

-- A level change resets the hover with no object call, and the bed window goes with the old map.
local function resetForLevel()
    state.pending = false
    state.markerKey = nil
    state.byLocation = nil
    hover.reset()
end

local function watchMapLoad()
    local reset = ctx.guard("bed map load", resetForLevel)
    if type(RegisterLoadMapPreHook) == "function" then
        RegisterLoadMapPreHook(reset)
    else
        RegisterLoadMapPostHook(reset)
    end
end

---@param context FtmContext
function M.install(context)
    ctx = context
    hover.install(ctx)
    inputLib = StaticFindObject(INPUT_LIB)
    if not ctx.valid(inputLib) then error("no " .. INPUT_LIB) end
    ctx.hook("bed confirm", WORLD_MAP .. ":HandleFastTravelConfirmationConfirmed", bedTravelOnConfirm, REQUIRED)
    ctx.hook("bed cancel", WORLD_MAP .. ":HandleFastTravelConfirmationCancelled", bedTravelOnCancel, REQUIRED)
    ctx.hook("bed selection", WORLD_MAP .. ":HandleFastTravelDestinationSelectionChanged", bedTravelOnSelection)
    ledgerTab.listen(ctx, "bed ledger tab", bedTravelOnLedgerTab)
    watchMapLoad()
end

return M
