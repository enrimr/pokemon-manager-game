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


## Sport vocabulary (theming 1c): what the chassis calls the entity. The
## returned terms are English i18n KEYS — pass them through tr() at render
## time so each pack ships its own translation rows.
static func entity_singular() -> String:
	return str(manifest().get("entity", {}).get("singular", "Pokémon"))


static func entity_plural() -> String:
	return str(manifest().get("entity", {}).get("plural", entity_singular()))


## Install the pack's vocabulary overlay (theming: vocabulary IS translation).
## <pack>/lexicon.json maps locale -> {i18n key -> override}, letting a pack
## rewrite sport terms in EVERY language without touching call sites (e.g. a
## football pack overrides "Squad Pokémon" in en AND es). Empirically in
## Godot 4.6 the FIRST translation added for a locale wins, so the overlay is
## inserted in front of the base catalog (tools/lexicon_check.tscn guards
## this). The Pokémon pack ships an empty lexicon — keys are already right.
static func install_lexicon(extra: Dictionary = {}) -> void:
	var lex: Dictionary = {}
	var f := FileAccess.open("%s/%s/lexicon.json" % [PACK_DIR, ACTIVE], FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			lex = parsed
	for locale in extra:
		if not lex.has(locale):
			lex[locale] = {}
		(lex[locale] as Dictionary).merge(extra[locale], true)
	for locale in lex:
		if not (lex[locale] is Dictionary):
			continue   # metadata entries like "_readme"
		var terms: Dictionary = lex[locale]
		if terms.is_empty():
			continue
		var t := Translation.new()
		t.locale = str(locale)
		for k in terms:
			t.add_message(str(k), str(terms[k]))
		var base := TranslationServer.get_translation_object(str(locale))
		if base != null:
			TranslationServer.remove_translation(base)
		TranslationServer.add_translation(t)
		if base != null:
			TranslationServer.add_translation(base)


## Onboarding step ids in wizard order. "identity", "club" and "confirm" are
## chassis builtins; any other id resolves to the pack step script at
## <pack>/onboarding/<id>_step.gd (duck-typed contract — see menu/onboarding.gd).
static func onboarding_steps() -> Array:
	var steps: Variant = manifest().get("onboarding", [])
	if steps is Array and not steps.is_empty():
		return steps
	return ["identity", "club", "confirm"]


static func onboarding_step_path(id: String) -> String:
	return "%s/%s/onboarding/%s_step.gd" % [PACK_DIR, ACTIVE, id]


## Pack-owned drop-in roots (theming 1d): screens and simulation services may
## live inside the active pack, discovered exactly like the shared ones.
static func screens_root() -> String:
	return "%s/%s/screens" % [PACK_DIR, ACTIVE]


static func services_root() -> String:
	return "%s/%s/services" % [PACK_DIR, ACTIVE]


## Construct the pack's match engine for one game (MatchEngine contract).
static func match_engine_new(team_a: Array, team_b: Array, seed: int,
		mode: String = "singles") -> MatchEngine:
	var path := str(manifest().get("match", {}).get("engine", ""))
	if path != "" and ResourceLoader.exists(path):
		var scr: GDScript = load(path)
		if scr != null:
			return scr.new(team_a, team_b, seed, mode)
	return BattleEngine.new(team_a, team_b, seed, mode)
