extends VBoxContainer
## SEASON STATS tab — FM-style Stats Centre: a full sortable/filterable table
## of every Pokémon in the competition (selectable stat categories, club and
## competition filters, name search, clickable column sorting) plus a Leaders
## board view. All numbers come from deterministic engine replays of the real
## simulated results (see Season.season_player_stats / fixture_detail).

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")

# ---- stat column definitions (key -> title/width/format/tooltip)
const STAT_DEFS := {
	"apps":    {"title": "Apps",    "w": 52, "fmt": "int", "tip": "Battle appearances (best-of-3 legs played in)"},
	"wins":    {"title": "W",       "w": 42, "fmt": "int", "tip": "Battles won"},
	"winpct":  {"title": "Win %",   "w": 58, "fmt": "pct", "tip": "Battles won per appearance"},
	"kos":     {"title": "KOs",     "w": 48, "fmt": "int", "tip": "Opposing Pokémon knocked out"},
	"ko_app":  {"title": "KO/App",  "w": 62, "fmt": "f2",  "tip": "Knockouts per appearance"},
	"dmg":     {"title": "Dmg",     "w": 58, "fmt": "int", "tip": "Total damage dealt"},
	"dmg_app": {"title": "Dmg/App", "w": 68, "fmt": "int", "tip": "Damage dealt per appearance"},
	"taken":   {"title": "Tkn",     "w": 58, "fmt": "int", "tip": "Total damage taken"},
	"tkn_app": {"title": "Tkn/App", "w": 66, "fmt": "int", "tip": "Damage taken per appearance"},
	"faints":  {"title": "Fnt",     "w": 44, "fmt": "int", "tip": "Times fainted"},
	"surv":    {"title": "Surv %",  "w": 58, "fmt": "pct", "tip": "Appearances survived without fainting"},
	"rating":  {"title": "Rat",     "w": 52, "fmt": "f2",  "tip": "Average match rating (FM 10-point scale)"},
}

const CATEGORIES := [
	["Overview", ["apps", "wins", "winpct", "kos", "dmg", "taken", "faints", "rating"]],
	["Attacking", ["apps", "kos", "ko_app", "dmg", "dmg_app", "rating"]],
	["Defence & Durability", ["apps", "taken", "tkn_app", "faints", "surv", "rating"]],
	["Per-Battle Rates", ["apps", "winpct", "ko_app", "dmg_app", "tkn_app", "rating"]],
	["All Columns", ["apps", "wins", "winpct", "kos", "ko_app", "dmg", "dmg_app",
		"taken", "tkn_app", "faints", "surv", "rating"]],
]

const COMPS := [["all", "League + Cup"], ["league", "League only"], ["cup", "Cup only"]]

# ---- TEAM stat column definitions (Teams mode of the Stats Centre)
const TEAM_DEFS := {
	"matches":   {"title": "P",      "w": 40, "fmt": "int",     "tip": "Matches played"},
	"mw":        {"title": "W",      "w": 40, "fmt": "int",     "tip": "Matches won"},
	"ml":        {"title": "L",      "w": 40, "fmt": "int",     "tip": "Matches lost"},
	"winpct":    {"title": "Win %",  "w": 56, "fmt": "pct",     "tip": "Match win rate"},
	"pts":       {"title": "Pts",    "w": 46, "fmt": "int",     "tip": "League points (cup matches award none)"},
	"bw":        {"title": "BF",     "w": 44, "fmt": "int",     "tip": "Battles (best-of-3 legs) won"},
	"bl":        {"title": "BA",     "w": 44, "fmt": "int",     "tip": "Battles (best-of-3 legs) lost"},
	"bpct":      {"title": "B-Win %", "w": 62, "fmt": "pct",    "tip": "Battle (leg) win rate"},
	"bdiff":     {"title": "B+/-",   "w": 52, "fmt": "sign",    "tip": "Battle difference (won minus lost)"},
	"hrec":      {"title": "Home",   "w": 62, "fmt": "rec_h",   "tip": "Home match record (W-L)"},
	"hbpct":     {"title": "H B%",   "w": 52, "fmt": "pct",     "tip": "Battle win rate at home"},
	"arec":      {"title": "Away",   "w": 62, "fmt": "rec_a",   "tip": "Away match record (W-L)"},
	"abpct":     {"title": "A B%",   "w": 52, "fmt": "pct",     "tip": "Battle win rate away"},
	"venue_gap": {"title": "H-A",    "w": 54, "fmt": "signpct", "tip": "Home advantage: home minus away battle-win %, in points"},
	"kos":       {"title": "KO+",    "w": 50, "fmt": "int",     "tip": "Opposing Pokémon knocked out (engine replays)"},
	"faints":    {"title": "KO-",    "w": 50, "fmt": "int",     "tip": "Own Pokémon fainted"},
	"kod":       {"title": "KO±",    "w": 52, "fmt": "sign",    "tip": "KO difference (scored minus conceded)"},
	"dmg_leg":   {"title": "Dmg/B",  "w": 58, "fmt": "int0",    "tip": "Damage dealt per battle"},
	"tkn_leg":   {"title": "Tkn/B",  "w": 58, "fmt": "int0",    "tip": "Damage taken per battle"},
	"turns_leg": {"title": "Turns",  "w": 54, "fmt": "f1",      "tip": "Average battle length in turns"},
	"avg_rat":   {"title": "Sq Rat", "w": 56, "fmt": "f2",      "tip": "Average match rating across the squad (FM 10-point scale)"},
	"form":      {"title": "Form",   "w": 86, "fmt": "form",    "tip": "Last five results, oldest first"},
	"streak":    {"title": "Strk",   "w": 50, "fmt": "streak",  "tip": "Current run (W = winning, L = losing)"},
	"best_w":    {"title": "Best",   "w": 48, "fmt": "int",     "tip": "Longest winning run this season"},
	"worst_l":   {"title": "Worst",  "w": 52, "fmt": "int",     "tip": "Longest losing run this season"},
}

