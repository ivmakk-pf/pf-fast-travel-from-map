-- Game-free logic of the bed travel of FastTravelFromMap: no UE4SS global, no UObject.
local M = {}

-- A map press opens the bed window at once: the game gives the mod no release of the press.
---@param hit boolean the mouse is on the bed icon
---@param isLeft boolean the press is a left press
---@return boolean
function M.press(hit, isLeft)
    return hit == true and isLeft == true
end

-- What a confirm of the window does. A selected fast-travel point means the window is the game's
-- own fast-travel window, so the game travels there.
---@param bedPending boolean the bed window is open
---@param fastTravelSelected boolean the world map manager has a selected fast-travel point
---@return "bed"|"vanilla"|"none"
function M.onConfirm(bedPending, fastTravelSelected)
    if fastTravelSelected then return "vanilla" end
    if bedPending then return "bed" end
    return "none"
end

---@class Vec3
---@field X number
---@field Y number
---@field Z number

---@param v Vec3?
---@return boolean
local function isSet(v)
    return v ~= nil and (v.X ~= 0 or v.Y ~= 0 or v.Z ~= 0)
end

-- The travel target: the claimed bed location, else the respawn point location, else nil.
---@param bedLocation Vec3?
---@param pointLocation Vec3?
---@return Vec3?
function M.target(bedLocation, pointLocation)
    if isSet(bedLocation) then return bedLocation end
    if isSet(pointLocation) then return pointLocation end
    return nil
end

-- The bed icon tint on the open map. The game draws the icon white (full brightness), so the
-- hover look is a dim icon that goes back to white while the mouse is on it.
local HOVER_COLOR = { R = 1, G = 1, B = 1, A = 1 }
local DIM_COLOR = { R = 0.75, G = 0.75, B = 0.75, A = 1 }

---@param hovered boolean
---@return table color an FLinearColor
function M.hoverColor(hovered)
    return hovered and HOVER_COLOR or DIM_COLOR
end

-- The color to set at a poll turn: only at the first turn (previous nil) and when the hover changes.
---@param previous boolean? the hover state of the last turn
---@param hovered boolean
---@return table? color
function M.hoverChange(previous, hovered)
    if previous == hovered then return nil end
    return M.hoverColor(hovered)
end

-- The hover poll runs each 50 ms while the map tab is open. The map makes its icons when the tab
-- opens (after a travel it makes new ones while the old ones stay valid), so the poll looks the icon
-- up again in the first seconds only. After that a turn is one validity check and one IsHovered read.
local GIVE_UP_TURNS = 20 -- the find of the icon tries for 1 s after the map tab opens
local REFIND_EACH = 10 -- the poll looks the icon up again each 0.5 s ...
local REFIND_UNTIL = 60 -- ... for the first 3 s after the map tab opens

-- What a poll turn does with the bed icon: look it up ("find") or use the one it has ("keep").
---@param turns integer the turn count of this map-tab open, from 1
---@param hasIcon boolean the poll has a valid icon from an earlier turn
---@return "find"|"keep"
function M.hoverTurn(turns, hasIcon)
    if not hasIcon then return "find" end
    if turns <= REFIND_UNTIL and turns % REFIND_EACH == 0 then return "find" end
    return "keep"
end

-- True when a turn that found no icon ends the poll.
---@param turns integer
---@return boolean
function M.hoverGiveUp(turns)
    return turns > GIVE_UP_TURNS
end

-- What a ledger-tab change does to the bed travel: on the map tab, arm the map hook and start the
-- hover ("map"); on another tab or a close, stop the hover, and close an open bed window ("clear").
---@param isMap boolean the ledger now shows the map tab
---@param pending boolean the bed window is open
---@return "map"|"clear"|"stop"
function M.onLedgerTab(isMap, pending)
    if isMap then return "map" end
    if pending then return "clear" end
    return "stop"
end

return M
