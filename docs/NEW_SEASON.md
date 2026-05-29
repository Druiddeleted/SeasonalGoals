# New-season data refresh

Everything the addon shows is per-season data. When a new raid tier / M+ season
launches, the maintainer refreshes it once and ships an update — end users just
update the addon (no per-user setup).

Some data is **auto-captured** by the in-game dev tooling; some is **hand-maintained**
from Wowhead / the in-game Adventure Guide because no stable client API exposes it.

| Data | File / table | How |
|---|---|---|
| Tier appearances (the grid) | `src/data_season.lua` → `NS.Season.appearances` | auto: `/sg discover all` |
| Season name + catalyst currency | `src/data_season.lua` → `NS.Season.name`, `.catalystCurrency` | hand |
| Tier-token boss sources + curio | `src/data_sources.lua` → `tierTokens` | hand |
| Accessory boss sources (optional) | `src/data_sources.lua` → `byClass` / `byArmor` | hand |
| Convertible feeder items | `src/data_feeders.lua` → `NS.Sources.feeders` | auto: `/sg discover feeders` + script |

## 0. Prep

- Log in on a character, run `/sg devmode on` (enables the `/sg discover …` tooling;
  it's hidden from `/sg help` otherwise and persists in SavedVariables).
- Open the **Adventure Guide (Shift-J)** and browse the new raids and the
  **Current Season** dungeon category once — some captures read better when the
  Journal has been opened. `/sg discover all` also needs the account to have the
  new tier sets available in the wardrobe (browse Appearances if a class comes up
  missing).

## 1. Tier appearances — `data_season.lua` (auto)

1. `/sg discover all` — opens a copyable dump with one `["CLASSFILE"] = { … }`
   block per class.
2. Replace the `NS.Season.appearances` table in `src/data_season.lua` with the
   emitted blocks.
3. Update `NS.Season.name` (e.g. `"Midnight Season 2"`) and confirm
   `NS.Season.catalystCurrency` (see step 4).

If a class is reported missing, it's usually because the account hasn't browsed
that class's tier set — view it in the wardrobe and re-run.

## 2. Tier-token boss sources + curio — `data_sources.lua` `tierTokens` (hand)

The 5 catalyzable slots (head/shoulder/chest/hands/legs) drop as **armor-type
tokens**, and a **curio** converts into any of the 5. Tokens carry no appearance,
so this can't be auto-matched — read it off the Adventure Guide / Wowhead raid
guide and fill `tierTokens`:

```lua
tierTokens = {
    head  = { "<Boss> — <Raid>", "<Curio item> — <Raid> (any tier slot)" },
    ...    -- one boss per slot, plus the curio line on all 5
}
```

The boss for a given slot is the same for every armor type (the token is shared),
so this is a single universal slot→boss map. Note which raid the **chest** token
and the **curio** come from — in S1 they were in a *different* raid than the rest.

## 3. Accessory boss sources — `byClass` / `byArmor` (hand, optional)

The 4 non-set slots (back/wrist/waist/feet) share their tier look with one class's
piece per armor type, but the tier look is a **distinct appearanceID** from the
raid drop, so appearance auto-matching does **not** work (we tried). Most are
effectively catalyst-sourced. If you know a confirmed shared-appearance drop
(e.g. "Chimaerus's leather belt = Monk waist"), add it:

```lua
byClass = { MONK = { waist = { "<Boss> — <Raid>" } }, ... }
```

Anything unmapped falls back to the catalyst note (correct). Don't guess.

## 4. Catalyst currency — `data_season.lua` `catalystCurrency` (hand)

Find the new season's catalyst currency ID and set `NS.Season.catalystCurrency`.
Verify with `/sg discover currency <id>` (prints name + quantity).

## 5. Convertible feeders — `data_feeders.lua` (auto)

1. `/sg discover feeders` — scans the Encounter Journal **Current Season** tier
   (raids + the full M+ pool, including legacy dungeons) and classifies every
   catalyzable armor piece by slot + armor type. Writes
   `SeasonalGoalsDB._devFeeders`.
2. `/reload` — flushes SavedVariables to disk.
3. Regenerate the shipped file:
   ```bash
   python3 scripts/build_feeders.py
   ```
   (Auto-finds the newest `SeasonalGoals.lua` under the retail WTF path; pass an
   explicit path as an argument otherwise.) This rewrites `src/data_feeders.lua`.

Slot + armor type come from `GetItemInfoInstant` (static item data), so the
capture is complete without force-loading. If the chat summary says
*"No 'Current Season' tier matched"*, inspect `_devFeeders.diag.tierNames`.

## 6. Ship it

1. `./sync SeasonalGoals` and `/reload` in-game; spot-check a few cells
   (hover + click) across classes/slots.
2. Bump `## Version` in `SeasonalGoals.toc`, add a `CHANGELOG.md` entry, and cut a
   release per the publishing steps in the repo-root `CLAUDE.md`
   (tag `x.y.z` / `x.y.z-alphaN`, push, watch the BigWigs packager Action).

## Notes

- SavedVariables live at
  `…/World of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/SeasonalGoals.lua`.
  The `_devDump` / `_devFeeders` keys are dev scratch space — write-only from the
  game's view, read by the maintainer's tooling, never shipped.
- `docs/` and `scripts/` are excluded from the packaged addon (see `.pkgmeta`).
