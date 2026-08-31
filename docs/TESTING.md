# Testing — Trainer Manager

Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot`
Project root: `/Users/enrique/development/projects/pokemon-manager-game`

## 1. Smoke test (headless, fast)

```sh
/Users/enrique/development/projects/pokemon-manager-game/scripts/smoke.sh
```

Runs two headless passes and exits nonzero on any failure:
1. Full game boot (`--quit-after 60`), greps output for `SCRIPT ERROR` / `ERROR`.
2. `res://tools/sim_check.tscn` — battle engine determinism + step-mode API checks,
   the items system (held-item effects fire, `use_item` actions work and cost the
   turn, Choice locks, AI item budget, determinism with items; club economy:
   buy/assign/unassign, budget enforcement, AI starting held items), a 50-day
   season fast-forward (league + cup fixtures simulated, table verified),
   and a save/load roundtrip incl. item inventories. Must print `SIM CHECK OK`.

Expected final line: `SMOKE OK`.

## 2. Screenshot harness (must run WINDOWED — headless cannot render)

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/enrique/development/projects/pokemon-manager-game res://tools/screenshots.tscn -- --screens=squad,tactics --out=artifacts/squad
```

- `--screens=` comma-separated screen folder names, or `all` for every discovered screen.
- `--out=` output directory (relative paths resolve against the project root).
- Boots the real shell + GameState (loads `user://save.json` if present, else a new career),
  navigates to each screen, waits 12 frames for layout, saves `<out>/<name>.png` at 1600x900.
- Exits `0` on success and prints `SCREENSHOTS OK`. Exits nonzero and prints
  `SCREENSHOT ERROR: ...` lines if a screen fails to load, renders black, or can't be saved.

Capture everything:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/enrique/development/projects/pokemon-manager-game res://tools/screenshots.tscn -- --screens=all --out=artifacts/all
```

### Direct-boot contract (menu piece — how testing skips the title screen)

The game's main scene is now `res://menu/title.tscn` (title menu + onboarding).
Testing tools keep booting straight into a career because the title scene
immediately swaps itself for `res://shell/main.tscn` when ANY of these hold
(`MenuFlow.quickstart()` in `res://menu/menu_flow.gd`):

- the run is **headless** (`--headless`) — covers smoke pass 1, sim_check and
  every headless driver;
- the CLI flag **`--quickstart`** is passed (before or after `--`);
- the env var **`TM_QUICKSTART`** is set (any non-empty value).

Harness scenes that instantiate `res://shell/main.tscn` themselves
(tools/screenshots.tscn, shell/picker_shots.tscn, tab_shots, drivers…) never
see the menu at all, and GameState is an autoload that boots a career
regardless of scene — so smoke, sim_check and the screenshot harness run
UNCHANGED. To boot the real windowed game without the menu:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path <project> --quickstart
```

## Notes

- To test from a fresh career, delete the save first:
  `rm -f "$HOME/Library/Application Support/Godot/app_userdata/Trainer Manager/save.json"`
- Regenerating data (foundation owner only): `python3 tools/gen_data.py`, then
  `python3 artifacts/evolutions/gen_evolutions.py` (evolution chains + stones) and
  `python3 artifacts/playtest2/gen_weather.py` (weather reachability: weather-move
  learnsets/instance moves, Drizzle Politoed / Drought Ninetales), then rerun smoke.

## 3. New-career club picker shots (shell-owned, windowed)

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/enrique/development/projects/pokemon-manager-game res://shell/picker_shots.tscn
```

Boots the real shell, opens the New Career club selector, captures both league
tabs and a career actually started at a Johto club to `artifacts/leagues/`,
then deletes the test save. Prints `PICKER SHOTS OK`.

Note: sim_check now also covers the two-league season (both championships,
cross-league Indigo Cup, per-league tables), the gen-2 type chart, the
`shared/sim/services/` auto-load convention and v1-save recovery — plus the
FULL SEASON BOUNDARY: it fast-forwards through matchday 30 (remaining league/
cup fixtures completed synthetically with valid detail stubs), verifies the
Championship Series resolves QF->SF->Final from the top four of each league,
danger-zone (14-16) clubs lose reputation, awards come deterministically from
real ratings, the ceremony writes `world.meta.history`, and the rollover
produces fresh season-2 fixtures (season-prefixed ids), +12-month ages and a
save/load-stable history.

## 4. Season-boundary screenshot save (competition-owned, headless)

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/enrique/development/projects/pokemon-manager-game res://screens/competition/season_shot_prep.tscn
```

Overwrites `user://save.json` (back it up first!) with a career sitting in the
off-season week right after the Championship Series Final + awards ceremony —
ideal for capturing the playoff bracket / History tab / season-end header via
the screenshot harness with `COMP_DEV_TAB=playoff|history|table`. Prints
`SEASON SHOT PREP OK`.

## 5. Multi-resolution screenshots (platform piece)

The harness accepts an optional window size (default 1600x900):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path <project> res://tools/screenshots.tscn -- --screens=settings,squad --out=artifacts/platform/1920x1080 --size=1920x1080
```

Verified sizes: 1280x720, 1600x900, 1920x1080, 2560x1440 (PNGs under
`artifacts/platform/<size>/`). Stretch is `canvas_items` + `expand`, so any
size renders the full chrome without letterboxing.

## 6. Release exports (platform piece)

One-time setup — install the Godot 4.6 export templates (~1.2 GB):

```sh
curl -L -o /tmp/godot_templates_4.6.tpz \
  https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_export_templates.tpz
mkdir -p "$HOME/Library/Application Support/Godot/export_templates/4.6.stable"
cd /tmp && unzip -q godot_templates_4.6.tpz && \
  mv templates/* "$HOME/Library/Application Support/Godot/export_templates/4.6.stable/"
```

Build everything (also preflights a clean headless boot first):

```sh
caffeinate -i /Users/enrique/development/projects/pokemon-manager-game/scripts/export_all.sh
```

Expected final line: `EXPORT ALL OK`. Outputs:
- `dist/macos/TrainerManager-macos.zip` — universal .app, ad-hoc signed.
  Launch test: `unzip`, then `open "Trainer Manager.app"` (or run the binary
  inside with `--quit-after 60`).
- `dist/windows/TrainerManager.exe` — x86_64, pck embedded.
- `dist/linux/TrainerManager.x86_64` — x86_64, pck embedded.
- `dist/web/` — no-threads web build (plain static hosting works, no
  COOP/COEP needed). Serve test: `python3 -m http.server -d dist/web 8931`
  then `curl -sI http://127.0.0.1:8931/index.html` → 200, `index.wasm` > 20 MB.

## 7. Title menu + onboarding shots (menu piece, windowed)

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/enrique/development/projects/pokemon-manager-game res://menu/menu_shots.tscn
```

Captures to `artifacts/menu/`, in BOTH locales (es/en): the title screen with
a save (Continue card shows club · manager — date · season) and without one,
the Settings overlay, each onboarding step (identity / club selection with
detail pane / contract summary) and the onboarding opened OVER the shell via
the in-game "New Career" menu item. Also asserts the start transaction stamps
`world.meta.manager_name` + the player club's `manager` field and writes the
save. Prints `MENU SHOTS OK`.

**Back up `user://save.json` first** — the run creates/deletes test saves
(it deletes its own test save at the end, but an existing career save is
overwritten during the run).
