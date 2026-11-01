-- The hover look of the bed icon on the open map: a poll reads IsHovered of the icon and sets its
-- tint on a change, only while the map tab is open. A new start or a stop ends the poll of the run
-- before. Runs on the local machine.
local logic = require("ftm.bed_travel.logic")

local M = {}

local HOVER_MS = 50

local ctx = nil ---@type FtmContext
local state = { run = 0, icon = nil } ---@type { run: integer, icon: UMapMarkerWidgetBase? }

---@class BedHoverPoll
---@field turns integer
---@field hovered boolean? the hover state of the last turn
---@field findIcon fun(turn: integer): UMapMarkerWidgetBase? a valid bed icon, or nil

-- One object can come back as different Lua values, so objects compare by address.
local function addressOf(obj)
    if obj == nil then return nil end
    return ctx.try(function()
        return obj:GetAddress()
    end)
end

-- Sets the icon back to the game's white. A failure must not stop the ledger-close cleanup.
local function restoreIcon(icon)
    -- A call on a destroyed object can crash the game, and pcall does not catch that.
    if icon == nil or not ctx.valid(icon) then return end
    ctx.try(function()
        icon:SetIconColor(logic.hoverColor(true))
    end)
end

---@param poll BedHoverPoll
local function lookUp(poll)
    local icon = poll.findIcon(poll.turns)
    if addressOf(icon) ~= addressOf(state.icon) then
        poll.hovered = nil
        restoreIcon(state.icon)
    end
    state.icon = icon
end

---@param poll BedHoverPoll
local function turn(poll)
    poll.turns = poll.turns + 1
    local hasIcon = state.icon ~= nil and ctx.valid(state.icon)
    if logic.hoverTurn(poll.turns, hasIcon) == "find" then lookUp(poll) end
    local icon = state.icon
    if icon == nil then
        if logic.hoverGiveUp(poll.turns) then state.run = state.run + 1 end
        return
    end
    local hovered = icon:IsHovered() == true
    local color = logic.hoverChange(poll.hovered, hovered)
    if color then
        icon:SetIconColor(color)
        if poll.hovered ~= nil then ctx.trace(hovered and "bed hover on" or "bed hover off") end
    end
    poll.hovered = hovered
end

function M.stop()
    state.run = state.run + 1
    local icon = state.icon
    state.icon = nil
    if ctx then restoreIcon(icon) end
end

---@param context FtmContext
---@param findIcon fun(turn: integer): UMapMarkerWidgetBase? a valid bed icon, or nil
function M.start(context, findIcon)
    ctx = context
    M.stop()
    local run = state.run
    local poll = { turns = 0, hovered = nil, findIcon = findIcon } ---@type BedHoverPoll
    LoopAsync(HOVER_MS, function()
        if run ~= state.run then return true end
        ExecuteInGameThread(function()
            if run ~= state.run then return end
            local ok, err = pcall(turn, poll)
            if not ok then
                state.run = state.run + 1
                ctx.warnOnce("bed hover", "bed hover: " .. tostring(err))
            end
        end)
        return false
    end)
end

return M
