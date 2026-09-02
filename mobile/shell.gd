extends Control
## Mobile-first portrait shell (mobile piece). A phone-native way to PLAY the
## same career: bottom tab navigation (Home / Inbox / Squad / League / More),
## a status strip with the Continue flow, and lightweight portrait screens
## that reuse every simulation service untouched. Dense desktop features
## (manual matches, training, transfers…) live in landscape: rotating the
## phone swaps to the desktop shell (compact mode) and back — all game state
## sits in the GameState autoload, so the swap is a plain scene change.

const TABS := [
	["home", "Dashboard"], ["inbox", "Inbox"], ["squad", "Squad"],
	["league", "League"], ["more", "More"],
]

var _content: MarginContainer
var _tab_btns: Dictionary = {}
var _tab_badges: Dictionary = {}
var _pages: Dictionary = {}
var _current := ""
var _continue_btn: Button
var _date_lbl: Label
var _cash_lbl: Label
var _advancing := false
var _swap_pending := false
var _match_due: Dictionary = {}   # fixture held for the Home match-due card


func _ready() -> void:
	if theme == null:
		theme = ThemeBuilder.build()
	if AudioManager.instance == null:
		add_child(load("res://shared/audio/audio_manager.tscn").instantiate())
	# hold player matchdays for a decision (Home shows the match-due card:
	# instant result, or rotate to landscape to manage it live)
	GameState.auto_sim_player_matches = false

	var bg := ColorRect.new()
	bg.color = MUI.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	layout.add_child(_build_topstrip())

	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_content.add_theme_constant_override(side, 8)
	layout.add_child(_content)
	layout.add_child(_build_tabbar())

	_pages["home"] = load("res://mobile/home.gd").new()
	_pages["inbox"] = load("res://mobile/inbox.gd").new()
	_pages["squad"] = load("res://mobile/squad.gd").new()
	_pages["league"] = load("res://mobile/league.gd").new()
	_pages["more"] = load("res://mobile/more.gd").new()
	for k in _pages:
		_pages[k].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pages[k].size_flags_vertical = Control.SIZE_EXPAND_FILL

	GameState.inbox_updated.connect(_refresh_badges)
	GameState.date_changed.connect(func(_d): _refresh_strip())
	get_window().size_changed.connect(_check_orientation)
	open_tab("home")
	_refresh_strip()
	_refresh_badges()


# ---------------------------------------------------------------- navigation

func open_tab(tab: String) -> void:
	if not _pages.has(tab) or tab == _current:
		if tab == _current and _pages[tab].has_method("go_root"):
			_pages[tab].go_root()   # re-tap = back to the tab's list
		return
	for c in _content.get_children():
		_content.remove_child(c)
	_content.add_child(_pages[tab])
	_current = tab
	for k in _tab_btns:
		_tab_btns[k].add_theme_color_override("font_color",
			Color.WHITE if k == tab else ThemeBuilder.COL_TEXT_DIM)
	if _pages[tab].has_method("refresh"):
		_pages[tab].refresh()
	AudioManager.on_screen_changed(tab)


## Shim for the inbox action buttons that target desktop screen names.
func navigate_to(screen_name: String, _context: Dictionary = {}) -> bool:
	var map := {"inbox": "inbox", "squad": "squad", "competition": "league"}
	if map.has(screen_name):
		open_tab(str(map[screen_name]))
		return true
	toast(tr("Rotate to landscape for %s") % tr(screen_name.capitalize()))
	return false


func toast(text: String) -> void:
	var t := PanelContainer.new()
	t.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(Color("2a3150"), ThemeBuilder.COL_ACCENT, 8, 14, 10))
	t.add_child(MUI.title(text, 13))
	t.set_anchors_preset(Control.PRESET_CENTER_TOP)
	t.position.y += 66   # under the status strip, clear of the tab bar
	add_child(t)
	get_tree().create_timer(2.2).timeout.connect(func():
		if is_instance_valid(t):
			t.queue_free())


# ---------------------------------------------------------------- chrome

func _build_topstrip() -> Control:
	var top := PanelContainer.new()
	var sb := ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 0, 10, 8)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	top.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	top.add_child(row)

	row.add_child(Crest.icon(GameState.player_club(), 38, {"no_tooltip": true}))
	var idcol := VBoxContainer.new()
	idcol.alignment = BoxContainer.ALIGNMENT_CENTER
	idcol.add_theme_constant_override("separation", 0)
	var club := MUI.title(str(GameState.player_club().get("short", "TM")), 15)
	idcol.add_child(club)
	_date_lbl = MUI.dim("", 11)
	idcol.add_child(_date_lbl)
	row.add_child(idcol)

	row.add_child(MUI.hspacer())

	var cashcol := VBoxContainer.new()
	cashcol.alignment = BoxContainer.ALIGNMENT_CENTER
	cashcol.add_theme_constant_override("separation", 0)
	_cash_lbl = MUI.label("", 12, ThemeBuilder.COL_GOOD)
	_cash_lbl.add_theme_font_override("font", MUI.bold())
	_cash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cashcol.add_child(_cash_lbl)
	row.add_child(cashcol)

	_continue_btn = MUI.button(tr("Continue"))
	_continue_btn.custom_minimum_size = Vector2(110, 44)
	_continue_btn.pressed.connect(_on_continue)
	row.add_child(_continue_btn)
	return top


