extends Node
## Autoload: DataStore
## Read-only static game data: species, moves, type chart.
## Loaded once at startup from res://shared/data/*.json.

var pokemon: Array = []            # Array[Dictionary], indexed list of species
var pokemon_by_id: Dictionary = {} # int id -> species dict
var pokemon_by_name: Dictionary = {}
var moves: Dictionary = {}         # move name -> move dict
var items: Dictionary = {}         # item id -> item dict (see items.json)
var types: Array = []
var type_chart: Dictionary = {}    # attacker -> {defender: mult}

const TYPE_COLORS := {
	"normal": Color("a8a090"), "fire": Color("f08030"), "water": Color("6890f0"),
	"grass": Color("78c850"), "electric": Color("f8d030"), "ice": Color("98d8d8"),
	"fighting": Color("c03028"), "poison": Color("a040a0"), "ground": Color("e0c068"),
	"flying": Color("a890f0"), "psychic": Color("f85888"), "bug": Color("a8b820"),
	"rock": Color("b8a038"), "ghost": Color("705898"), "dragon": Color("7038f8"),
}


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	pokemon = _load_json("res://shared/data/pokemon.json")
	for p in pokemon:
		pokemon_by_id[int(p["id"])] = p
		pokemon_by_name[p["name"]] = p
	moves = _load_json("res://shared/data/moves.json")
	items = _load_json("res://shared/data/items.json")
	var tc: Dictionary = _load_json("res://shared/data/typechart.json")
	types = tc["types"]
	type_chart = tc["chart"]
	print("DataStore: %d species, %d moves, %d items, %d types" % [pokemon.size(), moves.size(), items.size(), types.size()])


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataStore: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("DataStore: invalid JSON in %s" % path)
		return {}
	return parsed


func species(id: int) -> Dictionary:
	return pokemon_by_id.get(id, {})


func move(name: String) -> Dictionary:
	return moves.get(name, {})


## Item by id ({} if unknown). Item dict:
## {id, name, class: "held"|"usable", price, rarity, effects:[tags], desc}
func item(id: String) -> Dictionary:
	return items.get(id, {})


func item_name(id: String) -> String:
	return str(items.get(id, {}).get("name", id))


## All items as an Array, held first, then by price descending.
func items_list(cls: String = "") -> Array:
	var out: Array = []
	for it in items.values():
		if cls == "" or str(it["class"]) == cls:
			out.append(it)
	out.sort_custom(func(a, b):
		if a["class"] != b["class"]:
			return str(a["class"]) < str(b["class"])   # "held" < "usable"
		if int(a["price"]) != int(b["price"]):
			return int(a["price"]) > int(b["price"])
		return str(a["name"]) < str(b["name"]))
	return out


## Effectiveness multiplier of an attack type against a list of defender types.
func effectiveness(attack_type: String, defender_types: Array) -> float:
	var mult := 1.0
	var row: Dictionary = type_chart.get(attack_type, {})
	for t in defender_types:
		mult *= float(row.get(t, 1.0))
	return mult


func type_color(t: String) -> Color:
	return TYPE_COLORS.get(t, Color("888888"))


## Compute an actual stat for a species at a level with an IV (0-15).
func calc_stat(base: int, iv: int, level: int, is_hp: bool) -> int:
	var v := int(floor(float(2 * base + iv * 2) * float(level) / 100.0))
	return v + level + 10 if is_hp else v + 5


## Build a battler dict from a squad instance (see world.json schema).
## Battlers are the input format for BattleEngine.
func make_battler(inst: Dictionary) -> Dictionary:
	var sp: Dictionary = pokemon_by_id.get(int(inst["species_id"]), {})
	if sp.is_empty():
		push_error("make_battler: unknown species_id %s" % str(inst.get("species_id")))
		return {}
	var lvl := int(inst.get("level", 20))
	var ivs: Dictionary = inst.get("ivs", {})
	var base: Dictionary = sp["base"]
	var stats := {}
	for k in ["hp", "atk", "def", "spa", "spd", "spe"]:
		stats[k] = calc_stat(int(base[k]), int(ivs.get(k, 8)), lvl, k == "hp")
	var mv: Array = inst.get("moves", [])
	if mv.is_empty():
		mv = (sp["learnset"] as Array).slice(0, 4)
	var held: Variant = inst.get("held_item")
	return {
		"uid": inst.get("uid", ""),
		"name": inst.get("nickname") if inst.get("nickname") else sp["name"],
		"species": sp["name"],
		"types": sp["types"],
		"level": lvl,
		"stats": stats,
		"moves": mv,
		"held_item": str(held) if held != null and str(held) != "" else "",
		"nfe": bool(sp.get("evolves", false)),
	}