const TEAM_CATEGORIES := [
	["Overview", ["matches", "mw", "ml", "winpct", "pts", "bw", "bl", "bdiff", "bpct", "avg_rat", "streak"]],
	["Home / Away", ["matches", "winpct", "hrec", "hbpct", "arec", "abpct", "venue_gap"]],
	["Battles & KOs", ["matches", "bpct", "bdiff", "kos", "faints", "kod", "dmg_leg", "tkn_leg", "turns_leg"]],
	["Form & Streaks", ["matches", "winpct", "bpct", "form", "streak", "best_w", "worst_l", "avg_rat"]],
	["All Columns", ["matches", "mw", "ml", "winpct", "pts", "bpct", "bdiff", "hrec", "hbpct",
		"arec", "abpct", "kos", "faints", "kod", "avg_rat", "streak"]],
]

var _note: Label
var _view := "centre"
var _view_buttons: Dictionary = {}

# --- Stats Centre widgets/state
var _centre: VBoxContainer
var _tree: Tree
var _cat_sel: OptionButton
var _club_sel: OptionButton
var _comp_sel: OptionButton
var _search: LineEdit
var _apps_only: CheckBox
var _count_lbl: Label
var _cols: Array = []          # current column keys: ["rank","name","club","type","level", <stat keys>]
var _sort_key := "rating"
var _sort_asc := false

# --- Teams mode widgets/state
var _teams: VBoxContainer
var _ttree: Tree
var _tcat_sel: OptionButton
var _tcomp_sel: OptionButton
var _tsearch: LineEdit
var _tcount_lbl: Label
var _tinsights: HBoxContainer
var _tcols: Array = []
var _tsort_key := "pts"
var _tsort_asc := false

# --- Leaders widgets
var _leaders: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	# header: title, view switch, provenance note
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var title := UI.label("SEASON STATS", 16, Color.WHITE)
	head.add_child(title)
	for entry in [["centre", "Players"], ["teams", "Teams"], ["leaders", "Leaders"]]:
		var b := Button.new()
		b.text = entry[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_set_view.bind(entry[0]))
		head.add_child(b)
		_view_buttons[entry[0]] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_note = UI.dim("", 12)
	head.add_child(_note)
	add_child(head)

	_build_centre()
	_build_teams()
	_build_leaders()
	# Screenshot-harness hook only: pre-select a Stats view (inert in play).
	var dev_view := OS.get_environment("COMP_DEV_STATS_VIEW")
	if dev_view in ["centre", "teams", "leaders"]:
		_view = dev_view
	_apply_view()


# ================================================================ Stats Centre

func _build_centre() -> void:
	_centre = VBoxContainer.new()
	_centre.add_theme_constant_override("separation", 8)
	_centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_centre)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	bar.add_child(_toolbar_cap("CATEGORY"))
	_cat_sel = OptionButton.new()
	for entry in CATEGORIES:
		_cat_sel.add_item(entry[0])
	_cat_sel.select(0)
	_cat_sel.custom_minimum_size.x = 170
	_cat_sel.focus_mode = Control.FOCUS_NONE
	_cat_sel.tooltip_text = "Choose which stat columns are shown"
	_cat_sel.item_selected.connect(func(_i): _rebuild_table())
	bar.add_child(_cat_sel)

	bar.add_child(_toolbar_cap("CLUB"))
	_club_sel = OptionButton.new()
	_club_sel.add_item("All Clubs")
	_club_sel.set_item_metadata(0, "")
	var clubs: Array = GameState.world["clubs"].duplicate()
	clubs.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	for c in clubs:
		var idx := _club_sel.item_count
		_club_sel.add_item(str(c["name"]))
		_club_sel.set_item_metadata(idx, str(c["id"]))
	_club_sel.select(0)
	_club_sel.custom_minimum_size.x = 168
	_club_sel.focus_mode = Control.FOCUS_NONE
	_club_sel.tooltip_text = "Filter the table to one club's squad"
	_club_sel.item_selected.connect(func(_i): _rebuild_table())
	bar.add_child(_club_sel)

	bar.add_child(_toolbar_cap("COMPETITION"))
	_comp_sel = OptionButton.new()
	for entry in COMPS:
		var idx := _comp_sel.item_count
		_comp_sel.add_item(entry[1])
		_comp_sel.set_item_metadata(idx, entry[0])
	_comp_sel.select(0)
	_comp_sel.custom_minimum_size.x = 128
	_comp_sel.focus_mode = Control.FOCUS_NONE
	_comp_sel.tooltip_text = "Count league matches, cup matches, or both"
	_comp_sel.item_selected.connect(func(_i): _rebuild_table())
	bar.add_child(_comp_sel)

	_search = LineEdit.new()
	_search.placeholder_text = "Find Pokémon or species…"
	_search.custom_minimum_size.x = 190
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _rebuild_table())
	bar.add_child(_search)

	_apps_only = CheckBox.new()
	_apps_only.text = "Appearances only"
	_apps_only.focus_mode = Control.FOCUS_NONE
	_apps_only.add_theme_font_size_override("font_size", 12)
	_apps_only.tooltip_text = "Hide Pokémon that have not battled yet this season"
	_apps_only.toggled.connect(func(_on): _rebuild_table())
	bar.add_child(_apps_only)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_count_lbl = UI.dim("", 11)
	_count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_count_lbl)
	_centre.add_child(bar)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.column_titles_visible = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.column_title_clicked.connect(_on_title_clicked)
	UI.wire_tree_links(_tree)
	_centre.add_child(_tree)

	var foot := HBoxContainer.new()
	foot.add_child(UI.dim("click a column header to sort (click again to reverse) · Pokémon and club names link to profiles · Rat = avg match rating", 11))
	_centre.add_child(foot)


