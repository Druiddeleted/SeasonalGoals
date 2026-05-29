# Seasonal Goals

A grid-at-a-glance tracker for your account's seasonal tier transmog goals.

For every class and every tier slot, see whether you have the appearance
collected, whether you're holding an item that could catalyze into it, and
whether you actually have catalyst charges to do it right now — all in one
13 × 9 window with no per-character bookkeeping.

## What it tells you

Each cell shows one **state** for one (class, tier slot, target difficulty):

| Symbol | State | Meaning |
|:---:|---|---|
| ✓ | **Collected** | The account has unlocked this visual (any source counts) |
| **!** | **Catalyzable now** | Some character of this class has an item that could catalyze, AND has charges |
| **•** | **Have item — no charges** | Some character of this class has the item, but is out of catalyst charges |
| ✗ | **Missing** | No tracked character of this class has a contributing item |
| — | **No data** | We don't have shipped data for this class+slot yet |

The bottom row shows each class's current catalyst charge count (max across
all enabled characters of that class). Hover a class icon to see a per-class
progress summary; click an actionable cell to open a detail panel listing the
items, what each could catalyze to, and a per-item exclude/include toggle.

## Where to get missing items

Hover any cell that isn't collected — including red (**Missing**) cells — for a
quick "Drops from…" summary, then click it to open the detail panel's **"Where
to get this"** list: every item you can get for that look and where it drops,
grouped **Raid** and **Dungeon**.

- The **Raid** group leads with the direct tier sources — the slot's tier token,
  the curio (which converts into any tier slot), and any known matching-appearance
  accessory — followed by convertible same-slot pieces from raid bosses.
- The **Dungeon** group lists convertible same-slot pieces from the season's M+
  pool (including legacy dungeons).

Convertible pieces show as item rows — icon, name, and the boss/instance that
drops them — with a full tooltip on hover and shift-click to link in chat. This
source data ships with the addon per season.

## Multi-character

State is aggregated per-class across every character on your account:

- **Collected** is naturally account-wide (transmog appearance collection is
  account-shared in modern WoW).
- **Catalyzable / Have item** is "any enabled character of this class has it"
  — so if Warlock A holds the Hero 5 bracer and Warlock B doesn't, the
  warlock-wrist cell still goes catalyzable.
- The detail panel breaks down which character holds what, with an
  exclude/include checkbox per item GUID so you can mark "this piece is
  reserved for stats, don't count it toward the look".

## Accessibility

- **State is encoded by both color and symbol.** Even in monochrome, every
  cell carries a glyph the color can't lose.
- **Palette presets** in config: Default, Deuteranopia, Protanopia,
  Tritanopia, Monochrome. Swap from the config window.
- **Resizable cells**: the cell-size slider and the corner drag-grip both
  control how big the grid renders.
- **Window positions persist** across `/reload` and sessions.

## Slash commands

| Command | Effect |
|---|---|
| `/sg` | Toggle the main grid |
| `/sg config` | Open the config window |
| `/sg refresh [class]` | Clear the visual-cache (all classes, or just one). Accepts class names case-insensitively. |
| `/sg help` | List commands |

(Discovery and debug tools are dev-mode-gated; not surfaced to end users.)

## How catalyst-eligibility is decided

The addon scans bags + equipped slots for every character that logs in,
parses each item's track and rank from its tooltip, and stores
`(itemGUID → {track, rank, slot, …})` per-character in SavedVariables. An
item "contributes" to a (slot, difficulty) cell if its same-track upgrade
path can reach that difficulty:

| Track | Rank | Could produce |
|---|---|---|
| Veteran | 1–4 | LFR, Normal |
| Veteran | 5–6 | Normal |
| Champion | 1–4 | Normal, Heroic |
| Champion | 5–6 | Heroic |
| Hero | 1–4 | Heroic, Mythic |
| Hero | 5–6 | Mythic |
| Myth | 1–6 | Mythic |

When a visual is collected, items whose entire contribution set is now
covered get pruned automatically — storage stays bounded as you complete
the season.

## Per-season data refresh

Each new raid tier ships new appearance IDs and a new catalyst currency.
At season start the addon maintainer runs the dev-mode discover tooling
(`/sg discover all`) on one character per class and captures the appearance
data into `src/data_season.lua`. The "where to get this" data in
`src/data_sources.lua` — tier-token boss sources, feeder-content breakpoints,
and any known accessory sources — is hand-maintained from the season's gear
chart / raid guides, since it isn't exposed by a stable client API. End users
get the new tier just by updating the addon — no per-user setup.

## Installation

For now, clone into your WoW AddOns folder:

```
git clone git@github.com:Druiddeleted/SeasonalGoals.git \
  "<wow>/Interface/AddOns/SeasonalGoals"
```

CurseForge release pending project setup.

## License

[MIT](LICENSE).
