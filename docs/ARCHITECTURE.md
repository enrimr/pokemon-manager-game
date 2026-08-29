# Trainer Manager — Architecture

Football-Manager-style management game for Pokémon battles. Godot 4.6, GDScript only,
gl_compatibility renderer, 1600x900 window. Main scene: `res://shell/main.tscn`.

## Layout

```
project.godot            # autoloads + settings. ONLY the foundation owner edits this.
shell/                   # FM chrome: sidebar nav, top bar, Continue button
shared/
  theme/theme_builder.gd # dark FM skin, built programmatically, applied by shell
  data/
    data_store.gd        # autoload DataStore (static data + battler building)
    pokemon.json         # 151 species: types, base stats, learnsets, growth
    moves.json           # 136 moves: type/power/acc/pp/category/effect tags
    typechart.json       # gen-1 style 15-type effectiveness chart
    world.json           # Indigo League: 16 clubs, squads, staff, free agents, prospects
  sim/
    battle_engine.gd     # deterministic 6v6 battle engine (class_name BattleEngine)
    season.gd            # fixtures, calendar, table, instant match sim (class_name Season)
  game_state.gd          # autoload GameState (career state, advance_day, save/load)
screens/<name>/          # one folder per screen, discovered by convention
tools/
  gen_data.py            # regenerates the four data JSONs (python3 tools/gen_data.py)
  screenshots.{gd,tscn}  # screenshot harness (see docs/TESTING.md)
  sim_check.{gd,tscn}    # headless 50-day season + engine verification
scripts/smoke.sh         # smoke test runner
```

## Autoloads (registered in project.godot — do not add more without coordination)

- **DataStore** — read-only static data. Key API:
  - `species(id) -> Dictionary`, `move(name) -> Dictionary`
  - `effectiveness(attack_type, defender_types) -> float`
  - `type_color(type) -> Color` (for badges/monograms — no copyrighted art, ever)
  - `make_battler(instance) -> Dictionary` — converts a world.json squad instance
    into the battler format BattleEngine consumes.
