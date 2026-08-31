extends RefCounted
## Squad piece: customizable column views (FM-style saved views).
##
## The five presets are editable starting points: edit one and the change is
## stored as an override; Reset returns the factory layout. Users can also
## create, rename and delete their own views. Everything (overrides, custom
## views, the active view) lives inside the career save
## (GameState.world.meta.squad_views) so views survive save/load, exactly like
## FM's per-save views. Column definitions here are the single source of truth
## consumed by the table and by the column editor.

const STATE_KEY := "squad_views"
const MIN_COLS := 3
const MAX_COLS := 26
const MAX_VIEWS := 8          # custom views (presets not counted)
const MAX_NAME := 20
const LOCKED_COL := "name"    # every view keeps the Name column

## Factory presets — the editable starting points.
const PRESETS := {
	"General": ["pick", "name", "avail", "type", "babil", "lv", "age", "cur", "pot", "rec",
		"cond", "morale", "happy", "item", "apps", "rat", "salary", "status"],
	"Selection": ["pick", "name", "avail", "role", "type", "babil", "lv", "cond", "fit", "morale",
		"item", "apps", "kos", "rat", "value", "status"],
	"Battle Stats": ["pick", "name", "type", "lv", "babil", "nature", "cur", "pot", "hp", "atk", "def",
		"spa", "spd", "spe", "tot", "dev", "apps", "wins", "kos", "dmg", "taken", "faints", "rat"],
	"Contracts": ["pick", "name", "avail", "age", "lv", "cur", "pot", "rec", "morale",
		"salary", "wage_pct", "expiry", "days_left", "demand", "value", "status"],
	"Happiness": ["pick", "name", "pers", "sstat", "morale", "happy",
		"concern", "promise", "apps", "rat", "salary", "status"],
}

