extends Control
## Animated title-screen backdrop (menu piece). Pure theme-colored drawing —
## slow-drifting soft glows in the game's accent palette over the near-black
## navy, a faint dot grid and a grounding horizon band. Deliberately subtle:
## FM-style calm, not a particle show.

const DOT_SPACING := 56.0

var _t := 0.0
var _blobs: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# fixed seeded layout so every boot looks composed, not random
	_blobs = [
		{"col": ThemeBuilder.COL_ACCENT, "r": 340.0, "cx": 0.22, "cy": 0.30, "ax": 0.05, "ay": 0.035, "sp": 0.11, "ph": 0.0},
		{"col": Color("3a86c8"), "r": 300.0, "cx": 0.80, "cy": 0.22, "ax": 0.04, "ay": 0.05, "sp": 0.07, "ph": 2.1},
		{"col": Color("c8a03a"), "r": 240.0, "cx": 0.68, "cy": 0.82, "ax": 0.06, "ay": 0.03, "sp": 0.09, "ph": 4.2},
		{"col": Color("3ac88a"), "r": 210.0, "cx": 0.12, "cy": 0.86, "ax": 0.03, "ay": 0.045, "sp": 0.13, "ph": 1.3},
	]


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), ThemeBuilder.COL_BG)

	# drifting soft glows (concentric fades — cheap fake radial gradient)
	for b in _blobs:
		var cx: float = (b["cx"] + sin(_t * b["sp"] + b["ph"]) * b["ax"]) * sz.x
		var cy: float = (b["cy"] + cos(_t * b["sp"] * 0.8 + b["ph"]) * b["ay"]) * sz.y
		var col: Color = b["col"]
		for i in 5:
			var frac := 1.0 - float(i) / 5.0
			draw_circle(Vector2(cx, cy), b["r"] * frac, Color(col.r, col.g, col.b, 0.016 + 0.006 * i))

	# faint dot grid, FM data-room texture
	var dot := Color(1, 1, 1, 0.025)
	var y := DOT_SPACING * 0.5
	while y < sz.y:
		var x := DOT_SPACING * 0.5
		while x < sz.x:
			draw_circle(Vector2(x, y), 1.2, dot)
			x += DOT_SPACING
		y += DOT_SPACING

	# grounding horizon band + slow "scoreboard sweep" light
	var band_y := sz.y * 0.72
	draw_rect(Rect2(0, band_y, sz.x, 1), Color(ThemeBuilder.COL_BORDER, 0.6))
	var sweep_x := fposmod(_t * 42.0, sz.x + 500.0) - 250.0
	for i in 24:
		var a := 0.05 * (1.0 - absf(i - 12.0) / 12.0)
		draw_rect(Rect2(sweep_x + i * 10.0, band_y - 1, 10, 3),
			Color(ThemeBuilder.COL_ACCENT, a))

	# grounded footer band
	draw_rect(Rect2(0, sz.y - 120, sz.x, 120), Color(0, 0, 0, 0.30))
