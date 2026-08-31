extends Control
## Settings / Preferences screen (platform piece). FM-style preferences page:
## display, audio, gameplay and language sections. Every control applies
## immediately through the Settings autoload (persisted to user://settings.json).

const TABS := [["display", "Display"], ["audio", "Audio"], ["gameplay", "Gameplay"], ["language", "Language"]]

const MODES := [["windowed", "Windowed"], ["borderless", "Borderless Window"], ["fullscreen", "Fullscreen"]]
const AUTOSAVE := [[0, "Off"], [1, "Every day"], [3, "Every 3 days"], [7, "Weekly"], [14, "Fortnightly"]]
const SLIDERS := [
	["audio_master", "Master Volume", "Overall volume for everything."],
	["audio_music", "Music", "Menu and matchday music."],
	["audio_sfx", "Sound Effects", "Battle hits, UI clicks, notifications."],
	["audio_ambience", "Ambience", "Crowd and arena atmosphere."],
]
const LOCALE_NAMES := {"en": "English", "es": "Español (Spanish)"}

var _scroll: ScrollContainer
var _sections: Dictionary = {}
var _res_option: OptionButton
var _refreshing := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	_scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	_build_header(box)
	_build_display(_section(box, "display", "DISPLAY"))
	_build_audio(_section(box, "audio", "AUDIO"))
	_build_gameplay(_section(box, "gameplay", "GAMEPLAY"))
	_build_language(_section(box, "language", "LANGUAGE"))
	Settings.setting_changed.connect(func(_k, _v): _refresh_dependent())
	_refresh_dependent()


func select_tab(id: String) -> void:
	if _sections.has(id):
		await get_tree().process_frame
		_scroll.ensure_control_visible(_sections[id])


func on_show() -> void:
	pass


# -- layout helpers ----------------------------------------------------------

