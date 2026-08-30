extends Control
## Competition screen — FM24-style League Table / Fixtures & Results /
## Cup Bracket / Season Stats / Overview. All data live from GameState;
## per-Pokemon stats come from deterministic engine replays in Season.

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")
const TableTab := preload("res://screens/competition/table_tab.gd")
const FixturesTab := preload("res://screens/competition/fixtures_tab.gd")
const CupTab := preload("res://screens/competition/cup_tab.gd")
const StatsTab := preload("res://screens/competition/stats_tab.gd")
const OverviewTab := preload("res://screens/competition/overview_tab.gd")
const Profiles := preload("res://screens/competition/profiles.gd")

const TABS := [
	["table", "League Table"],
	["fixtures", "Fixtures & Results"],
	["cup", "Cup"],
	["stats", "Season Stats"],
	["overview", "Overview"],
]

var _tab_buttons: Dictionary = {}
var _views: Dictionary = {}
var _dirty: Dictionary = {}
var _current := "table"

var _hdr_round: Label
var _hdr_pos: Label
var _hdr_next: Label
var _hdr_leader: Label

# entity drill-down (club / Pokémon profiles) layered over the tabs
var _profile_wrap: VBoxContainer
var _profile: Control
var _crumb_bar: HBoxContainer
var _nav_stack: Array = []      # [{"kind":"club"|"pokemon","id":...}, ...]


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_tab_bar())

	var content := PanelContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_BG
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	content.add_theme_stylebox_override("panel", sb)
	root.add_child(content)

	_views["table"] = TableTab.new()
	_views["fixtures"] = FixturesTab.new()
	_views["cup"] = CupTab.new()
	_views["stats"] = StatsTab.new()
	_views["overview"] = OverviewTab.new()
	for key in _views:
		var v: Control = _views[key]
		v.visible = false
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(v)
		_dirty[key] = true

	# profile drill-down host (hidden until an entity link is followed)
	_profile_wrap = VBoxContainer.new()
	_profile_wrap.visible = false
	_profile_wrap.add_theme_constant_override("separation", 8)
	_profile_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_profile_wrap)
	_crumb_bar = HBoxContainer.new()
	_crumb_bar.add_theme_constant_override("separation", 8)
	_profile_wrap.add_child(_crumb_bar)
	_profile = Profiles.new()
	_profile_wrap.add_child(_profile)

	GameState.table_updated.connect(_on_data_changed)
	GameState.date_changed.connect(func(_d): _on_data_changed())
	_select_tab("table")


func on_show() -> void:
	# Dev hooks for screenshot verification only (env-gated, inert in play).
	var adv := OS.get_environment("COMP_DEV_ADVANCE")
	if adv != "":
		var prev_auto := GameState.auto_sim_player_matches
		GameState.auto_sim_player_matches = true
		for i in int(adv):
			GameState.advance_day()
		GameState.auto_sim_player_matches = prev_auto
		GameState.save_game()
	for key in _dirty:
		_dirty[key] = true
	var tab := OS.get_environment("COMP_DEV_TAB")
	if tab != "" and _views.has(tab):
		_select_tab(tab)
	else:
		_select_tab(_current)
	var prof := OS.get_environment("COMP_DEV_PROFILE")
	if prof != "":
		_dev_open_profile(prof)
	_refresh_header()


func _dev_open_profile(spec: String) -> void:
	## Screenshot-harness hook only: "club:<id>" | "pokemon:<uid>" | "pokemon:auto".
	var parts := spec.split(":")
	if parts.size() != 2:
		return
	var id := parts[1]
	if parts[0] == "pokemon" and id == "auto":
		var stats: Dictionary = Season.season_player_stats(GameState.fixtures)
		var best := ""
		var best_r := -1.0
		for uid in stats:
			var s: Dictionary = stats[uid]
			if int(s["battles"]) < 3:
				continue
			var r := float(s["rating_sum"]) / maxi(int(s["battles"]), 1)
			if r > best_r:
				best_r = r
				best = str(uid)
		id = best
	if id != "":
		comp_navigate({"kind": parts[0], "id": id})


