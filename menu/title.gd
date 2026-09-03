extends Control
## TITLE SCREEN (menu piece) — the game's main scene (project.godot).
## FM24-style game entry: typographic wordmark over a subtle animated
## theme-colored backdrop, procedural menu music, and the career doors:
## Continue (only when a save exists — shows club/manager/date/season),
## New Game (multi-step onboarding), Settings, Quit.
##
## DIRECT-BOOT CONTRACT (testing compatibility — do not break):
## when MenuFlow.quickstart() is true (headless run, `--quickstart` CLI flag
## or TM_QUICKSTART env var) this scene immediately swaps itself for
## res://shell/main.tscn, so scripts/smoke.sh, tools/sim_check.tscn,
## tools/screenshots.tscn and every headless driver behave exactly as before
## the menu existed. Harness scenes that instantiate the shell directly are
## unaffected either way (GameState is an autoload and boots regardless).

const Onboarding := preload("res://menu/onboarding.gd")
const Backdrop := preload("res://menu/backdrop.gd")
const SettingsScreen := preload("res://screens/settings/screen.tscn")

var _fonts: Dictionary = {}
var _onboarding: Control = null
var _settings_overlay: Control = null
var _narrow := false   # portrait phone layout (mobile piece)


func _ready() -> void:
	if MenuFlow.quickstart():
		get_tree().change_scene_to_file.call_deferred("res://shell/main.tscn")
		return
	theme = ThemeBuilder.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fonts = MenuFlow.fonts()
	# menu music + UI sounds (the shell builds its own manager once in-game)
	add_child(load("res://shared/audio/audio_manager.tscn").instantiate())
	_build()


func _build() -> void:
	_narrow = get_viewport_rect().size.x < 700.0   # portrait phone
	var backdrop: Control = Backdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_build_menu_only()
	if not get_window().size_changed.is_connected(_on_resized):
		get_window().size_changed.connect(_on_resized)


## Build stamp written by scripts/export_web.sh / export_all.sh at export
## time ("dev" when running from the editor) — lets testers verify at a
## glance that they are on the latest deploy (user request).
func _build_version() -> String:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else "dev"


## Rotation flips the layout between the wide and the portrait wordmark/menu.
func _on_resized() -> void:
	var narrow_now := get_viewport_rect().size.x < 700.0
	if narrow_now == _narrow:
		return
	for c in get_children():
		if c is Control:
			c.queue_free()
	_build()


func _wordmark() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var eyebrow := Label.new()
	eyebrow.text = tr("POKÉMON BATTLE MANAGEMENT")
	eyebrow.add_theme_font_override("font", _fonts["header"])
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	box.add_child(eyebrow)

	var row: BoxContainer = VBoxContainer.new() if _narrow else HBoxContainer.new()
	row.add_theme_constant_override("separation", 0 if _narrow else 18)
	var t1 := Label.new()
	t1.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # brand wordmark
	t1.text = "TRAINER"
	t1.add_theme_font_override("font", _fonts["header"])
	t1.add_theme_font_size_override("font_size", 46 if _narrow else 68)
	t1.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(t1)
	var t2 := Label.new()
	t2.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # brand wordmark
	t2.text = "MANAGER"
	t2.add_theme_font_override("font", _fonts["header"])
	t2.add_theme_font_size_override("font_size", 46 if _narrow else 68)
	t2.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	row.add_child(t2)
	box.add_child(row)

	var bar := ColorRect.new()
	bar.color = ThemeBuilder.COL_ACCENT
	bar.custom_minimum_size = Vector2(132, 4)
	box.add_child(bar)
	box.add_child(_gap(10))

	var tag := Label.new()
	tag.text = tr("You don't catch 'em all. You manage 'em.")
	tag.add_theme_font_override("font", _fonts["semibold"])
	tag.add_theme_font_size_override("font_size", 13 if _narrow else 16)
	tag.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	box.add_child(tag)
	return box


func _continue_sub_text() -> String:
	var s := MenuFlow.save_summary()
	if s.is_empty():
		return ""
	return "%s · %s  —  %s · %s" % [str(s["club"]), str(s["manager"]),
		I18n.pretty_date(str(s["date"])), tr("Season %d") % int(s["season"])]


func _gap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	return c


