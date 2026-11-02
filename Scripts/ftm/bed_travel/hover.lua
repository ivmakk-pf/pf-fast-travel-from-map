-- The hover look of the bed icon on the open map. The map's own Tick drives it: the game runs that
-- Tick each frame only while the map shows, on the game thread, so there is no poll to start or
-- stop. A check runs at most each 50 ms, reads IsHovered of the bed icon, and sets its tint on a
-- change. Runs on the local machine.
-- Only plain values stay between checks: the map makes its marker widgets again, and a kept widget
-- can be freed while IsValid still reads true (a call on it crashes the game). Each check looks the
-- icon up again from the map of the Tick.
local logic = require("ftm.bed_travel.logic")

local M = {}

local CHECK_S = 0.05 - 1e-6 -- 50 ms; the small margin keeps a check at exactly 50 ms from a float rounding
-- After a check with no bed icon, the next check waits 1 s: with a claimed bed whose marker is not
-- on the map, each check walks all markers, so the walk stays rare.
local MISS_S = 1.0 - 1e-6

local ctx = nil ---@type FtmContext

---@alias BedIconFinder fun(map: any): (UMapMarkerWidgetBase?, integer?) the valid bed icon and the marker count

---@class BedHoverState
---@field last number? the clock time of the last check
---@field map integer? the address of the map of the last check
---@field address integer? the address of the icon of the last check
---@field lastIcon integer? the address of the last icon found, kept over checks with no icon
---@field hovered boolean? the hover state of the last check
---@field color table? the color that the last check set on this icon
---@field broken boolean? a check threw: no more checks until the next reset
---@field wait number? the time from the last check to the next: CHECK_S, or MISS_S after a miss
---@field ticks integer
---@field checks integer
---@field ms number the total check time in ms (os.clock has 1 ms steps in UE4SS)
---@field slow integer the checks that read 1 ms or more
---@field markers integer? the marker count of the last check

local selected = false -- the travel window shows the bed (the gold look)
local state ---@type BedHoverState

local function fresh()
    state = { ticks = 0, checks = 0, ms = 0, slow = 0 }
end
fresh()

local function addressOf(obj)
    if obj == nil then return nil end
    return ctx.try(function()
        return obj:GetAddress()
    end)
end

-- A new icon resets the hover state. A new icon in place of an earlier one is the path of the
-- 1.0.0 crash, so it gets a trace for the in-game check.
local function follow(address)
    if not logic.iconChanged(state.address, address) then return end
    state.address = address
    state.hovered = nil
    state.color = nil
    if address == nil then return end
    if state.lastIcon ~= nil and state.lastIcon ~= address then ctx.trace("bed icon changed") end
    state.lastIcon = address
end

---@param map any
---@param findIcon BedIconFinder
local function check(map, findIcon)
    state.checks = state.checks + 1
    local icon, markers = findIcon(map)
    if icon ~= nil and not ctx.valid(icon) then icon = nil end
    state.markers = markers
    follow(addressOf(icon))
    if icon == nil then return false end
    local hovered = icon:IsHovered() == true
    if state.hovered ~= nil and hovered ~= state.hovered then
        ctx.trace(hovered and "bed hover on" or "bed hover off")
    end
    state.hovered = hovered
    -- The colors are constant tables, so a compare by identity finds a change.
    local color = logic.iconColor(hovered, selected)
    if color ~= state.color or logic.refreshTint(state.checks) then
        icon:SetIconColor(color)
        state.color = color
    end
    return true
end

---@param context FtmContext
function M.install(context)
    ctx = context
end

-- Runs from the hook of the map's Tick, after its body. `now` is the clock time in seconds. The map
-- is read from the hook parameter only when a check runs, not on each frame.
---@param mapParam RemoteUnrealParam the `self` parameter of the Tick hook
---@param findIcon BedIconFinder
---@param now number
function M.onTick(mapParam, findIcon, now)
    state.ticks = state.ticks + 1
    if state.broken or (state.last ~= nil and now - state.last < (state.wait or CHECK_S)) then return end
    state.last = now
    local map = mapParam:get()
    local mapAddress = addressOf(map)
    if mapAddress ~= state.map then
        state.map = mapAddress
        follow(nil)
    end
    local started = os.clock()
    local ok, found = pcall(check, map, findIcon)
    state.wait = (ok and found) and CHECK_S or MISS_S
    local ms = (os.clock() - started) * 1000
    state.ms = state.ms + ms
    if ms >= 1 then state.slow = state.slow + 1 end
    if not ok then
        state.broken = true
        ctx.warnOnce("bed hover", "bed hover: " .. tostring(found))
    end
end

-- The gold look while the travel window shows the bed. The next check sets the color.
---@param on boolean
function M.select(on)
    selected = on == true
end

-- At a ledger-tab change away from the map and at a map load: forgets the state and the gold, and
-- calls no game object. The icon keeps its tint while the map is hidden; the first check after the
-- map shows again sets it. Logs the numbers of the cost budget once (verbose only).
function M.reset()
    selected = false
    if state.ticks > 0 then
        ctx.trace(
            string.format(
                "bed hover end: %d ticks, %d checks, %.0f ms total, %d checks of 1 ms or more, %s markers",
                state.ticks,
                state.checks,
                state.ms,
                state.slow,
                tostring(state.markers)
            )
        )
    end
    fresh()
end

return M
