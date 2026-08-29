extends Control
## Training screen STUB — owned by the "training" piece.


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "Training"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Stub — the training piece will build schedules, development and coach assignments."
	hint.add_theme_color_override("font_color", Color("8b91a8"))
	box.add_child(hint)
	box.add_child(HSeparator.new())

	var staff: Array = GameState.player_club()["staff"]
	var info := Label.new()
	info.text = "Staff at the club (%d):" % staff.size()
	box.add_child(info)
	for s in staff:
		var r: Dictionary = s["ratings"]
		var l := Label.new()
		l.text = "  %s — %s  ·  Att %d  Def %d  Fit %d  JA %d  JP %d" % [
			s["name"], s["role"].capitalize(), r["attacking"], r["defending"],
			r["fitness"], r["judging_ability"], r["judging_potential"]]
		box.add_child(l)
