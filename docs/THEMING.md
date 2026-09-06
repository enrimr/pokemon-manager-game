# Multi-Competition Engine — theming investigation

*Status: PHASE 1 IMPLEMENTED (2026-09-06; the Pokémon game is byte-identical
and frozen-at-tag `v1-pokemon` before it). Live today: MatchEngine contract +
engine-owned tally, Packs facade + pack.json manifest, entity-stat registry,
multi-root screens/services discovery, manifest-driven onboarding with pack
steps + career-extras service hook, the pack lexicon (§3.4), and a fully
self-contained packs/pokemon/ (data, engine, assets, ui, screens, services,
onboarding, generator). Remaining seams for later phases: chassis binds
MonRoles/BattleEngine/PokeArt by class_name (a second pack must provide its
own or the loader must resolve per pack), commentary prose lives with the
live match view (phase 3), academy species biases, match-stat defs registry.*

Goal: evolve Trainer Manager from "an FM-style Pokémon game" into **a
management-game engine plus swappable Competition Packs** — the same chassis
running Pokémon, monster-taming reskins, football, basketball, Counter-Strike,
a collectible card game, or an influencer boxing event (La Velada style).

The guiding user insight: *the match is the customisable core* (a Pokémon
battle ↔ a football match ↔ a CS map), *onboarding steps vary* (catch your
starter ↔ pick your favourite club), and *the acquisition loop is themed*
(capture routes ↔ scouting foreign leagues ↔ signing from ranked ladders).

---

## 1. What the code says today

Two full coupling surveys (UI layer + core sim) agree on the split:

| Share | Verdict | What |
|---|---|---|
| ~55% | **Generic, reusable as-is** | Shell chrome (desktop + mobile), screen discovery, inbox + board + economy, competition suite (table/fixtures/cup/playoff/history), transfer market (structured deals, loans, personal terms, scouting knowledge, DoF), academy model, training scheduling, settings, game-over/sacking arc, onboarding wizard frame, save slots, calendar/season rollover, services plugin bus, i18n, procedural art (Portrait, PixelPortrait, Crest*, TrophyArt), theme, deep links, global search. |
| ~30% | **Parameterisable** | Squad table columns (already data-driven dicts in `screens/squad/views.gd`), competition `STAT_DEFS`, transfers filters, tactics plan-board pattern, match PRE/POST/IDLE views, commentary framework, awards, MonRoles ("position" abstraction), items store frame. |
| ~15% | **Rebuilt per sport** | `battle_engine.gd` + live match views (`live_view`, `battle_stage`, `mobile/battle`), `screens/routes/` + expeditions/legendaries services, evolution service, `starter_step.gd` (onboarding), the 8 data JSONs + `gen_data.py` catalogs, PokeArt/TrainerArt sprites. |

Hard numbers that make this credible:

- Of **5,906 translated strings**, only ~97 mention "Pokémon" and ~36
  "capture". The management prose is already sport-neutral.
- `world.json` already parameterises league names, cup name, currency, league
  pyramid (`meta.leagues` with tiers/regions) — the Kanto flavour is *data*.
- **Screens are drop-in** (`screens/*/screen.json`, no registry): delete
  `screens/routes/` and the nav entry disappears; the shell and MatchDirector
  already guard for absent screens.
- **Services are drop-in** (`shared/sim/services/*.gd`, duck-typed hooks
  `on_career_started/on_day/save_state/load_state`): the Pokémon-only
  mechanics (evolution, expeditions, legendaries, protégé) are *already*
  optional plugins that persist their own state.
- The **fixture contract is sport-agnostic**: `{id, comp, round, date, home,
  away, played, score_home, score_away, detail}`. "Score" means best-of-3
  battles today; it can mean goals, rounds, or judge cards.
- The **match screen is layered**: `screen.gd` routes IDLE/PRE/LIVE/POST;
  views talk to a duck-typed `runner`, never the engine. The LIVE view + the
  runner internals are the only Pokémon-shaped part.

## 2. Where the theme actually lives (the six seams)

1. **`DataStore`** (`shared/data/data_store.gd`) — the single sport-data
   facade (~250 refs across 48 UI files). Loads the 8 JSON catalogs, owns
   `TYPE_COLORS`, `calc_stat`, and `make_battler()` (instance → engine input).
2. **`BattleEngine` + its event vocabulary** — consumed by `match_runner`,
   `Season._tally_battle` (5 event types), `commentary.gd`, `report_gen.gd`.
3. **`Season.simulate_fixture` / `pick_team` / `compute_table`** — the one
   place the match engine is invoked for instant sims; best-of-3, 6-entity
   teams, no draws, and 3-points-per-win are baked in here.
4. **Four Pokémon services** (evolution, expeditions, legendaries, protégé) +
   flavour inside academy/challenges/season_flow (award names, starter trios,
   species pools, age-vs-evolution plausibility).
5. **Entity schema**: the generic half of an instance (`uid, level,
   condition, fitness, morale, age_months, contract, nickname`) vs the
   Pokémon half (`species_id, ivs, moves, nature, ability, held_item`).
   Stat keys `hp/atk/def/spa/spd/spe` are hardcoded as dict keys in squad
   views, transfers filters, tactics math and commentary.
