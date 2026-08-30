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
    items.json           # ~57 items: held (passive) + usable (battle consumables)
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
Club: `{id, name, short, manager, reputation(1-20), finances:{balance, wage_budget}, squad:[instance], staff:[..], items:{item_id: count}}`
Instance: `{uid, species_id, species, nickname, level, ivs:{..0-15}, moves:[4], held_item(item_id|null), condition, fitness, morale, age_months, contract:{salary, expiry}}`
Staff: `{name, role: coach|scout|physio, ratings:{attacking, defending, fitness, judging_ability, judging_potential, youth} (1-20)}`
Prospects additionally have `potential (1-20)` and `scouted_pct`.

### Gen-2 dataset extension (additive — nothing above changed shape)

- **pokemon.json** now has **251 species** (152-251 = Johto, incl. `dark`/`steel` types).
  Every species gained one new field: `ability` (an abilities.json id).
- **moves.json** now has **208 moves** (+72 gen-2, Bite retyped to dark). New inert tag
  `weather:<sun|rain|sand>` (engine ignores unknown tags; battle-depth wires it).
- **typechart.json** is the modern 18-type chart (gen-2 corrections applied: dark & steel
  rows/cols, bug/poison 0.5, ghost/psychic 2, steel resists, poison can't hit steel).
  `fairy` exists in chart+types as forward-compat; no fairy species/moves yet.
- **natures.json** — `{ "<Name>": {plus: "atk"|..|null, minus: ...|null} }`, the 25 real
  natures (+10%/-10%; 5 neutral). `DataStore.nature(name)`.
- **abilities.json** — `{ "<id>": {id, name, effects:[tags], desc} }`, 48 real abilities
  with machine-readable tags (grammar documented atop the ABILITIES table in
  tools/gen_data.py). `DataStore.ability(id)`, `ability_name(id)`.
- **world.json instances** (squad/free agent/prospect) each gained two fields:
  `nature` (natures.json name) and `ability` (abilities.json id, = species ability).
- `DataStore.make_battler()` copies `nature` + `ability` onto the battler dict
  (with `"Hardy"` / species-ability fallbacks for pre-gen-2 saves). **Neither is
  applied to stats or battle logic yet** — that's the battle-depth piece's contract.
- Regeneration is deterministic; gen-1 species rows, gen-1 move rows (except Bite),
  items.json and the whole world.json (modulo the two new instance fields) are
  byte-identical to the pre-gen-2 output.

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
commentary_hook, battle_end, item_used, held_item`. Damage events carry
`amount, hp_left, max_hp, effectiveness, crit`.
The match screen replays this log live and/or drives `step_turn` interactively.

## Season / calendar

`Season` (static): `make_league_fixtures` (double round-robin, 30 weekly rounds starting
season_start+7), `make_cup_round` (knockout, midweek every 4 weeks, generated round-by-round by
GameState when the previous round completes), `compute_table`, `simulate_fixture`
(best-of-3 6v6 battles between each club's top-6 by level/condition; battles won = match score;
no draws; 3 pts a win). `GameState.advance_day()` sims all fixtures due that day.

## Items system

Two item classes (see `items.json`, loaded by DataStore):

- **held** — passive while a Pokémon carries it. Lives on the squad instance's
  `held_item` slot; `DataStore.make_battler` copies it onto the battler
  (`held_item`, plus `nfe` for Eviolite) and the engine applies it automatically.
- **usable** — a trainer consumable spent as a battle action (potions, status
  heals, revives, X-boosts). Stored per club in `club["items"]`.

**items.json** — `{ "<id>": {id, name, class:"held"|"usable", price, rarity:
"common"|"uncommon"|"rare", effects:[tags], desc} }`
`DataStore.item(id)`, `item_name(id)`, `items_list(cls="")`.

Item effect tags (engine hooks):
held — `end_turn_heal:f` (Leftovers), `choice:<atk|spa|spe>:mult` (+move-lock),
`sash` (survive KO from full HP, single use), `life_orb` (1.3x dmg, 10% recoil),
`type_boost:<type>:mult`, `cure_berry:<status|confuse|all>` (fires on infliction,
single use), `sitrus:f` (heal at <=50% HP, single use), `quick_claw:p`,
`rocky_helmet:f`, `assault_vest` (SpD x1.5, no status moves), `eviolite`
(Def/SpD x1.5 if `nfe`), `shell_bell:f`, `kings_rock:p`, `bright_powder:f`,
`scope_lens`.
usable — `heal:<n|full>`, `cure:<status|confuse|all>`, `full_restore`,
`revive:f`, `xstat:<stat>:stages`, `dire_hit`, `guard_spec` (5 turns of
stat-drop immunity).

### Engine item API (the contract the match builder consumes)

```gdscript
eng.set_inventory(side, {item_id: count})  # give a side its matchday bag (engine copies it)
eng.inventory(side) -> Dictionary          # what's left (engine's live copy)
eng.items_used(side) -> int                # trainer items spent this battle
eng.set_ai_item_budget(side, n)            # cap AI-initiated item use (default 2)
```

Action format (third legal action type, alongside move/switch):

```gdscript
{"type": "use_item", "item": "<item_id>", "target": party_index}
```

- `legal_actions(side)` returns one `use_item` entry per valid item+target pair
  (heals target damaged mons — active or benched; cures target the matching
  status; revives target fainted mons; `xstat`/`dire_hit`/`guard_spec` target
  the active slot only). It also enforces Choice locks and Assault Vest.
- Using an item **costs that side's turn** (no move that turn), resolves after
  switches and before moves, and decrements the engine's bag copy. After the
  match, report consumption back with `GameState.consume_club_items(club_id,
  used)` — the engine never touches club inventories itself.
- With `null` actions (engine AI), the AI heals/cures from its bag when its
  active mon is hurting, at most `ai_item_budget` times per battle.
- Events: `item_used {side, item, item_name, pokemon, target_index}` when a
  trainer item is spent; `held_item {side, pokemon, item, item_name, effect,
  consumed}` whenever a passive item fires (leftovers tick, sash save, berry,
  quick claw, choice lock...). Both come with commentary_hook lines.
- Determinism holds: same teams + same bags + same seed = identical battle.

### Economy (GameState)

- `club_inventory(club_id)` / `player_inventory()` -> `{item_id: count}`.
- `buy_item(id, qty)` / `sell_item(id, qty)` — player shop, budget-enforced
  against `finances.balance` (sell-back at 50%). Returns "" or an error string.
- `assign_held_item(uid, item_id)` / `unassign_held_item(uid)` — equip squad
  Pokémon from the storeroom (swaps return the old item to stock).
- `consume_club_items(club_id, used)` — post-match consumption.
- Signal `inventory_changed` fires on any of the above.
- AI clubs get sensible starting held items on key mons (world gen) and shop
  occasionally on the daily tick (deterministic per seed+date+club).
- Everything lives inside `world`, so save/load persists it; `_ensure_item_state()`
  migrates pre-items saves (adds `items` stores and `held_item` slots).

The **Items screen** (`res://screens/items/`) is the shop + equip UI: catalog
with filters/prices/stock, buy/sell, and the squad equipment board
(pick item -> pick mon -> Equip).

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
| items        | `res://screens/items/` (items data/engine/economy built with the match piece grant) |
| shell        | `res://shell/`                                                           |

**NOBODY else** edits `shared/`, `project.godot`, `tools/`, or another piece's folder.
Need a shared change (new GameState API, new autoload, data regen)? Request it from the
foundation owner. Extending battle_engine.gd / season.gd: additive only — existing public
method signatures and the event/fixture dict schemas above are frozen contracts.

No copyrighted sprites or artwork anywhere. Visual identity = type-colored badges/monograms
(`DataStore.type_color`) + FM-style data density.

## Two-league world (Kanto + Johto) — leagues piece

The world is now **32 clubs in two 16-club leagues**, each with its own double
round-robin championship; the **Indigo Cup** is a 32-club cross-league knockout
(5 rounds: First Round, Second Round, Quarter-Final, Semi-Final, Final).

**world.json additions** (everything above stays shape-compatible):
- `meta.leagues`: `[{"id":"kanto","name":"Kanto League"},{"id":"johto","name":"Johto League"}]`
- `meta.cup_name`: `"Indigo Cup"`
- `meta.league_name` now always names the **player's** league (GameState keeps
  it in sync on career start/club choice) — every screen that renders it as its
  competition title keeps working untouched.
