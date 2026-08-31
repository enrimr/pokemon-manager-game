extends VBoxContainer
## SEASON STATS tab — FM-style Stats Centre: a full sortable/filterable table
## of every Pokémon in the competition (selectable + fully customisable stat
## column views, league-percentile shading, club and competition filters, name
## search, clickable column sorting), a Teams mode, a Data Hub view of visual
## analytics (scatter / bar charts) and a Leaders board. All numbers come from
## the per-Pokémon match details recorded when each fixture is played.

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")
const Charts := preload("res://screens/competition/charts.gd")

# ---- stat column definitions (key -> title/width/format/tooltip)
# "neg": lower is better (inverts percentile shading).
const STAT_DEFS := {
	"apps":    {"title": "Apps",    "w": 52, "fmt": "int", "tip": "Battle appearances (best-of-3 legs played in)", "shade": false},
	"wins":    {"title": "W",       "w": 42, "fmt": "int", "tip": "Battles won"},
	"winpct":  {"title": "Win %",   "w": 58, "fmt": "pct", "tip": "Battles won per appearance"},
	"kos":     {"title": "KOs",     "w": 48, "fmt": "int", "tip": "Opposing Pokémon knocked out"},
	"ko_app":  {"title": "KO/App",  "w": 62, "fmt": "f2",  "tip": "Knockouts per appearance"},
	"dmg":     {"title": "Dmg",     "w": 58, "fmt": "int", "tip": "Total damage dealt"},
	"dmg_app": {"title": "Dmg/App", "w": 68, "fmt": "int", "tip": "Damage dealt per appearance"},
	"taken":   {"title": "Tkn",     "w": 58, "fmt": "int", "tip": "Total damage taken", "neg": true},
	"tkn_app": {"title": "Tkn/App", "w": 66, "fmt": "int", "tip": "Damage taken per appearance", "neg": true},
	"faints":  {"title": "Fnt",     "w": 44, "fmt": "int", "tip": "Times fainted", "neg": true},
	"surv":    {"title": "Surv %",  "w": 58, "fmt": "pct", "tip": "Appearances survived without fainting"},
	"hits":    {"title": "Hits",    "w": 48, "fmt": "int", "tip": "Damaging moves landed"},
	"acc":     {"title": "Acc %",   "w": 56, "fmt": "pct", "tip": "Move accuracy: hits landed per attempt"},
	"crits":   {"title": "Crits",   "w": 48, "fmt": "int", "tip": "Critical hits landed"},
	"critr":   {"title": "Crit %",  "w": 56, "fmt": "pct", "tip": "Critical hits per hit landed"},
	"se":      {"title": "SE",      "w": 44, "fmt": "int", "tip": "Super-effective hits landed"},
	"sepct":   {"title": "SE %",    "w": 52, "fmt": "pct", "tip": "Share of hits that were super-effective (type-matchup exploitation)"},
	"dph":     {"title": "Dmg/Hit", "w": 62, "fmt": "int", "tip": "Average damage per hit landed"},
	"rating":  {"title": "Rat",     "w": 52, "fmt": "f2",  "tip": "Average match rating (FM 10-point scale)"},
}

const CATEGORIES := [
	["Overview", ["apps", "wins", "winpct", "kos", "dmg", "taken", "faints", "rating"]],
	["Attacking", ["apps", "kos", "ko_app", "dmg", "dmg_app", "dph", "rating"]],
	["Defence & Durability", ["apps", "taken", "tkn_app", "faints", "surv", "rating"]],
	["Technique", ["apps", "hits", "acc", "crits", "critr", "se", "sepct", "dph"]],
	["Per-Battle Rates", ["apps", "winpct", "ko_app", "dmg_app", "tkn_app", "rating"]],
	["All Columns", ["apps", "wins", "winpct", "kos", "ko_app", "dmg", "dmg_app",
		"taken", "tkn_app", "faints", "surv", "acc", "crits", "se", "dph", "rating"]],
]
const CUSTOM_CAT := "Custom view"

const COMPS := [["all", "League + Cup"], ["league", "League only"], ["cup", "Cup only"]]

