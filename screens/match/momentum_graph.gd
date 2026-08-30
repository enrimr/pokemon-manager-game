extends Control
## FM xG-style live momentum chart. Positive = the player's side on top.
## Fed incrementally by the live view; also used complete on the post screen.

var points: Array = []        # [{v, battle, turn}]
var faint_marks: Array = []   # [{idx, side}]
var player_side := 0
var shorts := ["US", "THEM"]

const COL_US := Color("57c979")
const COL_THEM := Color("e06060")
const COL_AXIS := Color("2e3550")
const COL_GRID := Color("222840")
const COL_SEP := Color("4c4494")


func set_data(p_points: Array, p_faints: Array, p_shorts: Array, p_player_side: int) -> void:
	points = p_points
	faint_marks = p_faints
	player_side = p_player_side
	shorts = [p_shorts[p_player_side], p_shorts[1 - p_player_side]]
	queue_redraw()


func _draw() -> void:
	var r := get_rect()
	var w := r.size.x
	var h := r.size.y
	var pad_l := 8.0
	var pad_r := 8.0
	var mid := h * 0.5
	var amp := h * 0.42

	# grid
	for frac in [0.25, 0.5, 0.75]:
		draw_line(Vector2(pad_l, mid - amp * 2.0 * (frac - 0.5)),
			Vector2(w - pad_r, mid - amp * 2.0 * (frac - 0.5)), COL_GRID, 1.0)
	draw_line(Vector2(pad_l, mid), Vector2(w - pad_r, mid), COL_AXIS, 1.0)

	var font := get_theme_default_font()
	draw_string(font, Vector2(pad_l + 2, 14), shorts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_US)
	draw_string(font, Vector2(pad_l + 2, h - 5), shorts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_THEM)

	if points.size() < 2:
		return
	var n := points.size()
	var span := maxi(n - 1, 24)
	var step := (w - pad_l - pad_r) / float(span)

	# battle separators
	for i in range(1, n):
		if points[i]["battle"] != points[i - 1]["battle"]:
			var x := pad_l + i * step
			var y := 4.0
			while y < h - 4.0:
				draw_line(Vector2(x, y), Vector2(x, minf(y + 4.0, h - 4.0)), COL_SEP, 1.0)
				y += 8.0
			draw_string(font, Vector2(x + 3, 14), "B%d" % int(points[i]["battle"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("8b91a8"))

	# filled area segments + line
	var line_pts := PackedVector2Array()
	for i in n:
		var v := clampf(float(points[i]["v"]), -1.0, 1.0)
		line_pts.append(Vector2(pad_l + i * step, mid - v * amp))
	for i in range(n - 1):
		var p0 := line_pts[i]
		var p1 := line_pts[i + 1]
		var avg := (float(points[i]["v"]) + float(points[i + 1]["v"])) * 0.5
		var col := (COL_US if avg >= 0.0 else COL_THEM)
		col.a = 0.22
		var poly := PackedVector2Array([p0, p1, Vector2(p1.x, mid), Vector2(p0.x, mid)])
		draw_colored_polygon(poly, col)
	# color line per-segment
	for i in range(n - 1):
		var avg2 := (float(points[i]["v"]) + float(points[i + 1]["v"])) * 0.5
		draw_line(line_pts[i], line_pts[i + 1], COL_US if avg2 >= 0.0 else COL_THEM, 2.0, true)

	# faint marks
	for m in faint_marks:
		var idx := int(m["idx"])
		if idx < 0 or idx >= n:
			continue
		var lost_by_player: bool = int(m["side"]) == player_side
		draw_circle(line_pts[idx], 3.5, COL_THEM if lost_by_player else COL_US)
		draw_circle(line_pts[idx], 1.8, Color("11141d"))

	# live head
	draw_circle(line_pts[n - 1], 3.0, Color("f2f4fa"))