func _toolbar_cap(text: String) -> Label:
	var l := UI.dim(text, 10)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _current_cat_keys() -> Array:
	return CATEGORIES[maxi(_cat_sel.selected, 0)][1]


func _on_title_clicked(col: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT or col <= 0 or col >= _cols.size():
		return   # col 0 is the rank column (always current sort order)
	var key: String = _cols[col]
	if _sort_key == key:
		_sort_asc = not _sort_asc
	else:
		_sort_key = key
		_sort_asc = key in ["name", "club", "type"]   # text asc, stats desc first
	_rebuild_table()


func _rebuild_table() -> void:
	# column layout for the selected category
	_cols = ["rank", "name", "club", "type", "level"]
	_cols.append_array(_current_cat_keys())
	if not _cols.has(_sort_key):
		_sort_key = "rating" if _current_cat_keys().has("rating") else str(_cols[5])
		_sort_asc = false
	_tree.clear()
	_tree.columns = _cols.size()
	for i in _cols.size():
		var key: String = _cols[i]
		var title := ""
		var width := 0
		var tip := ""
		match key:
			"rank": width = 36; title = "#"
			"name": title = "Pokémon"; tip = "Nickname (species if unnamed)"
			"club": title = "Club"; width = 62; tip = "Owning club"
			"type": title = "Type"; width = 108
			"level": title = "Lv"; width = 42
			_:
				title = STAT_DEFS[key]["title"]
				width = STAT_DEFS[key]["w"]
				tip = STAT_DEFS[key]["tip"]
		if key == _sort_key:
			title += " ▲" if _sort_asc else " ▼"
		_tree.set_column_title(i, title)
		_tree.set_column_title_alignment(i,
			HORIZONTAL_ALIGNMENT_LEFT if key in ["name", "type"] else HORIZONTAL_ALIGNMENT_CENTER)
		if tip != "":
			_tree.set_column_title_tooltip_text(i, tip)
		if width > 0:
			_tree.set_column_expand(i, false)
			_tree.set_column_custom_minimum_width(i, width)
		else:
			_tree.set_column_expand(i, true)

	# data
	var comp: String = str(_comp_sel.get_selected_metadata())
	var rows := _build_rows(comp)
	var total := rows.size()
	var with_apps: int = rows.filter(func(r): return int(r["apps"]) > 0).size()

	var club_filter: String = str(_club_sel.get_selected_metadata())
	var needle := _search.text.strip_edges().to_lower()
	var shown: Array = rows.filter(func(r):
		if club_filter != "" and str(r["club"].get("id", "")) != club_filter:
			return false
		if _apps_only.button_pressed and int(r["apps"]) == 0:
			return false
		if needle != "" and needle not in str(r["name"]).to_lower() \
				and needle not in str(r["species"]).to_lower():
			return false
		return true)
	_sort_rows(shown)
	_count_lbl.text = "%d of %d Pokémon shown · %d have battled" % [shown.size(), total, with_apps]

	var root := _tree.create_item()
	var stat_keys := _current_cat_keys()
	for idx in shown.size():
		var r: Dictionary = shown[idx]
		var item := root.create_child()
		var played: bool = int(r["apps"]) > 0
		item.set_text(0, str(idx + 1))
		item.set_custom_color(0, TB.COL_TEXT_DIM)
		item.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)

		item.set_text(1, str(r["name"]))
		item.set_custom_color(1, TB.COL_TEXT if played else TB.COL_TEXT_DIM)
		UI.cell_link(item, 1, {"kind": "pokemon", "id": str(r["uid"])},
			"%s (%s) — view Pokémon profile" % [r["name"], r["species"]])

		var club: Dictionary = r["club"]
		if not club.is_empty():
			item.set_icon(2, UI.badge_texture(UI.club_color(club), 10))
			item.set_text(2, str(club.get("short", "?")))
			UI.cell_link(item, 2, {"kind": "club", "id": str(club.get("id", ""))},
				"%s — view club profile" % club.get("name", "?"))
		else:
			item.set_text(2, "-")
			item.set_custom_color(2, TB.COL_TEXT_DIM)
		item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)

		item.set_text(3, "/".join(r["types"]))
		item.set_custom_color(3, DataStore.type_color(r["types"][0]).lightened(0.25)
			if not r["types"].is_empty() else TB.COL_TEXT_DIM)
		item.set_text(4, str(r["level"]))
		item.set_custom_color(4, TB.COL_TEXT_DIM)
		item.set_text_alignment(4, HORIZONTAL_ALIGNMENT_CENTER)

		for si in stat_keys.size():
			var col := 5 + si
			var key: String = stat_keys[si]
			item.set_text(col, _fmt_stat(key, r))
			item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_CENTER)
			var c := TB.COL_TEXT_DIM if not played else TB.COL_TEXT
			if played and key == "rating":
				c = _rating_color(float(r["rating"]))
			elif played and key == _sort_key:
				c = Color.WHITE
			item.set_custom_color(col, c)

		if not club.is_empty() and GameState.is_player_club(str(club.get("id", ""))):
			for c in _tree.columns:
				item.set_custom_bg_color(c, UI.COL_PLAYER_ROW)