# ---- TEAM stat column definitions (Teams mode of the Stats Centre)
const TEAM_DEFS := {
	"matches":   {"title": "P",      "w": 40, "fmt": "int",     "tip": "Matches played", "shade": false},
	"mw":        {"title": "W",      "w": 40, "fmt": "int",     "tip": "Matches won"},
	"ml":        {"title": "L",      "w": 40, "fmt": "int",     "tip": "Matches lost", "neg": true},
	"winpct":    {"title": "Win %",  "w": 56, "fmt": "pct",     "tip": "Match win rate"},
	"pts":       {"title": "Pts",    "w": 46, "fmt": "int",     "tip": "League points (cup matches award none)"},
	"bw":        {"title": "BF",     "w": 44, "fmt": "int",     "tip": "Battles (best-of-3 legs) won"},
	"bl":        {"title": "BA",     "w": 44, "fmt": "int",     "tip": "Battles (best-of-3 legs) lost", "neg": true},
	"bpct":      {"title": "B-Win %", "w": 62, "fmt": "pct",    "tip": "Battle (leg) win rate"},
	"bdiff":     {"title": "B+/-",   "w": 52, "fmt": "sign",    "tip": "Battle difference (won minus lost)"},
	"hrec":      {"title": "Home",   "w": 62, "fmt": "rec_h",   "tip": "Home match record (W-L)", "shade": false},
	"hbpct":     {"title": "H B%",   "w": 52, "fmt": "pct",     "tip": "Battle win rate at home"},
	"arec":      {"title": "Away",   "w": 62, "fmt": "rec_a",   "tip": "Away match record (W-L)", "shade": false},
	"abpct":     {"title": "A B%",   "w": 52, "fmt": "pct",     "tip": "Battle win rate away"},
	"venue_gap": {"title": "H-A",    "w": 54, "fmt": "signpct", "tip": "Home advantage: home minus away battle-win %, in points", "shade": false},
	"kos":       {"title": "KO+",    "w": 50, "fmt": "int",     "tip": "Opposing Pokémon knocked out (recorded match details)"},
	"faints":    {"title": "KO-",    "w": 50, "fmt": "int",     "tip": "Own Pokémon fainted", "neg": true},
	"kod":       {"title": "KO±",    "w": 52, "fmt": "sign",    "tip": "KO difference (scored minus conceded)"},
	"dmg_leg":   {"title": "Dmg/B",  "w": 58, "fmt": "int0",    "tip": "Damage dealt per battle"},
	"tkn_leg":   {"title": "Tkn/B",  "w": 58, "fmt": "int0",    "tip": "Damage taken per battle", "neg": true},
	"turns_leg": {"title": "Turns",  "w": 54, "fmt": "f1",      "tip": "Average battle length in turns", "shade": false},
	"acc":       {"title": "Acc %",  "w": 56, "fmt": "pct",     "tip": "Team move accuracy: hits landed per attempt"},
	"crits":     {"title": "Crits",  "w": 50, "fmt": "int",     "tip": "Critical hits landed"},
	"se":        {"title": "SE",     "w": 44, "fmt": "int",     "tip": "Super-effective hits landed"},
	"sepct":     {"title": "SE %",   "w": 52, "fmt": "pct",     "tip": "Share of hits that were super-effective (matchup play)"},
	"avg_rat":   {"title": "Sq Rat", "w": 56, "fmt": "f2",      "tip": "Average match rating across the squad (FM 10-point scale)"},
	"form":      {"title": "Form",   "w": 86, "fmt": "form",    "tip": "Last five results, oldest first", "shade": false},
	"streak":    {"title": "Strk",   "w": 50, "fmt": "streak",  "tip": "Current run (W = winning, L = losing)", "shade": false},
	"best_w":    {"title": "Best",   "w": 48, "fmt": "int",     "tip": "Longest winning run this season"},
	"worst_l":   {"title": "Worst",  "w": 52, "fmt": "int",     "tip": "Longest losing run this season", "neg": true},
}

const TEAM_CATEGORIES := [
	["Overview", ["matches", "mw", "ml", "winpct", "pts", "bw", "bl", "bdiff", "bpct", "avg_rat", "streak"]],
	["Home / Away", ["matches", "winpct", "hrec", "hbpct", "arec", "abpct", "venue_gap"]],
	["Battles & KOs", ["matches", "bpct", "bdiff", "kos", "faints", "kod", "dmg_leg", "tkn_leg", "turns_leg"]],
	["Technique", ["matches", "acc", "crits", "se", "sepct", "dmg_leg", "avg_rat"]],
	["Form & Streaks", ["matches", "winpct", "bpct", "form", "streak", "best_w", "worst_l", "avg_rat"]],
	["All Columns", ["matches", "mw", "ml", "winpct", "pts", "bpct", "bdiff", "hrec", "hbpct",
		"arec", "abpct", "kos", "faints", "kod", "acc", "sepct", "avg_rat", "streak"]],
]

var _note: Label
var _view := "centre"
var _view_buttons: Dictionary = {}
var _lg_sel: OptionButton     # region scope: "" = all regions merged

# --- Stats Centre widgets/state
var _centre: VBoxContainer
var _tree: Tree
var _cat_sel: OptionButton
var _club_sel: OptionButton
var _comp_sel: OptionButton
var _search: LineEdit
var _apps_only: CheckBox
var _pctl_check: CheckBox
var _cols_menu: MenuButton
var _count_lbl: Label
var _cols: Array = []          # current column keys: ["rank","name","club","type","level", <stat keys>]
var _sort_key := "rating"
var _sort_asc := false
var _custom_keys: Array = ["apps", "winpct", "kos", "ko_app", "acc", "sepct", "surv", "rating"]

# --- Teams mode widgets/state
var _teams: VBoxContainer
var _ttree: Tree
var _tcat_sel: OptionButton
var _tcomp_sel: OptionButton
var _tsearch: LineEdit
var _tpctl_check: CheckBox
var _tcols_menu: MenuButton
var _tcount_lbl: Label
var _tinsights: HBoxContainer
var _tcols: Array = []
var _tsort_key := "pts"
var _tsort_asc := false
var _tcustom_keys: Array = ["matches", "winpct", "pts", "bpct", "kod", "acc", "sepct", "avg_rat"]

# --- Data Hub widgets (chart Controls from charts.gd, deliberately untyped)
var _hub: VBoxContainer
var _hub_scatter
var _hub_top_rated
var _hub_kod
var _hub_venue
var _hub_note: Label

