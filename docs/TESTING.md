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

## Notes

- To test from a fresh career, delete the save first:
  `rm -f "$HOME/Library/Application Support/Godot/app_userdata/Trainer Manager/save.json"`
- Regenerating data (foundation owner only): `python3 tools/gen_data.py`, then rerun smoke.

## 3. New-career club picker shots (shell-owned, windowed)

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/enrique/development/projects/pokemon-manager-game res://shell/picker_shots.tscn
```

Boots the real shell, opens the New Career club selector, captures both league
tabs and a career actually started at a Johto club to `artifacts/leagues/`,
then deletes the test save. Prints `PICKER SHOTS OK`.

Note: sim_check now also covers the two-league season (both championships,
cross-league Indigo Cup, per-league tables), the gen-2 type chart, the
`shared/sim/services/` auto-load convention and v1-save recovery.
