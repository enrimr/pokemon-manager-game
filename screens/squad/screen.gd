extends Control
## Squad screen STUB — owned by the "squad" piece. Proves GameState wiring.


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "Squad"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Stub — the squad piece will build the full FM-style squad table here."
	hint.add_theme_color_override("font_color", Color("8b91a8"))
	box.add_child(hint)
	box.add_child(HSeparator.new())

	var pc: Dictionary = GameState.player_club()
	var squad: Array = pc["squad"]
	var info := Label.new()
	info.text = "%s — %d Pokémon in squad, wage budget %s %d" % [
		pc["name"], squad.size(),
		GameState.world["meta"]["currency"], int(pc["finances"]["wage_budget"])]
	box.add_child(info)

	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 300)
	for inst in squad:
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		list.add_item("%s  ·  Lv %d  ·  %s  ·  cond %d%%  ·  morale %d  ·  %s %d/wk" % [
			inst["species"], inst["level"], "/".join(sp["types"]),
			inst["condition"], inst["morale"],
			GameState.world["meta"]["currency"], inst["contract"]["salary"]])
	box.add_child(list)