## One row per squad Pokémon across every club (zero-filled if it hasn't
## battled), plus any stat entry whose owner left a squad mid-season.
func _build_rows(comp: String) -> Array:
	var stats: Dictionary = Season.season_player_stats_comp(GameState.fixtures, comp)
	var rows: Array = []
	var seen := {}
	for c in GameState.world["clubs"]:
		for inst in c["squad"]:
			var uid := str(inst["uid"])
			seen[uid] = true
			rows.append(_make_row(uid, UI.display_name(inst), str(inst.get("species", "?")),
				_types_of(int(inst.get("species_id", 0))), int(inst.get("level", 0)),
				c, stats.get(uid, {})))
	for uid in stats:
		if seen.has(str(uid)):
			continue
		var s: Dictionary = stats[uid]
		rows.append(_make_row(str(uid), str(s["name"]), str(s["species"]),
			[], int(s["level"]), UI.club_of_uid(str(uid)), s))
	return rows


func _make_row(uid: String, pname: String, species: String, types: Array,
		level: int, club: Dictionary, s: Dictionary) -> Dictionary:
	var apps := int(s.get("battles", 0))
	var d := float(maxi(apps, 1))
	return {
		"uid": uid, "name": pname, "species": species, "types": types,
		"level": level, "club": club,
		"apps": apps,
		"wins": int(s.get("wins", 0)),
		"winpct": 100.0 * float(s.get("wins", 0)) / d,
		"kos": int(s.get("kos", 0)),
		"ko_app": float(s.get("kos", 0)) / d,
		"dmg": int(s.get("dmg", 0)),
		"dmg_app": float(s.get("dmg", 0)) / d,
		"taken": int(s.get("taken", 0)),
		"tkn_app": float(s.get("taken", 0)) / d,
		"faints": int(s.get("faints", 0)),
		"surv": 100.0 * float(apps - int(s.get("faints", 0))) / d if apps > 0 else 0.0,
		"rating": float(s.get("rating_sum", 0.0)) / d,
	}


func _types_of(species_id: int) -> Array:
	var sp: Dictionary = DataStore.species(species_id)
	return sp.get("types", []) if not sp.is_empty() else []


func _sort_rows(rows: Array) -> void:
	var key := _sort_key
	var asc := _sort_asc
	rows.sort_custom(func(a, b):
		var va: Variant
		var vb: Variant
		match key:
			"name": va = str(a["name"]).to_lower(); vb = str(b["name"]).to_lower()
			"club": va = str(a["club"].get("name", "~")); vb = str(b["club"].get("name", "~"))
			"type":
				va = "/".join(a["types"]) if not a["types"].is_empty() else "~"
				vb = "/".join(b["types"]) if not b["types"].is_empty() else "~"
			_: va = a.get(key, 0); vb = b.get(key, 0)
		if va == vb:
			# tiebreak: more appearances first, then alphabetical
			if int(a["apps"]) != int(b["apps"]):
				return int(a["apps"]) > int(b["apps"])
			return str(a["name"]) < str(b["name"])
		return va < vb if asc else va > vb)


func _fmt_stat(key: String, r: Dictionary) -> String:
	if int(r["apps"]) == 0 and key != "apps":
		return "-"
	var v: Variant = r[key]
	match str(STAT_DEFS[key]["fmt"]):
		"pct": return "%d%%" % roundi(float(v))
		"f2": return "%.2f" % float(v)
	return str(int(v))


# ================================================================= Teams mode
# FM Stats Centre "Teams" view: full sortable club-level stat table (records,
# home/away splits, battle-win %, KO ledger, squad ratings, streaks) plus a
# Data Hub-style strip of computed insights. All from real sim results.

func _build_teams() -> void:
	_teams = VBoxContainer.new()
	_teams.add_theme_constant_override("separation", 8)
	_teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_teams)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	bar.add_child(_toolbar_cap("CATEGORY"))
	_tcat_sel = OptionButton.new()
	for entry in TEAM_CATEGORIES:
		_tcat_sel.add_item(entry[0])
	_tcat_sel.select(0)
	_tcat_sel.custom_minimum_size.x = 170
	_tcat_sel.focus_mode = Control.FOCUS_NONE
	_tcat_sel.tooltip_text = "Choose which team stat columns are shown"
	_tcat_sel.item_selected.connect(func(_i): _rebuild_teams())
	bar.add_child(_tcat_sel)

	bar.add_child(_toolbar_cap("COMPETITION"))
	_tcomp_sel = OptionButton.new()
	for entry in COMPS:
		var idx := _tcomp_sel.item_count
		_tcomp_sel.add_item(entry[1])
		_tcomp_sel.set_item_metadata(idx, entry[0])
	_tcomp_sel.select(0)
	_tcomp_sel.custom_minimum_size.x = 128
	_tcomp_sel.focus_mode = Control.FOCUS_NONE
	_tcomp_sel.tooltip_text = "Count league matches, cup matches, or both"
	_tcomp_sel.item_selected.connect(func(_i): _rebuild_teams())
	bar.add_child(_tcomp_sel)

	_tsearch = LineEdit.new()
	_tsearch.placeholder_text = "Find club…"
	_tsearch.custom_minimum_size.x = 170
	_tsearch.clear_button_enabled = true
	_tsearch.text_changed.connect(func(_t): _rebuild_teams_table())
	bar.add_child(_tsearch)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_tcount_lbl = UI.dim("", 11)
	_tcount_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_tcount_lbl)
	_teams.add_child(bar)

	_tinsights = HBoxContainer.new()
	_tinsights.add_theme_constant_override("separation", 8)
	_teams.add_child(_tinsights)

	_ttree = Tree.new()
	_ttree.hide_root = true
	_ttree.select_mode = Tree.SELECT_ROW
	_ttree.column_titles_visible = true
	_ttree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ttree.column_title_clicked.connect(_on_team_title_clicked)
	UI.wire_tree_links(_ttree)
	_teams.add_child(_ttree)

	var foot := HBoxContainer.new()
	foot.add_child(UI.dim("click a column header to sort (click again to reverse) · club names link to profiles · KO± and Sq Rat come from deterministic engine replays", 11))
	_teams.add_child(foot)


