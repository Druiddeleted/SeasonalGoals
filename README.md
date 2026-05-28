# Seasonal Goals

Tracks per-character progress toward seasonal goals across your account. The
first (and currently only) goal type is **tier set transmog**: for each class
and slot, are you wearing/holding an item that could catalyze into the target
difficulty's appearance — and have you actually collected the appearance yet.

## Status

Pre-alpha scaffold. The UI currently shows fake data so the layout can be
iterated on; the scanner and `/sg discover` season-bootstrap command are stubs.

## Slash commands

- `/sg` — toggle the main window
- `/sg discover` — (stub) dump the current season's tier set appearance IDs and
  catalyst currency ID for pasting into `src/data_season.lua`

## How seasonal data gets refreshed

Each new raid tier ships a new tier set with new appearance IDs and a new
catalyst currency. At season start, log in on one character of each class and
run `/sg discover`; paste the dumped table into `src/data_season.lua` and
commit. From then on the addon just reads from that file.
