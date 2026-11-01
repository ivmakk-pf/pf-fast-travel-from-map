-- The hover look of the bed icon on the open map: a poll reads IsHovered of the icon and sets its
-- tint on a change, only while the map tab is open. A new start or a stop ends the poll of the run
-- before. Runs on the local machine.
-- The poll keeps no widget between turns: the map makes its marker widgets again, and a kept
-- widget can be freed while IsValid still reads true (a call on it crashes the game). Each turn and
-- the stop look the icon up again from the UI manager.
local logic = require("ftm.bed_travel.logic")

local M = {}

local HOVER_MS = 50

local ctx = nil ---@type FtmContext
-- findIcon and poll are set from a start to the next stop, so a stop with no poll looks nothing up.
-- selected: the travel window shows the bed (the gold look), until the next select(false) or stop.
local state = { run = 0, findIcon = nil, poll = nil, selected = false } ---@type { run: integer, findIcon: BedIconFinder?, poll: BedHoverPoll?, selected: boolean }

---@alias BedIconFinder fun(ui: any): (UMapMarkerWidgetBase?, integer?) the valid bed icon and the marker count

---@class BedHoverPoll
---@field ui any the UI manager of the ledger
---@field turns integer
---@field misses integer the consecutive turns with no icon
---@field hovered boolean? the hover state of the last turn
---@field color table? the color that the poll set last on this icon
---@field address integer? the address of the icon of the last turn
---@field lastIcon integer? the address of the last icon found, kept over turns with no icon
---@field ms number the total turn time in ms (os.clock has 1 ms steps in UE4SS)
---@field slow integer the turns that read 1 ms or more
---@field markers integer? the marker count of the last walk

-- Logs the end of the poll once (verbose only): the numbers of the cost budget.
local function finish()
    local poll = state.poll
    state.poll = nil
    if poll == nil then return end
    ctx.trace(
        string.format(
            "bed hover end: %d turns, %.0f ms total, %d turns of 1 ms or more, %s markers",
            poll.turns,
            poll.ms,
            poll.slow,
            tostring(poll.markers)
        )
    )
end

local function addressOf(obj)
    if obj == nil then return nil end
    return ctx.try(function()
        return obj:GetAddress()
    end)
end

-- The valid bed icon of this call, or nil, and the marker count of the walk.
---@param findIcon BedIconFinder
---@return UMapMarkerWidgetBase?, integer?
local function iconOf(findIcon, ui)
    local icon, markers = findIcon(ui)
    if icon ~= nil and ctx.valid(icon) then return icon, markers end
    return nil, markers
end

-- A new icon resets the hover state. A new icon in place of an earlier one is the path of the
-- 1.0.0 crash, so it gets a trace for the in-game check.
---@param poll BedHoverPoll
local function follow(poll, address)
    if not logic.iconChanged(poll.address, address) then return end
    poll.address = address
    poll.hovered = nil
    poll.color = nil
    if address == nil then return end
    if poll.lastIcon ~= nil and poll.lastIcon ~= address then ctx.trace("bed icon changed") end
    poll.lastIcon = address
end

---@param poll BedHoverPoll
local function turn(poll)
    poll.turns = poll.turns + 1
    local icon, markers = iconOf(state.findIcon, poll.ui)
    poll.markers = markers
    poll.misses = logic.missTurns(poll.misses, icon ~= nil)
    follow(poll, addressOf(icon))
    if icon == nil then
        if logic.hoverGiveUp(poll.misses) then
            state.run = state.run + 1
            finish()
        end
        return
    end
    local hovered = icon:IsHovered() == true
    if poll.hovered ~= nil and hovered ~= poll.hovered then ctx.trace(hovered and "bed hover on" or "bed hover off") end
    poll.hovered = hovered
    -- The colors are constant tables, so a compare by identity finds a change.
    local color = logic.iconColor(hovered, state.selected)
    if color ~= poll.color then
        icon:SetIconColor(color)
        poll.color = color
    end
end

-- The gold look while the travel window shows the bed. The next turn sets the color.
---@param on boolean
function M.select(on)
    state.selected = on == true
end

-- Ends the poll. With a valid UI manager, sets the bed icon of this call back to the game's white.
-- With no UI manager (a map load), it only ends the poll and touches no object.
---@param ui any?
function M.stop(ui)
    state.run = state.run + 1
    state.selected = false
    finish()
    local findIcon = state.findIcon
    state.findIcon = nil
    if findIcon == nil or not ctx.valid(ui) then return end
    -- A failure must not stop the ledger-close cleanup.
    ctx.try(function()
        local icon = iconOf(findIcon, ui)
        if icon ~= nil then icon:SetIconColor(logic.hoverColor(true)) end
    end)
end

---@param context FtmContext
---@param ui any the UI manager of the ledger
---@param findIcon BedIconFinder
function M.start(context, ui, findIcon)
    ctx = context
    M.stop(ui)
    state.findIcon = findIcon
    local run = state.run
    local poll = { ui = ui, turns = 0, misses = 0, ms = 0, slow = 0 } ---@type BedHoverPoll
    state.poll = poll
    LoopAsync(HOVER_MS, function()
        if run ~= state.run then return true end
        ExecuteInGameThread(function()
            if run ~= state.run then return end
            local started = os.clock()
            local ok, err = pcall(turn, poll)
            local ms = (os.clock() - started) * 1000
            poll.ms = poll.ms + ms
            if ms >= 1 then poll.slow = poll.slow + 1 end
            if not ok then
                state.run = state.run + 1
                ctx.warnOnce("bed hover", "bed hover: " .. tostring(err))
            end
        end)
        return false
    end)
end

return M
