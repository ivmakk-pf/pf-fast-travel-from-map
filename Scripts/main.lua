-- FastTravelFromMap: travel from the normal map (M). Features: the fast travel to an unlocked
-- fast-travel point, and the travel to the player's claimed bed.
local MOD = "FastTravelFromMap"
local VERSION = "1.0.0"

local SCHEMA = require("ftm.core.schema")

-- Features: { config switch, module, name in the load line }. A failed install turns off only its feature.
local FEATURES = {
    { switch = "fast_travel", module = "ftm.fast_travel.feature", name = "fast travel" },
    { switch = "bed_travel", module = "ftm.bed_travel.feature", name = "bed travel" },
}

---@param ctx FtmContext
---@return table<string, boolean> installed the result of each feature, by its switch
local function installFeatures(ctx)
    local installed = {}
    for _, feature in ipairs(FEATURES) do
        if ctx.config[feature.switch] then
            local ok, err = pcall(function()
                require(feature.module).install(ctx)
            end)
            installed[feature.switch] = ok
            if not ok then
                ctx.warnOnce(feature.module, feature.name .. " not installed (a game change?): " .. tostring(err))
            end
        end
    end
    return installed
end

---@param installed table<string, boolean>
---@return string
local function loadLine(installed)
    return string.format(
        "v%s loaded (fast travel %s, bed travel %s)",
        VERSION,
        installed.fast_travel and "on" or "off",
        installed.bed_travel and "on" or "off"
    )
end

local ctx = require("ftm.core.context").new(MOD)
ctx.config = require("ftm.core.config_file").load(SCHEMA, ctx.log)
ctx.log(loadLine(installFeatures(ctx)))