func _team_cat_keys() -> Array:
	return TEAM_CATEGORIES[maxi(_tcat_sel.selected, 0)][1]


func _on_team_title_clicked(col: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT or col <= 0 or col >= _tcols.size():
		return   # col 0 = rank (always current sort order)
	var key: String = _tcols[col]
	if _tsort_key == key:
		_tsort_asc = not _tsort_asc
	else:
		_tsort_key = key
		_tsort_asc = key == "name"   # club name asc, stats desc first
	_rebuild_teams_table()


func _rebuild_teams() -> void:
	_rebuild_teams_table()
	_rebuild_team_insights()


func _rebuild_teams_table() -> void:
	_tcols = ["rank", "name"]
	_tcols.append_array(_team_cat_keys())
	if not _tcols.has(_tsort_key):
		var keys := _team_cat_keys()
		_tsort_key = "pts" if keys.has("pts") else str(keys[1])
		_tsort_asc = false
	_ttree.clear()
	_ttree.columns = _tcols.size()
	for i in _tcols.size():
		var key: String = _tcols[i]
		var col_title := ""
		var width := 0
		var tip := ""
		match key:
			"rank": width = 36; col_title = "#"
			"name": col_title = "Club"; tip = "Club (click for profile)"
			_:
				col_title = TEAM_DEFS[key]["title"]
				width = TEAM_DEFS[key]["w"]
				tip = TEAM_DEFS[key]["tip"]
		if key == _tsort_key:
			col_title += " ▲" if _tsort_asc else " ▼"
		_ttree.set_column_title(i, col_title)
		_ttree.set_column_title_alignment(i,
			HORIZONTAL_ALIGNMENT_LEFT if key == "name" else HORIZONTAL_ALIGNMENT_CENTER)
		if tip != "":
			_ttree.set_column_title_tooltip_text(i, tip)
		if width > 0:
			_ttree.set_column_expand(i, false)
			_ttree.set_column_custom_minimum_width(i, width)
		else:
			_ttree.set_column_expand(i, true)

	var comp: String = str(_tcomp_sel.get_selected_metadata())
	var rows := _build_team_rows(comp)
	var with_matches: int = rows.filter(func(r): return int(r["matches"]) > 0).size()
	var needle := _tsearch.text.strip_edges().to_lower()
	var shown: Array = rows.filter(func(r):
		return needle == "" or needle in str(r["name"]).to_lower() \
			or needle in str(r["short"]).to_lower())
	_sort_team_rows(shown)
	_tcount_lbl.text = "%d of %d clubs shown · %d have played" % [shown.size(), rows.size(), with_matches]

	var root := _ttree.create_item()
	var stat_keys := _team_cat_keys()
	for idx in shown.size():
		var r: Dictionary = shown[idx]
		var item := root.create_child()
		var played: bool = int(r["matches"]) > 0
		item.set_text(0, str(idx + 1))
		item.set_custom_color(0, TB.COL_TEXT_DIM)
		item.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)

		item.set_icon(1, UI.badge_texture(UI.club_color(r["club"]), 10))
		item.set_text(1, " " + str(r["name"]))
		item.set_custom_color(1, TB.COL_TEXT if played else TB.COL_TEXT_DIM)
		UI.cell_link(item, 1, {"kind": "club", "id": str(r["cid"])},
			"%s — view club profile" % r["name"])

		for si in stat_keys.size():
			var col := 2 + si
			var key: String = stat_keys[si]
			item.set_text(col, _fmt_team(key, r))
			item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_custom_color(col, _team_cell_color(key, r, played))

		if GameState.is_player_club(str(r["cid"])):
			for c in _ttree.columns:
				item.set_custom_bg_color(c, UI.COL_PLAYER_ROW)


## One stats row per club, from Season.season_club_stats (scores + replays).
func _build_team_rows(comp: String) -> Array:
	var stats: Dictionary = Season.season_club_stats(GameState.club_ids(), GameState.fixtures, comp)
	var rows: Array = []
	for cid in stats:
		var s: Dictionary = stats[cid]
		var club := GameState.club(str(cid))
		var m := int(s["matches"])
		var md := float(maxi(m, 1))
		var bt := float(maxi(int(s["bw"]) + int(s["bl"]), 1))
		var hbt := float(maxi(int(s["hbw"]) + int(s["hbl"]), 1))
		var abt := float(maxi(int(s["abw"]) + int(s["abl"]), 1))
		var legs := float(maxi(int(s["legs"]), 1))
		var results: Array = s["results"]
		var last5: Array = results.slice(maxi(0, results.size() - 5))
		var hbpct := 100.0 * float(s["hbw"]) / hbt
		var abpct := 100.0 * float(s["abw"]) / abt
		rows.append({
			"cid": str(cid), "club": club, "name": str(club.get("name", cid)),
			"short": str(club.get("short", "?")),
			"matches": m, "mw": int(s["mw"]), "ml": int(s["ml"]),
			"winpct": 100.0 * float(s["mw"]) / md, "pts": int(s["pts"]),
			"bw": int(s["bw"]), "bl": int(s["bl"]),
			"bpct": 100.0 * float(s["bw"]) / bt,
			"bdiff": int(s["bw"]) - int(s["bl"]),
			"hw": int(s["hw"]), "hl": int(s["hl"]), "hm": int(s["hm"]),
			"aw": int(s["aw"]), "al": int(s["al"]), "am": int(s["am"]),
			"hrec": float(s["hw"]) / float(maxi(int(s["hm"]), 1)),   # sort value
			"arec": float(s["aw"]) / float(maxi(int(s["am"]), 1)),   # sort value
			"hbpct": hbpct, "abpct": abpct, "venue_gap": hbpct - abpct,
			"kos": int(s["kos"]), "faints": int(s["faints"]),
			"kod": int(s["kos"]) - int(s["faints"]),
			"dmg_leg": float(s["dmg"]) / legs, "tkn_leg": float(s["taken"]) / legs,
			"turns_leg": float(s["turns"]) / legs,
			"avg_rat": float(s["rating_sum"]) / float(maxi(int(s["rating_apps"]), 1)),
			"form": last5,
			"form_pts": last5.filter(func(x): return x == "W").size(),
			"streak": int(s["streak"]), "best_w": int(s["best_w"]), "worst_l": int(s["worst_l"]),
		})
	return rows