6. **Vocabulary & art**: ~120 literal "Pokémon", 36 literal "Lv"; canonical
   sprites (PokeArt/TrainerArt); crest motifs keyed off squad's dominant type.

## 3. Proposed design: Competition Packs

A pack is a directory (e.g. `packs/pokemon/`, `packs/football/`) providing:

```
packs/<id>/
  pack.json           # manifest (see below)
  data/               # entity catalogs + world content (replaces shared/data JSONs)
  gen_world.py        # deterministic world generator (replaces gen_data.py's catalogs)
  engine/match_engine.gd   # implements the MatchEngine contract
  vocab.csv           # semantic term table (entity, level, acquisition verb, ...)
  services/           # pack-specific drop-in services (scouting trips, evolution...)
  screens/            # pack-specific screens (routes ↔ scouting hub) — same convention
  onboarding/         # extra wizard steps (starter ceremony ↔ franchise pick)
  art/                # sprite provider (optional; procedural fallbacks exist)
  strings.csv         # i18n rows for pack copy
```

### 3.1 The manifest (`pack.json`)

```json
{
  "id": "football",
  "name": "Football Manager Mode",
  "entity": {"singular": "Player", "plural": "Players", "roster_size": 22,
             "matchday_size": 11, "stats": [
    {"key": "pac", "title": "Pac", "long": "Pace"},
    {"key": "sho", "title": "Sho", "long": "Shooting"}, "..."]},
  "match": {"engine": "engine/match_engine.gd", "modes": ["league", "cup"],
            "draws": true, "points": {"win": 3, "draw": 1, "loss": 0},
            "score_label": "goals"},
  "modules": {"academy": true, "training": true, "items": false,
              "acquisition": "screens/scouting_hub"},
  "onboarding": ["identity", "club", "confirm"]
}
```

The manifest is what lets `compute_table` honour draws, the squad screen size
its views, the shell label its search box, and the onboarding wizard assemble
its steps.

### 3.2 The MatchEngine contract (formalise what already exists)

`BattleEngine`'s consumed surface **is already an interface** — write it down
and make `match_runner`/`Season` depend on it:

```gdscript
# required (instant sims — Season)
_init(team_a: Array, team_b: Array, seed: int, mode: String)
run_to_end() -> Array          # deterministic event log
winner() -> int                # -1 running / 0 / 1 / 2 = draw (NEW)
events: Array                  # [{"t": ..., "side": ...}, ...]
tally(events, teams) -> Dictionary   # NEW: per-entity stats for fixture.detail
                               # (moves Season._tally_battle into the engine)

# optional (interactive matches — the LIVE view)
is_over() / step_turn(a, b) / legal_actions(side) / preview_action(...)
team_state(side) / active info ...
```

Core event vocabulary (`battle_start/turn_start/score_event/faint→out/
switch→substitution/battle_end` + `commentary_hook`) stays shared so the
ticker, momentum graph, audio router and report generator keep working;
engines may emit extra types that generic consumers ignore (the engine
already tolerates unknown tags everywhere — same philosophy).

**A pack without an interactive engine is valid**: matches are then
watch/instant only (the LIVE view shows the ticker + momentum without an
action bar). That makes a new sport playable with just `run_to_end()` —
the cheapest possible on-ramp.

### 3.3 Entity schema registry

Replace the six hardcoded stat keys with the manifest's `entity.stats` list:

- `squad/views.gd` presets, `transfers/screen.gd` filters,
  `competition/stats_tab.gd` STAT_DEFS and `ui_helpers.STAT_SHORT` all become
  loops over the registry (they are already data-driven dicts — the change is
  *whose* dict).
- The instance dict keeps its generic half untouched (saves stay compatible
  per pack); the sport half becomes `inst["attrs"]` keyed by the registry.
- `MonRoles` (wall/sweeper/striker...) becomes a pack-provided role table.

### 3.4 Vocabulary table — IMPLEMENTED as the pack lexicon

Vocabulary IS translation: `<pack>/lexicon.json` maps locale → {i18n key →
override} and `Packs.install_lexicon()` shadows the base catalogs at boot
(first-added translation wins in Godot 4.6 — `tools/lexicon_check.tscn`
guards the mechanism). A football pack overrides "Squad Pokémon" in en AND
es without touching a single call site; the Pokémon pack ships an empty
lexicon because the chassis keys are already right. `Packs.entity_singular/
plural()` remains for strings composed at runtime (e.g. the global search
placeholder).

### 3.5 Modules (the routes ↔ scouting insight)

The acquisition loop is a **pack screen + pack service**, not engine code:

| Pack | Acquisition module (replaces `screens/routes/` + expeditions) |
|---|---|
| Pokémon | Route expeditions, wild captures, legendaries (as today) |
| Football | Scouting trips to foreign leagues; youth tournaments |
| Basketball | Draft combine + college scouting |
| Counter-Strike | Ranked-ladder tryouts, FPL-style talent LANs |
| TCG | Booster-box openings / singles market for new deck pieces |
| La Velada | Callout drama: influencers challenge you on social media |

