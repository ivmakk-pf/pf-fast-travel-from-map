# Copilot code-review instructions

This repo is a UE4SS Lua mod for *Permafrost*, a co-op Unreal Engine 5.4 game. The mod runs in UE4SS (Lua 5.4): it hooks game UFunctions with `RegisterHook`, watches new objects with `NotifyOnNewObject`, and reads and writes UObject properties at runtime. Review with these traps in mind; a general Lua review misses most of them.

## This mod

FastTravelFromMap has two features, each with an on/off key in `config.lua`. The code of a feature is in `Scripts/ftm/<feature>/`: `feature.lua` talks to the game, `logic.lua` is game-free and tested (the `*_logic.lua` rule below means these files). The shared helpers (log, warn once, guard, hook registration, config) are in `Scripts/ftm/core/`.

- **Ledger tab hook (shared).** `Scripts/ftm/ledger_tab.lua` registers the Blueprint hook `BPC_UserInterfaceManager_C:UpdateOnLedgerTabToggled` once, after `NotifyOnNewObject` of `/Script/Permafrost.UI_ManagerComponent` sees the first UI manager (deferred with `ExecuteInGameThread`). It calls each listener on a ledger open, tab change, or close. The map tab is the `ELedgerTab` value 4.
- **Fast travel.** On the map tab, `AddWorldMapContext` with the tag `WorldMap.Context.FastTravel`: the same context that the game sets for the map of a fast-travel point. The game's own fast-travel widgets, confirmation window, and travel then do the rest. The game clears the context when the ledger closes.
- **Bed travel.** A post hook of the Blueprint `UW_Journal_WorldMap_C:OnMouseButtonDown` (registered at the first map-tab open) opens the game's confirmation window with the name "Bed" when a left press hits the bed icon (`IsHovered`). Pre hooks of the native `Widget_WorldMap:HandleFastTravelConfirmationConfirmed` and `HandleFastTravelConfirmationCancelled` (registered at install, required) act on the confirm or cancel. The confirm closes the ledger and calls the player controller's `TeleportToLocation` (the game's fade and world streaming) with the claimed bed location.
- **Bed icon hover.** `Scripts/ftm/bed_travel/hover.lua` polls the bed icon each 50 ms with `LoopAsync`, only while the map tab is open, and sets its tint on a change. Each turn runs in `ExecuteInGameThread`. A new start or a stop ends the poll before it (a run counter).
- **Local only.** Every hook is a UI hook of the local player. The travel goes through the game's own server RPCs (`SERVER_TransitTo`, `Server_TeleportToLocation`), so a client with the mod can travel with a host without it. Flag code that needs the host to run the mod.

Invariants:

- **The fast-travel window and the bed window are one widget.** `HasSelectedFastTravelDestination()` of the world map manager tells them apart: with a selected fast-travel point the confirm is the game's own travel, and the mod only clears its pending flag. Flag a change that can teleport to the bed while a fast-travel point is selected.
- **The pending flag clears** on a cancel, on a confirm, and on a ledger close or tab change (which also collapses the window). Flag a path that can leave it set, so that a later confirm travels to the bed.
- **No travel without a target.** The target is `BedRespawnLocation`, else the respawn point actor location; when both are zero, no teleport.
- **Map markers are rebuilt.** After a travel the map makes new marker widgets while the old ones stay valid for a while, so the bed icon is looked up again by its marker key (the name of the respawn point actor), never kept across map opens.
- **`FindFirstOf` only once** for each map-tab open, at the first poll turn, and only without a cached map widget. Flag any other `FindFirstOf` or `FindAllOf` in the poll.
- **Restore the icon color.** A stop or an icon change sets the old icon back to white, after an `IsValid()` check.

## UE4SS traps

- **Object life.** A UObject can be destroyed at any time. Flag a stored object reference that is used without an `IsValid()` check.
- **Hook callbacks must not break the game.** Each callback body runs in `pcall`, and an error logs once. Flag a callback without `pcall`, and a log call in a per-call path with no once-only guard.
- **Blueprint hooks.** A Blueprint UFunction (`/Game/...`) exists only after its asset loads. Flag a `RegisterHook` on a `/Game/` path at mod start with no retry or load hook.
- **Full paths.** `RegisterHook` and `NotifyOnNewObject` need the full path (`/Script/Permafrost.Class:Function`, `/Game/.../BP_X.BP_X_C`). Flag a short class name.
- **Parameters.** Hook parameters are `RemoteUnrealParam`: read with `:get()`, write with `:set()`. Flag a direct use of the parameter as a value.
- **New objects.** The properties of an object from `NotifyOnNewObject` are not set at the callback. Flag a property read in that callback with no deferral.
- **Game thread.** Key bind and `LoopAsync` callbacks run outside the game thread. Flag UObject work there that is not inside `ExecuteInGameThread`.
- **Native crashes.** `pcall` does not catch a native crash. Flag a read of a whole struct or of soft object fields when the code needs only one field.
- **The Lua `debug` library.** Flag a local named `debug`, `print`, or another standard name that hides a library.

## Multiplayer

- **Side.** A `SERVER_` function body, `AUTHORITY_` functions, and inventory grants run on the host. Flag code that changes shared state (damage, loot, inventory) on a client, and host logic with no `HasAuthority()` check where both sides run the code.
- **Multiplayer kind.** The README states who must install the mod (Local only, Host, Every player). Flag a change that moves code to the other side without a README update.

## Performance

- Flag `FindAllOf`, `FindFirstOf`, `StaticFindObject`, string building, or table building in a tick hook, a `LoopAsync` with a short interval, or a hook of a function that runs often.

## Compatibility

- The mod must work with the vanilla game and with the mods named in the README. Flag a write of a game property that another named mod also writes, and an inventory grant that bypasses the game's own pickup path.

## Structure and tests

- **Pure logic is separated and tested.** Logic that does not need the running game lives in a `*_logic.lua` file with no UE4SS global and no UObject, tested under `tests/`. Flag new pure logic in a hook callback, and new pure logic with no test.
- **One function for each hook target,** named `<feature>On<Target>`.

## Release and config hygiene

- **Verbose ships off.** The `verbose` default is `false`. Debug lines go behind it; without it only the load line, warnings, and errors log.
- **The mod folder name never changes.** It is the `ue4ss\Mods\` folder and the home of the player's `config.lua`. Flag any rename.
- **The config file belongs to the player.** The mod writes `config.lua` only when it is missing. Flag code that overwrites it, and a `config.lua` in the repo or the zip.
- **The version** is the `VERSION` constant in `Scripts/main.lua`, printed in the load line.
- **No committed package output.** Flag `dist/` or a zip in the diff.
- **No game content.** Flag a header pasted from the UE4SS dump or an extracted game asset.
- **Changelog matches the change.** A player-visible change adds an `[Unreleased]` entry to `CHANGELOG.md` in player-facing wording. An internal-only refactor gets none.
