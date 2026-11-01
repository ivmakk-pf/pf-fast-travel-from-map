-- The one source of the config keys, defaults, ranges, and comments.
-- Its own file, so the tests can read it without the UE4SS globals of main.lua.
---@type ConfigEntry[]
return {
    {
        key = "fast_travel",
        default = true,
        comment = "The normal map (M) shows the fast-travel points and lets you travel to an unlocked one.",
    },
    {
        key = "bed_travel",
        default = true,
        comment = "A left click on your claimed bed on the normal map (M) lets you travel to the bed.",
    },
    { key = "verbose", default = false, comment = "Extra log lines in UE4SS.log. Keep off in normal play." },
}