# --- Leaders widgets
var _leaders: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	# header: title, view switch, provenance note
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var title := UI.label("SEASON STATS", 16, Color.WHITE)
	head.add_child(title)
	for entry in [["centre", "Players"], ["teams", "Teams"], ["hub", "Data Hub"], ["leaders", "Leaders"]]:
		var b := Button.new()
		b.text = tr(entry[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_set_view.bind(entry[0]))
		head.add_child(b)
		_view_buttons[entry[0]] = b

	# region scope: either league on its own, or an all-regions merge view
	var rcap := _toolbar_cap("REGION")
	head.add_child(rcap)
	_lg_sel = OptionButton.new()
	_lg_sel.add_item(tr("All Regions"))
	_lg_sel.set_item_metadata(0, "")
	for lg in GameState.leagues():
		var idx := _lg_sel.item_count
		_lg_sel.add_item(tr(str(lg["name"])))
		_lg_sel.set_item_metadata(idx, str(lg["id"]))
		if str(lg["id"]) == GameState.player_league_id():
			_lg_sel.select(idx)
	_lg_sel.custom_minimum_size.x = 138
	_lg_sel.focus_mode = Control.FOCUS_NONE
	_lg_sel.tooltip_text = "Scope every stat view to one league, or merge both regions"
	_lg_sel.item_selected.connect(func(_i): refresh())
	head.add_child(_lg_sel)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_note = UI.dim("", 12)
	head.add_child(_note)
	add_child(head)

	_build_centre()
	_build_teams()
	_build_hub()
	_build_leaders()
	# Screenshot-harness hooks only: pre-select a Stats view/region (inert in play).
	var dev_view := OS.get_environment("COMP_DEV_STATS_VIEW")
	if dev_view in ["centre", "teams", "hub", "leaders"]:
		_view = dev_view
	_apply_dev_region()
	_apply_view()


## Screenshot-harness hook only (inert in play): force the region scope.
## Re-applied on refresh because the screen's competition switcher context is
## pushed after tab _ready and would otherwise override it.
func _apply_dev_region() -> void:
	var dev_region := OS.get_environment("COMP_DEV_STATS_REGION")
	if dev_region == "all":
		_set_option(_lg_sel, "")
	elif dev_region != "":
		_set_option(_lg_sel, dev_region)


# ================================================================ Stats Centre

func _build_centre() -> void:
	_centre = VBoxContainer.new()
	_centre.add_theme_constant_override("separation", 8)
	_centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_centre)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	bar.add_child(_toolbar_cap("VIEW"))
	_cat_sel = OptionButton.new()
	for entry in CATEGORIES:
		_cat_sel.add_item(tr(entry[0]))
	_cat_sel.add_item(tr(CUSTOM_CAT))
	_cat_sel.select(0)
	_cat_sel.custom_minimum_size.x = 168
	_cat_sel.focus_mode = Control.FOCUS_NONE
	_cat_sel.tooltip_text = "Choose which stat columns are shown — or build your own view with Columns"
	_cat_sel.item_selected.connect(func(_i): _rebuild_table())
	bar.add_child(_cat_sel)

	_cols_menu = _make_cols_menu(STAT_DEFS, func() -> Array: return _custom_keys,
		func(keys: Array):
			_custom_keys = keys
			_cat_sel.select(CATEGORIES.size())   # switch to the custom view
			_rebuild_table())
	bar.add_child(_cols_menu)

	bar.add_child(_toolbar_cap("CLUB"))
	_club_sel = OptionButton.new()
	_club_sel.add_item(tr("All Clubs"))
	_club_sel.set_item_metadata(0, "")
	var clubs: Array = GameState.world["clubs"].duplicate()
	clubs.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	for c in clubs:
		var idx := _club_sel.item_count
		_club_sel.add_item(str(c["name"]))
		_club_sel.set_item_metadata(idx, str(c["id"]))
	_club_sel.select(0)
	_club_sel.custom_minimum_size.x = 150
	_club_sel.focus_mode = Control.FOCUS_NONE
	_club_sel.tooltip_text = "Filter the table to one club's squad"
	_club_sel.item_selected.connect(func(_i): _rebuild_table())
	bar.add_child(_club_sel)

	bar.add_child(_toolbar_cap("COMP"))
	_comp_sel = OptionButton.new()
	for entry in COMPS:
		var idx := _comp_sel.item_count
		_comp_sel.add_item(tr(entry[1]))
		_comp_sel.set_item_metadata(idx, entry[0])
	_comp_sel.select(0)
	_comp_sel.custom_minimum_size.x = 118
	_comp_sel.focus_mode = Control.FOCUS_NONE
	_comp_sel.tooltip_text = "Count league matches, cup matches, or both"
	_comp_sel.item_selected.connect(func(_i): _rebuild_table())
	bar.add_child(_comp_sel)

	_search = LineEdit.new()
	_search.placeholder_text = "Find Pokémon…"
	_search.custom_minimum_size.x = 148
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _rebuild_table())
	bar.add_child(_search)

	_apps_only = CheckBox.new()
	_apps_only.text = "Battled only"
	_apps_only.focus_mode = Control.FOCUS_NONE
	_apps_only.add_theme_font_size_override("font_size", 12)
	_apps_only.tooltip_text = "Hide Pokémon that have not battled yet this season"
	_apps_only.toggled.connect(func(_on): _rebuild_table())
	bar.add_child(_apps_only)

	_pctl_check = CheckBox.new()
	_pctl_check.text = "Percentiles"
	_pctl_check.button_pressed = true
	_pctl_check.focus_mode = Control.FOCUS_NONE
	_pctl_check.add_theme_font_size_override("font_size", 12)
	_pctl_check.tooltip_text = "Shade every stat cell by its league percentile:\ngreen = upper half, red = lower half, no tint = mid-pack.\nLower-is-better stats (damage taken, faints) are inverted."
	_pctl_check.toggled.connect(func(_on): _rebuild_table())
	bar.add_child(_pctl_check)

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
	foot.add_theme_constant_override("separation", 14)
	foot.add_child(UI.dim("click a header to sort · names link to profiles · the Columns menu builds a custom view", 11))
	foot.add_child(_pctl_legend())
	_centre.add_child(foot)


func _toolbar_cap(text: String) -> Label:
	var l := UI.dim(text, 10)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


# ------------------------------------------------------------- region scope

var _cup_focus := false


## Competition-switcher hook (screen.gd): a league context scopes the region
## filter to that league; the cup context merges regions and counts cup only.
func set_league_context(lg: String, cup: bool) -> void:
	if _lg_sel == null:
		return
	_set_option(_lg_sel, "" if cup else lg)
	if cup:
		_set_option(_comp_sel, "cup")
		_set_option(_tcomp_sel, "cup")
	elif _cup_focus:
		_set_option(_comp_sel, "all")
		_set_option(_tcomp_sel, "all")
	_cup_focus = cup


