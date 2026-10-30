# Changelog

All notable changes to this project will be documented in this file.

Reconstructed from this repository's git history: each release lists the
feature and fix commits it carried. Version bumps, screenshot additions
and CI syncs are left out.

## [1.2.0] - 2026-10-30

### Added
- Four more patience games, picked from the new **Game** menu entry; Klondike
  stays the default and each game keeps its own game in progress:
  - **FreeCell**: 4 free cells, supermoves limited to (free cells + 1) x
    2^(empty columns), Microsoft-compatible deal numbers 1-32000 with
    **Choose deal** (verified against deal #1).
  - **Spider**: 1, 2 or 4 suits; a row is dealt only when no column is empty;
    complete King-to-Ace runs of one suit go to the foundation by themselves.
    Face-down cards are drawn as thin edges and long columns squeeze to fit.
  - **Golf**: 7 columns of 5, play onto the waste one rank up or down;
    optional King-Ace wrap. Lost when the stock is out and nothing fits.
  - **Pyramid**: remove pairs adding up to 13 and lone Kings; 1, 2, 3 or
    unlimited passes through the stock. Covered cards are greyed out.
- **Statistics**: games played and won per game (Spider per suit count).
- A lost Golf or Pyramid game offers Undo next to New game.

### Changed
- The title bar shows the game being played ("Klondike" rather than
  "Solitaire").
- The status line's "Draw:" shows the draw count of the game in progress,
  which may differ from the setting for a resumed game.
- Card drawing moved to a shared widget base; a Klondike column longer than
  13 cards now squeezes instead of running past the board.

### Compatibility
- Klondike saves from earlier versions (no game tag) still load, under the
  same settings key.

## [1.1.0] - 2026-10-30

### Changed
- Redesigned play screen: Undo and Auto-complete moved from the title-bar
  menu to a full-width action bar under the board, since they are used during
  play. The cards are as large as the room allows while still fitting a full
  13-card column.
- The title-bar menu shows "Draw: 1" / "Draw: 3" (was "Draw 1"), in the same
  order as every other game: New game, Draw, Rules.
- The status line reads "Draw: 1 · Moves: 42 · Foundations: 12/52" and wraps
  in landscape instead of being cut off.
- A selected card gets a thick black outline (a light grey one read as
  thinner than the edge of an unselected card).
- The rules now mention double-tap to send a card to its foundation, Undo and
  Auto-complete.
- Once the game is won, the action bar shows "New game" in place of Undo and
  Auto-complete.

### Fixed
- Card labels were sized from the card width and then scaled again for the
  screen's DPI; the rank now fits the strip left visible on a fanned card on
  every screen.

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
