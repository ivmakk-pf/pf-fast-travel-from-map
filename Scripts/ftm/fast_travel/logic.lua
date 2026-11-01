-- Game-free logic of the fast travel of FastTravelFromMap: no UE4SS global, no UObject.
local M = {}

-- The game's ELedgerTab value of the map page.
M.MAP_TAB = 4

-- True when the ledger now shows the map page.
---@param tab any the CurrentTab of the ledger tab change
---@return boolean
function M.isMapTab(tab)
    return tab == M.MAP_TAB
end

return M