func _set_option(ob: OptionButton, meta: String) -> void:
	for i in ob.item_count:
		if str(ob.get_item_metadata(i)) == meta:
			ob.select(i)
			return


func _lg_filter() -> String:
	return str(_lg_sel.get_selected_metadata()) if _lg_sel != null else ""


func _lg_ids() -> Array:
	var f := _lg_filter()
	return GameState.all_club_ids() if f == "" else GameState.league_club_ids(f)


## Does this club fall inside the region scope? (unattached rows: merge only)
func _club_in_scope(club: Dictionary) -> bool:
	var f := _lg_filter()
	if f == "":
		return true
	if club.is_empty():
		return false
	return GameState.league_of(str(club.get("id", ""))) == f


## Percentile shading legend chip row (red -> neutral -> green swatches).
func _pctl_legend() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.tooltip_text = "Cell shading = league percentile for that stat\n(computed across every Pokémon with an appearance)"
	var cap := UI.dim("percentile:", 11)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cap)
	for entry in [[0.02, "low"], [0.5, ""], [0.98, "high"]]:
		var sq := Panel.new()
		sq.custom_minimum_size = Vector2(11, 11)
		sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		var t: Color = Charts.pct_tint(float(entry[0]), 0.55)
		sb.bg_color = t if t.a > 0.0 else TB.COL_PANEL_ALT
		sb.border_color = TB.COL_BORDER
		sb.set_border_width_all(1)
		sq.add_theme_stylebox_override("panel", sb)
		h.add_child(sq)
		if str(entry[1]) != "":
			var l := UI.dim(str(entry[1]), 10)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(l)
	return h


## Checkable column-picker popup (FM "customise view"). getter returns the
## current key list; setter receives the updated list.
func _make_cols_menu(defs: Dictionary, getter: Callable, setter: Callable) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = "Columns"
	mb.icon = GlyphIcons.tex("caret_down", 9, ThemeBuilder.COL_TEXT)
	mb.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mb.focus_mode = Control.FOCUS_NONE
	mb.custom_minimum_size = Vector2(96, 26)
	mb.add_theme_font_size_override("font_size", 12)
	mb.tooltip_text = "Build a custom view: tick exactly the stat columns you want"
	var pop := mb.get_popup()
	pop.hide_on_checkable_item_selection = false
	var keys: Array = defs.keys()
	mb.about_to_popup.connect(func():
		pop.clear()
		var current: Array = getter.call()
		for i in keys.size():
			var k: String = keys[i]
			pop.add_check_item("%s — %s" % [defs[k]["title"], str(defs[k]["tip"]).split("\n")[0]], i)
			pop.set_item_checked(i, current.has(k)))
	pop.index_pressed.connect(func(idx: int):
		var k: String = keys[idx]
		var current: Array = getter.call().duplicate()
		if current.has(k):
			if current.size() > 1:   # never allow an empty view
				current.erase(k)
		else:
			# keep the definition order stable regardless of click order
			current.append(k)
			var ordered: Array = []
			for kk in keys:
				if current.has(kk):
					ordered.append(kk)
			current = ordered
		pop.set_item_checked(idx, current.has(k))
		setter.call(current))
	return mb


func _current_cat_keys() -> Array:
	if _cat_sel.selected >= CATEGORIES.size():
		return _custom_keys
	return CATEGORIES[maxi(_cat_sel.selected, 0)][1]


## key -> {uid: percentile 0..1} across the whole qualifying population
## (league-wide context, independent of the club/search filters), ties
## averaged, "neg" stats inverted so green always means good.
func _compute_pctls(rows: Array, keys: Array, defs: Dictionary,
		qualify: Callable, id_key: String) -> Dictionary:
	var out := {}
	var pop: Array = rows.filter(qualify)
	var n := pop.size()
	if n < 2:
		return out
	for key in keys:
		var d: Dictionary = defs.get(key, {})
		if not bool(d.get("shade", true)) or str(d.get("fmt", "int")) == "form":
			continue
		var vals: Array = []
		for r in pop:
			vals.append(float(r[key]))
		vals.sort()
		var m := {}
		for r in pop:
			var v := float(r[key])
			var lo := vals.bsearch(v, true)
			var hi := vals.bsearch(v, false)
			var p := ((float(lo) + float(hi) - 1.0) / 2.0) / float(n - 1)
			if bool(d.get("neg", false)):
				p = 1.0 - p
			m[str(r[id_key])] = p
		out[key] = m
	return out


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
	# column layout for the selected category (+ league column when merged)
	_cols = ["rank", "name", "club", "type", "level"]
	if _lg_filter() == "":
		_cols.append("lg")
	_cols.append_array(_current_cat_keys())
	if not _cols.has(_sort_key):
		_sort_key = "rating" if _current_cat_keys().has("rating") else str(_current_cat_keys()[0])
		_sort_asc = false
	_tree.clear()
	_tree.columns = _cols.size()
	# fit-to-width for normal views; allow horizontal scroll only when a very
	# wide custom / all-columns view genuinely needs it
	_tree.scroll_horizontal_enabled = _cols.size() > 14
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
			"lg": title = "Lg"; width = 46; tip = "League the owning club competes in"
			_:
				title = STAT_DEFS[key]["title"]
				width = STAT_DEFS[key]["w"]
				tip = STAT_DEFS[key]["tip"]
		if key == _sort_key:
			title += " ^" if _sort_asc else " v"
		_tree.set_column_title(i, tr(title))
		_tree.set_column_title_alignment(i,
			HORIZONTAL_ALIGNMENT_LEFT if key in ["name", "type"] else HORIZONTAL_ALIGNMENT_CENTER)
		if tip != "":
			_tree.set_column_title_tooltip_text(i, tr(tip))
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

	# league-wide percentile context (FM Data-Hub-style shading)
	var pctls: Dictionary = {}
	if _pctl_check.button_pressed:
		pctls = _compute_pctls(rows, _current_cat_keys(), STAT_DEFS,
			func(r): return int(r["apps"]) > 0, "uid")

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
	_count_lbl.text = tr("%d/%d shown · %d battled") % [shown.size(), total, with_apps]

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
			I18n.t("%s (%s) — view Pokémon profile") % [r["name"], r["species"]])

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

		item.set_text(3, I18n.types_join(r["types"]))
		item.set_custom_color(3, DataStore.type_color(r["types"][0]).lightened(0.25)
			if not r["types"].is_empty() else TB.COL_TEXT_DIM)
		item.set_text(4, str(r["level"]))
		item.set_custom_color(4, TB.COL_TEXT_DIM)
		item.set_text_alignment(4, HORIZONTAL_ALIGNMENT_CENTER)

		var base := _cols.size() - stat_keys.size()
		if _cols.has("lg"):
			var lgid := str(r.get("lg", ""))
			item.set_text(5, UI.league_tag(lgid) if lgid != "" else "-")
			item.set_custom_color(5, UI.league_color(lgid).lightened(0.25)
				if lgid != "" else TB.COL_TEXT_DIM)
			item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)

		for si in stat_keys.size():
			var col := base + si
			var key: String = stat_keys[si]
			item.set_text(col, _fmt_stat(key, r))
			item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_CENTER)
			var c := TB.COL_TEXT_DIM if not played else TB.COL_TEXT
			if played and key == "rating":
				c = _rating_color(float(r["rating"]))
			elif played and key == _sort_key:
				c = Color.WHITE
			item.set_custom_color(col, c)
			if played and pctls.has(key):
				var p: float = float((pctls[key] as Dictionary).get(str(r["uid"]), 0.5))
				var tint: Color = Charts.pct_tint(p)
				if tint.a > 0.0:
					item.set_custom_bg_color(col, tint)
				item.set_tooltip_text(col, I18n.t("%s: %s — %d. percentile league-wide") % [
					STAT_DEFS[key]["title"], _fmt_stat(key, r), roundi(p * 100.0)])

		if not club.is_empty() and GameState.is_player_club(str(club.get("id", ""))):
			# with percentile shading on, keep the "your club" wash off the
			# stat cells so the percentile tints stay readable
			var last_col: int = base if not pctls.is_empty() else _tree.columns
			for c in last_col:
				item.set_custom_bg_color(c, UI.COL_PLAYER_ROW)