func _on_data_changed() -> void:
	for key in _dirty:
		_dirty[key] = true
	if is_inside_tree() and is_visible_in_tree():
		_refresh_header()
		if _profile_wrap.visible and not _nav_stack.is_empty():
			_profile.refresh()   # profiles stay live as Continue advances
		else:
			_refresh_current()


# ------------------------------------------------- entity click-through nav

## Single entry point for every entity hyperlink on this screen (and for the
## shell's global search context via reveal_search_target).
## ctx: {"kind": "club"|"pokemon"|"fixture"|"tab", "id": ...}
func comp_navigate(ctx: Dictionary) -> void:
	var kind := str(ctx.get("kind", ""))
	var id := str(ctx.get("id", ""))
	if id == "":
		return
	match kind:
		"club", "pokemon":
			_push_profile({"kind": kind, "id": id})
		"fixture":
			_close_profile()
			_select_tab("fixtures")
			_views["fixtures"].select_fixture(id)
		"tab":
			if _views.has(id):
				_select_tab(id)


## Shell hands global-search results (clubs, rival Pokémon) to this screen.
func reveal_search_target(ctx: Dictionary) -> void:
	comp_navigate(ctx)


func _push_profile(entry: Dictionary) -> void:
	if not _nav_stack.is_empty():
		var top: Dictionary = _nav_stack.back()
		if top["kind"] == entry["kind"] and top["id"] == entry["id"]:
			_profile.refresh()
			return
	_nav_stack.append(entry)
	if _nav_stack.size() > 24:
		_nav_stack.pop_front()
	_show_profile()


func _show_profile() -> void:
	for k in _views:
		_views[k].visible = false
	_profile_wrap.visible = true
	_profile.show_ctx(_nav_stack.back())
	_rebuild_crumbs()


func _profile_back() -> void:
	_nav_stack.pop_back()
	if _nav_stack.is_empty():
		_close_profile()
		_select_tab(_current)
	else:
		_show_profile()


func _jump_to_stack(idx: int) -> void:
	_nav_stack.resize(idx + 1)
	_show_profile()


func _close_profile() -> void:
	_nav_stack.clear()
	_profile_wrap.visible = false


func _rebuild_crumbs() -> void:
	for c in _crumb_bar.get_children():
		c.queue_free()
	var back := Button.new()
	back.text = "‹ Back"
	back.custom_minimum_size = Vector2(72, 26)
	back.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	back.tooltip_text = "Back to %s" % (_crumb_name(_nav_stack[_nav_stack.size() - 2])
		if _nav_stack.size() > 1 else _tab_title(_current))
	back.pressed.connect(_profile_back)
	_crumb_bar.add_child(back)
	_crumb_bar.add_child(VSeparator.new())

	# root crumb: the tab this drill-down started from
	var root_btn := UI.link(_tab_title(_current), 12, TB.COL_TEXT_DIM,
		{"kind": "tab", "id": _current}, "Back to %s" % _tab_title(_current))
	root_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_crumb_bar.add_child(root_btn)
	for i in _nav_stack.size():
		var sep := UI.dim("›", 12)
		sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_crumb_bar.add_child(sep)
		var nm := _crumb_name(_nav_stack[i])
		if i == _nav_stack.size() - 1:
			var cur := UI.label(nm, 13, Color.WHITE)
			cur.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_crumb_bar.add_child(cur)
		else:
			var lb := UI.Link.new(nm, 12, TB.COL_TEXT_DIM)
			lb.tooltip_text = "Back to %s" % nm
			lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var idx := i
			lb.pressed.connect(func(): _jump_to_stack(idx))
			_crumb_bar.add_child(lb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crumb_bar.add_child(spacer)
	var hint := UI.dim("Club & Pokémon profile · all names are links", 11)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_crumb_bar.add_child(hint)


func _crumb_name(entry: Dictionary) -> String:
	match str(entry["kind"]):
		"club":
			return str(GameState.club(str(entry["id"])).get("name", "Club"))
		"pokemon":
			var inst := UI.find_instance(str(entry["id"]))
			return UI.display_name(inst) if not inst.is_empty() else "Pokémon"
	return "?"


func _tab_title(key: String) -> String:
	for entry in TABS:
		if entry[0] == key:
			return entry[1]
	return key


# ------------------------------------------------------------------ header

func _build_header() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.border_color = TB.COL_BORDER
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	var title := Label.new()
	title.text = str(GameState.world["meta"]["league_name"]).to_upper()
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	name_box.add_child(title)
	name_box.add_child(UI.dim("with the Indigo Cup · Season %s" % GameState.season_start.split("-")[0], 12))
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_box)

	_hdr_round = _header_stat(h, "MATCHDAY")
	_hdr_pos = _header_stat(h, "YOUR POSITION")
	_hdr_next = _header_stat(h, "NEXT MATCHDAY")
	_hdr_leader = _header_stat(h, "LEADER")
	return panel


