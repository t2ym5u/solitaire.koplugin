# Changelog

All notable changes to this project will be documented in this file.

Reconstructed from this repository's git history: each release lists the
feature and fix commits it carried. Version bumps, screenshot additions
and CI syncs are left out.

## [1.0.13] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.0.12] - 2026-08-05

### Added
- Add ES and DE translations

### Changed
- Add issue/PR templates and CONTRIBUTING.md

## [1.0.11] - 2026-08-04

### Changed
- Symlink common/ to shared game-common (identical content)

### Fixed
- Clamp status text to available width

## [1.0.9] - 2026-07-31

### Fixed
- Shrink and split corner rank/suit labels, unify centered suit glyph size

## [1.0.8] - 2026-07-29

### Fixed
- Grow tableau widget to fit the worst-case 13-card fan; shrink stock/waste/foundation suit glyph

## [1.0.7] - 2026-07-29

### Fixed
- Drop deprecated name field from _meta.lua

## [1.0.4] - 2026-07-28

### Changed
- Add GPL-3.0 LICENSE
- Add README

## [1.0.1] - 2026-07-21

### Added
- Taller landscape board, double-tap to foundation, red/black clarity