- **GameState** — the running career. Signals: `career_started`, `date_changed(date)`,
  `fixture_played(fixture)`, `table_updated`, `inbox_updated`, `player_match_due(fixture)`.
  Key API: `player_club()`, `club(id)`, `league_table()`, `player_table_position()`,
  `next_player_fixture()`, `fixtures_on(date)`, `free_agents()`, `prospects()`,
  `advance_day()`, `advance_to_next_event()`, `save_game()`, `load_game()` (user://save.json),
  `add_inbox_message(date, title, body)`.
  Boots by loading `user://save.json` if present, else starts a new career.
  `auto_sim_player_matches` (default true): the match piece sets this false and listens to
  `player_match_due` to run interactive matches instead of instant sim.

## Screen convention (how 8 builders avoid collisions)

At startup the shell scans `res://screens/*/`. A folder becomes a nav entry iff it contains:

- `screen.tscn` — root must be a Control; instanced into the shell's content area
  (theme inherited automatically). Optional method `on_show()` is called after instancing.
- `screen.json` — `{"title": "Squad", "order": 10, "icon_letter": "S"}`
  (lower `order` = higher in the sidebar; current stubs use 10..70 in steps of 10).
- `screen.gd` — your script(s). Everything for your screen lives in your folder.

There is NO central registry to edit. Drop your folder in, it appears.

## Data schemas

**pokemon.json** — array of
`{id, name, types:[..], base:{hp,atk,def,spa,spd,spe}, growth, learnset:[move names]}`

**moves.json** — `{ "<Name>": {type, power, accuracy, pp, category: "phys"|"spec"|"status", effects:[tags]} }`
Effect tags (colon-separated): `burn:0.1`, `para:0.3`, `sleep:1.0`, `poison:0.3`, `freeze:0.1`,
`confuse:0.1`, `flinch:0.3`, `stat:<stat>:<±stages>[:chance][:self]`, `priority:1`,
`recoil:0.25`, `drain:0.5`, `heal:0.5`, `crit:1` (high-crit), `fixed:level`, `fixed:40`,
`never_miss`, `confuse_self`. `power 0` + non-status = fixed damage; `accuracy 0` = can't miss.

**world.json** — `{meta:{league_name, season_start, player_club_id, currency}, clubs:[..], free_agents:[..], prospects:[..]}`
Club: `{id, name, short, manager, reputation(1-20), finances:{balance, wage_budget}, squad:[instance], staff:[..]}`
Instance: `{uid, species_id, species, nickname, level, ivs:{..0-15}, moves:[4], condition, fitness, morale, age_months, contract:{salary, expiry}}`
Staff: `{name, role: coach|scout|physio, ratings:{attacking, defending, fitness, judging_ability, judging_potential, youth} (1-20)}`
Prospects additionally have `potential (1-20)` and `scouted_pct`.

Dates are ISO strings (`"2026-08-01"`); they compare correctly with `<`/`>` and
`Season.date_add(date, days)` does calendar math.

## Battle engine API (`BattleEngine`, RefCounted)

```gdscript
var eng := BattleEngine.new(team_a, team_b, seed)   # teams: Array of DataStore.make_battler() dicts (1..6 each)
eng.run_to_end() -> Array                           # fast mode; returns full event log
eng.step_turn(action_a, action_b) -> Array          # step mode; null = engine AI decides that side
eng.legal_actions(side) -> Array                    # [{"type":"move","index":i}, {"type":"switch","index":slot}]
eng.is_over() -> bool ; eng.winner() -> int         # -1 running, else 0/1
eng.active_battler(side) / eng.team_state(side)     # live battler dicts (hp, status, stages, pp...)
eng.events                                          # full log so far
```

Deterministic: same teams + same seed = identical battle. Mechanics: speed/priority order,
gen-style damage formula with STAB/type chart/crits/0.85-1.0 roll, burn/para/sleep/poison/freeze,
confusion, flinch, stat stages ±6 (incl. acc/eva), recoil/drain/heal, fixed damage, switching,
auto-replacement on faint (best matchup), simple-but-sensible AI (best expected damage, switches
out of hard counters). Turn cap 300 (winner = higher remaining HP fraction).

Event log entries all have `"t"`: `battle_start, turn_start, move_used, damage, miss, faint,
switch, status_applied, status_tick, stat_change, heal, flinch, confused_hit, asleep, paralyzed,
commentary_hook, battle_end`. Damage events carry `amount, hp_left, max_hp, effectiveness, crit`.
The match screen replays this log live and/or drives `step_turn` interactively.

## Season / calendar

`Season` (static): `make_league_fixtures` (double round-robin, 30 weekly rounds starting
season_start+7), `make_cup_round` (knockout, midweek every 4 weeks, generated round-by-round by
GameState when the previous round completes), `compute_table`, `simulate_fixture`
(best-of-3 6v6 battles between each club's top-6 by level/condition; battles won = match score;
no draws; 3 pts a win). `GameState.advance_day()` sims all fixtures due that day.

## FILE OWNERSHIP (the collision rules)

| Piece        | Owns (exclusive write access)                                            |
|--------------|--------------------------------------------------------------------------|
| squad        | `res://screens/squad/`                                                   |
| tactics      | `res://screens/tactics/`                                                 |
| match        | `res://screens/match/` **plus** `res://shared/sim/battle_engine.gd`      |
| competition  | `res://screens/competition/` **plus** fixture/table logic in `res://shared/sim/season.gd` (keep existing public signatures; coordinate via GameState API) |
| transfers    | `res://screens/transfers/`                                               |
| training     | `res://screens/training/`                                                |
| inbox        | `res://screens/inbox/`                                                   |
| shell        | `res://shell/`                                                           |

**NOBODY else** edits `shared/`, `project.godot`, `tools/`, or another piece's folder.
Need a shared change (new GameState API, new autoload, data regen)? Request it from the
foundation owner. Extending battle_engine.gd / season.gd: additive only — existing public
method signatures and the event/fixture dict schemas above are frozen contracts.

No copyrighted sprites or artwork anywhere. Visual identity = type-colored badges/monograms
(`DataStore.type_color`) + FM-style data density.
