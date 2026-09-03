extends RefCounted
## Dev-tool save guard: lets headless checks and dev drivers run destructive
## careers (delete_save / new_career / save_game) WITHOUT clobbering the
## player's real careers. Call backup() before touching GameState, restore()
## before quitting (both idempotent, safe if no save exists).
##
## Careers live one-per-file in user://saves/ (multi-slot saves piece), so the
## guard snapshots the WHOLE directory (plus the legacy user://save.json) and
## restore() puts back exactly that set — dev slots created meanwhile are
## deleted, deleted player slots come back.
##
##   const SaveGuard := preload("res://tools/save_guard.gd")
##   SaveGuard.backup()  ...  SaveGuard.restore()

const SAVE_PATH := "user://save.json"     # legacy single slot
const SAVE_DIR := "user://saves"

static var _snapshot := {}    # relative file name -> content ("" key = legacy save.json)
static var _active := false


static func _dir_files() -> Array:
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return []
	var out: Array = []
	for fn in d.get_files():
		if fn.ends_with(".json"):
			out.append(fn)
	return out


static func backup() -> void:
	if _active:
		return
	_active = true
	_snapshot = {}
	if FileAccess.file_exists(SAVE_PATH):
		_snapshot[""] = FileAccess.get_file_as_string(SAVE_PATH)
	for fn in _dir_files():
		_snapshot[fn] = FileAccess.get_file_as_string("%s/%s" % [SAVE_DIR, fn])


## For dev drivers that MUST leave a dev save as the active career
## (screenshot harness prep): park the player's real careers in a one-time
## backup dir first. Never overwrites an existing backup, so repeated dev
## runs cannot destroy the originals. Restore by copying the files back.
static func preserve_player_save() -> void:
	const BAK_DIR := "user://saves_player_bak"
	var existing := DirAccess.open(BAK_DIR)
	if existing != null and not existing.get_files().is_empty():
		return   # already parked once — never clobber it
	var files := _dir_files()
	var legacy := FileAccess.file_exists(SAVE_PATH)
	if files.is_empty() and not legacy:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAK_DIR))
	if legacy:
		var f := FileAccess.open("%s/save.json" % BAK_DIR, FileAccess.WRITE)
		if f != null:
			f.store_string(FileAccess.get_file_as_string(SAVE_PATH))
	for fn in files:
		var g := FileAccess.open("%s/%s" % [BAK_DIR, fn], FileAccess.WRITE)
		if g != null:
			g.store_string(FileAccess.get_file_as_string("%s/%s" % [SAVE_DIR, fn]))
	print("save_guard: player careers parked at %s (copy them back to restore)" % BAK_DIR)


static func restore() -> void:
	if not _active:
		return
	_active = false
	# legacy single save
	if _snapshot.has(""):
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(str(_snapshot[""]))
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	# slot dir: back to exactly the snapshot set
	for fn in _dir_files():
		if not _snapshot.has(fn):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [SAVE_DIR, fn]))
	for key in _snapshot:
		if str(key) == "":
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
		var g := FileAccess.open("%s/%s" % [SAVE_DIR, str(key)], FileAccess.WRITE)
		if g != null:
			g.store_string(str(_snapshot[key]))
	_snapshot = {}
