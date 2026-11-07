# Changelog

All notable changes to this mod are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this mod uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.2] - 2026-11-07

### Changed

- Your bed icon stays on the map when the game setting Show Location Indicators is off.

### Fixed

- A click on your bed icon opens its travel window after a fast travel too. Before, the icon could stop taking clicks.
- A click on your bed icon opens its travel window when a quest icon or a fast-travel icon overlaps it. The bed icon now stays on top.

## [1.1.1] - 2026-11-02

### Changed

- Less work while the map is open: the mod finds your bed icon by its name, not by a check of every icon on the map.
- The bed icon's hover look now updates with the map itself, only while the map is on screen. The mod no longer runs a timer in the background while the map tab is open.

## [1.1.0] - 2026-11-01

### Added

- Gold bed icon on the map while its travel window is open, as on a selected fast-travel point.

### Fixed

- Game crash when you closed the ledger, or quit the game, after the map was open.

## [1.0.0] - 2026-11-01

### Added

- Fast travel from the map (M): the unlocked fast-travel points show on the map, and a click on one opens the game's travel window.
- Bed travel: a click on the claimed bed on the map travels to it.
- `config.lua` with one on/off setting for each feature.
