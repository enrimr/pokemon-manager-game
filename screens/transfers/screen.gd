extends Control
## Transfers screen STUB — owned by the "transfers" piece.


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "Transfers"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Stub — the transfers piece will build the market, offers and negotiations."
	hint.add_theme_color_override("font_color", Color("8b91a8"))
	box.add_child(hint)
	box.add_child(HSeparator.new())

	var pc: Dictionary = GameState.player_club()
	var info := Label.new()
	info.text = "Balance: %s %d  ·  %d free agents on the market  ·  %d scoutable prospects" % [
		GameState.world["meta"]["currency"], pc["finances"]["balance"],
		GameState.free_agents().size(), GameState.prospects().size()]
	box.add_child(info)

	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 260)
	for inst in GameState.free_agents().slice(0, 12):
		list.add_item("%s  ·  Lv %d  ·  asking %s %d/wk" % [
			inst["species"], inst["level"],
			GameState.world["meta"]["currency"], inst["contract"]["salary"]])
	box.add_child(list)
