extends Control
## Competition screen — FM24-style League Table / Fixtures & Results /
## Cup Bracket / Season Stats / Overview. All data live from GameState;
## per-Pokemon stats come from deterministic engine replays in Season.

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")
const TableTab := preload("res://screens/competition/table_tab.gd")
const FixturesTab := preload("res://screens/competition/fixtures_tab.gd")
const CupTab := preload("res://screens/competition/cup_tab.gd")
const PlayoffTab := preload("res://screens/competition/playoff_tab.gd")
const StatsTab := preload("res://screens/competition/stats_tab.gd")
const OverviewTab := preload("res://screens/competition/overview_tab.gd")
const HistoryTab := preload("res://screens/competition/history_tab.gd")
const Profiles := preload("res://screens/competition/profiles.gd")
const SeasonFlow := preload("res://shared/sim/services/season_flow.gd")

const TABS := [
	["table", "League Table"],
	["fixtures", "Fixtures & Results"],
	["cup", "Cup"],
	["playoff", "Championship Series"],
	["stats", "Season Stats"],
	["overview", "Overview"],
	["history", "History"],
]

var _tab_buttons: Dictionary = {}
var _views: Dictionary = {}
var _dirty: Dictionary = {}
var _current := "table"

# competition context: a league id ("kanto"/"johto") or "cup" (Indigo Cup).
# FM lets you browse ANY competition — every tab renders for this context.
var _comp_ctx := ""
var _ctx_buttons: Dictionary = {}

var _hdr_title: Label
var _hdr_sub: Label
var _hdr_round: Label
var _hdr_round_cap: Label
var _hdr_pos: Label
var _hdr_pos_cap: Label
var _hdr_next: Label
var _hdr_leader: Label
var _hdr_leader_cap: Label

# entity drill-down (club / Pokémon profiles) layered over the tabs
var _profile_wrap: VBoxContainer
var _profile: Control
var _crumb_bar: HBoxContainer
var _nav_stack: Array = []      # [{"kind":"club"|"pokemon","id":...}, ...]


func _ready() -> void:
	_comp_ctx = GameState.player_league_id()
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
	_views["playoff"] = PlayoffTab.new()
	_views["stats"] = StatsTab.new()
	_views["overview"] = OverviewTab.new()
	_views["history"] = HistoryTab.new()
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
	_apply_ctx(_comp_ctx)
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
	var lg := OS.get_environment("COMP_DEV_LEAGUE")
	if lg != "" and (lg == "cup" or GameState.leagues().any(func(l): return str(l["id"]) == lg)):
		comp_set_league(lg)
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


# --------------------------------------------------- competition switching

## Public: switch which competition every tab renders (league id or "cup").
## Tabs call this too (UI walk) when a cross-league link needs the context to
## follow, e.g. opening a Johto fixture while browsing Kanto.
func comp_set_league(ctx: String) -> void:
	if ctx == _comp_ctx:
		_apply_ctx(ctx)   # re-assert button states (re-click of active toggle)
		return
	_apply_ctx(ctx)
	for key in _dirty:
		_dirty[key] = true
	if not _nav_stack.is_empty():
		_close_profile()
	if ctx == "cup" and _current == "table":
		_select_tab("cup")   # a knockout has no league table
	else:
		_select_tab(_current)
	_refresh_header()


## Push the context into every tab that understands it and restyle the switcher.
func _apply_ctx(ctx: String) -> void:
	_comp_ctx = ctx
	var lg := ctx if ctx != "cup" else GameState.player_league_id()
	for k in _views:
		if _views[k].has_method("set_league_context"):
			_views[k].set_league_context(lg, ctx == "cup")
	for k in _ctx_buttons:
		var b: Button = _ctx_buttons[k]
		var active: bool = k == ctx
		b.set_pressed_no_signal(active)
		var col: Color = UI.league_color(str(k)) if k != "cup" else Color(0.83, 0.68, 0.21)
		b.add_theme_color_override("font_color", col.lightened(0.3) if active else TB.COL_TEXT_DIM)
		b.add_theme_stylebox_override("normal", _ctx_style(active, col))
		b.add_theme_stylebox_override("hover", _ctx_style(true, col))
		b.add_theme_stylebox_override("pressed", _ctx_style(true, col))
	# a cup context greys out the League Table tab
	if _tab_buttons.has("table"):
		var tb: Button = _tab_buttons["table"]
		tb.disabled = ctx == "cup"
		tb.tooltip_text = "Knockout competition — no league table" if ctx == "cup" else ""


