-- Fast travel: the normal map (M) shows the fast-travel points and lets the player travel to an
-- unlocked one, through the game's own fast-travel map state.
-- Runs on the local machine: the ledger-tab hook is a UI hook of the player.
local logic = require("ftm.fast_travel.logic")
local ledgerTab = require("ftm.ledger_tab")

local M = {}

-- The map context that the game sets for the map of a fast-travel point; it lets the map draw and
-- select the fast-travel markers. The game clears it when the ledger closes.
local FAST_TRAVEL_CONTEXT = "WorldMap.Context.FastTravel"

local ctx = nil ---@type FtmContext

---@param ui UBPC_UserInterfaceManager_C
---@param tab integer
local function fastTravelOnLedgerTab(ui, tab)
    if not logic.isMapTab(tab) or not ctx.valid(ui) then return end
    ui:AddWorldMapContext({ TagName = FName(FAST_TRAVEL_CONTEXT) })
    ctx.trace("context added")
end

---@param context FtmContext
function M.install(context)
    ctx = context
    ledgerTab.listen(ctx, "fast travel ledger tab", fastTravelOnLedgerTab)
end

return M
