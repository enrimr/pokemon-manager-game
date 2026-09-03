extends Node
## Contact sheet: official trainer faces + front/back battle sprites.
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14172a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(20, 20)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	for n in ["Misty", "Brock", "Ash Ketchum", "Professor Oak", "Lt. Surge", "Gary Oak",
			"Sabrina", "Giovanni", "Red", "Lance", "Professor Elm", "Whitney"]:
		var v := VBoxContainer.new()
		v.add_child(TrainerArt.avatar(n, 72))
		var l := Label.new()
		l.text = n
		l.add_theme_font_size_override("font_size", 10)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		grid.add_child(v)
	for n in ["Misty", "Brock", "Ash Ketchum", "Professor Oak", "Lt. Surge", "Gary Oak",
			"Sabrina", "Giovanni", "Red", "Lance", "Professor Elm", "Whitney"]:
		grid.add_child(TrainerArt.avatar(n, 44))
	for id in [6, 25, 130, 143, 249, 150]:
		grid.add_child(PokeArt.icon(id, 72, {"view": "front"}))
	for id in [6, 25, 130, 143, 249, 150]:
		grid.add_child(PokeArt.icon(id, 72, {"view": "back"}))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://artifacts/art_sheet.png"))
	print("ART SHEET OK")
	get_tree().quit()
