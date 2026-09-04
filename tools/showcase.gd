extends Node
## Showcase sheet (art piece): every hairstyle, every pose and a league
## crowd of deterministic pixel portraits -> artifacts/showcase.png
## Run: godot --path . --resolution 1120x560 res://tools/showcase.tscn
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14172a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.position = Vector2(14, 10)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var mk_label := func(t: String) -> Label:
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color("8b91a8"))
		return l

	root.add_child(mk_label.call("14 PEINADOS (misma persona)"))
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	for st in 14:
		r1.add_child(PixelPortrait.avatar("Serena Oak", 72, {"hair_s": st, "pose": 0}))
	root.add_child(r1)

	root.add_child(mk_label.call("8 POSES (misma persona)"))
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	for pz in 8:
		r2.add_child(PixelPortrait.avatar("Brock Stone", 72, {"pose": pz}))
	root.add_child(r2)

	root.add_child(mk_label.call("LA LIGA (deterministas por nombre)"))
	var names := ["Ash Maple", "Misty Fuji", "Serena Oak", "Gary Elm", "Dawn Silph",
		"Paul Birch", "Iris Hale", "Cilan Rowan", "May Devon", "Lance Ivy",
		"Erika Snap", "Volkner Cerise", "Lillie Westwood", "Silver Kukui", "Karen Laramie",
		"Flint Goodshow", "Zoey Harrison", "Barry Magnolia", "Casey Berlitz", "Wally Juniper",
		"Whitney Ketchum", "Todd Waterflower", "Bianca Sycamore", "Bruno Oak", "Mallow Stone",
		"Trevor Elm", "Alexa Fuji", "Goh Maple", "Phoebe Silph", "Jessie Hale",
		"James Rowan", "Cynthia Snap", "Morty Devon", "Jasmine Birch", "Falkner Ivy",
		"Daisy Kukui", "Ritchie Stone", "Winona Elm", "Tracey Fuji", "Brock Stone",
		"Misty Snap", "Ash Berlitz"]
	var grid := GridContainer.new()
	grid.columns = 14
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for n in names:
		grid.add_child(PixelPortrait.avatar(n, 72))
	root.add_child(grid)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://artifacts/showcase.png"))
	print("SHOWCASE OK")
	get_tree().quit()
