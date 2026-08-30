extends Control
## BattleStage — the animated arena centerpiece of the live match view.
## Two platforms, type-coloured animated Pokémon medallions (monograms — no
## copyrighted art), attack lunges, projectile bursts by move type, hit
## flashes/shakes, floating damage numbers, status pulses, faint drops,
## switch slides, item flourishes. Driven by play_event() from the live view.

const UI := preload("res://screens/match/ui_bits.gd")

var runner  # MatchRunner

var _meds: Array = [null, null]   # Medallion per side (0 = home, bottom-left)
var _caption: Label
var _sub_caption: Label
var _time := 0.0
var _cap_tween: Tween = null


# ================================================================= medallion

class Medallion:
	extends Control
	## Animated disc representing the active Pokémon: type-split ring, HP arc,
	## species monogram, level tag, status pulse. Position is driven by the
	## stage every frame (home + idle bob + anim_offset).

	const UIB := preload("res://screens/match/ui_bits.gd")

	var battler: Dictionary = {}   # live vm dict (hp mutates under us — good)
	var anim_offset := Vector2.ZERO
	var flash := 0.0               # 0..1 white impact overlay
	var t := 0.0                   # shared clock (set by stage)
	var facing := 1                # 1 = faces right (home), -1 faces left

	func set_battler(b: Dictionary) -> void:
		battler = b
		queue_redraw()

	func center() -> Vector2:
		return global_position + size * 0.5

	func _draw() -> void:
		if battler.is_empty():
			return
		var c := size * 0.5
		var r := size.x * 0.5 - 14.0
		var fainted := bool(battler.get("fainted", false))
		var types: Array = battler.get("types", ["normal"])
		var col_a: Color = DataStore.type_color(str(types[0]))
		var col_b: Color = DataStore.type_color(str(types[types.size() - 1]))
		if fainted:
			col_a = col_a.lerp(Color("3a3f52"), 0.75)
			col_b = col_b.lerp(Color("3a3f52"), 0.75)
		# status pulse ring (outside everything)
		var status := str(battler.get("status", ""))
		if status != "" and not fainted:
			var sc: Color = UIB.STATUS_COLORS.get(status, Color.WHITE)
			sc.a = 0.35 + 0.3 * (0.5 + 0.5 * sin(t * 5.0))
			draw_arc(c, r + 12.0, 0.0, TAU, 40, sc, 3.0, true)
		if bool(battler.get("confused", false)) and not fainted:
			var cc: Color = UIB.STATUS_COLORS["confused"]
			cc.a = 0.3 + 0.25 * (0.5 + 0.5 * sin(t * 7.0 + 1.7))
			draw_arc(c, r + 17.0, 0.0, TAU, 40, cc, 2.0, true)
		# body disc: darker fill, type-split rim
		var fill := col_a.lerp(Color("11141d"), 0.62)
		draw_circle(c, r, fill)
		draw_arc(c, r - 1.0, -PI * 0.5, PI * 0.5, 32, col_a, 6.0, true)
		draw_arc(c, r - 1.0, PI * 0.5, PI * 1.5, 32, col_b, 6.0, true)
		# inner sheen
		var sheen := Color(1, 1, 1, 0.05)
		draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.55, sheen)
		# HP arc (starts at 12 o'clock, clockwise)
		var frac := clampf(float(battler.get("hp", 0)) / maxf(float(battler.get("max_hp", 1)), 1.0), 0.0, 1.0)
		if not fainted:
			draw_arc(c, r + 7.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, UIB.hp_color(frac), 4.0, true)
		# monogram
		var font := get_theme_default_font()
		var mono := str(battler.get("species", battler.get("name", "?"))).substr(0, 3).to_upper()
		var fs := int(size.x * 0.26)
		var msz := font.get_string_size(mono, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var mcol := Color("f2f4fa") if not fainted else Color("6a7188")
		draw_string(font, c + Vector2(-msz.x * 0.5, msz.y * 0.32), mono,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mcol)
		# level tag
		var lv := "Lv%d" % int(battler.get("level", 0))
		var lsz := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
		var tag_pos := c + Vector2(r * 0.25, r * 0.78)
		draw_rect(Rect2(tag_pos - Vector2(4, 11), lsz + Vector2(8, 5)), Color("11141dcc"))
		draw_string(font, tag_pos, lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b9bfd0"))
		# impact flash
		if flash > 0.0:
			draw_circle(c, r, Color(1, 1, 1, flash * 0.75))


# ================================================================= lifecycle

func setup(p_runner) -> void:
	runner = p_runner


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in 2:
		var m := Medallion.new()
		m.facing = 1 if side == 0 else -1
		m.size = Vector2(118, 118) if side == 0 else Vector2(100, 100)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		_meds[side] = m
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 17)
	_caption.add_theme_color_override("font_color", Color("f2f4fa"))
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_caption.offset_top = 8
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_sub_caption = Label.new()
	_sub_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_caption.add_theme_font_size_override("font_size", 12)
	_sub_caption.add_theme_color_override("font_color", Color("8b91a8"))
	_sub_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_sub_caption.offset_top = 32
	_sub_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_caption)
	sync_actives()


