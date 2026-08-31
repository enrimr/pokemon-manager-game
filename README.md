# Trainer Manager

**Football Manager, but for Pokémon battles and tournaments.** A deep management sim built in Godot 4.6: run a club of Pokémon across two leagues, set battle tactics, play matches turn by turn (or delegate them), work the transfer market, develop youth prospects, survive the board — and get sacked if you don't.

Every screen was iterated against a harsh bar: blind, fresh-context reviewers compared each one side-by-side with Football Manager 2024's equivalent and sent it back until ours won.

## Features

- **Two leagues, real seasons** — Kanto League and Johto League (16 clubs each), a cross-league Indigo Cup, a Championship Series playoff between both leagues' top four, end-of-season awards, an honours history, and full multi-season rollover (aging, contracts, fresh fixtures).
- **Playable battles** — a deterministic 6v6 engine with all 251 gen 1–2 species, 25 natures, 48 functional abilities, weather, held items and battle consumables. Play every turn yourself (moves, switches, items — including 2v2 doubles with real targeting rules in cup ties), or watch the live viewer with commentary, momentum graph and touchline instructions, or instant-sim it.
- **Management depth** — FM-style squad views (custom column editor), tactics with role suitability and type-coverage analysis, staged scouting with travel days and knowledge levels, multi-clause transfer negotiations, training schedules, mentoring, move learning, **evolutions with manager approval**, a youth academy with monthly intake days, an item shop/economy, board confidence, ultimatums and a real sacking arc with continue-at-another-club.
- **A living inbox** — match reports, scout dossiers, rival manager mind-games with persistent personas, pledges that are tracked and called in, board requests, season digests.
- **Product polish** — main menu + onboarding (create your manager, pick a club with board-expectation previews), procedural original audio (reactive match SFX, crowd, music), resolution-independent UI, settings screen, full **English + Spanish** localization with live switching, autosaves.

No copyrighted assets: the visual identity is type colors, monograms and data density; all audio is procedurally generated. This is a non-commercial fan project — Pokémon and its names are trademarks of Nintendo/Creatures/Game Freak.

## Running

Requires [Godot 4.6](https://godotengine.org). From the repo root:

```sh
godot --path .          # macOS: /Applications/Godot.app/Contents/MacOS/Godot --path .
```

Useful flags/env vars:

| Flag | Effect |
|---|---|
| *(none)* | Normal launch: title screen → continue / new career |
| `--quickstart` or `TM_QUICKSTART=1` | Skip the menu, boot straight into a career (testing) |
| headless (`--headless`) | Always direct-boots; locale pinned to `en` for deterministic tests |

Prebuilt binaries for macOS, Windows, Linux and Web land in `dist/` via `scripts/export_all.sh` (needs Godot export templates installed).

## Development

```sh
bash scripts/smoke.sh        # headless boot + full sim check (engine determinism,
                             # season boundary, save/load) — must print SMOKE OK
bash scripts/export_all.sh   # rebuild all four platform exports into dist/
```

Screenshot harness (used by automated reviewers, handy for debugging):

```sh
godot --path . res://tools/screenshots.tscn -- --screens=all --out=artifacts/shots [--size=1920x1080]
```

- **`docs/ARCHITECTURE.md`** — data schemas, battle engine API, season/services conventions, file-ownership map, items/evolutions/settings contracts.
- **`docs/TESTING.md`** — the direct-boot contract, harness usage, dev drivers, per-piece self-tests.

Screens are discovered by convention: any `res://screens/<name>/screen.tscn` + `screen.json` appears in the sidebar. Daily-tick systems drop a script into `res://shared/sim/services/` and get lifecycle + save/load hooks automatically.

Saves live in Godot's user dir (`user://save.json`, `user://settings.json`).