Evolution ↔ "player development milestones" (football: breakout season;
CS: role switch) can reuse the same pending-approval service pattern.

## 4. Mapping the requested examples

| | Match engine | Entity + stats | Onboarding twist | Draws/points | Reuses live view? |
|---|---|---|---|---|---|
| **Pokémon** (v1) | Existing BattleEngine | Species, 6 stats, moves | Starter ceremony | No draws, 3-0 | Yes (as-is) |
| **Digimon-like** | **Same engine**, retuned type chart/moves | Monster catalog | Partner ceremony | Same | Yes — pure data reskin, cheapest proof (⚠ IP: use original monsters, same as we avoid Pokémon art) |
| **Football** | New: possession/chance sim → goal events | 11+bench, Pac/Sho/Pas/Def... | Pick your club + captain | Draws, 3-1-0 | New pitch view; ticker/momentum reuse |
| **Basketball** | New: possession sim, quarters | 5+bench | Franchise pick | No draws (OT) | New court view |
| **Counter-Strike** | New: round-by-round map sim (econ, sides) | 5 players, Aim/Util/IGL... | Sign your IGL | Draws possible (config) | Round ticker reuses momentum graph |
| **TCG** | Card-game sim (best-of-3 sets — closest to today's series!) | Decks = "squads", cards = items?? or entities | Choose your starter deck | No draws | Turn-based → could adapt the action bar |
| **La Velada** | Boxing bout sim (rounds, judge cards) | Influencer fighters, Pow/Chin/Cardio | Sign your first fighter | Draws possible | Bout view; commentary is the star |

Notes:
- **TCG** maps eerily well: best-of-N series, turn-based actions, an
  interactive action bar — the current match_runner shape survives mostly
  intact with a different engine.
- **La Velada** is the smallest world: one annual event, few fighters — it
  stresses the calendar assumptions (weekly league) more than the match. The
  pack manifest needs a "season shape" knob eventually; v1 can model it as a
  short league + cup.
- **Football/Basketball** need draws + richer score labels; `compute_table`
  and `club_form` grow a draw branch driven by the manifest.

## 5. Phased roadmap

- **Phase 0 — freeze (done)**: tag `v1-pokemon`.
- **Phase 1 — carve the seams, zero behaviour change** (the big one, all
  verifiable with existing green checks + `overflow_scan`):
  1. Write the MatchEngine contract; move `Season._tally_battle` into the
     engine as `tally()`; make `match_runner` hold "an engine", not
     BattleEngine.
  2. Entity-stats registry + manifest loader (`PackStore` autoload or a
     DataStore facade); squad/transfers/stats/tactics read the registry.
  3. Vocab table for the ~150 coupled strings; `screen.json` gains a
     `"pack"` field; `pack.json` for Pokémon describing exactly today's game.
  4. Move routes/evolution/legendaries/protégé/starter-step under
     `packs/pokemon/` (services bus + screens convention already support it —
     watch the export `.gdc` discovery pitfall, already solved once in
     `_load_services`).
- **Phase 2 — prove with a second pack**: either a **monster reskin**
  (same engine, new catalogs — validates data/vocab/art seams in days) or
  **football instant-sim only** (validates the engine contract + draws with
  no live view). Recommendation: do the monster reskin first, football
  second — they stress *different* seams.
- **Phase 3 — interactive match per sport**: new LIVE views where wanted;
  PRE/POST/ticker/momentum/audio come free.
- **Phase 4 — pack selector**: title screen offers the installed packs;
  saves record their pack id (one career = one pack).

## 6. Risks & open questions

- **IP**: Digimon/named influencers are trademarks, same as Pokémon species
  names. The project already ships zero copyrighted *art*; a distributable
  build with third-party names needs the same treatment for *words* (original
  monster/fighter names) or personal-use-only packs.
- **i18n keys are English sentences**, not semantic ids — pack strings need
  their own translation rows (the mechanism exists; it's volume, ~150 rows).
- **Season stat aggregation** (`kos/dmg/ratings`) is battle-flavoured; the
  `tally()` move puts stat *production* in the engine, but stat *display*
  needs the registry (phase 1.2) before a non-combat pack reads sanely.
- **Calendar shapes** beyond weekly-league+cup (La Velada) are future work.
- **Testing matrix** multiplies per pack — the existing headless harness
  pattern (sim_check per pack, overflow_scan reused) keeps it tractable.
- **Save compatibility**: pack id must ride the save header; cross-pack loads
  refuse politely (the v1→v2 save-versioning pattern already exists).

## 7. Verdict

The codebase is unusually well-positioned for this: the chassis/theme split
already exists in its architecture (data-driven world, drop-in screens,
drop-in services, duck-typed runner, event-log matches, one data facade).
Phase 1 is disciplined refactoring, not a rewrite — and after it, "a new
sport" costs: one match engine (or none for sim-only), one data generator,
one vocab table, one acquisition module, one onboarding step, and art.
