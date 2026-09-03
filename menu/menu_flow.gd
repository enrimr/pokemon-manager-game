class_name MenuFlow
## Static helpers shared by the title screen, the onboarding wizard and the
## shell's routing (menu piece). No state — everything reads/writes GameState.
##
## MANAGER IDENTITY: the player's name lives in world.meta.manager_name
## (+ optional world.meta.manager_nickname) AND is written onto the player
## club's "manager" field — the field every board mail, press piece and
## mind-games generator already renders (pc["manager"]). It therefore flows
## into the whole world with zero changes elsewhere, persists in the save
## (world is saved whole), and survives season rollovers.


## True when the game should skip the title screen and boot straight into a
## career: headless runs (smoke, sim_check, drivers), an explicit
## `--quickstart` CLI flag, or the TM_QUICKSTART env var. This is the contract
## that keeps every existing testing tool working unchanged.
static func quickstart() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if OS.get_environment("TM_QUICKSTART") != "":
		return true
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for a in args:
		if a == "--quickstart":
			return true
	return false


static func has_save() -> bool:
	if GameState.save_slot != "" and FileAccess.file_exists(GameState.save_path()):
		return true
	return not GameState.list_saves().is_empty()


## Which shell to boot into (mobile piece): phones in portrait get the
## mobile-first shell; everything else gets the desktop shell (which runs
## compact mode on phones in landscape). Rotating swaps scenes — all game
## state lives in the GameState autoload.
static func shell_scene() -> String:
	if Settings.is_mobile():
		var s: Vector2i = DisplayServer.window_get_size()
		if s.y > s.x:
			return "res://mobile/shell.tscn"
	return "res://shell/main.tscn"


## The player manager's display name (world.meta.manager_name; falls back to
## the club's generated manager for careers started before the menu existed).
static func manager_name() -> String:
	var n := str(GameState.world.get("meta", {}).get("manager_name", ""))
	if n != "":
		return n
	return str(GameState.player_club().get("manager", ""))


static func manager_nickname() -> String:
	return str(GameState.world.get("meta", {}).get("manager_nickname", ""))


## Summary of the CURRENT loaded career for the title screen's Continue card.
## GameState.boot() already loaded user://save.json, so the live state IS the
## save whenever has_save() is true.
static func save_summary() -> Dictionary:
	if not has_save() or GameState.world.is_empty():
		return {}
	var pc := GameState.player_club()
	return {
		"club": str(pc.get("name", "")),
		"manager": manager_name(),
		"date": str(GameState.current_date),
		"season": GameState.season_no(),
		"league": str(GameState.league_name()),
	}


## Write the manager identity into the running world (see header note).
static func apply_manager_identity(name: String, nickname: String = "") -> void:
	var n := name.strip_edges()
	if n == "" or GameState.world.is_empty():
		return
	GameState.world["meta"]["manager_name"] = n
	var nick := nickname.strip_edges()
	if nick != "":
		GameState.world["meta"]["manager_nickname"] = nick
	else:
		GameState.world["meta"].erase("manager_nickname")
	GameState.player_club()["manager"] = n


## The full "start a fresh career" transaction used by the onboarding wizard:
## boot the new world at the chosen club IN ITS OWN SAVE SLOT (existing
## careers stay on disk — Load Game lists them), stamp the manager identity
## onto it, hand over the professor's starter (the protégé ceremony —
## starter_id 0 skips it, for legacy/tool callers) and persist. Same fixed
## seed the shell has always used.
static func start_career(club_id: String, name: String, nickname: String = "",
		starter_id: int = 0, starter_nick: String = "") -> void:
	GameState.new_career(20260801, club_id)
	apply_manager_identity(name, nickname)
	if starter_id > 0 and ProtegeService.instance != null:
		ProtegeService.instance.select_starter(starter_id, starter_nick)
	GameState.save_game()


## Shared menu typography (mirrors the shell's system-font stack).
static func fonts() -> Dictionary:
	var bold := SystemFont.new()
	bold.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
	bold.font_weight = 700
	var semibold := SystemFont.new()
	semibold.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
	semibold.font_weight = 600
	var header := FontVariation.new()
	header.base_font = bold
	header.spacing_glyph = 2
	return {"bold": bold, "semibold": semibold, "header": header}
