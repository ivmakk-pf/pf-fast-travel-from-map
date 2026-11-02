![version](https://img.shields.io/badge/version-1.1.1-blue) ![coverage](https://img.shields.io/badge/coverage-98%25-brightgreen)

# Fast Travel From Map

Fast travel from the map, wherever you are.

To fast travel, you must first walk to a fast-travel point, and your bed is never a travel target: after a long trip, you walk home. With this mod, open the map (M) anywhere, click an unlocked fast-travel point or your bed, and confirm.

## Features

- **Fast travel**: the map (M) shows your unlocked fast-travel points, the same as the map of a fast-travel point. Click one to open the game's travel window, then confirm. Locked points stay locked.
- **Bed travel**: click your claimed bed on the map to travel to it. The bed icon lights up under the mouse and turns gold while its travel window is open, as a fast-travel point does.
- **The game's own travel**: each trip uses the game's travel window, screen fade, and loading of the area.

## Save safety

The mod stores nothing in your save, so you can remove it at any time.

## Multiplayer

Tested only in single player. Each player can install it or not: it changes only your own map. A player with the mod can travel also when the host does not have it. In co-op, the bed travel of a client can do nothing when the bed is far away.

## Requirements

- Permafrost (Early Access), the update of 30 October 2026 or later.
- [UE4SS for Permafrost](https://www.nexusmods.com/permafrost/mods/42), the UE4SS build that the mod is tested with.

## Installation

1. Install [UE4SS for Permafrost](https://www.nexusmods.com/permafrost/mods/42).
2. Extract this mod's zip into the game folder (the folder with Permafrost.exe). The mod lands in Permafrost\Binaries\Win64\ue4ss\Mods. Full path example for Steam:
   `C:\Program Files (x86)\Steam\steamapps\common\Permafrost\Permafrost\Binaries\Win64\ue4ss\Mods\FastTravelFromMap`

## Uninstall

Delete the `FastTravelFromMap` folder from the `ue4ss\Mods` folder.

## Configuration

To change mod settings, edit `ue4ss\Mods\FastTravelFromMap\config.lua` while the game is closed (see [CONFIG.md](CONFIG.md) for every setting). Changes apply at the next game start.

## Development

The code of each feature is in `Scripts/ftm/<feature>/`: `feature.lua` talks to the game, and `logic.lua` is game-free. The specs in `tests/` run with [busted](https://lunarmodules.github.io/busted/) on Lua 5.4, with fake UE4SS globals (`tests/fakes.lua`). They need the rocks `busted` and `luafilesystem` (and `luacov` for the coverage). From the repo root:

```
busted
busted --coverage
```

`./package.ps1` makes the install zip in `dist/`.

## License

Licensed under the GNU General Public License v3.0. Copyright (C) 2026 ivmakk.

Do not reupload this mod or a changed copy without credit and a link to this repository.