func _sort_team_rows(rows: Array) -> void:
	var key := _tsort_key
	var asc := _tsort_asc
	rows.sort_custom(func(a, b):
		var va: Variant
		var vb: Variant
		match key:
			"name": va = str(a["name"]).to_lower(); vb = str(b["name"]).to_lower()
			"form": va = a["form_pts"]; vb = b["form_pts"]
			_: va = a.get(key, 0); vb = b.get(key, 0)
		if va == vb:
			# tiebreak: league points, then battle diff, then name
			if int(a["pts"]) != int(b["pts"]):
				return int(a["pts"]) > int(b["pts"])
			if int(a["bdiff"]) != int(b["bdiff"]):
				return int(a["bdiff"]) > int(b["bdiff"])
			return str(a["name"]) < str(b["name"])
		return va < vb if asc else va > vb)


func _fmt_team(key: String, r: Dictionary) -> String:
	if int(r["matches"]) == 0 and key != "matches":
		return "-"
	match str(TEAM_DEFS[key]["fmt"]):
		"pct": return "%d%%" % roundi(float(r[key]))
		"sign": return "%+d" % int(r[key]) if int(r[key]) != 0 else "0"
		"signpct": return "%+d" % roundi(float(r[key])) if roundi(float(r[key])) != 0 else "0"
		"f1": return "%.1f" % float(r[key])
		"f2": return "%.2f" % float(r[key])
		"int0": return str(roundi(float(r[key])))
		"rec_h": return "%d-%d" % [int(r["hw"]), int(r["hl"])]
		"rec_a": return "%d-%d" % [int(r["aw"]), int(r["al"])]
		"form": return " ".join(r["form"]) if not (r["form"] as Array).is_empty() else "-"
		"streak":
			var st := int(r["streak"])
			if st == 0:
				return "-"
			return "W%d" % st if st > 0 else "L%d" % (-st)
	return str(int(r[key]))


func _team_cell_color(key: String, r: Dictionary, played: bool) -> Color:
	if not played:
		return TB.COL_TEXT_DIM
	match key:
		"winpct", "bpct", "hbpct", "abpct":
			var v := float(r[key])
			if v >= 60.0:
				return UI.COL_WIN
			if v <= 40.0:
				return UI.COL_LOSS
		"bdiff", "kod", "venue_gap", "streak":
			var s := float(r[key])
			if s > 0.0:
				return UI.COL_WIN
			if s < 0.0:
				return UI.COL_LOSS
		"avg_rat":
			return _rating_color(float(r["avg_rat"]))
		"form":
			var w := int(r["form_pts"])
			var n: int = (r["form"] as Array).size()
			if n >= 3 and w * 2 > n + 1:
				return UI.COL_WIN
			if n >= 3 and w * 2 < n - 1:
				return UI.COL_LOSS
		"worst_l":
			if int(r["worst_l"]) >= 3:
				return UI.COL_LOSS
	if key == _tsort_key:
		return Color.WHITE
	return TB.COL_TEXT


## Data Hub-style computed insight chips above the teams table.
func _rebuild_team_insights() -> void:
	for c in _tinsights.get_children():
		c.queue_free()
	var comp: String = str(_tcomp_sel.get_selected_metadata())
	var rows: Array = _build_team_rows(comp).filter(func(r): return int(r["matches"]) > 0)
	if rows.is_empty():
		_tinsights.add_child(_insight_chip("NO DATA YET", {},
			"Team statistics appear once the first matchday has been played"))
		return

	var by := func(k: String, best_high: bool) -> Dictionary:
		var out: Dictionary = rows[0]
		for r in rows:
			if (float(r[k]) > float(out[k])) == best_high and float(r[k]) != float(out[k]):
				out = r
		return out

	var atk: Dictionary = by.call("kos", true)
	_tinsights.add_child(_insight_chip("BEST ATTACK", atk, "%d KOs · %.1f per battle" %
		[int(atk["kos"]), float(atk["kos"]) / maxf(float(atk["bw"] + atk["bl"]), 1.0)]))
	var def: Dictionary = by.call("faints", false)
	_tinsights.add_child(_insight_chip("TIGHTEST DEFENCE", def, "%d Pokémon lost in %d matches" %
		[int(def["faints"]), int(def["matches"])]))
	var home_rows: Array = rows.filter(func(r): return int(r["hm"]) >= 2)
	if not home_rows.is_empty():
		home_rows.sort_custom(func(a, b): return float(a["hbpct"]) > float(b["hbpct"]))
		var fort: Dictionary = home_rows[0]
		_tinsights.add_child(_insight_chip("FORTRESS", fort, "%d%% battle wins at home (%d-%d)" %
			[roundi(float(fort["hbpct"])), int(fort["hw"]), int(fort["hl"])]))
	var away_rows: Array = rows.filter(func(r): return int(r["am"]) >= 2)
	if not away_rows.is_empty():
		away_rows.sort_custom(func(a, b): return float(a["abpct"]) > float(b["abpct"]))
		var trav: Dictionary = away_rows[0]
		_tinsights.add_child(_insight_chip("ROAD WARRIORS", trav, "%d%% battle wins away (%d-%d)" %
			[roundi(float(trav["abpct"])), int(trav["aw"]), int(trav["al"])]))
	var hot: Dictionary = by.call("streak", true)
	if int(hot["streak"]) > 0:
		_tinsights.add_child(_insight_chip("IN FORM", hot,
			"won last %d in a row" % int(hot["streak"])))
	var cold: Dictionary = by.call("streak", false)
	if int(cold["streak"]) < 0:
		_tinsights.add_child(_insight_chip("IN CRISIS", cold,
			"lost last %d in a row" % (-int(cold["streak"]))))