func _process(delta: float) -> void:
	_time += delta
	for side in 2:
		var m: Medallion = _meds[side]
		if m == null:
			continue
		m.t = _time
		var bob := Vector2(0, sin(_time * 2.2 + side * 2.1) * 4.0)
		if bool(m.battler.get("fainted", false)):
			bob = Vector2.ZERO
		m.position = _slot(side) - m.size * 0.5 + bob + m.anim_offset
		m.queue_redraw()
	queue_redraw()


func _slot(side: int) -> Vector2:
	## Home fights from the near (bottom-left) platform, away from the far one.
	var w := size.x
	var h := size.y
	if side == 0:
		return Vector2(w * 0.30, h * 0.62)
	return Vector2(w * 0.72, h * 0.33)


func sync_actives() -> void:
	if runner == null:
		return
	for side in 2:
		var team: Array = runner.vm["teams"][side]
		if team.is_empty():
			continue
		var m: Medallion = _meds[side]
		m.set_battler(team[runner.vm["active"][side]])
		m.anim_offset = Vector2.ZERO
		m.modulate.a = 0.35 if bool(m.battler.get("fainted", false)) else 1.0


# ================================================================= background

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 40.0 or h < 40.0:
		return  # not laid out yet
	# arena floor gradient
	draw_rect(Rect2(0, 0, w, h), Color("141827"))
	draw_rect(Rect2(0, h * 0.42, w, h * 0.58), Color("171c2e"))
	draw_rect(Rect2(0, h * 0.68, w, h * 0.32), Color("1a2033"))
	# crowd band (deterministic dot noise)
	var band_h := h * 0.16
	for i in 90:
		var hx := absi(("c%d" % i).hash())
		var cx := fmod(float(hx % 977) / 977.0, 1.0) * w
		var cy := fmod(float((hx / 7) % 631) / 631.0, 1.0) * band_h + 4.0
		var flicker := 0.10 + 0.05 * sin(_time * 1.5 + float(i))
		draw_circle(Vector2(cx, cy), 2.0,
			Color.from_hsv(float(hx % 360) / 360.0, 0.35, 0.8, flicker))
	draw_line(Vector2(0, band_h + 8), Vector2(w, band_h + 8), Color("2e3550"), 1.0)
	# centre line + circle, stadium style
	var mid := Vector2(w * 0.51, h * 0.52)
	draw_ellipse_outline(mid, w * 0.10, h * 0.055, Color("2e355077"), 1.5)
	draw_line(Vector2(w * 0.40, h * 0.80), Vector2(w * 0.62, h * 0.24), Color("2e355055"), 1.5)
	# platforms
	for side in 2:
		var s := _slot(side)
		var pr := (w * 0.135) if side == 0 else (w * 0.115)
		var club: Dictionary = runner.club_for_side(side) if runner != null else {}
		var rim: Color = UI.club_color(club) if not club.is_empty() else Color("2e3550")
		var plat_c := s + Vector2(0, (68.0 if side == 0 else 58.0))
		draw_ellipse_fill(plat_c, pr, pr * 0.30, Color("11141d"))
		draw_ellipse_fill(plat_c + Vector2(0, -3), pr, pr * 0.30, Color("222840"))
		draw_ellipse_outline(plat_c + Vector2(0, -3), pr, pr * 0.30, rim * Color(1, 1, 1, 0.85), 2.0)
		# soft shadow under the medallion
		draw_ellipse_fill(plat_c + Vector2(0, -6), pr * 0.45, pr * 0.13, Color(0, 0, 0, 0.35))
		if runner != null:
			var font := get_theme_default_font()
			var tag := str(club.get("short", "?")) + ("  ·  YOU" if side == runner.player_side else "")
			var col := Color("f2f4fa") if side == runner.player_side else Color("8b91a8")
			draw_string(font, plat_c + Vector2(-pr, 22), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


func draw_ellipse_fill(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 36:
		var a := TAU * float(i) / 36.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func draw_ellipse_outline(c: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var prev := c + Vector2(rx, 0)
	for i in range(1, 37):
		var a := TAU * float(i) / 36.0
		var p := c + Vector2(cos(a) * rx, sin(a) * ry)
		draw_line(prev, p, col, width, true)
		prev = p


# ================================================================= event anims

func play_event(e: Dictionary) -> void:
	if not is_inside_tree():
		return
	var t := str(e.get("t", ""))
	match t:
		"battle_start":
			sync_actives()
			_set_caption("BATTLE %d OF 3" % runner.battle_no, Color("9a8dff"), "")
		"switch":
			_anim_switch(int(e["side"]))
		"move_used":
			_anim_move(e)
		"damage":
			_anim_damage(e)
		"miss":
			_anim_miss(int(e["side"]))
		"faint":
			_anim_faint(int(e["side"]), str(e.get("pokemon", "")))
		"heal":
			_anim_heal(e)
		"status_applied":
			_anim_status(e)
		"stat_change":
			_anim_stat(e)
		"flinch":
			_float_at(int(e["side"]), "FLINCHED", Color("e0b050"), 13)
		"confused_hit":
			_float_at(int(e["side"]), "HIT ITSELF", Color("e0b050"), 13)
		"paralyzed":
			_float_at(int(e["side"]), "FULLY PARALYSED", Color("f8d030"), 12)
		"asleep":
			_float_at(int(e["side"]), "FROZEN" if e.get("frozen", false) else "ASLEEP",
				Color("98d8d8") if e.get("frozen", false) else Color("8b91a8"), 12)
		"item_used":
			_anim_item(e)
		"held_item":
			_float_at(int(e["side"]), "◆ " + str(e.get("item_name", "")), Color("e0b050"), 12, -26.0)
		"battle_end":
			var s: Array = runner.shorts()
			_set_caption("BATTLE %d — %s TAKE IT" % [runner.battle_no, s[int(e["winner"])]],
				Color("57c979") if int(e["winner"]) == runner.player_side else Color("e06060"), "")


func _anim_switch(side: int) -> void:
	var m: Medallion = _meds[side]
	var out_dir := -1.0 if side == 0 else 1.0
	var tw := create_tween()
	tw.tween_property(m, "anim_offset", Vector2(out_dir * 240.0, 10.0), 0.22)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(m, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		var team: Array = runner.vm["teams"][side]
		m.set_battler(team[runner.vm["active"][side]]))
	tw.tween_property(m, "anim_offset", Vector2.ZERO, 0.3)\
		.from(Vector2(out_dir * 240.0, -6.0)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "modulate:a", 1.0, 0.25)


func _anim_move(e: Dictionary) -> void:
	var side := int(e.get("side", 0))
	var mname := str(e.get("move", ""))
	var mv: Dictionary = DataStore.move(mname)
	var mtype := str(mv.get("type", "normal"))
	var mcol: Color = DataStore.type_color(mtype)
	var cat := str(mv.get("category", "phys"))
	_set_caption("%s — %s" % [str(e.get("pokemon", "?")), mname], mcol,
		"%s · %s" % [mtype.to_upper(), cat.to_upper()])
	var me: Medallion = _meds[side]
	var foe: Medallion = _meds[1 - side]
	var to_foe := (_slot(1 - side) - _slot(side))
	match cat:
		"phys":
			var tw := create_tween()
			tw.tween_property(me, "anim_offset", to_foe * 0.42, 0.16)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.tween_property(me, "anim_offset", Vector2.ZERO, 0.24)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_burst(foe.center() - global_position, mcol, 7, 26.0, 0.12)
		"spec":
			_projectile(me.center() - global_position, foe.center() - global_position, mcol, 8)
			var tw2 := create_tween()
			tw2.tween_property(me, "anim_offset", to_foe.normalized() * 14.0, 0.1)
			tw2.tween_property(me, "anim_offset", Vector2.ZERO, 0.16)
		_:
			_ring(me.center() - global_position, mcol)
			_burst(me.center() - global_position, mcol, 6, 34.0, 0.0, true)


func _anim_damage(e: Dictionary) -> void:
	var side := int(e["side"])
	var m: Medallion = _meds[side]
	var amount := int(e.get("amount", 0))
	var crit := bool(e.get("crit", false))
	var eff := float(e.get("effectiveness", 1.0))
	var recoil := bool(e.get("recoil", false))
	# flash + shake
	var tw := create_tween()
	tw.tween_method(func(v): m.flash = v, 0.9, 0.0, 0.3)
	var shake := create_tween()
	var mag := 14.0 if crit or eff >= 2.0 else 8.0
	if recoil:
		mag = 5.0
	for i in 4:
		var off := Vector2((mag if i % 2 == 0 else -mag) * (1.0 - float(i) * 0.22), 0)
		shake.tween_property(m, "anim_offset", off, 0.04)
	shake.tween_property(m, "anim_offset", Vector2.ZERO, 0.06)
	# floating damage number
	var pos := m.center() - global_position + Vector2(randf_range(-14, 14), -m.size.y * 0.55)
	var txt := ("-%d" % amount) if not crit else ("CRIT -%d" % amount)
	var col := Color("f2f4fa")
	if crit:
		col = Color("e0b050")
	elif recoil:
		col = Color("a884d8")
	var fsize := 15 + int(clampf(float(amount) / maxf(float(e.get("max_hp", 1)), 1.0) * 26.0, 0.0, 13.0))
	_float_text(pos, txt, col, fsize + (4 if crit else 0))
	if not recoil:
		if eff >= 2.0:
			_float_text(pos + Vector2(0, 20), "SUPER EFFECTIVE!", Color("e0b050"), 11)
		elif eff == 0.0:
			_float_text(pos + Vector2(0, 20), "IMMUNE", Color("6a7188"), 11)
		elif eff < 1.0:
			_float_text(pos + Vector2(0, 20), "resisted", Color("6a7188"), 10)


func _anim_miss(side: int) -> void:
	## side = the attacker; the defender sidesteps out of the way.
	var d: Medallion = _meds[1 - side]
	var tw := create_tween()
	tw.tween_property(d, "anim_offset", Vector2(22.0 * (1.0 if 1 - side == 1 else -1.0), -6), 0.12)
	tw.tween_property(d, "anim_offset", Vector2.ZERO, 0.18)
	_float_at(1 - side, "MISS", Color("8b91a8"), 13)


func _anim_faint(side: int, _name: String) -> void:
	var m: Medallion = _meds[side]
	var tw := create_tween()
	tw.tween_property(m, "anim_offset", Vector2(0, 54.0), 0.5)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "modulate:a", 0.35, 0.5)
	_float_at(side, "FAINTED", Color("e06060"), 16)
	_burst(m.center() - global_position, Color("6a7188"), 8, 40.0, 0.0, true)


func _anim_heal(e: Dictionary) -> void:
	var side := int(e["side"])
	var m: Medallion = _meds[side]
	if bool(e.get("revived", false)):
		m.modulate.a = 1.0
		m.anim_offset = Vector2(0, 40)
		var tw := create_tween()
		tw.tween_property(m, "anim_offset", Vector2.ZERO, 0.4)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_float_at(side, "REVIVED!", Color("57c979"), 15)
	else:
		_float_at(side, "+%d" % int(e.get("amount", 0)), Color("57c979"), 15)
	# rising sparkles
	var base := m.center() - global_position
	for i in 5:
		_spark(base + Vector2(randf_range(-30, 30), randf_range(-6, 16)),
			Color("57c979"), Vector2(0, -randf_range(26, 48)), 0.55)


func _anim_status(e: Dictionary) -> void:
	var side := int(e["side"])
	var st := str(e.get("status", ""))
	var labels := {"burn": "BURNED!", "para": "PARALYSED!", "sleep": "ASLEEP!",
		"poison": "POISONED!", "freeze": "FROZEN!", "confused": "CONFUSED!",
		"cured": "CURED!", "woke": "WOKE UP", "thawed": "THAWED"}
	var col: Color = UI.STATUS_COLORS.get(st, Color("57c979") if st in ["cured", "woke", "thawed"] else Color("e0b050"))
	_float_at(side, str(labels.get(st, st.to_upper())), col, 14)
	_ring(_meds[side].center() - global_position, col)


func _anim_stat(e: Dictionary) -> void:
	var side := int(e["side"])
	var d := int(e.get("delta", 0))
	var names := {"atk": "ATK", "def": "DEF", "spa": "SPA", "spd": "SPD",
		"spe": "SPE", "acc": "ACC", "eva": "EVA"}
	var arrow := "▲".repeat(mini(absi(d), 2)) if d > 0 else "▼".repeat(mini(absi(d), 2))
	_float_at(side, "%s %s" % [arrow, names.get(str(e["stat"]), str(e["stat"]).to_upper())],
		Color("57c979") if d > 0 else Color("e06060"), 13)


func _anim_item(e: Dictionary) -> void:
	var side := int(e["side"])
	var iname := str(e.get("item_name", "Item"))
	_set_caption("ITEM — %s" % iname, Color("9a8dff"), "used on %s · costs the turn" % str(e.get("pokemon", "?")))
	var target_active: bool = int(e.get("target_index", -1)) == int(runner.vm["active"][side])
	var m: Medallion = _meds[side]
	var corner := Vector2(size.x * (0.12 if side == 0 else 0.88), size.y * 0.82)
	_float_text(corner, "🧰 %s" % iname, Color("9a8dff"), 14)
	if target_active:
		_projectile(corner, m.center() - global_position, Color("9a8dff"), 5)
		_ring(m.center() - global_position, Color("9a8dff"))
	else:
		_float_text(corner + Vector2(0, 18), "→ %s (bench)" % str(e.get("pokemon", "?")), Color("8b91a8"), 11)


# ================================================================= primitives

func _set_caption(text: String, col: Color, sub: String) -> void:
	_caption.text = text
	_caption.add_theme_color_override("font_color", col)
	_caption.modulate.a = 1.0
	_sub_caption.text = sub
	_sub_caption.modulate.a = 1.0
	if _cap_tween != null and _cap_tween.is_valid():
		_cap_tween.kill()
	_cap_tween = create_tween()
	_cap_tween.tween_interval(1.4)
	_cap_tween.tween_property(_caption, "modulate:a", 0.25, 0.8)
	_cap_tween.parallel().tween_property(_sub_caption, "modulate:a", 0.0, 0.8)


func _float_at(side: int, text: String, col: Color, fsize: int, dy := -40.0) -> void:
	var m: Medallion = _meds[side]
	_float_text(m.center() - global_position + Vector2(randf_range(-10, 10), -m.size.y * 0.5), text, col, fsize, dy)


func _float_text(pos: Vector2, text: String, col: Color, fsize: int, dy := -40.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("11141d"))
	l.add_theme_constant_override("outline_size", 4)
	l.position = pos - Vector2(30, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 10
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y + dy, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


func _dot(col: Color, d: float) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(d, d)
	p.size = Vector2(d, d)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(d / 2.0))
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 5
	return p


func _spark(pos: Vector2, col: Color, vel: Vector2, dur: float) -> void:
	var p := _dot(col, randf_range(5.0, 8.0))
	p.position = pos
	add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "position", pos + vel, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "modulate:a", 0.0, dur)
	tw.tween_callback(p.queue_free)


func _burst(pos: Vector2, col: Color, n: int, radius: float, delay := 0.0, slow := false) -> void:
	for i in n:
		var a := TAU * float(i) / float(n) + randf_range(-0.3, 0.3)
		var v := Vector2(cos(a), sin(a)) * radius * randf_range(0.7, 1.25)
		var p := _dot(col, randf_range(5.0, 9.0))
		p.position = pos
		p.modulate.a = 0.0
		add_child(p)
		var tw := create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
		tw.tween_callback(func(): p.modulate.a = 1.0)
		tw.tween_property(p, "position", pos + v, 0.5 if slow else 0.32)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 0.5 if slow else 0.32)
		tw.tween_callback(p.queue_free)


func _projectile(from: Vector2, to: Vector2, col: Color, n: int) -> void:
	for i in n:
		var p := _dot(col, randf_range(6.0, 10.0))
		p.position = from + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		add_child(p)
		var tw := create_tween()
		tw.tween_interval(float(i) * 0.03)
		var mid := (from + to) * 0.5 + Vector2(randf_range(-24, 24), randf_range(-36, -8))
		tw.tween_property(p, "position", mid, 0.11)
		tw.tween_property(p, "position", to + Vector2(randf_range(-12, 12), randf_range(-12, 12)), 0.11)
		tw.tween_property(p, "modulate:a", 0.0, 0.12)
		tw.tween_callback(p.queue_free)
	# impact flare a beat later
	var flare := create_tween()
	flare.tween_interval(0.24)
	flare.tween_callback(func(): _burst(to, col, 6, 24.0))


func _ring(pos: Vector2, col: Color) -> void:
	var p := _dot(Color(0, 0, 0, 0), 22.0)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = col
	sb.set_border_width_all(3)
	p.position = pos - Vector2(11, 11)
	p.pivot_offset = Vector2(11, 11)
	add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector2(4.0, 4.0), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "modulate:a", 0.0, 0.45)
	tw.tween_callback(p.queue_free)