func _ctx_style(active: bool, col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.set_corner_radius_all(3)
	sb.bg_color = Color(col.r, col.g, col.b, 0.14) if active else TB.COL_PANEL
	sb.border_color = Color(col.r, col.g, col.b, 0.8) if active else TB.COL_BORDER
	sb.set_border_width_all(1)
	return sb


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
		"league":
			_close_profile()
			comp_set_league(id)
			if id != "cup" and _current != "table":
				_select_tab("table")


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
	_hdr_title = Label.new()
	_hdr_title.add_theme_font_size_override("font_size", 22)
	_hdr_title.add_theme_color_override("font_color", Color.WHITE)
	name_box.add_child(_hdr_title)
	_hdr_sub = UI.dim("", 12)
	name_box.add_child(_hdr_sub)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_box)

	_hdr_round = _header_stat(h, "MATCHDAY")
	_hdr_round_cap = _hdr_round.get_parent().get_child(1)
	_hdr_pos = _header_stat(h, "YOUR POSITION")
	_hdr_pos_cap = _hdr_pos.get_parent().get_child(1)
	_hdr_next = _header_stat(h, "NEXT MATCHDAY")
	_hdr_leader = _header_stat(h, "LEADER")
	_hdr_leader_cap = _hdr_leader.get_parent().get_child(1)
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
	if _comp_ctx == "cup":
		_refresh_header_cup()
		return
	var season_t := "Season %d" % GameState.season_no()
	_hdr_title.text = GameState.league_name(_comp_ctx).to_upper()
	var other := ""
	for lg in GameState.leagues():
		if str(lg["id"]) != _comp_ctx:
			other = str(lg["name"])
	_hdr_sub.text = "with the %s and the %s · %s" % [other, GameState.cup_name(), season_t] \
		if other != "" else "with the %s · %s" % [GameState.cup_name(), season_t]

	var lg_fixtures: Array = Season.league_fixtures(GameState.fixtures, _comp_ctx)
	var completed := 0
	for f in lg_fixtures:
		if f["played"]:
			completed = maxi(completed, int(f["round"]))
	var total := Season.total_league_rounds(lg_fixtures)
	_hdr_round_cap.text = "MATCHDAY"
	_hdr_round.text = "%d / %d" % [completed, total]

	# "your position" only exists inside the player's own championship —
	# browsing the other league shows its front-runner gap instead.
	var table: Array = GameState.league_table(_comp_ctx)
	if _comp_ctx == GameState.player_league_id():
		_hdr_pos_cap.text = "YOUR POSITION"
		var pos := GameState.player_table_position()
		var no_games := true
		for r in table:
			if GameState.is_player_club(r["club_id"]):
				no_games = int(r.get("played", 0)) == 0
		_hdr_pos.text = "—" if no_games else _ord(pos)
		_hdr_pos.add_theme_color_override("font_color", TB.COL_ACCENT.lightened(0.35))
	else:
		_hdr_pos_cap.text = "TITLE GAP 1st-2nd"
		if table.size() >= 2 and int(table[0]["played"]) > 0:
			_hdr_pos.text = "%d pts" % (int(table[0]["points"]) - int(table[1]["points"]))
		else:
			_hdr_pos.text = "—"
		_hdr_pos.add_theme_color_override("font_color", Color.WHITE)

	var upcoming: Array = lg_fixtures.filter(func(f): return not f["played"] and f["date"] > GameState.current_date)
	if upcoming.is_empty():
		_hdr_next.text = _season_end_text()
	else:
		upcoming.sort_custom(func(a, b): return a["date"] < b["date"])
		var days := Season.days_between(GameState.current_date, upcoming[0]["date"])
		_hdr_next.text = "%s (%dd)" % [UI.short_date(upcoming[0]["date"]), days]

	_hdr_leader_cap.text = "LEADER"
	if table.is_empty() or int(table[0]["played"]) == 0:
		_hdr_leader.text = "-"
	else:
		var leader := GameState.club(table[0]["club_id"])
		_hdr_leader.text = "%s · %d pts" % [leader.get("short", "?"), int(table[0]["points"])]


