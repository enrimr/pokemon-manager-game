extends Node
## Settings autoload ("Settings" in project.godot — platform piece).
## Single source of truth for user preferences. Persists to user://settings.json,
## applies everything (window mode/resolution/UI scale, audio bus volumes,
## locale) at boot and live on change.
##
## CONTRACT for other builders (also documented in docs/ARCHITECTURE.md):
##   Settings.get_setting(key, default) -> Variant
##   Settings.set_setting(key, value)          # applies + persists + emits
##   signal setting_changed(key, value)
## Keys:
##   window_mode: "windowed"|"borderless"|"fullscreen"
##   resolution: "1600x900" (windowed size; presets in RESOLUTIONS)
##   ui_scale: float 0.75..1.5          (stretch scale multiplier)
##   audio_master/audio_music/audio_sfx/audio_ambience: float 0..1 (linear).
##     Applied to AudioServer buses "Master"/"Music"/"SFX"/"Ambience".
##     Missing buses are created here so sliders always work; the audio piece
##     may ship its own bus layout — existing buses are never duplicated.
##   ai_coach_uses_bag: bool            (fallback only — the live key is
##                                       GameState.setting("ai_coach_uses_bag"),
##                                       polish piece, persisted in the save)
##   autosave_days: int 0|1|3|7|14      (0 = off; autosave runs here off
##                                       GameState.date_changed, skipped headless)
##   locale: "en" | any TranslationServer locale (localization piece adds "es")

signal setting_changed(key: String, value: Variant)

const SAVE_PATH := "user://settings.json"
const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const UI_SCALES := [0.75, 0.85, 1.0, 1.15, 1.3, 1.5]
const AUTOSAVE_CHOICES := [0, 1, 3, 7, 14]
const BUSES := {
	"audio_master": "Master", "audio_music": "Music",
	"audio_sfx": "SFX", "audio_ambience": "Ambience",
}
const DEFAULTS := {
	"window_mode": "windowed", "resolution": "1600x900", "ui_scale": 1.0,
	"audio_master": 1.0, "audio_music": 0.8, "audio_sfx": 0.8, "audio_ambience": 0.7,
	"ai_coach_uses_bag": true, "autosave_days": 7, "locale": "en",
}

var _data: Dictionary = {}
var _days_since_autosave := 0
var _headless := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_data = DEFAULTS.duplicate()
	_data["locale"] = _default_locale()
	_load()
	apply_all()
	if not _headless and GameState.has_signal("date_changed"):
		GameState.date_changed.connect(_on_date_changed)


func get_setting(key: String, default: Variant = null) -> Variant:
	if _data.has(key):
		return _data[key]
	return DEFAULTS.get(key, default)


func set_setting(key: String, value: Variant) -> void:
	if _data.get(key) == value:
		return
	_data[key] = value
	_apply_one(key)
	_save()
	setting_changed.emit(key, value)


func reset_to_defaults() -> void:
	_data = DEFAULTS.duplicate()
	_data["locale"] = _default_locale()
	apply_all()
	_save()
	setting_changed.emit("", null)


func all() -> Dictionary:
	return _data.duplicate()


func apply_all() -> void:
	_apply_audio()
	_apply_locale()
	_apply_display()


# -- application ------------------------------------------------------------

func _apply_one(key: String) -> void:
	if BUSES.has(key):
		_apply_audio()
	elif key == "locale":
		_apply_locale()
	elif key in ["window_mode", "resolution", "ui_scale"]:
		_apply_display()


func _apply_display() -> void:
	if _headless:
		return
	var win := get_window()
	win.min_size = Vector2i(1152, 648)
	win.content_scale_factor = clampf(float(get_setting("ui_scale")), 0.5, 2.0)
	var mode := String(get_setting("window_mode"))
	match mode:
		"fullscreen":
			win.mode = Window.MODE_FULLSCREEN
		"borderless":
			win.mode = Window.MODE_WINDOWED
			win.borderless = true
			var scr := DisplayServer.screen_get_usable_rect(win.current_screen)
			win.position = scr.position
			win.size = scr.size
		_:
			var was := win.mode
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
			var parts := String(get_setting("resolution")).split("x")
			if parts.size() == 2:
				var sz := Vector2i(int(parts[0]), int(parts[1]))
				if win.size != sz or was != Window.MODE_WINDOWED:
					win.size = sz
					var scr2 := DisplayServer.screen_get_usable_rect(win.current_screen)
					win.position = scr2.position + (scr2.size - sz) / 2


func _apply_audio() -> void:
	# When the shell's AudioManager is alive it owns bus volumes (persisted in
	# GameState.settings + user://audio_settings.json); don't fight it. This
	# path only runs pre-AudioManager (boot) or without the shell.
	if AudioManager.instance != null:
		return
	for key in BUSES:
		var bus: String = BUSES[key]
		var idx := AudioServer.get_bus_index(bus)
		if idx == -1:
			idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus)
			if bus != "Master":
				AudioServer.set_bus_send(idx, "Master")
		var v := clampf(float(get_setting(key)), 0.0, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func _apply_locale() -> void:
	# Headless runs (smoke, sim_check, per-piece proof drivers) stay on the
	# English source strings so their inbox/title assertions are deterministic
	# regardless of the machine's OS language or the user's saved preference.
	if _headless:
		TranslationServer.set_locale("en")
		return
	TranslationServer.set_locale(String(get_setting("locale")))


func _default_locale() -> String:
	# Fresh profiles follow the OS language when a translation ships for it.
	var lang := OS.get_locale_language()
	for t in TranslationServer.get_loaded_locales():
		if String(t).substr(0, 2) == lang:
			return lang
	return String(DEFAULTS["locale"])


func _on_date_changed(_date: String) -> void:
	var every := int(get_setting("autosave_days"))
	if every <= 0:
		return
	_days_since_autosave += 1
	if _days_since_autosave >= every:
		_days_since_autosave = 0
		if GameState.has_method("save_game"):
			GameState.save_game()


# -- persistence ------------------------------------------------------------

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in DEFAULTS:
			if parsed.has(k) and typeof(parsed[k]) != TYPE_NIL:
				_data[k] = _coerce(k, parsed[k])


func _coerce(key: String, v: Variant) -> Variant:
	match typeof(DEFAULTS[key]):
		TYPE_BOOL: return bool(v)
		TYPE_INT: return int(v)
		TYPE_FLOAT: return float(v)
		_: return String(v)


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_data, "\t"))
