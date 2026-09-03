extends Node
## Regression check: Crest.icon must stay square inside a tall HBox row
## (the home next-match card stretched badges to the row height).

func _ready() -> void:
	var club := {"id": "sfr", "name": "SFR", "short": "SFR", "squad": []}
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(390, 120)
	var c := Crest.icon(club, 40, {"no_tooltip": true})
	row.add_child(c)
	var tall := Control.new()
	tall.custom_minimum_size = Vector2(10, 120)
	tall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tall)
	add_child(row)
	await get_tree().process_frame
	await get_tree().process_frame
	if absf(c.size.y - 40.0) < 0.5 and absf(c.size.x - 40.0) < 0.5:
		print("CREST CHECK OK ", c.size)
	else:
		print("CREST CHECK FAIL ", c.size)
	get_tree().quit()
