# Configuration

Every setting lives in `Permafrost\Binaries\Win64\ue4ss\Mods\FastTravelFromMap\config.lua`, written the first time you run the game with the mod installed. Edit it with any text editor while the game is closed. Changes apply at the next game start. A mod update keeps this file.

| Setting | Default | Values | What it does |
|---|---|---|---|
| `fast_travel` | `true` | `true`, `false` | The map (M) shows your unlocked fast-travel points and lets you travel to one. `false` gives the normal map. |
| `bed_travel` | `true` | `true`, `false` | A left click on your claimed bed on the map (M) lets you travel to the bed. `false` turns the bed travel off. |
| `verbose` | `false` | `true`, `false` | Writes extra lines to `UE4SS.log` for troubleshooting. Keep it off in normal play. |

A value of the wrong type applies as the default. When the game cannot read the file (for example after a typo), every setting applies as the default, and the file stays as it is.
