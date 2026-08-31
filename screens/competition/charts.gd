class_name CompCharts
extends RefCounted
## Competition piece: FM Data-Hub-grade chart widgets, custom-drawn Controls.
## Everything follows the house dataviz rules: color carries entity identity
## (club color / accent), text stays in text tokens, grids are recessive,
## every plot has hover tooltips (data inspection), and no dual axes.
##
## Widgets:
##   PositionChart  — league position over matchdays, all clubs, zones shaded
##   Sparkline      — small inline trend line (ratings, positions)
##   BarChartH      — horizontal bars, plain or diverging around zero
##   ScatterChart   — labeled scatter with mean crosshair + quadrant captions
##   PercentileBar  — 0..100 percentile gauge with diverging tier color

const TB := preload("res://shared/theme/theme_builder.gd")

const COL_GRID := Color(0.18, 0.208, 0.314, 0.55)          # recessive grid
const COL_WIN := Color("57c979")
const COL_LOSS := Color("e06060")
const COL_GOLD := Color(0.95, 0.83, 0.4)


## Diverging percentile tint: red (bad) -> neutral -> green (good).
static func pct_color(p: float) -> Color:
	p = clampf(p, 0.0, 1.0)
	if p >= 0.5:
		return COL_WIN.lerp(Color.WHITE, 1.0 - (p - 0.5) * 2.0 * 0.9)
	return COL_LOSS.lerp(Color.WHITE, 1.0 - (0.5 - p) * 2.0 * 0.9)


## Subtle diverging row/cell background tint for percentile context in tables.
static func pct_tint(p: float, max_alpha: float = 0.20) -> Color:
	p = clampf(p, 0.0, 1.0)
	var a := absf(p - 0.5) * 2.0
	if a < 0.12:
		return Color(0, 0, 0, 0)   # neutral midfield: no tint
	var base := COL_WIN if p >= 0.5 else COL_LOSS
	return Color(base.r, base.g, base.b, a * max_alpha)


static func ordinal(n: int) -> String:
	if n <= 0:
		return "-"
	return I18n.ordinal(n)


# ============================================================== PositionChart

