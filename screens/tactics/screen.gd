extends Control
## Tactics screen STUB — owned by the "tactics" piece.


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "Tactics"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Stub — the tactics piece will add battle order, move sets and instructions."
	hint.add_theme_color_override("font_color", Color("8b91a8"))
	box.add_child(hint)
	box.add_child(HSeparator.new())

	var lineup := Season.pick_team(GameState.player_club())
	var info := Label.new()
	info.text = "Current auto-picked battle six (by level & condition):"
	box.add_child(info)
	for b in lineup:
		var l := Label.new()
		l.text = "  %d. %s  Lv %d  ·  %s  ·  HP %d SPE %d  ·  %s" % [
			lineup.find(b) + 1, b["name"], b["level"], "/".join(b["types"]),
			b["stats"]["hp"], b["stats"]["spe"], ", ".join(b["moves"])]
		box.add_child(l)
