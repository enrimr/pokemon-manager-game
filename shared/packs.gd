class_name Packs
extends Object
## Competition Pack registry (theming phase 1 — docs/THEMING.md §3).
##
## A pack describes the SPORT: the entity and its stat schema, the match
## engine, the table rules. The management chassis reads the sport through
## this facade instead of hardcoding Pokémon. The Pokémon pack is the
## reference product; the active pack is fixed until a pack selector ships.

const ACTIVE := "pokemon"
const PACK_DIR := "res://packs"

static var _manifest: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var path := "%s/%s/pack.json" % [PACK_DIR, ACTIVE]
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_manifest = parsed
		if _manifest.is_empty():
			push_error("Packs: cannot load %s" % path)
	return _manifest


static func id() -> String:
	return str(manifest().get("id", ACTIVE))


## The sport's entity attribute schema: [{key, title, long}] in display order.
## Drives squad view columns, transfer filters and profile panes.
static func entity_stats() -> Array:
	return manifest().get("entity", {}).get("stats", [])


static func entity_stat_keys() -> Array:
	return entity_stats().map(func(s): return str(s["key"]))


## Entities fielded per game (6 for Pokémon, 11 for football...).
static func matchday_size() -> int:
	return int(manifest().get("entity", {}).get("matchday_size", 6))


## A fixture is a best-of-N series of games (3 for Pokémon; 1 for football).
static func series_best_of() -> int:
	return int(manifest().get("match", {}).get("series_best_of", 3))


static func draws_allowed() -> bool:
	return bool(manifest().get("match", {}).get("draws", false))


static func points_for(outcome: String) -> int:
	var pts: Dictionary = manifest().get("match", {}).get("points",
		{"win": 3, "draw": 1, "loss": 0})
	return int(pts.get(outcome, 0))


## Construct the pack's match engine for one game (MatchEngine contract).
static func match_engine_new(team_a: Array, team_b: Array, seed: int,
		mode: String = "singles") -> MatchEngine:
	var path := str(manifest().get("match", {}).get("engine", ""))
	if path != "" and ResourceLoader.exists(path):
		var scr: GDScript = load(path)
		if scr != null:
			return scr.new(team_a, team_b, seed, mode)
	return BattleEngine.new(team_a, team_b, seed, mode)