## Multi-club league position tracker. All clubs drawn as thin recessive
## lines; your club in accent; hovering picks out any club in its own color.
class PositionChart:
	extends Control
	var series: Array = []        # [{id, label, color, values: Array[int], highlight: bool}]
	var n_positions := 16
	var zone_title_end := 1
	var zone_promo_end := 4
	var zone_releg_from := 14
	var _hover := -1              # hovered series index

	const M_LEFT := 34.0
	const M_RIGHT := 64.0
	const M_TOP := 10.0
	const M_BOTTOM := 22.0

	# (duplicated from the outer scope: inner classes cannot call outer statics)
	static func ordinal(n: int) -> String:
		if n <= 0:
			return "-"
		return I18n.ordinal(n)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_exited.connect(func():
			_hover = -1
			queue_redraw())

	func set_data(p_series: Array, p_n_positions: int) -> void:
		series = p_series
		n_positions = maxi(p_n_positions, 2)
		_hover = -1
		queue_redraw()

	func _rounds() -> int:
		var r := 0
		for s in series:
			r = maxi(r, (s["values"] as Array).size())
		return r

	func _plot(rect_size: Vector2) -> Rect2:
		return Rect2(M_LEFT, M_TOP,
			maxf(rect_size.x - M_LEFT - M_RIGHT, 10.0),
			maxf(rect_size.y - M_TOP - M_BOTTOM, 10.0))

	func _xy(round_i: int, pos: float, plot: Rect2, rounds: int) -> Vector2:
		var fx: float = 0.0 if rounds <= 1 else float(round_i) / float(rounds - 1)
		var fy: float = (pos - 1.0) / float(n_positions - 1)
		return Vector2(plot.position.x + fx * plot.size.x, plot.position.y + fy * plot.size.y)

	func _draw() -> void:
		var font := get_theme_default_font()
		var rounds := _rounds()
		if series.is_empty() or rounds < 1:
			draw_string(font, Vector2(12, size.y / 2.0),
				"The position graph appears after the first full matchday.",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TB.COL_TEXT_DIM)
			return
		var plot := _plot(size)
		var half_row := plot.size.y / float(n_positions - 1) / 2.0

		# zone bands (champions gold / championship series green / relegation red)
		var band := func(from_pos: float, to_pos: float, col: Color):
			var y0 := _xy(0, from_pos, plot, rounds).y - half_row
			var y1 := _xy(0, to_pos, plot, rounds).y + half_row
			draw_rect(Rect2(plot.position.x, y0, plot.size.x, y1 - y0), col)
		band.call(1.0, float(zone_title_end), Color(0.83, 0.68, 0.21, 0.07))
		if zone_promo_end > zone_title_end:
			band.call(float(zone_title_end + 1), float(zone_promo_end), Color(0.34, 0.79, 0.47, 0.05))
		band.call(float(zone_releg_from), float(n_positions), Color(0.88, 0.38, 0.38, 0.05))

		# horizontal grid + position labels (1, 4, 8, 12, n)
		var marks: Array = [1, zone_promo_end, 8, 12, n_positions]
		for p in marks:
			var y := _xy(0, float(p), plot, rounds).y
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), COL_GRID, 1.0)
			draw_string(font, Vector2(4, y + 4), ordinal(int(p)),
				HORIZONTAL_ALIGNMENT_LEFT, M_LEFT - 6, 10, TB.COL_TEXT_DIM)
		# vertical ticks every 5 matchdays
		var step := 5
		for r in range(step, rounds + 1, step):
			var x := _xy(r - 1, 1.0, plot, rounds).x
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), COL_GRID, 1.0)
			draw_string(font, Vector2(x - 8, size.y - 6), str(r),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TB.COL_TEXT_DIM)
		draw_string(font, Vector2(plot.position.x, size.y - 6), "MD",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TB.COL_TEXT_DIM)

		# lines: recessive first, then highlight, then hovered on top
		var order: Array = []
		for i in series.size():
			if i != _hover and not bool(series[i].get("highlight", false)):
				order.append(i)
		for i in series.size():
			if i != _hover and bool(series[i].get("highlight", false)):
				order.append(i)
		if _hover >= 0:
			order.append(_hover)
		for i in order:
			var s: Dictionary = series[i]
			var vals: Array = s["values"]
			if vals.is_empty():
				continue
			var highlight: bool = bool(s.get("highlight", false))
			var hovered: bool = i == _hover
			var col: Color
			var width: float
			if hovered:
				col = s["color"]
				width = 2.4
			elif highlight:
				col = TB.COL_ACCENT.lightened(0.15)
				width = 2.4
			else:
				col = Color(TB.COL_TEXT_DIM, 0.30)
				width = 1.2
			var pts := PackedVector2Array()
			for r in vals.size():
				pts.append(_xy(r, float(vals[r]), plot, rounds))
			if pts.size() == 1:
				draw_circle(pts[0], 3.0, col)
			else:
				draw_polyline(pts, col, width, true)
			# end dot + right-edge direct label at the final position
			var last := pts[pts.size() - 1]
			if highlight or hovered:
				draw_circle(last, 3.4, col)
				# 2px surface ring so overlapping marks stay separable
				draw_arc(last, 4.6, 0, TAU, 20, TB.COL_BG, 2.0, true)
			var lbl_col := col if (highlight or hovered) else Color(TB.COL_TEXT_DIM, 0.75)
			draw_string(font, Vector2(plot.end.x + 8, last.y + 4), str(s["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, M_RIGHT - 10, 10, lbl_col)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			var idx := _nearest_series(ev.position)
			if idx != _hover:
				_hover = idx
				queue_redraw()

	func _nearest_series(p: Vector2) -> int:
		var rounds := _rounds()
		if rounds < 1:
			return -1
		var plot := _plot(size)
		var best := -1
		var best_d := 10.0
		for i in series.size():
			var vals: Array = series[i]["values"]
			for r in vals.size():
				var d := p.distance_to(_xy(r, float(vals[r]), plot, rounds))
				if d < best_d:
					best_d = d
					best = i
		return best

	func _get_tooltip(at_position: Vector2) -> String:
		var idx := _nearest_series(at_position)
		if idx < 0:
			return ""
		var s: Dictionary = series[idx]
		var vals: Array = s["values"]
		var rounds := _rounds()
		var plot := _plot(size)
		var best_r := vals.size() - 1
		var best_d := 1e9
		for r in vals.size():
			var d: float = absf(at_position.x - _xy(r, 1.0, plot, rounds).x)
			if d < best_d:
				best_d = d
				best_r = r
		return "%s — %s after Matchday %d" % [s.get("full", s["label"]),
			ordinal(int(vals[best_r])), best_r + 1]


# ================================================================== Sparkline

## Small inline trend line. `invert` for position-like data (lower = better).
class Sparkline:
	extends Control
	var values: Array = []        # floats
	var labels: Array = []        # optional per-point tooltip captions
	var color: Color = TB.COL_ACCENT
	var invert := false
	var ref_value := NAN          # dashed reference line (e.g. league average)
	var v_min := NAN
	var v_max := NAN              # explicit range; auto if NAN

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_data(p_values: Array, p_labels: Array = []) -> void:
		values = p_values
		labels = p_labels
		queue_redraw()

	func _range() -> Vector2:
		var lo := v_min
		var hi := v_max
		if is_nan(lo) or is_nan(hi):
			lo = 1e18
			hi = -1e18
			for v in values:
				lo = minf(lo, float(v))
				hi = maxf(hi, float(v))
			if not is_nan(ref_value):
				lo = minf(lo, ref_value)
				hi = maxf(hi, ref_value)
			var pad := maxf((hi - lo) * 0.15, 0.15)
			lo -= pad
			hi += pad
		return Vector2(lo, hi)

	func _pt(i: int, v: float, r: Vector2) -> Vector2:
		var n := values.size()
		var fx: float = 0.5 if n <= 1 else float(i) / float(n - 1)
		var fy := clampf((v - r.x) / maxf(r.y - r.x, 0.0001), 0.0, 1.0)
		if not invert:
			fy = 1.0 - fy
		return Vector2(3.0 + fx * (size.x - 6.0), 2.0 + fy * (size.y - 4.0))

	func _draw() -> void:
		if values.is_empty():
			var font := get_theme_default_font()
			draw_string(font, Vector2(2, size.y / 2.0 + 4), "—",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TB.COL_TEXT_DIM)
			return
		var r := _range()
		if not is_nan(ref_value):
			var ry := _pt(0, ref_value, r).y
			draw_dashed_line(Vector2(2, ry), Vector2(size.x - 2, ry),
				Color(TB.COL_TEXT_DIM, 0.5), 1.0, 3.0)
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(_pt(i, float(values[i]), r))
		if pts.size() >= 2:
			# soft area fill under/over the line
			var poly := PackedVector2Array(pts)
			var base_y: float = 2.0 if invert else size.y - 2.0
			poly.append(Vector2(pts[pts.size() - 1].x, base_y))
			poly.append(Vector2(pts[0].x, base_y))
			draw_colored_polygon(poly, Color(color, 0.09))
			draw_polyline(pts, color, 1.6, true)
		var last := pts[pts.size() - 1]
		draw_circle(last, 2.6, color.lightened(0.2))

	func _get_tooltip(at_position: Vector2) -> String:
		if values.is_empty():
			return ""
		var r := _range()
		var best := 0
		var best_d := 1e9
		for i in values.size():
			var d: float = absf(at_position.x - _pt(i, float(values[i]), r).x)
			if d < best_d:
				best_d = d
				best = i
		var cap: String = str(labels[best]) if best < labels.size() else "#%d" % (best + 1)
		return "%s: %s" % [cap, I18n.decimal(float(values[best]), 2).trim_suffix(",00").trim_suffix(".00")]


# =================================================================== BarChartH

## Horizontal bar chart. Bars are 2px-gapped, value-labeled at their data end,
## diverging around zero when negative values appear. Rows carry club colors.
class BarChartH:
	extends Control
	var rows: Array = []           # [{label, value, color, tip}]
	var decimals := 0
	var suffix := ""
	var label_w := 96.0
	var _hover := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_exited.connect(func():
			_hover = -1
			queue_redraw())

	func set_data(p_rows: Array) -> void:
		rows = p_rows
		_hover = -1
		queue_redraw()

	func _fmt(v: float) -> String:
		var s := ("%+.*f" % [decimals, v]) if _diverging() else ("%.*f" % [decimals, v])
		return s + suffix

	func _diverging() -> bool:
		for r in rows:
			if float(r["value"]) < 0.0:
				return true
		return false

	func _row_rect(i: int) -> Rect2:
		var h := size.y / maxf(rows.size(), 1.0)
		return Rect2(0, i * h, size.x, h)

	func _draw() -> void:
		if rows.is_empty():
			return
		var font := get_theme_default_font()
		var diverging := _diverging()
		var vmax := 0.0001
		for r in rows:
			vmax = maxf(vmax, absf(float(r["value"])))
		var plot_x := label_w + 8.0
		var val_w := 46.0
		var plot_w := maxf(size.x - plot_x - val_w, 20.0)
		var zero_x: float = plot_x + (plot_w / 2.0 if diverging else 0.0)
		var span: float = (plot_w / 2.0 if diverging else plot_w)
		var row_h := size.y / float(rows.size())
		var bar_h := clampf(row_h - 4.0, 4.0, 15.0)

		# baseline
		draw_line(Vector2(zero_x, 0), Vector2(zero_x, size.y), COL_GRID, 1.0)

		for i in rows.size():
			var r: Dictionary = rows[i]
			var v := float(r["value"])
			var y := i * row_h + (row_h - bar_h) / 2.0
			var w := span * absf(v) / vmax
			var col: Color = r.get("color", TB.COL_ACCENT)
			if diverging:
				col = COL_WIN if v >= 0.0 else COL_LOSS
			if i == _hover:
				col = col.lightened(0.2)
				draw_rect(Rect2(0, i * row_h, size.x, row_h), Color(1, 1, 1, 0.04))
			var bx := zero_x if v >= 0.0 else zero_x - w
			draw_rect(Rect2(bx, y, maxf(w, 1.0), bar_h), Color(col, 0.85))
			# identity swatch stays with the entity even when bars are diverging
			var swatch: Color = r.get("color", col)
			draw_rect(Rect2(0, y + (bar_h - 9.0) / 2.0, 9, 9), swatch)
			draw_rect(Rect2(0, y + (bar_h - 9.0) / 2.0, 9, 9), swatch.darkened(0.35), false, 1.0)
			# text tokens: label + value, never in series color
			draw_string(font, Vector2(14, y + bar_h - 1.0), str(r["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, label_w - 14.0, 10, TB.COL_TEXT)
			var vx := (bx + w + 6.0) if v >= 0.0 else (bx - 6.0 - font.get_string_size(
				_fmt(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x)
			draw_string(font, Vector2(vx, y + bar_h - 1.0), _fmt(v),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color.WHITE if i == _hover else TB.COL_TEXT_DIM)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			var idx := clampi(int(ev.position.y / maxf(size.y / maxf(rows.size(), 1.0), 1.0)),
				0, rows.size() - 1) if not rows.is_empty() else -1
			if idx != _hover:
				_hover = idx
				queue_redraw()

	func _get_tooltip(at_position: Vector2) -> String:
		if rows.is_empty():
			return ""
		var idx := clampi(int(at_position.y / (size.y / float(rows.size()))), 0, rows.size() - 1)
		var r: Dictionary = rows[idx]
		return str(r.get("tip", "%s: %s" % [r["label"], _fmt(float(r["value"]))]))


# ================================================================ ScatterChart

## Labeled scatter with dashed mean crosshair and quadrant captions.
class ScatterChart:
	extends Control
	var points: Array = []         # [{label, x, y, color, highlight, tip}]
	var x_title := ""
	var y_title := ""
	var quads: Array = []          # 4 captions [top-left, top-right, bottom-left, bottom-right]
	var _hover := -1

	const M_LEFT := 30.0
	const M_RIGHT := 12.0
	const M_TOP := 8.0
	const M_BOTTOM := 26.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_exited.connect(func():
			_hover = -1
			queue_redraw())

	func set_data(p_points: Array) -> void:
		points = p_points
		_hover = -1
		queue_redraw()

	func _bounds() -> Rect2:
		var lo := Vector2(1e18, 1e18)
		var hi := Vector2(-1e18, -1e18)
		for p in points:
			lo.x = minf(lo.x, float(p["x"]))
			lo.y = minf(lo.y, float(p["y"]))
			hi.x = maxf(hi.x, float(p["x"]))
			hi.y = maxf(hi.y, float(p["y"]))
		var pad := (hi - lo) * 0.14
		pad.x = maxf(pad.x, 0.5)
		pad.y = maxf(pad.y, 0.5)
		return Rect2(lo - pad, hi - lo + pad * 2.0)

	func _plot() -> Rect2:
		return Rect2(M_LEFT, M_TOP, maxf(size.x - M_LEFT - M_RIGHT, 10.0),
			maxf(size.y - M_TOP - M_BOTTOM, 10.0))

	func _to_px(x: float, y: float, b: Rect2, plot: Rect2) -> Vector2:
		var fx := (x - b.position.x) / maxf(b.size.x, 0.0001)
		var fy := (y - b.position.y) / maxf(b.size.y, 0.0001)
		return Vector2(plot.position.x + fx * plot.size.x, plot.end.y - fy * plot.size.y)

	func _draw() -> void:
		var font := get_theme_default_font()
		if points.is_empty():
			draw_string(font, Vector2(12, size.y / 2.0), "No data yet.",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TB.COL_TEXT_DIM)
			return
		var b := _bounds()
		var plot := _plot()
		draw_rect(plot, COL_GRID, false, 1.0)

		# league-average crosshair (dashed, recessive)
		var mean := Vector2.ZERO
		for p in points:
			mean += Vector2(float(p["x"]), float(p["y"]))
		mean /= float(points.size())
		var mpx := _to_px(mean.x, mean.y, b, plot)
		draw_dashed_line(Vector2(plot.position.x, mpx.y), Vector2(plot.end.x, mpx.y),
			Color(TB.COL_TEXT_DIM, 0.45), 1.0, 4.0)
		draw_dashed_line(Vector2(mpx.x, plot.position.y), Vector2(mpx.x, plot.end.y),
			Color(TB.COL_TEXT_DIM, 0.45), 1.0, 4.0)

		# quadrant captions
		if quads.size() == 4:
			var qcol := Color(TB.COL_TEXT_DIM, 0.6)
			draw_string(font, plot.position + Vector2(6, 12), str(quads[0]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, qcol)
			draw_string(font, Vector2(plot.end.x - 6 - font.get_string_size(str(quads[1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, plot.position.y + 12), str(quads[1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, qcol)
			draw_string(font, Vector2(plot.position.x + 6, plot.end.y - 6), str(quads[2]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, qcol)
			draw_string(font, Vector2(plot.end.x - 6 - font.get_string_size(str(quads[3]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, plot.end.y - 6), str(quads[3]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, qcol)

		# axis titles (single axis each — never dual)
		draw_string(font, Vector2(plot.position.x, size.y - 8), x_title,
			HORIZONTAL_ALIGNMENT_LEFT, plot.size.x, 10, TB.COL_TEXT_DIM)
		draw_set_transform(Vector2(12, plot.end.y), -PI / 2.0)
		draw_string(font, Vector2.ZERO, y_title, HORIZONTAL_ALIGNMENT_LEFT, plot.size.y, 10,
			TB.COL_TEXT_DIM)
		draw_set_transform(Vector2.ZERO, 0.0)

		# dots + direct labels (identity via club color AND text label — not color-alone)
		for i in points.size():
			var p: Dictionary = points[i]
			var px := _to_px(float(p["x"]), float(p["y"]), b, plot)
			var col: Color = p.get("color", TB.COL_ACCENT)
			var highlight: bool = bool(p.get("highlight", false))
			var rad: float = 6.0 if highlight else 4.5
			if i == _hover:
				rad += 1.5
			# 2px surface ring separates overlapping dots
			draw_circle(px, rad + 2.0, TB.COL_PANEL)
			draw_circle(px, rad, col)
			if highlight:
				draw_arc(px, rad + 3.0, 0, TAU, 24, TB.COL_ACCENT.lightened(0.2), 1.5, true)
			var lbl_col: Color = Color.WHITE if (highlight or i == _hover) else TB.COL_TEXT_DIM
			draw_string(font, px + Vector2(rad + 4.0, 4.0), str(p["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lbl_col)

	func _nearest(p: Vector2) -> int:
		if points.is_empty():
			return -1
		var b := _bounds()
		var plot := _plot()
		var best := -1
		var best_d := 14.0
		for i in points.size():
			var d := p.distance_to(_to_px(float(points[i]["x"]), float(points[i]["y"]), b, plot))
			if d < best_d:
				best_d = d
				best = i
		return best

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			var idx := _nearest(ev.position)
			if idx != _hover:
				_hover = idx
				queue_redraw()

	func _get_tooltip(at_position: Vector2) -> String:
		var idx := _nearest(at_position)
		if idx < 0:
			return ""
		return str(points[idx].get("tip", points[idx]["label"]))


# =============================================================== PercentileBar

## FM-style percentile gauge: value's league percentile as a filled track.
class PercentileBar:
	extends Control
	var pctl := 0.0    # 0..1

	# (duplicated from the outer scope: inner classes cannot call outer statics)
	static func pct_color(p: float) -> Color:
		p = clampf(p, 0.0, 1.0)
		if p >= 0.5:
			return COL_WIN.lerp(Color.WHITE, 1.0 - (p - 0.5) * 2.0 * 0.9)
		return COL_LOSS.lerp(Color.WHITE, 1.0 - (0.5 - p) * 2.0 * 0.9)

	func _init() -> void:
		custom_minimum_size = Vector2(90, 10)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_pct(p: float) -> void:
		pctl = clampf(p, 0.0, 1.0)
		tooltip_text = I18n.t("League percentile: %d (higher is better)") % roundi(pctl * 100.0)
		queue_redraw()

	func _draw() -> void:
		var track := Rect2(0, (size.y - 8.0) / 2.0, size.x, 8.0)
		draw_rect(track, TB.COL_BG)
		draw_rect(track, TB.COL_BORDER, false, 1.0)
		# quartile ticks (recessive)
		for q in [0.25, 0.5, 0.75]:
			var x: float = track.position.x + track.size.x * q
			draw_line(Vector2(x, track.position.y), Vector2(x, track.end.y),
				COL_GRID, 1.0)
		var col := pct_color(pctl)
		draw_rect(Rect2(track.position.x + 1, track.position.y + 1,
			maxf((track.size.x - 2) * pctl, 1.0), track.size.y - 2), Color(col, 0.75))
		var mx: float = track.position.x + 1 + maxf((track.size.x - 2) * pctl - 1.0, 0.0)
		draw_rect(Rect2(mx, track.position.y - 1, 2, track.size.y + 2), col)
