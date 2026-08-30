extends Node
## Builder utility (training piece): lay down real calendar plans through the
## public TrainingService API so a screenshot shows per-date planning in use.
## Run: Godot --headless res://screens/training/plan_demo.tscn

func _ready() -> void:
	var svc: Node = load("res://screens/training/training_service.gd").ensure()
	# One-off single-date edit on the first free day.
	for i in range(1, 14):
		var d: String = Season.date_add(GameState.current_date, i)
		if svc.effective_plan(d)["kind"] == "normal":
			svc.set_date_session(d, "am", "rest")
			svc.set_date_intensity(d, "light")
			print("DEMO: single-date edit on %s" % d)
			break
	# Heavy development block stamped on next week (per-date, template untouched).
	svc.apply_preset_to_week("development", Season.date_add(GameState.current_date, 7))
	print("DEMO: development preset on week %s" % Season.date_add(GameState.current_date, 7))
	# Opponent prep into the next unplayed fixture.
	var fixtures: Array = svc.upcoming_player_fixtures(14)
	if not fixtures.is_empty():
		svc.plan_prep_for_fixture(str(fixtures[0]["date"]), 3)
		print("DEMO: prep planned into fixture %s" % fixtures[0]["date"])
	svc.set_view_weeks(2)
	svc.save_state()
	print("DEMO DONE")
	get_tree().quit(0)
