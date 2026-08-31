extends Node
## Headless selftest for the Settings autoload (platform piece).
## Run: godot --headless --path <project> res://screens/settings/selftest.tscn
## Prints SETTINGS SELFTEST OK and exits 0, or FAIL lines and exits 1.

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: %s" % msg)
	else:
		printerr("  FAIL: %s" % msg)
		_fails += 1


func _run() -> void:
	var backup: String = ""
	if FileAccess.file_exists(Settings.SAVE_PATH):
		backup = FileAccess.get_file_as_string(Settings.SAVE_PATH)

	_check(Settings.get_setting("ui_scale") != null, "defaults available")
	Settings.set_setting("audio_music", 0.35)
	Settings.set_setting("autosave_days", 3)
	Settings.set_setting("locale", "es")
	_check(FileAccess.file_exists(Settings.SAVE_PATH), "settings.json written")
	_check(TranslationServer.get_locale().begins_with("es"), "locale applied live")

	# roundtrip: wipe in-memory state and reload from disk
	Settings._data = Settings.DEFAULTS.duplicate()
	Settings._load()
	_check(absf(float(Settings.get_setting("audio_music")) - 0.35) < 0.001, "audio_music persisted")
	_check(int(Settings.get_setting("autosave_days")) == 3, "autosave_days persisted")
	_check(String(Settings.get_setting("locale")) == "es", "locale persisted")

	# audio buses exist and carry the loaded volume
	Settings.apply_all()
	var idx := AudioServer.get_bus_index("Music")
	_check(idx != -1, "Music bus exists")
	if idx != -1:
		var lin := db_to_linear(AudioServer.get_bus_volume_db(idx))
		_check(absf(lin - 0.35) < 0.01, "Music bus volume applied (%.2f)" % lin)

	# GameState per-save settings bridge (polish piece)
	if GameState.has_method("setting"):
		GameState.set_setting("ai_coach_uses_bag", false)
		_check(bool(GameState.setting("ai_coach_uses_bag")) == false, "GameState.set_setting roundtrip")
		GameState.set_setting("ai_coach_uses_bag", true)

	# restore the user's real settings file
	if backup != "":
		var f := FileAccess.open(Settings.SAVE_PATH, FileAccess.WRITE)
		f.store_string(backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.SAVE_PATH))
	Settings._data = Settings.DEFAULTS.duplicate()
	Settings._load()
	Settings.apply_all()

	if _fails == 0:
		print("SETTINGS SELFTEST OK")
		get_tree().quit(0)
	else:
		printerr("SETTINGS SELFTEST FAILED: %d" % _fails)
		get_tree().quit(1)