## One row per squad Pokémon across every club (zero-filled if it hasn't
## battled), plus any stat entry whose owner left a squad mid-season.
func _build_rows(comp: String) -> Array:
	var stats: Dictionary = Season.season_player_stats_comp(GameState.fixtures, comp)
	var rows: Array = []
	var seen := {}
	for c in GameState.world["clubs"]:
		if not _club_in_scope(c):
			continue   # region scope: no stat bleed between the leagues
		for inst in c["squad"]:
			var uid := str(inst["uid"])
			seen[uid] = true
			rows.append(_make_row(uid, UI.display_name(inst), str(inst.get("species", "?")),
				_types_of(int(inst.get("species_id", 0))), int(inst.get("level", 0)),
				c, stats.get(uid, {})))
	for uid in stats:
		if seen.has(str(uid)):
			continue
		var owner := UI.club_of_uid(str(uid))
		if not _club_in_scope(owner):
			continue
		var s: Dictionary = stats[uid]
		rows.append(_make_row(str(uid), str(s["name"]), str(s["species"]),
			[], int(s["level"]), owner, s))
	return rows


func _make_row(uid: String, pname: String, species: String, types: Array,
		level: int, club: Dictionary, s: Dictionary) -> Dictionary:
	var apps := int(s.get("battles", 0))
	var d := float(maxi(apps, 1))
	var hits := int(s.get("hits", 0))
	var misses := int(s.get("misses", 0))
	var hd := float(maxi(hits, 1))
	return {
		"uid": uid, "name": pname, "species": species, "types": types,
		"level": level, "club": club,
		"lg": GameState.league_of(str(club.get("id", ""))) if not club.is_empty() else "",
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
		"hits": hits,
		"acc": 100.0 * float(hits) / maxf(float(hits + misses), 1.0),
		"crits": int(s.get("crits", 0)),
		"critr": 100.0 * float(s.get("crits", 0)) / hd,
		"se": int(s.get("se", 0)),
		"sepct": 100.0 * float(s.get("se", 0)) / hd,
		"dph": float(s.get("dmg", 0)) / hd,
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
		"f2": return I18n.decimal(float(v), 2)
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

	bar.add_child(_toolbar_cap("VIEW"))
	_tcat_sel = OptionButton.new()
	for entry in TEAM_CATEGORIES:
		_tcat_sel.add_item(tr(entry[0]))
	_tcat_sel.add_item(tr(CUSTOM_CAT))
	_tcat_sel.select(0)
	_tcat_sel.custom_minimum_size.x = 168
	_tcat_sel.focus_mode = Control.FOCUS_NONE
	_tcat_sel.tooltip_text = "Choose which team stat columns are shown — or build your own view with Columns"
	_tcat_sel.item_selected.connect(func(_i): _rebuild_teams())
	bar.add_child(_tcat_sel)

	_tcols_menu = _make_cols_menu(TEAM_DEFS, func() -> Array: return _tcustom_keys,
		func(keys: Array):
			_tcustom_keys = keys
			_tcat_sel.select(TEAM_CATEGORIES.size())
			_rebuild_teams_table())
	bar.add_child(_tcols_menu)

	bar.add_child(_toolbar_cap("COMPETITION"))
	_tcomp_sel = OptionButton.new()
	for entry in COMPS:
		var idx := _tcomp_sel.item_count
		_tcomp_sel.add_item(tr(entry[1]))
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

	_tpctl_check = CheckBox.new()
	_tpctl_check.text = "Percentiles"
	_tpctl_check.button_pressed = true
	_tpctl_check.focus_mode = Control.FOCUS_NONE
	_tpctl_check.add_theme_font_size_override("font_size", 12)
	_tpctl_check.tooltip_text = "Shade every stat cell by its league percentile:\ngreen = upper half, red = lower half, no tint = mid-pack.\nLower-is-better stats (battles lost, KOs conceded) are inverted."
	_tpctl_check.toggled.connect(func(_on): _rebuild_teams_table())
	bar.add_child(_tpctl_check)

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
	foot.add_theme_constant_override("separation", 14)
	foot.add_child(UI.dim("click a header to sort · club names link to profiles · KO± / Acc / SE from recorded match details", 11))
	foot.add_child(_pctl_legend())
	_teams.add_child(foot)


func _team_cat_keys() -> Array:
	if _tcat_sel.selected >= TEAM_CATEGORIES.size():
		return _tcustom_keys
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
	if _lg_filter() == "":
		_tcols.append("lg")
	_tcols.append_array(_team_cat_keys())
	if not _tcols.has(_tsort_key):
		var keys := _team_cat_keys()
		_tsort_key = "pts" if keys.has("pts") else str(keys[mini(1, keys.size() - 1)])
		_tsort_asc = false
	_ttree.clear()
	_ttree.columns = _tcols.size()
	_ttree.scroll_horizontal_enabled = _tcols.size() > 16
	for i in _tcols.size():
		var key: String = _tcols[i]
		var col_title := ""
		var width := 0
		var tip := ""
		match key:
			"rank": width = 36; col_title = "#"
			"name": col_title = "Club"; tip = "Club (click for profile)"
			"lg": col_title = "Lg"; width = 46; tip = "League the club competes in"
			_:
				col_title = TEAM_DEFS[key]["title"]
				width = TEAM_DEFS[key]["w"]
				tip = TEAM_DEFS[key]["tip"]
		if key == _tsort_key:
			col_title += " ^" if _tsort_asc else " v"
		_ttree.set_column_title(i, tr(col_title))
		_ttree.set_column_title_alignment(i,
			HORIZONTAL_ALIGNMENT_LEFT if key == "name" else HORIZONTAL_ALIGNMENT_CENTER)
		if tip != "":
			_ttree.set_column_title_tooltip_text(i, tr(tip))
		if width > 0:
			_ttree.set_column_expand(i, false)
			_ttree.set_column_custom_minimum_width(i, width)
		else:
			_ttree.set_column_expand(i, true)

	var comp: String = str(_tcomp_sel.get_selected_metadata())
	var rows := _build_team_rows(comp)
	var with_matches: int = rows.filter(func(r): return int(r["matches"]) > 0).size()

	var pctls: Dictionary = {}
	if _tpctl_check.button_pressed:
		pctls = _compute_pctls(rows, _team_cat_keys(), TEAM_DEFS,
			func(r): return int(r["matches"]) > 0, "cid")
	var needle := _tsearch.text.strip_edges().to_lower()
	var shown: Array = rows.filter(func(r):
		return needle == "" or needle in str(r["name"]).to_lower() \
			or needle in str(r["short"]).to_lower())
	_sort_team_rows(shown)
	_tcount_lbl.text = tr("%d/%d clubs · %d played") % [shown.size(), rows.size(), with_matches]

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

		var base := _tcols.size() - stat_keys.size()
		if _tcols.has("lg"):
			var lgid := str(r.get("lg", ""))
			item.set_text(2, UI.league_tag(lgid))
			item.set_custom_color(2, UI.league_color(lgid).lightened(0.25))
			item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)

		for si in stat_keys.size():
			var col := base + si
			var key: String = stat_keys[si]
			item.set_text(col, _fmt_team(key, r))
			item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_custom_color(col, _team_cell_color(key, r, played))
			if played and pctls.has(key):
				var p: float = float((pctls[key] as Dictionary).get(str(r["cid"]), 0.5))
				var tint: Color = Charts.pct_tint(p)
				if tint.a > 0.0:
					item.set_custom_bg_color(col, tint)
				item.set_tooltip_text(col, I18n.t("%s: %s — %d. percentile league-wide") % [
					TEAM_DEFS[key]["title"], _fmt_team(key, r), roundi(p * 100.0)])

		if GameState.is_player_club(str(r["cid"])):
			var last_col: int = base if not pctls.is_empty() else _ttree.columns
			for c in last_col:
				item.set_custom_bg_color(c, UI.COL_PLAYER_ROW)


