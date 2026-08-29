extends Control
## Shell v0: FM-style chrome. Left sidebar nav + top bar + content area.
## Screens are discovered BY CONVENTION at startup: every folder under
## res://screens/ that contains screen.tscn + screen.json becomes a nav entry.
## screen.json: {"title": "Squad", "order": 10, "icon_letter": "S"}
##
## OWNERSHIP: the "shell" piece owns res://shell/. Screen pieces never edit
## this file — they just drop their folder into res://screens/.
##
## Public API (used by tools/screenshots.gd and screens):
##   navigate_to(name: String) -> bool
##   screens: Dictionary  (name -> {title, order, icon_letter, path})
##   current_screen_name: String

var screens: Dictionary = {}
var current_screen_name: String = ""

var _content: MarginContainer
var _nav_box: VBoxContainer
var _nav_buttons: Dictionary = {}
var _date_label: Label
var _club_label: Label
var _pos_label: Label
var _continue_btn: Button


func _ready() -> void:
	theme = ThemeBuilder.build()
	_build_chrome()
	_discover_screens()
	_build_nav()
	GameState.date_changed.connect(func(_d): _refresh_topbar())
	GameState.table_updated.connect(_refresh_topbar)
	GameState.career_started.connect(_refresh_topbar)
	_refresh_topbar()
	if not screens.is_empty():
		navigate_to(screens.keys().front())


# ------------------------------------------------------------------ navigation

func navigate_to(screen_name: String) -> bool:
	if not screens.has(screen_name):
		push_error("Shell: unknown screen '%s'" % screen_name)
		return false
	for child in _content.get_children():
		child.queue_free()
	var packed: PackedScene = load(screens[screen_name]["path"])
	if packed == null:
		push_error("Shell: failed to load scene for screen '%s'" % screen_name)
		return false
	var inst := packed.instantiate()
	_content.add_child(inst)
	current_screen_name = screen_name
	for n in _nav_buttons:
		_nav_buttons[n].button_pressed = (n == screen_name)
	if inst.has_method("on_show"):
		inst.call("on_show")
	return true


func _discover_screens() -> void:
	var dir := DirAccess.open("res://screens")
	if dir == null:
		push_warning("Shell: res://screens not found")
		return
	for folder in dir.get_directories():
		var scene_path := "res://screens/%s/screen.tscn" % folder
		var meta_path := "res://screens/%s/screen.json" % folder
		if not FileAccess.file_exists(meta_path) or not ResourceLoader.exists(scene_path):
			continue
		var meta: Variant = JSON.parse_string(FileAccess.open(meta_path, FileAccess.READ).get_as_text())
		if meta == null or typeof(meta) != TYPE_DICTIONARY:
			push_warning("Shell: bad screen.json in %s" % folder)
			continue
		screens[folder] = {
			"title": meta.get("title", folder.capitalize()),
			"order": int(meta.get("order", 999)),
			"icon_letter": meta.get("icon_letter", folder.substr(0, 1).to_upper()),
			"path": scene_path,
		}
	print("Shell: discovered %d screens: %s" % [screens.size(), ", ".join(screens.keys())])


# ------------------------------------------------------------------ chrome

func _build_chrome() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = ThemeBuilder.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	# --- top bar
	var top := PanelContainer.new()
	var top_style := ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 0, 16, 8)
	top.add_theme_stylebox_override("panel", top_style)
	top.custom_minimum_size.y = 52
	layout.add_child(top)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	top.add_child(top_row)

	var badge := _make_badge()
	top_row.add_child(badge)

	_club_label = Label.new()
	_club_label.add_theme_font_size_override("font_size", 18)
	_club_label.add_theme_color_override("font_color", Color.WHITE)
	top_row.add_child(_club_label)

	_pos_label = Label.new()
	_pos_label.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	top_row.add_child(_pos_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	_date_label = Label.new()
	_date_label.add_theme_font_size_override("font_size", 16)
	top_row.add_child(_date_label)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue  ▶"
	_continue_btn.custom_minimum_size = Vector2(150, 36)
	_continue_btn.add_theme_color_override("font_color", Color.WHITE)
	_continue_btn.add_theme_stylebox_override("normal",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT_DIM, ThemeBuilder.COL_ACCENT, 4, 12, 6))
	_continue_btn.add_theme_stylebox_override("hover",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT, ThemeBuilder.COL_ACCENT, 4, 12, 6))
	_continue_btn.pressed.connect(_on_continue)
	top_row.add_child(_continue_btn)

	# --- body: sidebar + content
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	layout.add_child(body)

	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 208
	sidebar.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_BORDER, 0, 8, 12))
	body.add_child(sidebar)

	_nav_box = VBoxContainer.new()
	_nav_box.add_theme_constant_override("separation", 4)
	sidebar.add_child(_nav_box)

	var title := Label.new()
	title.text = "TRAINER MANAGER"
	title.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	title.add_theme_font_size_override("font_size", 13)
	_nav_box.add_child(title)
	var sep := HSeparator.new()
	_nav_box.add_child(sep)

	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_content.add_theme_constant_override(side, 16)
	body.add_child(_content)


func _make_badge() -> Control:
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(36, 36)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeBuilder.COL_ACCENT
	sb.set_corner_radius_all(18)
	badge.add_theme_stylebox_override("panel", sb)
	var letter := Label.new()
	letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_color_override("font_color", Color.WHITE)
	letter.text = str(GameState.player_club().get("short", "TM")).substr(0, 2)
	badge.add_child(letter)
	return badge


func _build_nav() -> void:
	var names := screens.keys()
	names.sort_custom(func(a, b): return screens[a]["order"] < screens[b]["order"])
	var ordered := {}
	for n in names:
		ordered[n] = screens[n]
	screens = ordered
	for n in names:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "  %s   %s" % [screens[n]["icon_letter"], screens[n]["title"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.y = 34
		btn.pressed.connect(navigate_to.bind(n))
		_nav_box.add_child(btn)
		_nav_buttons[n] = btn


func _on_continue() -> void:
	GameState.advance_to_next_event()
	_refresh_topbar()
	# re-instance current screen so stubs show fresh data
	if current_screen_name != "":
		navigate_to(current_screen_name)


func _refresh_topbar() -> void:
	var pc := GameState.player_club()
	_club_label.text = str(pc.get("name", "—"))
	_date_label.text = Season.pretty_date(GameState.current_date)
	var pos := GameState.player_table_position()
	_pos_label.text = "%s · %s in %s" % [pc.get("manager", ""), _ordinal(pos), GameState.world["meta"]["league_name"]]


func _ordinal(n: int) -> String:
	if n <= 0:
		return "—"
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