func _build_header(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	var title := Label.new()
	title.text = "Preferences"
	title.add_theme_font_size_override("font_size", 22)
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var reset := Button.new()
	reset.text = "Reset to Defaults"
	reset.pressed.connect(_on_reset)
	row.add_child(reset)
	box.add_child(row)
	var note := Label.new()
	note.text = "Changes apply immediately and are saved to your profile (user://settings.json)."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	box.add_child(note)


func _section(box: VBoxContainer, id: String, heading: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_%s" % side, 14)
	panel.add_child(inner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	inner.add_child(v)
	var head := Label.new()
	head.text = heading
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	v.add_child(head)
	box.add_child(panel)
	_sections[id] = panel
	return v


func _row(parent: VBoxContainer, label_text: String, desc: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.4
	var lab := Label.new()
	lab.text = label_text
	left.add_child(lab)
	if desc != "":
		var d := Label.new()
		d.text = desc
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 10)
		d.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		left.add_child(d)
	row.add_child(left)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END if control is CheckButton else Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not control is CheckButton:
		control.size_flags_stretch_ratio = 1.0
	row.add_child(control)
	parent.add_child(row)


# -- sections ----------------------------------------------------------------

func _build_display(v: VBoxContainer) -> void:
	# In the browser the canvas follows the window (adaptive resize policy) —
	# window mode and resolution don't apply there and stay disabled.
	var web := OS.has_feature("web")
	var mode := OptionButton.new()
	for m in MODES:
		mode.add_item(m[1])
	mode.selected = _index_of(MODES, Settings.get_setting("window_mode"))
	mode.item_selected.connect(func(i): Settings.set_setting("window_mode", MODES[i][0]))
	mode.disabled = web
	_row(v, "Window Mode",
		"The browser window controls the size in the web version." if web
		else "Borderless fills the screen without exclusive fullscreen.", mode)

	_res_option = OptionButton.new()
	for r in Settings.RESOLUTIONS:
		_res_option.add_item(String(r).replace("x", " × "))
	var cur := String(Settings.get_setting("resolution"))
	var ridx := Settings.RESOLUTIONS.find(cur)
	_res_option.selected = maxi(ridx, 0)
	_res_option.item_selected.connect(func(i): Settings.set_setting("resolution", Settings.RESOLUTIONS[i]))
	_res_option.disabled = web
	_row(v, "Resolution", "Window size (windowed mode only). The UI scales to any size.", _res_option)

	var scale := OptionButton.new()
	for s in Settings.UI_SCALES:
		scale.add_item("%d%%" % int(round(float(s) * 100.0)))
	var sidx := 2
	for i in Settings.UI_SCALES.size():
		if is_equal_approx(float(Settings.UI_SCALES[i]), float(Settings.get_setting("ui_scale"))):
			sidx = i
	scale.selected = sidx
	scale.item_selected.connect(func(i): Settings.set_setting("ui_scale", Settings.UI_SCALES[i]))
	_row(v, "UI Scale", "Zoom the whole interface. 100% is the designed density.", scale)


func _build_audio(v: VBoxContainer) -> void:
	# Live volumes are owned by the shell's AudioManager (audio piece):
	# AudioManager.set_volume persists to GameState.settings + its file.
	# Without it (headless/tools) fall back to the profile store.
	var am_live: bool = AudioManager.instance != null
	if am_live:
		var en := CheckButton.new()
		en.button_pressed = AudioManager.instance._enabled
		en.toggled.connect(func(on): AudioManager.set_enabled(on))
		_row(v, "Enable Audio", "Master switch for all game audio.", en)
	for spec in SLIDERS:
		var key: String = spec[0]
		var bus: String = Settings.BUSES[key]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = AudioManager.volume(bus) if am_live else float(Settings.get_setting(key))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(220, 0)
		var pct := Label.new()
		pct.custom_minimum_size = Vector2(44, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct.text = "%d%%" % int(round(slider.value * 100.0))
		slider.value_changed.connect(func(val):
			pct.text = "%d%%" % int(round(val * 100.0))
			if AudioManager.instance != null:
				AudioManager.set_volume(bus, val)
			else:
				Settings.set_setting(key, val))
		h.add_child(slider)
		h.add_child(pct)
		_row(v, spec[1], spec[2], h)


func _build_gameplay(v: VBoxContainer) -> void:
	# ai_coach_uses_bag lives in GameState.settings (polish piece, persisted in
	# the save); fall back to the profile store if that API is unavailable.
	var bag := CheckButton.new()
	var via_gs: bool = GameState.has_method("setting")
	if via_gs:
		bag.button_pressed = bool(GameState.setting("ai_coach_uses_bag", true))
		bag.toggled.connect(func(on): GameState.set_setting("ai_coach_uses_bag", on))
	else:
		bag.button_pressed = bool(Settings.get_setting("ai_coach_uses_bag"))
		bag.toggled.connect(func(on): Settings.set_setting("ai_coach_uses_bag", on))
	_row(v, "AI Coach Uses the Bag", "Let your assistant spend battle items when you delegate or instant-sim matches.", bag)

	var auto := OptionButton.new()
	for a in AUTOSAVE:
		auto.add_item(a[1])
	auto.selected = _index_of(AUTOSAVE, int(Settings.get_setting("autosave_days")))
	auto.item_selected.connect(func(i): Settings.set_setting("autosave_days", AUTOSAVE[i][0]))
	_row(v, "Autosave", "How often the career is saved automatically as days advance.", auto)


func _build_language(v: VBoxContainer) -> void:
	var locales: Array = ["en"]
	for l in TranslationServer.get_loaded_locales():
		var code := String(l).substr(0, 2)
		if not locales.has(code):
			locales.append(code)
	var cur := String(Settings.get_setting("locale"))
	if not locales.has(cur):
		locales.append(cur)
	var opt := OptionButton.new()
	for i in locales.size():
		var code: String = locales[i]
		opt.add_item(LOCALE_NAMES.get(code, TranslationServer.get_locale_name(code)))
		opt.set_item_metadata(i, code)
		if code == cur:
			opt.selected = i
	opt.item_selected.connect(func(i): Settings.set_setting("locale", opt.get_item_metadata(i)))
	_row(v, "Language", "Switches the whole interface at once. Mail already delivered to your Inbox keeps the language it was written in — new mail arrives in the selected language.", opt)


# -- behaviour ---------------------------------------------------------------

func _refresh_dependent() -> void:
	if _refreshing:
		return
	_refreshing = true
	if is_instance_valid(_res_option):
		_res_option.disabled = OS.has_feature("web") \
			or String(Settings.get_setting("window_mode")) != "windowed"
	_refreshing = false


func _on_reset() -> void:
	Settings.reset_to_defaults()
	# rebuild the page so every control shows defaults
	for c in get_children():
		c.queue_free()
	_sections.clear()
	await get_tree().process_frame
	_ready()


func _index_of(pairs: Array, value: Variant) -> int:
	for i in pairs.size():
		if pairs[i][0] == value:
			return i
	return 0
