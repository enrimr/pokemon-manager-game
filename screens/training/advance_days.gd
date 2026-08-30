extends Node
## Builder utility (training piece): advance the career N days headlessly so a
## fixture sits inside the visible training week for screenshot verification.
## Run: Godot --headless res://screens/training/advance_days.tscn -- --days=N

func _ready() -> void:
	var days := 4
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).split("=")[1])
	# Keep the training model ticking alongside the career, exactly as it does
	# when the screen has been opened in a normal session.
	var svc: Node = load("res://screens/training/training_service.gd").ensure()
	for i in days:
		GameState.advance_day()
	svc.save_state()
	GameState.save_game()
	print("ADVANCED %d days -> %s" % [days, GameState.current_date])
	get_tree().quit(0)
