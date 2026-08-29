extends Control
## Competition screen STUB — owned by the "competition" piece (which may also
## extend fixture/table logic in res://shared/sim/season.gd via GameState).


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "Competition"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Stub — the competition piece will build full tables, fixtures and cup bracket."
	hint.add_theme_color_override("font_color", Color("8b91a8"))
	box.add_child(hint)
	box.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "%-4s %-26s %4s %4s %4s %5s %5s %5s" % ["Pos", GameState.world["meta"]["league_name"], "P", "W", "L", "BF", "BA", "Pts"]
	header.add_theme_color_override("font_color", Color("8b91a8"))
	box.add_child(header)

	var table: Array = GameState.league_table()
	for i in table.size():
		var row: Dictionary = table[i]
		var c: Dictionary = GameState.club(row["club_id"])
		var l := Label.new()
		l.text = "%-4d %-26s %4d %4d %4d %5d %5d %5d" % [
			i + 1, c["name"], row["played"], row["won"], row["lost"],
			row["bf"], row["ba"], row["points"]]
		if GameState.is_player_club(row["club_id"]):
			l.add_theme_color_override("font_color", Color("7b6cff"))
		box.add_child(l)
