-- The ledger-tab hook that the fast travel and the bed travel share: it calls each listener when
-- the ledger opens, switches tab, or closes. Runs on the local machine: a UI hook of the player.
local M = {}

local UI_MANAGER = "/Script/Permafrost.UI_ManagerComponent"
local UI_MANAGER_BP = "BPC_UserInterfaceManager_C"
local HOOK = "/Game/Permafrost/Blueprints/Components/BPC_UserInterfaceManager.BPC_UserInterfaceManager_C"
    .. ":UpdateOnLedgerTabToggled"

local ctx = nil ---@type FtmContext
local state = { watching = false, hooked = false, listeners = {} }

-- Runs after the Blueprint body: the ledger opened, switched tab, or closed.
local function onLedgerTab(self, currentTab)
    local ui = self:get() ---@type UBPC_UserInterfaceManager_C
    local tab = currentTab:get()
    for _, listener in ipairs(state.listeners) do
        listener(ui, tab)
    end
end

-- The Blueprint class is loaded once the game makes its UI manager, so the hook registers then, once.
local function onUiManager(ui)
    if state.hooked or not ctx.valid(ui) then return end
    local class = ctx.try(function()
        return ui:GetClass():GetFName():ToString()
    end)
    if class ~= UI_MANAGER_BP then
        ctx.warnOnce(
            "ui class",
            "unknown UI manager class " .. tostring(class) .. " (a game change?); the map features are off"
        )
        return
    end
    state.hooked = true
    if ctx.hook("ledger tab", HOOK, onLedgerTab) then ctx.trace("ledger tab hook armed") end
end

-- A new object is not set up yet at the watch callback, so the work waits for the game thread.
local function onNewUiManager(ui)
    ExecuteInGameThread(ctx.guard("ui manager", function()
        onUiManager(ui)
    end))
end

-- Adds a listener of the ledger tab. The first call starts the watch of the UI manager. A failed
-- watch throws and adds no listener, so the next call tries the watch again.
---@param context FtmContext
---@param key string the warning key of the listener's errors
---@param fn fun(ui: UBPC_UserInterfaceManager_C, tab: integer)
function M.listen(context, key, fn)
    ctx = context
    if not state.watching then
        NotifyOnNewObject(UI_MANAGER, onNewUiManager)
        state.watching = true
    end
    state.listeners[#state.listeners + 1] = ctx.guard(key, fn)
end

return M
