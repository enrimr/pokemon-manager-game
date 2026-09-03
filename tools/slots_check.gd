extends Node
## Headless functional check for multi-slot saves (saves piece):
## two careers coexist, Load Game round-trips, deletion cleans sidecars,
## legacy user://save.json migrates. Run:
##   godot --headless --path . res://tools/slots_check.tscn

const SaveGuard := preload("res://tools/save_guard.gd")

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL: " + what)


func _ready() -> void:
	SaveGuard.backup()

	# ---- two careers, two slots
	GameState.new_career(111)
	GameState.world["meta"]["manager_name"] = "Slot Uno"
	GameState.save_game()
	var slot_a := GameState.save_slot
	GameState.new_career(222, str(GameState.club_ids()[2]))
	GameState.world["meta"]["manager_name"] = "Slot Dos"
	GameState.save_game()
	var slot_b := GameState.save_slot
	_check(slot_a != "" and slot_b != "" and slot_a != slot_b, "each career gets its own slot")

	var saves := GameState.list_saves()
	var ids := saves.map(func(s): return str(s["id"]))
	_check(ids.has(slot_a) and ids.has(slot_b), "list_saves sees both careers")
	_check(str(saves[0]["id"]) == slot_b, "newest career listed first")
	_check(str(saves[0]["manager"]) == "Slot Dos", "index carries the manager name")

	# ---- round-trip back to career A
	_check(GameState.load_slot(slot_a), "load_slot(A) succeeds")
	_check(GameState.save_slot == slot_a, "active slot follows the load")
	_check(str(GameState.world["meta"]["manager_name"]) == "Slot Uno",
		"career A's world came back")
	_check(str(GameState.list_saves()[0]["id"]) == slot_a,
		"loading touches last_played (A now first)")

	# ---- sidecar state is per-slot
	var tsvc: Node = load("res://screens/training/training_service.gd").ensure()
	_check(str(tsvc._state_path()).ends_with(slot_a + ".training.json"),
		"training state rides career A's slot")

	# ---- deletion cleans the slot AND its sidecars
	var side := "%s/%s.training.json" % [GameState.SAVE_DIR, slot_b]
	var f := FileAccess.open(side, FileAccess.WRITE)
	f.store_string("{}")
	f = null
	GameState.delete_slot(slot_b)
	_check(not FileAccess.file_exists("%s/%s.json" % [GameState.SAVE_DIR, slot_b]),
		"deleted slot file is gone")
	_check(not FileAccess.file_exists(side), "deleted slot's sidecars are gone")
	_check(not GameState.list_saves().map(func(s): return str(s["id"])).has(slot_b),
		"deleted slot left the list")

	# ---- legacy migration: user://save.json becomes the career_legacy slot
	GameState.delete_slot("career_legacy")   # the name must be free for this test
	var legacy := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	legacy.store_string(FileAccess.get_file_as_string(GameState.save_path()))
	legacy = null
	GameState._migrate_legacy_save()
	_check(not FileAccess.file_exists(GameState.SAVE_PATH), "legacy save.json consumed")
	_check(FileAccess.file_exists(GameState.SAVE_DIR + "/career_legacy.json"),
		"legacy save became the career_legacy slot")
	GameState.delete_slot("career_legacy")

	SaveGuard.restore()
	print("SLOTS CHECK OK" if _fails == 0 else "SLOTS CHECK FAILED (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