## One stats row per club, from Season.season_club_stats (scores + recorded details).
func _build_team_rows(comp: String) -> Array:
	var stats: Dictionary = Season.season_club_stats(_lg_ids(), GameState.fixtures, comp)
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
			"lg": GameState.league_of(str(cid)),
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
			"acc": 100.0 * float(s.get("hits", 0)) / maxf(float(int(s.get("hits", 0)) + int(s.get("misses", 0))), 1.0),
			"crits": int(s.get("crits", 0)),
			"se": int(s.get("se", 0)),
			"sepct": 100.0 * float(s.get("se", 0)) / maxf(float(s.get("hits", 0)), 1.0),
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
		"f1": return I18n.decimal(float(r[key]), 1)
		"f2": return I18n.decimal(float(r[key]), 2)
		"int0": return str(roundi(float(r[key])))
		"rec_h": return "%d-%d" % [int(r["hw"]), int(r["hl"])]
		"rec_a": return "%d-%d" % [int(r["aw"]), int(r["al"])]
		"form": return " ".join((r["form"] as Array).map(func(x): return I18n.t(str(x)))) \
			if not (r["form"] as Array).is_empty() else "-"
		"streak":
			var st := int(r["streak"])
			if st == 0:
				return "-"
			return (I18n.t("W") + str(st)) if st > 0 else (I18n.t("L") + str(-st))
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
		_tinsights.add_child(_insight_chip(tr("NO DATA YET"), {},
			tr("Team statistics appear once the first matchday has been played")))
		return

	var by := func(k: String, best_high: bool) -> Dictionary:
		var out: Dictionary = rows[0]
		for r in rows:
			if (float(r[k]) > float(out[k])) == best_high and float(r[k]) != float(out[k]):
				out = r
		return out

	var atk: Dictionary = by.call("kos", true)
	_tinsights.add_child(_insight_chip(tr("BEST ATTACK"), atk, tr("%d KOs · %.1f per battle") %
		[int(atk["kos"]), float(atk["kos"]) / maxf(float(atk["bw"] + atk["bl"]), 1.0)]))
	var def: Dictionary = by.call("faints", false)
	_tinsights.add_child(_insight_chip(tr("TIGHTEST DEFENCE"), def, tr("%d Pokémon lost in %d matches") %
		[int(def["faints"]), int(def["matches"])]))
	var home_rows: Array = rows.filter(func(r): return int(r["hm"]) >= 2)
	if not home_rows.is_empty():
		home_rows.sort_custom(func(a, b): return float(a["hbpct"]) > float(b["hbpct"]))
		var fort: Dictionary = home_rows[0]
		_tinsights.add_child(_insight_chip(tr("FORTRESS"), fort, tr("%d%% battle wins at home (%d-%d)") %
			[roundi(float(fort["hbpct"])), int(fort["hw"]), int(fort["hl"])]))
	var away_rows: Array = rows.filter(func(r): return int(r["am"]) >= 2)
	if not away_rows.is_empty():
		away_rows.sort_custom(func(a, b): return float(a["abpct"]) > float(b["abpct"]))
		var trav: Dictionary = away_rows[0]
		_tinsights.add_child(_insight_chip(tr("ROAD WARRIORS"), trav, tr("%d%% battle wins away (%d-%d)") %
			[roundi(float(trav["abpct"])), int(trav["aw"]), int(trav["al"])]))
	var hot: Dictionary = by.call("streak", true)
	if int(hot["streak"]) > 0:
		_tinsights.add_child(_insight_chip(tr("IN FORM"), hot,
			tr("won last %d in a row") % int(hot["streak"])))
	var cold: Dictionary = by.call("streak", false)
	if int(cold["streak"]) < 0:
		_tinsights.add_child(_insight_chip(tr("IN CRISIS"), cold,
			tr("lost last %d in a row") % (-int(cold["streak"]))))


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
			{"kind": "club", "id": str(r["cid"])}, tr("%s — view club profile") % r["name"])
		v.add_child(lnk)
	v.add_child(UI.dim(detail, 10))
	p.add_child(v)
	return p