func _insight_chip(caption: String, r: Dictionary, detail: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: Color = UI.club_color(r["club"]) if not r.is_empty() else TB.COL_BORDER
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.border_color = Color(col.r, col.g, col.b, 0.8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UI.dim(caption, 9))
	if not r.is_empty():
		var lnk := UI.link(str(r["name"]), 13, Color.WHITE,
			{"kind": "club", "id": str(r["cid"])}, "%s — view club profile" % r["name"])
		v.add_child(lnk)
	v.add_child(UI.dim(detail, 10))
	p.add_child(v)
	return p


# ==================================================================== Leaders

func _build_leaders() -> void:
	_leaders = GridContainer.new()
	_leaders.columns = 2
	_leaders.add_theme_constant_override("h_separation", 10)
	_leaders.add_theme_constant_override("v_separation", 10)
	_leaders.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_leaders)


func _set_view(view: String) -> void:
	_view = view
	_apply_view()
	refresh()


func _apply_view() -> void:
	for k in _view_buttons:
		_view_buttons[k].set_pressed_no_signal(k == _view)
		_view_buttons[k].add_theme_color_override("font_color",
			Color.WHITE if k == _view else TB.COL_TEXT_DIM)
	_centre.visible = _view == "centre"
	_teams.visible = _view == "teams"
	_leaders.visible = _view == "leaders"


func refresh() -> void:
	var played_n: int = GameState.fixtures.filter(func(f): return f["played"]).size()
	_note.text = "computed from %d simulated match%s · deterministic engine replays" % [
		played_n, "" if played_n == 1 else "es"]
	match _view:
		"centre":
			_rebuild_table()
		"teams":
			_rebuild_teams()
		_:
			_refresh_leaders(played_n)


func _refresh_leaders(played_n: int) -> void:
	for c in _leaders.get_children():
		c.queue_free()

	if played_n == 0:
		var empty := UI.card("No data yet")
		UI.card_body(empty).add_child(UI.dim(
			"Season statistics appear after the first matchday has been played.\nPress Continue to advance to the opening fixtures.", 13))
		_leaders.columns = 1
		_leaders.add_child(empty)
		return
	_leaders.columns = 2

	var stats: Dictionary = Season.season_player_stats(GameState.fixtures)
	var club_of := _club_of_uid()
	var rows: Array = []
	for uid in stats:
		var s: Dictionary = stats[uid]
		var r: Dictionary = s.duplicate()
		r["uid"] = uid
		r["club"] = club_of.get(uid, {})
		r["avg_rating"] = float(s["rating_sum"]) / maxi(int(s["battles"]), 1)
		rows.append(r)

	# --- Top rated (min 3 battle appearances)
	var rated := rows.filter(func(r): return int(r["battles"]) >= 3)
	rated.sort_custom(func(a, b): return a["avg_rating"] > b["avg_rating"])
	_leaders.add_child(_leader_card("Top Rated Pokémon", ["Pokémon", "Club", "Lv", "Apps", "Rat"],
		[0, 58, 44, 52, 54], rated, func(r): return [
			str(r["name"]), _short(r), str(r["level"]), str(r["battles"]), "%.2f" % r["avg_rating"]],
		func(r): return _rating_color(r["avg_rating"])))

	# --- Most KOs
	var kos := rows.duplicate()
	kos.sort_custom(func(a, b):
		if int(a["kos"]) != int(b["kos"]):
			return int(a["kos"]) > int(b["kos"])
		return int(a["dmg"]) > int(b["dmg"]))
	_leaders.add_child(_leader_card("Most KOs", ["Pokémon", "Club", "Apps", "KOs", "KO/App"],
		[0, 58, 52, 48, 62], kos, func(r): return [
			str(r["name"]), _short(r), str(r["battles"]), str(r["kos"]),
			"%.2f" % (float(r["kos"]) / maxi(int(r["battles"]), 1))],
		func(_r): return Color.WHITE))

	# --- Most damage
	var dmg := rows.duplicate()
	dmg.sort_custom(func(a, b): return int(a["dmg"]) > int(b["dmg"]))
	_leaders.add_child(_leader_card("Most Damage Dealt", ["Pokémon", "Club", "Apps", "Dmg", "Dmg/App"],
		[0, 58, 52, 62, 66], dmg, func(r): return [
			str(r["name"]), _short(r), str(r["battles"]), str(r["dmg"]),
			str(int(float(r["dmg"]) / maxi(int(r["battles"]), 1)))],
		func(_r): return Color.WHITE))

	# --- Club battle win-rates
	var crec := Season.club_battle_stats(GameState.club_ids(), GameState.fixtures)
	var clubs: Array = []
	for cid in crec:
		var c: Dictionary = crec[cid]
		if int(c["matches"]) == 0:
			continue
		var total := maxi(int(c["bw"]) + int(c["bl"]), 1)
		clubs.append({"cid": cid, "matches": c["matches"], "mw": c["mw"], "ml": c["ml"],
			"bw": c["bw"], "bl": c["bl"], "rate": float(c["bw"]) / total})
	clubs.sort_custom(func(a, b): return a["rate"] > b["rate"])
	_leaders.add_child(_club_card(clubs))


