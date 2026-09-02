extends Node
## Dev-only contact sheet: renders a grid of Portrait faces to one PNG.
func _ready() -> void:
	get_window().size = Vector2i(1040, 640)
	_run.call_deferred()
func _run() -> void:
	await get_tree().process_frame
	var bg := ColorRect.new()
	bg.color = Color("11141d")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.position = Vector2(20, 20)
	add_child(grid)
	var styles := ["crop", "side", "buzz", "spiky", "curly", "afro", "receding",
		"bald", "bob", "long", "bun", "ponytail", "pixie"]
	grid.columns = 7
	for st in styles:
		grid.add_child(Portrait.avatar("Ash " + st, 130, {"style": st, "age": 30}))
	for st in styles:
		grid.add_child(Portrait.avatar("Misty " + st, 130, {"style": st, "age": 26}))
	for i in 12:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://") + "artifacts/portrait_sheet.png")
	print("SHEET OK")
	get_tree().quit(0)