## Every column the table can render. `w` is the preferred min width; the
## table scales widths down responsively and h-scrolls beyond that, so no
## column can ever be lost to the viewport.
const COLS := {
	"pick": {"title": "Picked", "w": 84, "expand": false, "num": false,
		"cat": "Selection", "desc": "Matchday selection: starter slot + role, or bench order."},
	"role": {"title": "Role", "w": 100, "expand": false, "num": false,
		"cat": "Selection", "desc": "Tactical role from the saved tactic."},
	"avail": {"title": "Avail", "w": 76, "expand": false, "num": false,
		"cat": "Selection", "desc": "Availability doubts: fatigue, fitness, ailments, listing, unhappiness."},
	"name": {"title": "Name", "w": 140, "expand": true, "num": false,
		"cat": "Identity", "desc": "Name (always shown — a view without names is useless)."},
	"species": {"title": "Species", "w": 108, "expand": true, "num": false,
		"cat": "Identity", "desc": "Species, useful when nicknames hide it."},
	"type": {"title": "Type", "w": 96, "expand": false, "num": false,
		"cat": "Identity", "desc": "Type(s) with color pill."},
	"lv": {"title": "Lv", "w": 40, "expand": false, "num": true,
		"cat": "Identity", "desc": "Level."},
	"age": {"title": "Age", "w": 56, "expand": false, "num": true,
		"cat": "Identity", "desc": "Age in years and months."},
	"item": {"title": "Held Item", "w": 100, "expand": false, "num": false,
		"cat": "Identity", "desc": "Held item (equip from the Items screen)."},
	"babil": {"title": "Ability", "w": 96, "expand": false, "num": false,
		"cat": "Identity", "desc": "Battle ability — a passive power the engine applies (immunities, entry effects...)."},
	"nature": {"title": "Nature", "w": 116, "expand": false, "num": false,
		"cat": "Identity", "desc": "Nature: +10% to one battle stat, −10% to another. Already applied to the attribute columns."},
	"cur": {"title": "Cur Ability", "w": 84, "expand": false, "num": true,
		"cat": "Coach Report", "desc": "Current ability stars (coach judgement)."},
	"pot": {"title": "Potential", "w": 84, "expand": false, "num": true,
		"cat": "Coach Report", "desc": "Potential star range with scouting confidence."},
	"rec": {"title": "Coach Call", "w": 98, "expand": false, "num": false,
		"cat": "Coach Report", "desc": "Coach verdict: keep, develop, sell."},
	"dev": {"title": "Dev", "w": 52, "expand": false, "num": true,
		"cat": "Coach Report", "desc": "Attribute points gained this season."},
	"hp": {"title": "HP", "w": 50, "expand": false, "num": true,
		"cat": "Attributes", "desc": "Effective HP."},
	"atk": {"title": "Atk", "w": 50, "expand": false, "num": true,
		"cat": "Attributes", "desc": "Effective Attack."},
	"def": {"title": "Def", "w": 50, "expand": false, "num": true,
		"cat": "Attributes", "desc": "Effective Defence."},
	"spa": {"title": "SpA", "w": 50, "expand": false, "num": true,
		"cat": "Attributes", "desc": "Effective Sp. Attack."},
	"spd": {"title": "SpD", "w": 50, "expand": false, "num": true,
		"cat": "Attributes", "desc": "Effective Sp. Defence."},
	"spe": {"title": "Spe", "w": 50, "expand": false, "num": true,
		"cat": "Attributes", "desc": "Effective Speed."},
	"tot": {"title": "Tot", "w": 56, "expand": false, "num": true,
		"cat": "Attributes", "desc": "Attribute total."},
	"apps": {"title": "Apps", "w": 52, "expand": false, "num": true,
		"cat": "Season Stats", "desc": "Battles fought this season."},
	"wins": {"title": "Won", "w": 50, "expand": false, "num": true,
		"cat": "Season Stats", "desc": "Battles on the winning side."},
	"kos": {"title": "KOs", "w": 48, "expand": false, "num": true,
		"cat": "Season Stats", "desc": "Knockouts scored."},
	"dmg": {"title": "Dmg", "w": 56, "expand": false, "num": true,
		"cat": "Season Stats", "desc": "Damage dealt this season."},
	"taken": {"title": "Tkn", "w": 56, "expand": false, "num": true,
		"cat": "Season Stats", "desc": "Damage taken this season."},
	"faints": {"title": "Fnt", "w": 44, "expand": false, "num": true,
		"cat": "Season Stats", "desc": "Times fainted."},
	"rat": {"title": "Av Rat", "w": 60, "expand": false, "num": true,
		"cat": "Season Stats", "desc": "Average match rating."},
	"cond": {"title": "Cond", "w": 56, "expand": false, "num": true,
		"cat": "Condition & Mind", "desc": "Match condition %."},
	"fit": {"title": "Fit", "w": 52, "expand": false, "num": true,
		"cat": "Condition & Mind", "desc": "Base fitness %."},
	"morale": {"title": "Morale", "w": 86, "expand": false, "num": false,
		"cat": "Condition & Mind", "desc": "Day-to-day mood (tooltip = the mood ledger)."},
	"happy": {"title": "Happiness", "w": 90, "expand": false, "num": false,
		"cat": "Condition & Mind", "desc": "Structural happiness with explained factors."},
	"pers": {"title": "Personality", "w": 110, "expand": false, "num": false,
		"cat": "Condition & Mind", "desc": "Character archetype from the coach's read."},
	"sstat": {"title": "Status", "w": 96, "expand": false, "num": false,
		"cat": "Condition & Mind", "desc": "Squad status tier (Star, Important, Prospect...)."},
	"concern": {"title": "Main Concern", "w": 128, "expand": true, "num": false,
		"cat": "Condition & Mind", "desc": "Loudest active happiness concern."},
	"promise": {"title": "Promise", "w": 96, "expand": false, "num": false,
		"cat": "Condition & Mind", "desc": "Outstanding / kept / broken promise."},
	"salary": {"title": "Salary", "w": 88, "expand": false, "num": true,
		"cat": "Contract & Value", "desc": "Weekly wage."},
	"wage_pct": {"title": "Wage %", "w": 64, "expand": false, "num": true,
		"cat": "Contract & Value", "desc": "Share of the total wage bill."},
	"expiry": {"title": "Expires", "w": 96, "expand": false, "num": true,
		"cat": "Contract & Value", "desc": "Contract expiry date."},
	"days_left": {"title": "Days", "w": 54, "expand": false, "num": true,
		"cat": "Contract & Value", "desc": "Days left on the contract."},
	"demand": {"title": "Wants", "w": 100, "expand": false, "num": true,
		"cat": "Contract & Value", "desc": "Estimated wage demand in new talks."},
	"value": {"title": "Value", "w": 88, "expand": false, "num": true,
		"cat": "Contract & Value", "desc": "Estimated transfer value."},
	"status": {"title": "Status", "w": 92, "expand": false, "num": false,
		"cat": "Contract & Value", "desc": "Live transfer state: active bids, listed, talks off."},
}

const CATS := ["Selection", "Identity", "Coach Report", "Attributes",
	"Season Stats", "Condition & Mind", "Contract & Value"]


static func col_def(id: String) -> Dictionary:
	return COLS.get(id, {"title": id, "w": 60, "expand": false, "num": false,
		"cat": "Other", "desc": ""})


# ------------------------------------------------------------------ state

## Views state inside the save. Shape:
## {overrides: {preset_name: [ids]}, custom: {name: [ids]}, order: [names], active: name}
static func _state() -> Dictionary:
	var meta: Dictionary = GameState.world["meta"]
	if not (meta.get(STATE_KEY) is Dictionary):
		meta[STATE_KEY] = {}
	var st: Dictionary = meta[STATE_KEY]
	for k in ["overrides", "custom"]:
		if not (st.get(k) is Dictionary):
			st[k] = {}
	if not (st.get("order") is Array):
		st["order"] = []
	if not st.has("active"):
		st["active"] = "General"
	return st