- every club has `league: "kanto"|"johto"`. Johto squads/free agents/prospects
  are gen-2 flavoured (~80% Johto natives, no legendaries/Unown) and carry an
  **inert** `native_region: "Johto"` field (the transfers piece's regional
  scouting maps them by type today — cross-region watches already pay domestic
  travel days — and can adopt a first-class Johto region later; do NOT set a
  live `region` key on domestic instances, the coverage board only knows its
  own REGIONS).

**Fixtures**: `fixture["league"]` = `"kanto"|"johto"` for league fixtures
(`""`/absent = cup). Fixture ids are prefixed per league ("L…" Kanto, "J…"
Johto, "C…" cup) via the new optional `Season.make_league_fixtures(ids, start,
id_prefix="L", league_id="")` params. `Season.compute_table` (and the club
stats aggregates) silently skip fixtures involving clubs outside the passed id
set, so passing one league's ids with `GameState.fixtures` is safe; cup stats
credit the tracked side of a cross-league tie.

**GameState league API** (existing calls keep their per-league semantics):
- `club_ids()` -> the PLAYER'S league's club ids (unchanged behaviour for all
  table/stats screens). `all_club_ids()` -> all 32.
- `leagues()` -> `[{id,name}]`; `league_club_ids(id)`; `league_of(club_id)`;
  `player_league_id()`; `league_name(id="")`; `cup_name()`.