func _build_tabbar() -> Control:
	var bar := PanelContainer.new()
	var sb := ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 0, 0, 0)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	bar.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	bar.add_child(row)
	for t in TABS:
		var key: String = t[0]
		var holder := Control.new()
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.custom_minimum_size.y = 54
		var b := Button.new()
		b.text = tr(str(t[1])).to_upper()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_theme_font_override("font", MUI.bold())
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		b.pressed.connect(open_tab.bind(key))
		holder.add_child(b)
		var badge := Label.new()
		badge.visible = false
		badge.add_theme_font_size_override("font_size", 9)
		badge.add_theme_font_override("font", MUI.bold())
		badge.add_theme_color_override("font_color", Color.WHITE)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = ThemeBuilder.COL_BAD
		bsb.set_corner_radius_all(7)
		bsb.content_margin_left = 5
		bsb.content_margin_right = 5
		badge.add_theme_stylebox_override("normal", bsb)
		badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
		badge.position += Vector2(14, 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(badge)
		row.add_child(holder)
		_tab_btns[key] = b
		_tab_badges[key] = badge
	return bar


func _refresh_strip() -> void:
	_date_lbl.text = I18n.pretty_date(GameState.current_date)
	var cur := str(GameState.world["meta"].get("currency", "P$"))
	_cash_lbl.text = "%s%s" % [cur, I18n.number(int(GameState.player_club()["finances"]["balance"]))]


func _refresh_badges() -> void:
	var unread := 0
	for m in GameState.inbox:
		if not m.get("read", false):
			unread += 1
	var badge: Label = _tab_badges["inbox"]
	badge.visible = unread > 0
	badge.text = str(mini(unread, 99))


# ---------------------------------------------------------------- continue

func _on_continue() -> void:
	if _advancing:
		return
	# a matchday is held for your decision: NEVER advance past it (that would
	# abandon the fixture unplayed and the league would pull ahead of you)
	if not due_fixture().is_empty():
		open_tab("home")
		if _pages["home"].has_method("refresh"):
			_pages["home"].refresh()
		toast(tr("Matchday! Resolve today's match first."))
		return
	AudioManager.play("continue")
	_advancing = true
	_continue_btn.disabled = true
	var played := {}
	var stop := false
	for i in 30:
		var inbox_before: int = GameState.inbox.size()
		for e in GameState.advance_day():
			if str(e["t"]) == "player_match_due":
				stop = true
				_match_due = e["fixture"]
			elif str(e["t"]) == "fixture_played":
				var f: Dictionary = e["fixture"]
				if GameState.is_player_club(str(f["home"])) or GameState.is_player_club(str(f["away"])):
					stop = true
					played = f
		var new_count: int = GameState.inbox.size() - inbox_before
		for j in new_count:
			if GameState.inbox[j].get("urgent", false):
				stop = true
		if stop:
			break
		await get_tree().process_frame
	GameState.save_game()
	_advancing = false
	_continue_btn.disabled = false
	_refresh_strip()
	_refresh_badges()
	if _pages[_current].has_method("refresh"):
		_pages[_current].refresh()
	if not _match_due.is_empty():
		open_tab("home")
	if not played.is_empty():
		var we_home: bool = GameState.is_player_club(str(played["home"]))
		var us := int(played["score_home"] if we_home else played["score_away"])
		var them := int(played["score_away"] if we_home else played["score_home"])
		var opp: Dictionary = GameState.club(str(played["away"] if we_home else played["home"]))
		AudioManager.play("crowd_cheer" if us > them else "crowd_gasp")
		toast("%s %d–%d %s" % [tr("Won") if us > them else tr("Lost"),
			us, them, str(opp.get("name", "?"))])


# ---------------------------------------------------------------- rotation

## Landscape = the desktop shell in compact mode. Debounced: browsers fire a
## burst of resizes while rotating.
func _check_orientation() -> void:
	if _swap_pending or _advancing:
		return
	var s := get_window().size
	if s.x > s.y:
		_swap_pending = true
		get_tree().create_timer(0.35).timeout.connect(func():
			var s2 := get_window().size
			if s2.x > s2.y:
				GameState.save_game()
				get_tree().change_scene_to_file("res://shell/main.tscn")
			else:
				_swap_pending = false)


## Home match-due card: take the instant result (the same sim every AI
## fixture gets). Managing it live = rotate to landscape -> Match screen.
func play_due_instant() -> void:
	var f := due_fixture()
	if f.is_empty():
		return
	GameState._play_fixture(f)
	GameState.save_game()
	_match_due = {}
	_refresh_strip()
	_refresh_badges()
	if _pages[_current].has_method("refresh"):
		_pages[_current].refresh()
	var we_home: bool = GameState.is_player_club(str(f["home"]))
	var us := int(f["score_home"] if we_home else f["score_away"])
	var them := int(f["score_away"] if we_home else f["score_home"])
	var opp: Dictionary = GameState.club(str(f["away"] if we_home else f["home"]))
	AudioManager.play("crowd_cheer" if us > them else "crowd_gasp")
	toast("%s %d–%d %s" % [tr("Won") if us > them else tr("Lost"),
		us, them, str(opp.get("name", "?"))])


## The player fixture currently held for a decision ({} if none).
func due_fixture() -> Dictionary:
	var nf := GameState.next_player_fixture()
	if not nf.is_empty() and str(nf["date"]) == GameState.current_date \
			and not nf.get("played", false):
		return nf
	return {}
