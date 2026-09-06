class_name MatchEngine
extends RefCounted
## The Competition Pack match-engine contract (theming phase 1 — see
## docs/THEMING.md §3.2). A pack's engine simulates ONE game of a fixture
## series between two matchday teams. BattleEngine is the Pokémon
## implementation and the reference for the full surface.
##
## REQUIRED (instant sims — Season.simulate_fixture):
##   _init(team_a: Array, team_b: Array, seed: int, mode: String)
##       teams: arrays of entity dicts (DataStore.make_battler format for the
##       Pokémon pack). Same inputs + same seed MUST replay identically —
##       Season reconciles saved match reports by deterministic replay.
##   run_to_end() -> Array      full event log
##   winner() -> int            0 / 1 (or -1 while running)
##   turn: int                  game length for the report
##   events: Array              [{"t": <type>, "side": 0|1, ...}, ...]
##   tally(events, teams, winner, out)   fold one game's events into the
##       per-uid stats dict persisted as fixture["detail"]["players"] —
##       the stat keys are the pack's to define (the UI reads them through
##       the pack's stat definitions).
##
## OPTIONAL (interactive matches — the live match view / runner):
##   is_over(), step_turn(a, b), legal_actions(side), preview_move(...),
##   active_battler(side), team_state(side), set_inventory(...), weather()...
##   A pack without this surface is watch/instant only.
##
## Event vocabulary: generic consumers (ticker, momentum, audio, reports)
## understand the core types (battle_start, turn_start, damage→score events,
## faint, switch, battle_end, commentary_hook) and IGNORE unknown types, so
## engines may emit sport-specific extras freely.


func run_to_end() -> Array:
	return []


func winner() -> int:
	return -1


## Fold one game's event log into per-uid aggregate stats (see BattleEngine
## for the Pokémon implementation). Default: no per-entity stats recorded.
func tally(_events: Array, _teams: Array, _winner: int, _out: Dictionary) -> void:
	pass
