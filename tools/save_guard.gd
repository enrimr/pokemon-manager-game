extends RefCounted
## Dev-tool save guard: lets headless checks and dev drivers run destructive
## careers (delete_save / new_career / save_game) WITHOUT clobbering the
## player's real user://save.json. Call backup() before touching GameState,
## restore() before quitting (both idempotent, safe if no save exists).
##
##   const SaveGuard := preload("res://tools/save_guard.gd")
##   SaveGuard.backup()  ...  SaveGuard.restore()

const SAVE_PATH := "user://save.json"

static var _backup := ""
static var _had_save := false
static var _active := false


static func backup() -> void:
	if _active:
		return
	_active = true
	_had_save = FileAccess.file_exists(SAVE_PATH)
	_backup = FileAccess.get_file_as_string(SAVE_PATH) if _had_save else ""


## For dev drivers that MUST leave a dev save in the main slot (screenshot
## harness prep): park the player's real save in a one-time backup slot
## first. Never overwrites an existing backup, so repeated dev runs cannot
## destroy the original. Restore by copying user://save.player.bak back.
static func preserve_player_save() -> void:
	const BAK := "user://save.player.bak"
	if not FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BAK):
		return
	var f := FileAccess.open(BAK, FileAccess.WRITE)
	if f != null:
		f.store_string(FileAccess.get_file_as_string(SAVE_PATH))
		print("save_guard: player's save.json parked at %s (copy it back to restore)" % BAK)


static func restore() -> void:
	if not _active:
		return
	_active = false
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_backup)
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
