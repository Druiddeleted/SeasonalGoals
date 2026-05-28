# Changelog

## 0.1.0 — Initial release

First public release. Covers tier transmog tracking for all 13 classes at all
4 raid difficulties (LFR / Normal / Heroic / Mythic).

### Main grid
- 13 × 9 grid (one column per class, one row per tier slot).
- Cell state: collected ✓, catalyzable now !, have item but no charges •,
  missing ✗, no data —.
- Bottom "Charges" row shows current catalyst currency per class (max across
  all enabled characters of that class), with per-character breakdown on hover.
- Hover any class icon for a progress summary (collected / catalyzable /
  missing counts at that class's target difficulty).
- Click an actionable cell to open the detail panel: per-character item
  listing with icon, full game-tooltip on hover (enchants/gems/etc.),
  track + rank, "would catalyze to X" or "needs +N ranks" hint, and a
  per-item exclude/include toggle.

### Multi-character
- All state aggregated per-class across every character on the account.
- Per-character item state captured by a bag + equipped scan on relevant
  events (login, bag update, equipment change, item upgrade).
- Items whose entire contribution set is collected get pruned automatically
  so per-character storage stays bounded as the season fills out.

### Configuration
- Per-class enable/disable (hide classes you don't care about).
- Per-class target difficulty (LFR / Normal / Heroic / Mythic).
- Column-sort modes: default, name A→Z / Z→A, armor weight Plate→Cloth /
  Cloth→Plate.
- Resizable cells via a slider in config and a drag-grip on the main window.
- Window positions and sizes persist across sessions.

### Accessibility
- Every cell carries a glyph (white-with-black-outline texture) in addition
  to its color, so state is readable in any palette including monochrome.
- Palette presets: Default, Deuteranopia, Protanopia, Tritanopia, Monochrome.

### Other
- Minimap button (toggleable in config). Left-click toggles the grid,
  right-click opens config, drag repositions around the ring.
- Visual-cache layer: account-wide collection state cached per source ID,
  trusted-forever-within-a-season once positive, recomputed on relevant
  events for negative entries. Avoids redundant API calls.
- Coalesced refresh: rapid event bursts (bag update + transmog learn +
  currency tick in the same frame) collapse to one recompute via
  `C_Timer.After(0, ...)`.

### Slash commands
- `/sg` — toggle the main grid
- `/sg config` — open the config window
- `/sg refresh [class]` — clear the visual cache (all, or just one class)
- `/sg help` — list commands

### Known caveats
- Tooltip parsing is English-locale only for now (looks for the standard
  "Track Rank/Max" upgrade-level line).
- Detail panel currently re-renders rows on every external event; works fine
  but isn't pooled.
- One known data quirk in monk heroic legs uses a Blizzard-side variant
  source ID; documented inline in `src/data_season.lua`.