## What comes after matchday 30 — the season never dead-ends: Championship
## Series rounds, then the ceremony, then the next season's start date.
func _season_end_text() -> String:
	var po: Array = Season.playoff_fixtures(GameState.fixtures)
	if po.is_empty():
		return "CS draw pending" if Season.league_complete(GameState.fixtures) else "Season over"
	var pending: Array = po.filter(func(f): return not f["played"])
	if not pending.is_empty():
		pending.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
		return "CS %s %s" % [Season.playoff_round_name(int(pending[0]["round"])),
			UI.short_date(str(pending[0]["date"]))]
	var flow: Variant = SeasonFlow.instance
	if flow != null and str(flow.rollover_date) != "":
		return "Season %d: %s" % [GameState.season_no() + 1, UI.short_date(str(flow.rollover_date))]
	return "Off-season"


func _refresh_header_cup() -> void:
	_hdr_title.text = GameState.cup_name().to_upper()
	var names: Array = GameState.leagues().map(func(l): return str(l["name"]))
	_hdr_sub.text = "cross-league knockout · clubs from the %s · Season %d" % [
		" and ".join(names), GameState.season_no()]
	var cup: Array = Season.cup_fixtures(GameState.fixtures)
	var max_round := 0
	var total_rounds := 5
	for f in cup:
		max_round = maxi(max_round, int(f["round"]))
	_hdr_round_cap.text = "ROUND"
	_hdr_round.text = "%s (%d/%d)" % [Season.cup_round_name(max_round), max_round, total_rounds] \
		if max_round > 0 else "Draw pending"

	# your cup status
	_hdr_pos_cap.text = "YOUR STATUS"
	var pid: String = GameState.world["meta"]["player_club_id"]
	var out_round := 0
	for f in cup:
		if f["played"] and (f["home"] == pid or f["away"] == pid) \
				and Season.fixture_winner(f) != pid:
			out_round = int(f["round"])
	var current: Array = cup.filter(func(f): return int(f["round"]) == max_round)
	var final_done: bool = max_round == total_rounds \
		and not current.any(func(f): return not f["played"])
	if final_done and Season.fixture_winner(current[0]) == pid:
		_hdr_pos.text = "Champions"
		_hdr_pos.add_theme_color_override("font_color", Color(0.95, 0.83, 0.4))
	elif out_round > 0:
		_hdr_pos.text = "Out (%s)" % Season.cup_round_name(out_round)
		_hdr_pos.add_theme_color_override("font_color", UI.COL_LOSS)
	else:
		_hdr_pos.text = "In the draw"
		_hdr_pos.add_theme_color_override("font_color", UI.COL_WIN)

	var upcoming: Array = cup.filter(func(f): return not f["played"] and f["date"] > GameState.current_date)
	if upcoming.is_empty():
		_hdr_next.text = "Final played" if final_done else "Next draw pending"
	else:
		upcoming.sort_custom(func(a, b): return a["date"] < b["date"])
		var days := Season.days_between(GameState.current_date, upcoming[0]["date"])
		_hdr_next.text = "%s (%dd)" % [UI.short_date(upcoming[0]["date"]), days]

	_hdr_leader_cap.text = "HOLDERS / WINNERS"
	if final_done:
		_hdr_leader.text = str(GameState.club(Season.fixture_winner(current[0])).get("short", "?"))
	else:
		_hdr_leader.text = "TBD"


# ------------------------------------------------------------------ tabs

func _build_tab_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for entry in TABS:
		var b := Button.new()
		b.text = entry[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(_select_tab.bind(entry[0]))
		bar.add_child(b)
		_tab_buttons[entry[0]] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# competition switcher (FM: browse any competition, not just your own)
	var cap := UI.dim("COMPETITION", 10)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(cap)
	var entries: Array = []
	for lg in GameState.leagues():
		entries.append([str(lg["id"]), str(lg["name"])])
	entries.append(["cup", GameState.cup_name()])
	for entry in entries:
		var b := Button.new()
		b.text = str(entry[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(108, 28)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.tooltip_text = "Browse the %s" % entry[1]
		b.pressed.connect(comp_set_league.bind(str(entry[0])))
		bar.add_child(b)
		_ctx_buttons[str(entry[0])] = b
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