# =================================================================== Data Hub
# FM Data Hub: visual analytics computed from the same recorded match-detail
# aggregates — attack/defence scatter, top-rated bars, KO-difference and
# home-advantage diverging bars. Every mark is hoverable for exact numbers.

func _build_hub() -> void:
	_hub = VBoxContainer.new()
	_hub.add_theme_constant_override("separation", 8)
	_hub.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_hub)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_hub_note = UI.dim("", 11)
	_hub_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_hub_note)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var hint := UI.dim("hover any mark for exact numbers · position graph: League Table › Position Graph", 11)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(hint)
	_hub.add_child(bar)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hub.add_child(grid)

	var mk_card := func(title: String, chart: Control, caption: String) -> PanelContainer:
		var card := UI.card(title)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
		chart.custom_minimum_size.y = 220
		UI.card_body(card).add_child(chart)
		if caption != "":
			UI.card_body(card).add_child(UI.dim(caption, 10))
		return card

	_hub_scatter = Charts.ScatterChart.new()
	_hub_scatter.x_title = tr("damage dealt per battle »")
	_hub_scatter.y_title = tr("damage taken per battle »")
	_hub_scatter.quads = [tr("leaky, low output"), tr("all-out brawlers"), tr("cagey, low output"), tr("complete sides")]
	grid.add_child(mk_card.call(tr("Attack vs Defence · every club"),
		_hub_scatter, tr("dashed lines = league average · ring = your club · right & low = complete side")))

	_hub_top_rated = Charts.BarChartH.new()
	_hub_top_rated.decimals = 2
	_hub_top_rated.label_w = 128.0
	grid.add_child(mk_card.call(tr("Top Rated Pokémon · avg match rating (min 3 apps)"),
		_hub_top_rated, tr("swatch = owning club color")))

	_hub_kod = Charts.BarChartH.new()
	_hub_kod.label_w = 108.0
	grid.add_child(mk_card.call(tr("KO Difference · knocked out minus lost"),
		_hub_kod, tr("green = beats opponents up, red = gets beaten up · swatch = club color")))

	_hub_venue = Charts.BarChartH.new()
	_hub_venue.label_w = 108.0
	_hub_venue.suffix = "pp"
	grid.add_child(mk_card.call(tr("Home Advantage · home minus away battle-win %"),
		_hub_venue, tr("positive = fortress at home, negative = travels better · swatch = club color")))


