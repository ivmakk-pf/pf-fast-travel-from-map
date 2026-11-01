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

-- The gold of a selected fast-travel icon: the tint of the Pressed brush of its button, which the
-- game shows while the point is the target of the travel window (read in game, build 26265449).
local SELECTED_COLOR = { R = 0.64, G = 0.31, B = 0, A = 1 }

-- The bed icon tint: the gold while the travel window shows the bed, else the hover look.
---@param hovered boolean
---@param selected boolean
---@return table color an FLinearColor
function M.iconColor(hovered, selected)
    if selected then return SELECTED_COLOR end
    return M.hoverColor(hovered)
end

-- True when a change of the travel window's destination still shows the bed: the mod's own bed
-- window. Any other change (a fast-travel point, no destination) ends the golden look.
---@param hasDestination boolean
---@param name string? the destination name, nil when it cannot be read
---@param bedName string the destination name of the mod's bed window
---@return boolean
function M.isBedSelection(hasDestination, name, bedName)
    return hasDestination == true and name == bedName
end

-- The hover poll runs each 50 ms while the map tab is open, and looks the icon up at each turn: the
-- map makes its icons again (after a travel, and when it updates its markers).
local GIVE_UP_TURNS = 20 -- the poll ends after 1 s of turns with no icon

-- True when the icon of this turn is not the icon of the turn before (by address).
---@param previousAddress integer?
---@param address integer?
---@return boolean
function M.iconChanged(previousAddress, address)
    return previousAddress ~= address
end

-- The count of consecutive turns with no icon: a found icon sets it back to 0.
---@param previous integer
---@param found boolean
---@return integer
function M.missTurns(previous, found)
    if found then return 0 end
    return previous + 1
end

-- True when the consecutive turns with no icon end the poll.
---@param missTurns integer
---@return boolean
function M.hoverGiveUp(missTurns)
    return missTurns > GIVE_UP_TURNS
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