static func _persist() -> void:
	GameState.save_game()


## All view names in display order: presets first, then custom views.
static func view_names() -> Array:
	var st := _state()
	var names: Array = []
	for p in PRESETS:
		names.append(p)
	for n in st["order"]:
		if (st["custom"] as Dictionary).has(n):
			names.append(str(n))
	return names


static func has_view(name: String) -> bool:
	return PRESETS.has(name) or (_state()["custom"] as Dictionary).has(name)


static func is_preset(name: String) -> bool:
	return PRESETS.has(name)


## True when a preset carries user edits (shown as "Preset *").
static func is_modified(name: String) -> bool:
	return PRESETS.has(name) and (_state()["overrides"] as Dictionary).has(name)


## The column list a view renders, sanitized (known ids, deduped, Name kept).
static func columns(name: String) -> Array:
	var st := _state()
	var raw: Array = []
	if (st["overrides"] as Dictionary).has(name):
		raw = st["overrides"][name]
	elif (st["custom"] as Dictionary).has(name):
		raw = st["custom"][name]
	elif PRESETS.has(name):
		raw = PRESETS[name]
	else:
		raw = PRESETS["General"]
	return sanitize(raw)


static func sanitize(raw: Array) -> Array:
	var out: Array = []
	for id in raw:
		if COLS.has(str(id)) and not out.has(str(id)):
			out.append(str(id))
	if not out.has(LOCKED_COL):
		out.insert(mini(1, out.size()), LOCKED_COL)
	return out


static func active() -> String:
	var a := str(_state()["active"])
	return a if has_view(a) else "General"


static func set_active(name: String) -> void:
	if has_view(name):
		_state()["active"] = name
		_persist()


# ------------------------------------------------------------------ mutations

static func _check_cols(cols: Array) -> String:
	var clean := sanitize(cols)
	if clean.size() < MIN_COLS:
		return I18n.t("A view needs at least %d columns.") % MIN_COLS
	if clean.size() > MAX_COLS:
		return I18n.t("A view can hold at most %d columns.") % MAX_COLS
	return ""


static func _check_name(name: String) -> String:
	var n := name.strip_edges()
	if n.length() < 2 or n.length() > MAX_NAME:
		return I18n.t("View names must be 2-%d characters.") % MAX_NAME
	if has_view(n):
		return I18n.t("A view called '%s' already exists.") % n
	return ""


## Save a column layout onto an existing view. Presets store an override
## (dropped again if it matches the factory layout). Returns "" or an error.
static func save_columns(name: String, cols: Array) -> String:
	if not has_view(name):
		return I18n.t("No view called '%s'.") % name
	var err := _check_cols(cols)
	if err != "":
		return err
	var clean := sanitize(cols)
	var st := _state()
	if PRESETS.has(name):
		if clean == (PRESETS[name] as Array):
			(st["overrides"] as Dictionary).erase(name)
		else:
			st["overrides"][name] = clean
	else:
		st["custom"][name] = clean
	_persist()
	return ""


## Create a new custom view. Returns "" or an error.
static func create(name: String, cols: Array) -> String:
	var n := name.strip_edges()
	var err := _check_name(n)
	if err == "":
		err = _check_cols(cols)
	if err != "":
		return err
	var st := _state()
	if (st["custom"] as Dictionary).size() >= MAX_VIEWS:
		return I18n.t("Custom view limit reached (%d). Delete one first.") % MAX_VIEWS
	st["custom"][n] = sanitize(cols)
	(st["order"] as Array).append(n)
	st["active"] = n
	_persist()
	return ""


## Rename a custom view (presets keep their names). Returns "" or an error.
static func rename(old_name: String, new_name: String) -> String:
	var st := _state()
	if not (st["custom"] as Dictionary).has(old_name):
		return I18n.t("Only custom views can be renamed.")
	var n := new_name.strip_edges()
	if n == old_name:
		return ""
	var err := _check_name(n)
	if err != "":
		return err
	st["custom"][n] = st["custom"][old_name]
	(st["custom"] as Dictionary).erase(old_name)
	var order: Array = st["order"]
	var i := order.find(old_name)
	if i >= 0:
		order[i] = n
	if str(st["active"]) == old_name:
		st["active"] = n
	_persist()
	return ""


## Delete a custom view. Returns "" or an error.
static func delete_view(name: String) -> String:
	var st := _state()
	if not (st["custom"] as Dictionary).has(name):
		return I18n.t("Presets can't be deleted — use Reset to restore their layout.")
	(st["custom"] as Dictionary).erase(name)
	(st["order"] as Array).erase(name)
	if str(st["active"]) == name:
		st["active"] = "General"
	_persist()
	return ""


## Drop a preset's override, restoring the factory layout.
static func reset(name: String) -> void:
	var st := _state()
	if (st["overrides"] as Dictionary).has(name):
		(st["overrides"] as Dictionary).erase(name)
		_persist()