func _refresh_hub() -> void:
	var team_rows: Array = _build_team_rows("all").filter(func(r): return int(r["matches"]) > 0)
	_hub_note.text = tr("%d clubs with matches played · all marks from recorded match details") % team_rows.size()

	# 1) attack vs defence scatter
	var pts: Array = []
	for r in team_rows:
		if int(r["matches"]) < 1:
			continue
		pts.append({
			"label": str(r["short"]), "x": float(r["dmg_leg"]), "y": float(r["tkn_leg"]),
			"color": UI.club_color(r["club"]),
			"highlight": GameState.is_player_club(str(r["cid"])),
			"tip": I18n.t("%s\nDamage dealt / battle: %d\nDamage taken / battle: %d\nBattle win rate: %d%%") % [
				str(r["name"]), roundi(float(r["dmg_leg"])), roundi(float(r["tkn_leg"])),
				roundi(float(r["bpct"]))],
		})
	_hub_scatter.set_data(pts)

	# 2) top rated Pokémon
	var prows: Array = _build_rows("all").filter(func(r): return int(r["apps"]) >= 3)
	prows.sort_custom(func(a, b): return float(a["rating"]) > float(b["rating"]))
	var bars: Array = []
	for r in prows.slice(0, 10):
		var club: Dictionary = r["club"]
		bars.append({
			"label": str(r["name"]), "value": float(r["rating"]),
			"color": UI.club_color(club) if not club.is_empty() else TB.COL_ACCENT,
			"tip": I18n.t("%s (%s, Lv %d) — %s\nAvg rating %s over %d apps · %d KOs") % [
				str(r["name"]), str(r["species"]), int(r["level"]),
				str(club.get("name", "unattached")), I18n.decimal(float(r["rating"]), 2),
				int(r["apps"]), int(r["kos"])],
		})
	_hub_top_rated.set_data(bars)

	# 3) KO difference (diverging)
	var kod_rows := team_rows.duplicate()
	kod_rows.sort_custom(func(a, b): return int(a["kod"]) > int(b["kod"]))
	var kod_bars: Array = []
	for r in kod_rows:
		kod_bars.append({
			"label": str(r["short"]), "value": float(r["kod"]),
			"color": UI.club_color(r["club"]),
			"tip": I18n.t("%s\nKOs scored %d · conceded %d · difference %+d") % [
				str(r["name"]), int(r["kos"]), int(r["faints"]), int(r["kod"])],
		})
	_hub_kod.set_data(kod_bars)

	# 4) home advantage (diverging, needs home+away sample)
	var venue_rows: Array = team_rows.filter(func(r): return int(r["hm"]) >= 1 and int(r["am"]) >= 1)
	venue_rows.sort_custom(func(a, b): return float(a["venue_gap"]) > float(b["venue_gap"]))
	var venue_bars: Array = []
	for r in venue_rows:
		venue_bars.append({
			"label": str(r["short"]), "value": float(r["venue_gap"]),
			"color": UI.club_color(r["club"]),
			"tip": I18n.t("%s\nHome battle-win %d%% (%d-%d) · away %d%% (%d-%d)") % [
				str(r["name"]), roundi(float(r["hbpct"])), int(r["hw"]), int(r["hl"]),
				roundi(float(r["abpct"])), int(r["aw"]), int(r["al"])],
		})
	_hub_venue.set_data(venue_bars)


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
	_hub.visible = _view == "hub"
	_leaders.visible = _view == "leaders"


func refresh() -> void:
	_apply_dev_region()
	var played_n: int = GameState.fixtures.filter(func(f): return f["played"]).size()
	var scope: String = tr("all regions") if _lg_filter() == "" else tr(GameState.league_name(_lg_filter()))
	_note.text = tr("%s · computed from %d simulated match%s (world-wide)") % [
		scope, played_n, "" if played_n == 1 else "es"]
	match _view:
		"centre":
			_rebuild_table()
		"teams":
			_rebuild_teams()
		"hub":
			_refresh_hub()
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
		if not _club_in_scope(r["club"]):
			continue   # leaders board honours the region scope
		r["avg_rating"] = float(s["rating_sum"]) / maxi(int(s["battles"]), 1)
		rows.append(r)

	# --- Top rated (min 3 battle appearances)
	var rated := rows.filter(func(r): return int(r["battles"]) >= 3)
	rated.sort_custom(func(a, b): return a["avg_rating"] > b["avg_rating"])
	_leaders.add_child(_leader_card(tr("Top Rated Pokémon"), ["Pokémon", "Club", "Lv", "Apps", "Rat"],
		[0, 58, 44, 52, 54], rated, func(r): return [
			str(r["name"]), _short(r), str(r["level"]), str(r["battles"]), I18n.decimal(float(r["avg_rating"]), 2)],
		func(r): return _rating_color(r["avg_rating"])))

	# --- Most KOs
	var kos := rows.duplicate()
	kos.sort_custom(func(a, b):
		if int(a["kos"]) != int(b["kos"]):
			return int(a["kos"]) > int(b["kos"])
		return int(a["dmg"]) > int(b["dmg"]))
	_leaders.add_child(_leader_card(tr("Most KOs"), ["Pokémon", "Club", "Apps", "KOs", "KO/App"],
		[0, 58, 52, 48, 62], kos, func(r): return [
			str(r["name"]), _short(r), str(r["battles"]), str(r["kos"]),
			I18n.decimal(float(r["kos"]) / maxi(int(r["battles"]), 1), 2)],
		func(_r): return Color.WHITE))

	# --- Most damage
	var dmg := rows.duplicate()
	dmg.sort_custom(func(a, b): return int(a["dmg"]) > int(b["dmg"]))
	_leaders.add_child(_leader_card(tr("Most Damage Dealt"), ["Pokémon", "Club", "Apps", "Dmg", "Dmg/App"],
		[0, 58, 52, 62, 66], dmg, func(r): return [
			str(r["name"]), _short(r), str(r["battles"]), str(r["dmg"]),
			str(int(float(r["dmg"]) / maxi(int(r["battles"]), 1)))],
		func(_r): return Color.WHITE))

	# --- Club battle win-rates
	var crec := Season.club_battle_stats(_lg_ids(), GameState.fixtures)
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
		tree.set_column_title(i + 1, tr(titles[i]))
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
			I18n.t("%s — view Pokémon profile") % r["name"])
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
	var card := UI.card(tr("Best Clubs · Battle Win Rate"))
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
		tree.set_column_title(i, tr(titles[i]) if titles[i] != "#" else "#")
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
