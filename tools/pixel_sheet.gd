extends Node
## Contact sheet: 30 procedural pixel portraits vs official trainer sprites.
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14172a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.position = Vector2(16, 14)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)
	var names := ["Ash Maple", "Misty Fuji", "Brock Stone", "Serena Oak", "Gary Elm",
		"Dawn Silph", "Paul Birch", "Iris Hale", "Cilan Rowan", "May Devon",
		"Lance Ivy", "Erika Snap", "Volkner Cerise", "Lillie Westwood", "Silver Kukui",
		"Karen Laramie", "Flint Goodshow", "Zoey Harrison", "Barry Magnolia", "Casey Berlitz",
		"Wally Juniper", "Whitney Ketchum", "Todd Waterflower", "Bianca Sycamore", "Bruno Oak",
		"Mallow Stone", "Trevor Elm", "Alexa Fuji", "Goh Maple", "Phoebe Silph",
		"Jessie Hale", "James Rowan", "Cynthia Snap", "Morty Devon", "Jasmine Birch",
		"Falkner Ivy", "Daisy Kukui", "Ritchie Stone", "Winona Elm", "Tracey Fuji"]
	for n in names:
		grid.add_child(PixelPortrait.avatar(n, 72))
	# officials for style comparison
	for n in ["Misty", "Brock", "Red", "Professor Oak", "Whitney", "Lance",
			"Sabrina", "Gary Oak", "Erika", "Lt. Surge"]:
		grid.add_child(TrainerArt.avatar(n, 72))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://artifacts/pixel_sheet.png"))
	print("PIXEL SHEET OK")
	get_tree().quit()
