extends SceneTree
## Dev helper for the inbox piece: advance the career N days and save,
## so the screenshot harness has a rich in-season inbox to render.
## Run: godot --headless --path . -s res://screens/inbox/dev_advance.gd -- 55

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null:
		push_error("dev_advance: GameState autoload missing")
		quit(1)
		return
	(load("res://tools/save_guard.gd") as GDScript).preserve_player_save()
	var days := 55
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		days = int(args[0])
	for i in days:
		gs.advance_day()
	gs.save_game()
	print("dev_advance: advanced %d days -> %s, %d inbox messages, saved." %
		[days, gs.current_date, gs.inbox.size()])
	quit(0)