func _club_of_uid() -> Dictionary:
	var out := {}
	for c in GameState.world["clubs"]:
		for inst in c["squad"]:
			out[str(inst["uid"])] = c
	return out


func _short(r: Dictionary) -> String:
	var club: Dictionary = r["club"]
	return str(club.get("short", "-")) if not club.is_empty() else "-"


func _leader_card(title: String, titles: Array, widths: Array, rows: Array,
		cells: Callable, last_col_color: Callable) -> PanelContainer:
	var card := UI.card(title)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tree := Tree.new()
	tree.hide_root = true
	tree.columns = titles.size() + 1
	tree.column_titles_visible = true
	tree.custom_minimum_size.y = 244
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.set_column_title(0, "#")
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 30)
	for i in titles.size():
		tree.set_column_title(i + 1, titles[i])
		tree.set_column_title_alignment(i + 1, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER)
		if int(widths[i]) > 0:
			tree.set_column_expand(i + 1, false)
			tree.set_column_custom_minimum_width(i + 1, int(widths[i]))
	UI.wire_tree_links(tree)
	var root := tree.create_item()
	for idx in mini(rows.size(), 7):
		var r: Dictionary = rows[idx]
		var vals: Array = cells.call(r)
		var item := root.create_child()
		item.set_text(0, str(idx + 1))
		item.set_custom_color(0, TB.COL_TEXT_DIM)
		for i in vals.size():
			item.set_text(i + 1, str(vals[i]))
			if i > 0:
				item.set_text_alignment(i + 1, HORIZONTAL_ALIGNMENT_CENTER)
		UI.cell_link(item, 1, {"kind": "pokemon", "id": str(r["uid"])},
			"%s — view Pokémon profile" % r["name"])
		var club: Dictionary = r.get("club", {})
		if not club.is_empty():
			item.set_icon(1, UI.badge_texture(UI.club_color(club), 10))
			item.set_custom_color(2, TB.COL_TEXT_DIM)
			UI.cell_link(item, 2, {"kind": "club", "id": str(club.get("id", ""))},
				"%s — view club profile" % club.get("name", "?"))
			if GameState.is_player_club(str(club.get("id", ""))):
				for c in tree.columns:
					item.set_custom_bg_color(c, UI.COL_PLAYER_ROW)
		item.set_custom_color(vals.size(), last_col_color.call(r))
		if idx == 0:
			item.set_custom_color(1, Color(0.95, 0.83, 0.4))
	UI.card_body(card).add_child(tree)
	return card


func _club_card(clubs: Array) -> PanelContainer:
	var card := UI.card("Best Clubs · Battle Win Rate")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tree := Tree.new()
	tree.hide_root = true
	tree.columns = 6
	tree.column_titles_visible = true
	tree.custom_minimum_size.y = 244
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titles := ["#", "Club", "Matches", "W-L", "Battles", "Win %"]
	var widths := [30, 0, 62, 56, 66, 60]
	for i in tree.columns:
		tree.set_column_title(i, titles[i])
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT if i == 1 else HORIZONTAL_ALIGNMENT_CENTER)
		if widths[i] > 0:
			tree.set_column_expand(i, false)
			tree.set_column_custom_minimum_width(i, widths[i])
	UI.wire_tree_links(tree)
	var root := tree.create_item()
	for idx in mini(clubs.size(), 7):
		var r: Dictionary = clubs[idx]
		var club := GameState.club(r["cid"])
		var item := root.create_child()
		item.set_text(0, str(idx + 1))
		item.set_custom_color(0, TB.COL_TEXT_DIM)
		item.set_icon(1, UI.badge_texture(UI.club_color(club), 10))
		item.set_text(1, " " + str(club.get("name", r["cid"])))
		UI.cell_link(item, 1, {"kind": "club", "id": str(r["cid"])},
			"%s — view club profile" % club.get("name", r["cid"]))
		item.set_text(2, str(r["matches"]))
		item.set_text(3, "%d-%d" % [r["mw"], r["ml"]])
		item.set_text(4, "%d-%d" % [r["bw"], r["bl"]])
		item.set_text(5, "%d%%" % int(round(r["rate"] * 100.0)))
		item.set_custom_color(5, UI.COL_WIN if r["rate"] >= 0.5 else UI.COL_LOSS)
		for c in [2, 3, 4, 5]:
			item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)
		if GameState.is_player_club(str(r["cid"])):
			for c in tree.columns:
				item.set_custom_bg_color(c, UI.COL_PLAYER_ROW)
		if idx == 0:
			item.set_custom_color(1, Color(0.95, 0.83, 0.4))
	UI.card_body(card).add_child(tree)
	return card


func _rating_color(r: float) -> Color:
	if r >= 7.6:
		return Color(0.95, 0.83, 0.4)
	if r >= 7.0:
		return UI.COL_WIN
	if r < 6.2:
		return UI.COL_LOSS
	return Color.WHITE
