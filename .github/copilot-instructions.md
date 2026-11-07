# Copilot code-review instructions

This repo is a UE4SS Lua mod for *Permafrost*, a co-op Unreal Engine 5.4 game. The mod runs in UE4SS (Lua 5.4): it hooks game UFunctions with `RegisterHook`, watches new objects with `NotifyOnNewObject`, and reads and writes UObject properties at runtime. Review with these traps in mind; a general Lua review misses most of them.

## This mod

FastTravelFromMap has two features, each with an on/off key in `config.lua`. The code of a feature is in `Scripts/ftm/<feature>/`: `feature.lua` talks to the game, `logic.lua` is game-free and tested (the `*_logic.lua` rule below means these files). The shared helpers (log, warn once, guard, hook registration, config) are in `Scripts/ftm/core/`.

- **Ledger tab hook (shared).** `Scripts/ftm/ledger_tab.lua` registers the Blueprint hook `BPC_UserInterfaceManager_C:UpdateOnLedgerTabToggled` once, after `NotifyOnNewObject` of `/Script/Permafrost.UI_ManagerComponent` sees the first UI manager (deferred with `ExecuteInGameThread`). It calls each listener on a ledger open, tab change, or close. The map tab is the `ELedgerTab` value 4.
- **Fast travel.** On the map tab, `AddWorldMapContext` with the tag `WorldMap.Context.FastTravel`: the same context that the game sets for the map of a fast-travel point. The game's own fast-travel widgets, confirmation window, and travel then do the rest. The game clears the context when the ledger closes.
- **Bed travel.** A post hook of the Blueprint `UW_Journal_WorldMap_C:OnMouseButtonDown` (registered at the first map-tab open) opens the game's confirmation window with the name "Bed" when a left press hits the bed icon (`IsHovered`). Pre hooks of the native `Widget_WorldMap:HandleFastTravelConfirmationConfirmed` and `HandleFastTravelConfirmationCancelled` (registered at install, required) act on the confirm or cancel. The confirm closes the ledger and calls the player controller's `TeleportToLocation` (the game's fade and world streaming) with the claimed bed location.
- **Bed icon hover and gold.** A hook of the Blueprint `UW_Journal_WorldMap_C:Tick` (registered at the first map-tab open, with the press hook) calls `hover.onTick` each frame while the map shows, on the game thread. At most each 50 ms, `Scripts/ftm/bed_travel/hover.lua` checks the bed icon's `IsHovered` and sets its tint on a change: dim, white under the mouse, and the vanilla gold of a selected fast-travel point (`logic.iconColor`) while the bed window is open. The bed icon has no button and no mouse event that UE4SS can hook (an `OnMouseEnter` hook never fired), so the hover rides on the map's Tick.
- **Bed icon on top.** A post hook of the Blueprint `UW_Journal_WorldMap_C:CreateMapMarker` (registered at the first map-tab open) moves a new bed icon into `Markers_Overlay_MovingTargets` and sets its tint, in the frame that the game makes it, and ends the 1 s wait after a miss. The game makes every marker again at a change of the map contexts, so at most map opens. That overlay is above `Markers_Overlay`. `AddChildToOverlay` takes the icon out of its old panel, so the move needs no remove. A hover check also moves an icon that is not in the top overlay.
- **Bed icon lookup.** With a valid `BedRespawnPoint`, the key is the actor name. With an empty one and a set `BedRespawnLocation`, the bed marker is the one with a key that starts with `BP_RespawnPointTemplate_C` and a `TargetLocation` at the bed location. Flag a match by location alone: a player marker stands at the bed after a travel. The bed location is read only with an empty actor reference.
- **Gold on and off.** `hover.select(true)` when the mod opens the bed window; `hover.select(false)` at a cancel, a confirm, and in a pre hook of the native `Widget_WorldMap:HandleFastTravelDestinationSelectionChanged` for any destination that is not the bed (a click on a fast-travel point, a collapse). A reset clears it.
- **Local only.** Every hook is a UI hook of the local player. The travel goes through the game's own server RPCs (`SERVER_TransitTo`, `Server_TeleportToLocation`), so a client with the mod can travel with a host without it. Flag code that needs the host to run the mod.

Invariants:

- **The fast-travel window and the bed window are one widget.** `HasSelectedFastTravelDestination()` of the world map manager tells them apart: with a selected fast-travel point the confirm is the game's own travel, and the mod only clears its pending flag. Flag a change that can teleport to the bed while a fast-travel point is selected.
- **The pending flag clears** on a cancel, on a confirm, and on a ledger close or tab change (which also collapses the window). Flag a path that can leave it set, so that a later confirm travels to the bed.
- **No travel without a target.** The target is `BedRespawnLocation`, else the respawn point actor location; when both are zero, no teleport.
- **No widget reference across game-thread calls.** The map makes its marker widgets again (after a travel, at a marker update). A kept widget can be freed while `IsValid()` still reads true, and a call on it crashes the game (the 1.0.0 crash). Each hover check reads the map of its Tick hook, and the ledger-close cleanup reads the chain `ui.LedgerMenu.Panel_Map` again in the same call; both find the bed icon by its marker key (the name of the respawn point actor). The hover keeps only plain Lua values between checks (counts, the last hover state, the map and icon addresses as numbers). Flag a widget or a map stored in mod state.
- **No `FindFirstOf` or `FindAllOf`** in the Tick hook or the other hooks. The Tick hook runs each frame: its work before the 50 ms throttle is one clock compare.
- **No async work.** The hover has no `LoopAsync` and nothing to stop at a quit or a level change: the engine stops the map's Tick. A ledger close or tab change and each map load (`RegisterLoadMapPreHook`, else the post hook) reset the hover state and the gold with no object call. Flag a `LoopAsync` or a kept object in the hover.
- **The icon tint at a close.** A reset touches no object, so the icon keeps its last tint while the map is hidden; the first check after the map shows again sets it. An old icon is never touched after an icon change.

## UE4SS traps

- **Object life.** A UObject can be destroyed at any time, and `IsValid()` on a kept reference is not safe: after a garbage collection the memory can belong to a new object and still read as valid. Get an object again in each game-thread call from a live owner (a hook parameter, a property chain from a long-lived object). Flag a stored widget or actor reference that is used in a later call.
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
