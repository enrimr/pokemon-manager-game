extends Node
## Builder utility (training piece): form real mentor groups through the
## public TrainingService API so screenshots show mentoring in live use.
## Run: Godot --headless res://screens/training/mentor_demo.tscn

func _ready() -> void:
	var svc: Node = load("res://screens/training/training_service.gd").ensure()
	var squad: Array = GameState.player_club()["squad"]
	var made := 0
	for m in squad:
		if made >= 2:
			break
		if not svc.mentor_eligible(m) or not (svc.group_of(str(m["uid"])) as Dictionary).is_empty():
			continue
		var juniors: Array = []
		for j in squad:
			if svc.junior_eligible(j) and (svc.group_of(str(j["uid"])) as Dictionary).is_empty() \
					and svc.can_mentor(m, j) == "":
				juniors.append(j)
		if juniors.is_empty():
			continue
		if svc.create_mentor_group(str(m["uid"])) != "":
			continue
		for j in juniors.slice(0, 2):
			var err: String = svc.add_junior(str(m["uid"]), str(j["uid"]))
			print("DEMO: %s mentoring %s (%s)" % [m["species"], j["species"], "ok" if err == "" else err])
		made += 1
	svc.save_state()
	GameState.save_game()
	print("DEMO: %d mentor groups active" % (svc.mentor_groups() as Array).size())
	get_tree().quit(0)