func _header_stat(parent: HBoxContainer, caption: String) -> Label:
	var sep := VSeparator.new()
	parent.add_child(sep)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var value := Label.new()
	value.text = "-"
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(value)
	var cap := UI.dim(caption, 10)
	v.add_child(cap)
	parent.add_child(v)
	return value


func _refresh_header() -> void:
	var fixtures: Array = GameState.fixtures
	var completed := 0
	for f in fixtures:
		if f["comp"] == "league" and f["played"]:
			completed = maxi(completed, int(f["round"]))
	var total := Season.total_league_rounds(fixtures)
	_hdr_round.text = "%d / %d" % [completed, total]

	var pos := GameState.player_table_position()
	_hdr_pos.text = _ord(pos)
	_hdr_pos.add_theme_color_override("font_color", TB.COL_ACCENT.lightened(0.35))

	var upcoming: Array = fixtures.filter(func(f): return not f["played"] and f["date"] > GameState.current_date)
	if upcoming.is_empty():
		_hdr_next.text = "Season over"
	else:
		upcoming.sort_custom(func(a, b): return a["date"] < b["date"])
		var days := Season.days_between(GameState.current_date, upcoming[0]["date"])
		_hdr_next.text = "%s (%dd)" % [UI.short_date(upcoming[0]["date"]), days]

	var table: Array = GameState.league_table()
	if table.is_empty() or int(table[0]["played"]) == 0:
		_hdr_leader.text = "-"
	else:
		var leader := GameState.club(table[0]["club_id"])
		_hdr_leader.text = "%s · %d pts" % [leader.get("short", "?"), int(table[0]["points"])]


# ------------------------------------------------------------------ tabs

func _build_tab_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for entry in TABS:
		var b := Button.new()
		b.text = entry[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 32)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_select_tab.bind(entry[0]))
		bar.add_child(b)
		_tab_buttons[entry[0]] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	return bar


func _select_tab(key: String) -> void:
	_current = key
	if _profile_wrap != null:
		_close_profile()
	for k in _tab_buttons:
		var b: Button = _tab_buttons[k]
		var active: bool = k == key
		b.set_pressed_no_signal(active)
		if active:
			b.add_theme_stylebox_override("normal", _tab_style(true))
			b.add_theme_stylebox_override("hover", _tab_style(true))
			b.add_theme_stylebox_override("pressed", _tab_style(true))
			b.add_theme_color_override("font_color", Color.WHITE)
		else:
			b.add_theme_stylebox_override("normal", _tab_style(false))
			b.add_theme_stylebox_override("hover", _tab_style(false, true))
			b.add_theme_stylebox_override("pressed", _tab_style(true))
			b.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
	for k in _views:
		_views[k].visible = k == key
	_refresh_current()


func _refresh_current() -> void:
	if _dirty.get(_current, false):
		_dirty[_current] = false
		_views[_current].refresh()


func _tab_style(active: bool, hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	if active:
		sb.bg_color = TB.COL_PANEL_ALT
		sb.border_color = TB.COL_ACCENT
		sb.set_border_width_all(0)
		sb.border_width_bottom = 3
	else:
		sb.bg_color = Color("1e2436") if hover else TB.COL_PANEL
		sb.border_color = TB.COL_BORDER
		sb.set_border_width_all(1)
	return sb


func _ord(n: int) -> String:
	if n <= 0:
		return "-"
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
