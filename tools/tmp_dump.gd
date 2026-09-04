extends Node
func _ready() -> void:
	for spec in [["Ash Maple", 7], ["Misty Fuji", 7], ["Iris Hale", 7], ["Cilan Rowan", 7]]:
		var img: Image = PixelPortrait._draw(str(spec[0]), {"pose": int(spec[1])})
		img.resize(48 * 6, 48 * 6, Image.INTERPOLATE_NEAREST)
		img.save_png(ProjectSettings.globalize_path("res://artifacts/dump_%s.png" % str(spec[0]).replace(" ", "_")))
	print("DUMP OK")
	get_tree().quit()