- `league_table(league_id="")` -> standings (default: player's league).
- `new_career(seed, club_id="")` — optional club choice from either league;
  plain boot still defaults to Pallet Pioneers.

**New-career club picker** (`shell/club_picker.gd`): FM-style full-screen
selector opened by the top-bar menu's "New Career" — league tabs, one row per
club (type-coloured crest, manager, reputation meter, balance, world-percentile
squad-strength stars + top-six avg level), double-click or "Start at <club>".

**Save compatibility**: saves are `version: 2`. `GameState.boot()` (called
from `_ready`) detects a v1/corrupt save, starts a fresh career instead of
crashing, posts a clear inbox note ("Save file from an earlier era") and
immediately writes a v2 save.

### Season end, Championship Series & rollover (leagues piece)

The season no longer dead-ends after matchday 30 — the drop-in service
`shared/sim/services/season_flow.gd` (`SeasonFlowService.instance`) runs it:

- **Championship Series** (`comp == "playoff"`, ids `P###`): once BOTH
  championships complete, positions **1-4 of each league** enter a seeded
  cross-league knockout (QF `K1vJ4, J2vK3, J1vK4, K2vJ3` — champions can only
  meet in the Final; weekly rounds, normal best-of-3-battles fixtures). The
  Final crowns the **Indigo Champion**. The table zone legend ("Championship
  Series (1-4)") feeds exactly this. Helpers: `Season.playoff_fixtures/
  playoff_round_name/make_playoff_round/league_complete/comp_label`,
  `Season.PLAYOFF_NAME`, `Season.INDIGO_TITLE`.
- **Danger Zone (14-16)** (renamed from "Relegation Zone" — no lower tier
  exists, so the zone is real *differently*): at the ceremony every club that
  finishes there loses 1 reputation, 25% of its transfer budget and 3% of its
  bank (sponsor pullback). The player additionally gets a **board ultimatum**
  (top-10 next season, judged at next season's ceremony: met = praise + funds,
  missed = another reputation hit) and their star Pokémon demands an exit
  (morale -25, `exit_request` flag on the instance for the transfers piece).
- **Ceremony + history**: end-of-season awards mail (league champions rep +1,
  Indigo Champion rep +1, Pokémon of the Season + Best Developer from real
  recorded match ratings — deterministic, `SeasonFlowService.compute_awards`)
  plus a player season-review mail; a permanent record is appended to
  `world.meta.history` (`GameState.season_history()` / `add_history_entry`),
  rendered by the Competition screen's **History** tab.
- **Rollover**: 7 days after the Final, `GameState.start_new_season()` —
  `season_no` +1 (`GameState.season_no()`, world.meta.season_no), calendar
  jumps 364 days to the new preseason, fresh fixtures for both leagues + a new
  cup draw, every instance ages +12 months; squads/finances/development/items
  carry over. New signal `season_rolled(season_no)`. Fixture ids from season 2
  on are prefixed `S<n>` (`GameState.season_id_prefix()`) so id-keyed state
  (e.g. the economy's settled-fixture guard) never collides across seasons.
  Continue flows through all of it via plain `advance_day()` — the shell stops
  on the urgent season-end mails and plays player playoff ties normally.

Competition screen: new **Championship Series** tab (qualification race +
format before the playoff, live bracket + champion after) and **History** tab
(roll of honour + per-season cards). Header shows CS dates / next-season start
instead of "Season over".

## Simulation services (drop-in convention for later builders)

Any script at **`res://shared/sim/services/*.gd`** is auto-loaded by GameState
at career start — new career AND save load — ticked daily, and persisted inside
the save. **No GameState/project.godot edits needed**; drop the file in.

```gdscript
# res://shared/sim/services/my_service.gd
extends RefCounted            # any Object subclass works

# ALL hooks are optional (discovered with has_method):

func service_id() -> String:                  # unique id for persistence.
	return "my_service"                       # default: file basename.

func on_career_started(gs) -> void:           # after new_career OR load_game,
	pass                                      # world + saved state are ready.

func on_day(gs, date: String) -> void:        # every GameState.advance_day(),
	pass                                      # after fixtures/economy settle.

func save_state() -> Dictionary:              # JSON-safe dict; stored under
	return {}                                 # world.meta.services[service_id].

func load_state(state: Dictionary) -> void:   # restored BEFORE
	pass                                      # on_career_started fires.
```

Details:
- `gs` is the GameState autoload (use its public API/signals).
- Load order is alphabetical by filename; instances live until the next
  career start/load. `GameState.register_service(obj)` registers an already
  constructed object with the same lifecycle (used by tests).
- State rides `world.meta.services`, so it saves/loads with the world and
  numbers come back as JSON floats — cast in `load_state`.
- sim_check drops a probe service in and verifies discovery, daily ticking and
  state round-trip; keep services deterministic (seed off GameState.career_seed
  + date, like `_ai_daily_items`).

## Battle depth: natures, abilities, weather (battle-depth piece)

All three are engine-internal and deterministic (same teams + seed = same battle).
The battler fields `nature` and `ability` set by `DataStore.make_battler` are now
load-bearing; pre-gen-2 fallbacks ("Hardy", species ability) keep old saves valid.

- **Natures** — applied once when battlers are initialised: +10% / -10% on one
  non-HP stat (floored; never HP). Visible in `active_battler()["stats"]`.
- **Abilities** — every tag in abilities.json fires at its hook. Entry
  (Intimidate, Drizzle/Drought/Sand Stream), immunity/absorb (Levitate,
  Flash Fire — charges its own Fire moves x1.5 — Water/Volt Absorb), contact
  (Static, Poison Point, Flame Body, Effect Spore, Cute Charm, Rough Skin;
  "contact" = physical moves), survival (Sturdy, reusable), end-of-turn
  (Speed Boost, Shed Skin, Rain Dish), conditional multipliers (Guts — also
  ignores the burn Attack drop — Thick Fat, Huge Power, Hustle, Chlorophyll,
  Swift Swim, pinch boosts Overgrow/Blaze/Torrent/Swarm), status/stat
  protection (Immunity, Limber, Insomnia, Vital Spirit, Water Veil, Magma
  Armor, Own Tempo, Inner Focus, Keen Eye, Hyper Cutter, Clear Body, Shield
  Dust), plus Natural Cure, Synchronize, Pressure, Early Bird, Sand Veil,
  Compound Eyes, Serene Grace, Rock Head. Unknown tags stay inert.
- **Weather** — `eng.weather() -> ""|"sun"|"rain"|"sand"|"hail"`,
  `eng.weather_turns_left() -> int`. Sunny Day / Rain Dance / Sandstorm
  (`weather:<kind>` move tag) last 5 turns; auto-weather abilities 8.
  Sun: fire x1.5 / water x0.5; rain: the reverse. Sandstorm chips non
  rock/ground/steel 1/16 per turn (Sand Veil holders exempt) and gives Rock
  types SpD x1.5; hail chips non-ice 1/16. The AI scores weather-boosted
  moves higher and knows when to cast a weather move.

New event types (all with commentary_hook lines alongside):

- `ability_triggered {side, pokemon, ability, ability_name, effect}` — effect
  is the fired tag, e.g. "entry_stat", "immune", "absorb", "contact_status",
  "sturdy", "end_turn_stat", "pinch_boost", "resist", "reflect_status".
- `weather_start {kind, turns, source: "move"|"ability", side, pokemon}`
- `weather_end {kind}`
- `weather_chip {side, pokemon, kind, amount, hp_left, max_hp}`

`preview_move` now folds in weather, pinch/charge boosts and Thick Fat, and
returns `est_frac 0` against ability-immune targets. sim_check covers natures,
10+ abilities, weather lifecycle and depth determinism.

## Evolutions (evolutions piece)

Gen 1+2 evolution chains with an FM-style **manager approval** flow. Mechanics
live in the drop-in service `res://shared/sim/services/evolution.gd`
(auto-loaded, daily tick, persisted under `world.meta.services.evolution`);
the chain data is `shared/data/evolutions.json`; evolution stones/items are
ordinary shop items in `items.json`. Both data changes are produced by
`artifacts/evolutions/gen_evolutions.py` (idempotent — rerun it after any
`tools/gen_data.py` regeneration to restore the stone items). UI pieces
consume the service — nothing here renders.

**evolutions.json** — `{meta: {dev_per_level}, evolutions: {"<species_id>":
[{to, method, ...}]}}`. 113 species, 122 edges (Eevee is a 5-way branch).
Methods:
- `level` (`{level, cond?}`) — mainline level thresholds. Levels are static in
  this world, so the test is **effective level** = instance level +
  `dev_points / dev_per_level` (6), where dev points are the training piece's
  recorded development (`total_gained`). Tyrogue branches on base+IV
  Atk/Def via `cond: "atk>def" | "def>atk" | "atk=def"`.
- `development` (`{dev, level?, morale?, kind}`) — mainline **trade evos**
  (Alakazam, Machamp, Golem, Gengar) are high-development milestones
  (`kind:"trade"`, dev ≥ 36 + level gate); **happiness evos** (Crobat,
  Blissey, the babies) are `kind:"bond"` (dev ≥ 15 and morale ≥ 80).
- `stone` (`{stone}`) — consumes one item from club stock. New shop items:
  fire/water/thunder/leaf/moon/sun stones, metal_coat, dragon_scale, up_grade
  (class `usable`, inert `evolve:*` tag — never a battle action); King's Rock
  doubles as Politoed/Slowking trigger. Espeon/Umbreon go via Sun/Moon Stone
  (documented liberty: no day/night clock).

### Service API (`EvolutionService`, via `EvolutionService.instance` or
`load("res://shared/sim/services/evolution.gd").instance`; set on career
start/load)

```gdscript
# signals
pending_added(entry)                    # a player mon awaits your decision
pending_changed                         # approval queue mutated
evolved(uid, from_id, to_id, club_id)   # any club's instance transformed

# queries
chain_of(species_id) -> Array           # raw options ([] = final form)
eligibility(inst) -> Array              # [{to, to_name, method, ok, why}]
stone_options(uid) -> Array             # [{item_id, item_name, to, to_name, owned}]
pending() / is_pending(uid) / pending_for(uid)
dev_points(uid) / dev_levels(uid) / effective_level(inst)
recent_evolutions(days=7) / evolution_log()

# actions (return "" or an error string)
approve(uid)              # transform now: +6 morale, inbox follow-up
postpone(uid)             # -3 morale (the mon feels held back); offer
                          # returns after 14 days if still eligible
use_stone(uid, item_id)   # spend a stone from stock = instant approval
```

Flow: the daily tick scans the player squad; when a non-stone option is
satisfied the mon enters the **pending** queue and an inbox message asks for
a decision (stone routes get a one-time staff hint instead — buy the stone,
`use_stone` whenever). **Approval transforms the instance in place**: species
id/name (nickname preserved if custom), base stats/types/growth follow the new
species via DataStore, ability updates unless customised, moves are kept and
the pre-evo learnset is merged into `inst["learnset_extra"]` (still learnable
in training), +6 morale. AI clubs evolve autonomously on a seeded daily check
(level evos 2 levels late, trade proxies at Lv 34, bond at Lv 24 + morale,
stones bought from club funds at Lv 30) — deterministic per
career_seed+date+club, at most one per club per day.

Persistence: pending queue, postponements, stone hints and the world evolution
log ride `save_state()/load_state()`. Proof driver:
`res://artifacts/evolutions/driver.tscn` (headless; prints
`EVOLUTION DRIVER OK`) — full Charmander→Charizard chain via real training
weeks, Eevee via shop purchase + `use_stone`, postpone tradeoff, AI-club
evolutions with a determinism replay, and a save/load roundtrip.