func _menu_button(main: String, sub: String, primary: bool, action: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0 if _narrow else 560, 58 if sub != "" else 46)
	if _narrow:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base_bg: Color = ThemeBuilder.COL_ACCENT_DIM if primary else ThemeBuilder.COL_PANEL
	var base_bd: Color = ThemeBuilder.COL_ACCENT if primary else ThemeBuilder.COL_BORDER
	btn.add_theme_stylebox_override("normal", ThemeBuilder._flat(base_bg, base_bd, 6, 18, 8))
	btn.add_theme_stylebox_override("hover",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT if primary else Color("2a3150"),
			ThemeBuilder.COL_ACCENT, 6, 18, 8))
	btn.add_theme_stylebox_override("pressed",
		ThemeBuilder._flat(Color("9488ff"), Color("b0a8ff"), 6, 18, 8))
	btn.pressed.connect(action)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 1)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 18)
	m.add_child(box)
	btn.add_child(m)

	var l1 := Label.new()
	l1.text = main.to_upper()
	l1.add_theme_font_override("font", _fonts["header"])
	l1.add_theme_font_size_override("font_size", 17)
	l1.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(l1)
	if sub != "":
		var l2 := Label.new()
		l2.text = sub
		l2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l2.add_theme_font_size_override("font_size", 11)
		l2.add_theme_color_override("font_color",
			Color("d8d4ff") if primary else ThemeBuilder.COL_TEXT_DIM)
		box.add_child(l2)
	return btn


func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	if _narrow:
		# phones: the giant wordmark is right above — no brand echo needed
		l.text = ""
	else:
		var leagues: Array = GameState.leagues()
		var names: Array = leagues.map(func(lg): return tr(str(lg["name"])))
		l.text = "TRAINER MANAGER  ·  %s  ·  %s" % [" / ".join(names), tr(GameState.cup_name())]
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # never force col width
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	row.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var engine := Label.new()
	engine.text = "%s · %s" % [tr("Made with Godot 4.6"), _build_version()]
	engine.add_theme_font_size_override("font_size", 11)
	engine.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	row.add_child(engine)
	return row


# ------------------------------------------------------------------ actions

func _on_continue() -> void:
	AudioManager.play("continue")
	get_tree().change_scene_to_file(MenuFlow.shell_scene())


func _on_new_game() -> void:
	if _onboarding != null and is_instance_valid(_onboarding):
		return
	AudioManager.play("confirm")
	_onboarding = Onboarding.new()
	_onboarding.setup(_fonts["bold"], _fonts["semibold"], _fonts["header"])
	_onboarding.career_created.connect(func():
		_onboarding = null
		get_tree().change_scene_to_file(MenuFlow.shell_scene()))
	_onboarding.cancelled.connect(func(): _onboarding = null)
	add_child(_onboarding)


func _on_settings() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var vp := get_viewport_rect().size   # phones: never wider than the screen
	panel.custom_minimum_size = Vector2(minf(1180.0, vp.x - 12.0), minf(760.0, vp.y - 12.0))
	panel.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_ACCENT_DIM, 8, 16, 12))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = tr("Settings").to_upper()
	title.add_theme_font_override("font", _fonts["header"])
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := Button.new()
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(120, 36)
	back.pressed.connect(func():
		overlay.queue_free()
		_settings_overlay = null
		_refresh_menu())
	head.add_child(back)
	col.add_child(head)
	var screen: Control = SettingsScreen.instantiate()
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(screen)
	if screen.has_method("on_show"):
		screen.call("on_show")
	add_child(overlay)
	_settings_overlay = overlay


## Locale may have changed in Settings — rebuild the composed strings.
func _refresh_menu() -> void:
	for child in get_children():
		if child is MarginContainer:
			child.queue_free()
	_build_menu_only.call_deferred()


func _build_menu_only() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20 if _narrow else 120)
	margin.add_theme_constant_override("margin_right", 20 if _narrow else 120)
	margin.add_theme_constant_override("margin_top", 46 if _narrow else 90)
	margin.add_theme_constant_override("margin_bottom", 24 if _narrow else 48)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	margin.add_child(col)
	col.add_child(_wordmark())
	col.add_child(_gap(46))
	var menu := VBoxContainer.new()
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _narrow else Control.SIZE_SHRINK_BEGIN
	menu.add_theme_constant_override("separation", 10)
	col.add_child(menu)
	var has_save := MenuFlow.has_save()
	if has_save:
		menu.add_child(_menu_button(tr("Continue"), _continue_sub_text(), true, _on_continue))
	menu.add_child(_menu_button(tr("New Game"),
		tr("Create your manager and pick a club — 32 clubs, two leagues"),
		not has_save, _on_new_game))
	menu.add_child(_menu_button(tr("Settings"),
		tr("Display, audio, gameplay and language"), false, _on_settings))
	menu.add_child(_menu_button(tr("Quit"), "", false, func(): get_tree().quit()))
	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stretch)
	col.add_child(_footer())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if _onboarding == null and _settings_overlay == null:
			if MenuFlow.has_save():
				_on_continue()
			else:
				_on_new_game()
			accept_event()
