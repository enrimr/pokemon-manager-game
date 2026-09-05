extends Control
## BattleStage — the animated arena centerpiece of the live match view.
## Two platforms, type-coloured animated Pokémon medallions (monograms — no
## copyrighted art), attack lunges, projectile bursts by move type, hit
## flashes/shakes, floating damage numbers, status pulses, faint drops,
## switch slides, item flourishes. Driven by play_event() from the live view.

const UI := preload("res://screens/match/ui_bits.gd")

var runner  # MatchRunner

var _meds: Array = [[], []]       # Medallions per side per slot (doubles: 2 each)
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
	var sprite_view := ""          # "back" (our side) | "front" (theirs)
	var _sprite: Texture2D = null

	func set_battler(b: Dictionary) -> void:
		battler = b
		_sprite = null
		var sid := PokeArt.id_of(str(b.get("species", "")))
		if sid > 0:
			_sprite = PokeArt.tex_view(sid, sprite_view)
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
		# species art: gen-V battle sprite (back = ours, front = theirs),
		# flipped to face the opponent; monogram only when art is missing
		var font := get_theme_default_font()
		if _sprite != null:
			var s := r * 1.7
			var tint := Color.WHITE if not fainted else Color(0.5, 0.52, 0.6, 0.85)
			var rect := Rect2(c - Vector2(s, s) * 0.5 - Vector2(0, r * 0.08), Vector2(s, s))
			var flip := (facing < 0 and sprite_view == "back") \
				or (facing > 0 and sprite_view == "front")
			if flip:
				# mirror about the disc centre: the rect is centred on c.x,
				# so only the texture flips, not its position
				draw_set_transform(Vector2(c.x * 2.0, 0.0), 0.0, Vector2(-1, 1))
			draw_texture_rect(_sprite, rect, false, tint)
			if flip:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var mono := str(battler.get("species", battler.get("name", "?"))).substr(0, 3).to_upper()
			var fs := int(size.x * 0.26)
			var msz := font.get_string_size(mono, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			var mcol := Color("f2f4fa") if not fainted else Color("6a7188")
			draw_string(font, c + Vector2(-msz.x * 0.5, msz.y * 0.32), mono,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mcol)
		# level tag
		var lv := tr("Lv%d") % int(battler.get("level", 0))
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
	_ensure_meds()
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
		for k in _meds[side].size():
			var m: Medallion = _meds[side][k]
			if m == null:
				continue
			m.t = _time
			var bob := Vector2(0, sin(_time * 2.2 + side * 2.1 + k * 1.3) * 4.0)
			if bool(m.battler.get("fainted", false)):
				bob = Vector2.ZERO
			m.position = _slot_pos(side, k) - m.size * 0.5 + bob + m.anim_offset
			m.queue_redraw()
	queue_redraw()


## How many active slots this battle runs per side (1 singles, 2 doubles).
func _slots_n() -> int:
	if runner == null:
		return 1
	return runner.vm["actives"][0].size()


## Create/trim the medallion pool to match the current battle format.
func _ensure_meds() -> void:
	var n := _slots_n()
	for side in 2:
		while _meds[side].size() > n:
			var old: Medallion = _meds[side].pop_back()
			if old != null:
				old.queue_free()
		while _meds[side].size() < n:
			var k: int = _meds[side].size()
			var m := Medallion.new()
			m.facing = 1 if side == 0 else -1
			m.sprite_view = "back" if runner != null and side == runner.player_side else "front"
			m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var base := 118.0 if side == 0 else 100.0
			if n > 1:
				base *= 0.82
			m.size = Vector2(base, base)
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(m)
			_meds[side].append(m)


func _slot_pos(side: int, slot: int) -> Vector2:
	## Home fights from the near (bottom-left) platforms, away from the far ones.
	var w := size.x
	var h := size.y
	if _slots_n() <= 1:
		return Vector2(w * 0.30, h * 0.62) if side == 0 else Vector2(w * 0.72, h * 0.33)
	if side == 0:
		return Vector2(w * 0.24, h * 0.56) if slot == 0 else Vector2(w * 0.41, h * 0.72)
	return Vector2(w * 0.63, h * 0.27) if slot == 0 else Vector2(w * 0.80, h * 0.40)


func _med(side: int, slot: int) -> Medallion:
	if slot < 0 or slot >= _meds[side].size():
		return null if _meds[side].is_empty() else _meds[side][0]
	return _meds[side][slot]


## Medallion an event refers to: explicit slot key first, then name lookup.
func _med_from_event(e: Dictionary, slot_key: String = "slot") -> Medallion:
	var side := int(e.get("side", 0))
	if e.has(slot_key):
		return _med(side, int(e[slot_key]))
	var pname := str(e.get("pokemon", ""))
	for k in _meds[side].size():
		var m: Medallion = _meds[side][k]
		if m != null and str(m.battler.get("name", "")) == pname:
			return m
	return _med(side, 0)


func sync_actives() -> void:
	if runner == null:
		return
	_ensure_meds()
	for side in 2:
		var team: Array = runner.vm["teams"][side]
		if team.is_empty():
			continue
		for k in _meds[side].size():
			var m: Medallion = _meds[side][k]
			var idx: int = int(runner.vm["actives"][side][k]) if k < runner.vm["actives"][side].size() else -1
			if idx < 0 or idx >= team.size():
				m.set_battler({})
				m.modulate.a = 0.0
				continue
			m.set_battler(team[idx])
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
	_draw_weather(w, h)
	# centre line + circle, stadium style
	var mid := Vector2(w * 0.51, h * 0.52)
	draw_ellipse_outline(mid, w * 0.10, h * 0.055, Color("2e355077"), 1.5)
	draw_line(Vector2(w * 0.40, h * 0.80), Vector2(w * 0.62, h * 0.24), Color("2e355055"), 1.5)
	# platforms (one per active slot; doubles gets a pair per side)
	var slots_n := _slots_n()
	for side in 2:
		var club: Dictionary = runner.club_for_side(side) if runner != null else {}
		var rim: Color = UI.club_color(club) if not club.is_empty() else Color("2e3550")
		for k in slots_n:
			var s := _slot_pos(side, k)
			var pr := ((w * 0.135) if side == 0 else (w * 0.115)) * (0.82 if slots_n > 1 else 1.0)
			var drop := (68.0 if side == 0 else 58.0) * (0.82 if slots_n > 1 else 1.0)
			var plat_c := s + Vector2(0, drop)
			draw_ellipse_fill(plat_c, pr, pr * 0.30, Color("11141d"))
			draw_ellipse_fill(plat_c + Vector2(0, -3), pr, pr * 0.30, Color("222840"))
			draw_ellipse_outline(plat_c + Vector2(0, -3), pr, pr * 0.30, rim * Color(1, 1, 1, 0.85), 2.0)
			# soft shadow under the medallion
			draw_ellipse_fill(plat_c + Vector2(0, -6), pr * 0.45, pr * 0.13, Color(0, 0, 0, 0.35))
			if runner != null and k == slots_n - 1:
				var font := get_theme_default_font()
				var tag := str(club.get("short", "?")) + (tr("  ·  YOU") if side == runner.player_side else "")
				var col := Color("f2f4fa") if side == runner.player_side else Color("8b91a8")
				draw_string(font, plat_c + Vector2(-pr, 22), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


## Ambient weather layer: atmosphere tint + animated particles + a labelled
## chip in the top-right corner. Reads the runner's view model, so it stays in
## step with the replayed event stream (and survives re-instancing mid-battle).
func _draw_weather(w: float, h: float) -> void:
	var wk := "" if runner == null else str(runner.vm.get("weather", ""))
	if wk == "":
		return
	var spec: Dictionary = {
		"sun": {"label": tr("HARSH SUNLIGHT"), "col": Color("f0a848")},
		"rain": {"label": tr("POURING RAIN"), "col": Color("58a8f0")},
		"sand": {"label": tr("SANDSTORM"), "col": Color("d8c078")},
		"hail": {"label": tr("HAIL"), "col": Color("98d8d8")},
	}.get(wk, {})
	if spec.is_empty():
		return
	var col: Color = spec["col"]
	draw_rect(Rect2(0, 0, w, h), Color(col.r, col.g, col.b, 0.05))
	match wk:
		"sun":
			for i in 5:
				var x0 := w * (0.1 + 0.2 * float(i)) + sin(_time * 0.4 + float(i)) * 18.0
				var pts := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 26, 0),
					Vector2(x0 + 96, h * 0.6), Vector2(x0 + 58, h * 0.6)])
				draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.05))
		"rain":
			for i in 46:
				var hx := absi(("r%d" % i).hash())
				var x := fmod(float(hx % 887) / 887.0 * w + _time * 30.0, w)
				var y := fmod(float((hx / 5) % 641) / 641.0 * h + _time * (300.0 + float(hx % 90)), h)
				draw_line(Vector2(x, y), Vector2(x - 5, y + 14), Color(col.r, col.g, col.b, 0.4), 1.5)
		"sand":
			for i in 36:
				var hx := absi(("s%d" % i).hash())
				var y := fmod(float(hx % 733) / 733.0 * h + sin(_time * 2.0 + float(i)) * 12.0, h)
				var x := fmod(float((hx / 3) % 911) / 911.0 * w + _time * (170.0 + float(hx % 120)), w)
				draw_line(Vector2(x, y), Vector2(x + 12, y + 2), Color(col.r, col.g, col.b, 0.35), 2.0)
		"hail":
			for i in 26:
				var hx := absi(("h%d" % i).hash())
				var x := fmod(float(hx % 887) / 887.0 * w + sin(_time * 1.6 + float(i)) * 20.0, w)
				var y := fmod(float((hx / 5) % 641) / 641.0 * h + _time * (120.0 + float(hx % 60)), h)
				draw_circle(Vector2(x, y), 2.4, Color(col.r, col.g, col.b, 0.5))
	# weather chip (top-right)
	var font := get_theme_default_font()
	var turns := 0 if runner == null else int(runner.vm.get("weather_turns", 0))
	var txt: String = str(spec["label"]) + ((" · %d" % turns) if turns > 0 else "")
	var tsz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var pad := Vector2(8, 5)
	var box := Rect2(Vector2(w - tsz.x - pad.x * 2 - 10, 10), tsz + pad * 2)
	draw_rect(box, Color("11141dcc"))
	draw_rect(box, Color(col.r, col.g, col.b, 0.8), false, 1.0)
	draw_string(font, box.position + Vector2(pad.x, pad.y + tsz.y * 0.72), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


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
			if runner.doubles_now():
				_set_caption(tr("BATTLE %d OF 3 — 2v2 DOUBLES") % runner.battle_no,
					Color("9a8dff"), tr("two actives per side · pick your targets"))
			else:
				_set_caption(tr("BATTLE %d OF 3") % runner.battle_no, Color("9a8dff"), "")
		"switch":
			_anim_switch(e)
		"move_used":
			_anim_move(e)
		"damage":
			_anim_damage(e)
		"miss":
			_anim_miss(e)
		"faint":
			_anim_faint(e)
		"heal":
			_anim_heal(e)
		"status_applied":
			_anim_status(e)
		"stat_change":
			_anim_stat(e)
		"no_target":
			_float_med(_med_from_event(e), tr("NO TARGET"), Color("8b91a8"), 13)
		"flinch":
			_float_med(_med_from_event(e), tr("FLINCHED"), Color("e0b050"), 13)
		"confused_hit":
			_float_med(_med_from_event(e), tr("HIT ITSELF"), Color("e0b050"), 13)
		"paralyzed":
			_float_med(_med_from_event(e), tr("FULLY PARALYSED"), Color("f8d030"), 12)
		"asleep":
			_float_med(_med_from_event(e), tr("FROZEN") if e.get("frozen", false) else tr("ASLEEP"),
				Color("98d8d8") if e.get("frozen", false) else Color("8b91a8"), 12)
		"item_used":
			_anim_item(e)
		"weather_start":
			_anim_weather_start(e)
		"weather_end":
			_set_caption(tr("THE SKIES CLEAR"), Color("8b91a8"), "")
		"weather_chip":
			var wcol := Color("d8c078") if str(e.get("kind", "")) == "sand" else Color("98d8d8")
			_float_med(_med_from_event(e), "-%d %s" % [int(e.get("amount", 0)),
				tr("SAND") if str(e.get("kind", "")) == "sand" else tr("HAIL")], wcol, 12)
		"ability_triggered":
			_anim_ability(e)
		"held_item":
			_float_med(_med_from_event(e), "• " + tr(str(e.get("item_name", ""))), Color("e0b050"), 12, -26.0)
		"battle_end":
			var s: Array = runner.shorts()
			_set_caption(tr("BATTLE %d — %s TAKE IT") % [runner.battle_no, s[int(e["winner"])]],
				Color("57c979") if int(e["winner"]) == runner.player_side else Color("e06060"), "")


func _anim_switch(e: Dictionary) -> void:
	var side := int(e.get("side", 0))
	var slot := int(e.get("slot", 0))
	var m: Medallion = _med(side, slot)
	if m == null:
		return
	# Big caption so a tactical switch never reads as a faint (user report
	# 2026-09-05). Battle-start send-outs keep the battle caption instead.
	if not bool(e.get("first", false)):
		var shorts: Array = runner.shorts()
		var club := str(shorts[side]) if side < shorts.size() else ""
		if bool(e.get("forced", false)):
			_set_caption(tr("%s SEND OUT %s") % [club.to_upper(), str(e.get("to", "?"))],
				Color("4dc3e6"), tr("replacing the fallen %s") % str(e.get("from", "?")))
		else:
			_set_caption(tr("SWITCH — %s") % club.to_upper(), Color("4dc3e6"),
				tr("%s is recalled · %s steps in") % [str(e.get("from", "?")), str(e.get("to", "?"))])
	var out_dir := -1.0 if side == 0 else 1.0
	var tw := create_tween()
	tw.tween_property(m, "anim_offset", Vector2(out_dir * 240.0, 10.0), 0.22)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(m, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		var team: Array = runner.vm["teams"][side]
		var actives: Array = runner.vm["actives"][side]
		var idx: int = int(actives[slot]) if slot < actives.size() else int(runner.vm["active"][side])
		if idx >= 0 and idx < team.size():
			m.set_battler(team[idx]))
	tw.tween_property(m, "anim_offset", Vector2.ZERO, 0.3)\
		.from(Vector2(out_dir * 240.0, -6.0)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "modulate:a", 1.0, 0.25)


## Where an attack from `side` should aim: the chosen target's medallion, or
## the midpoint of the standing foes for spread moves.
func _aim_point(e: Dictionary, side: int) -> Vector2:
	if e.has("target_slot"):
		var tm := _med(1 - side, int(e["target_slot"]))
		if tm != null:
			return tm.center() - global_position
	var pts: Array = []
	for k in _meds[1 - side].size():
		var m: Medallion = _meds[1 - side][k]
		if m != null and not m.battler.is_empty() and not bool(m.battler.get("fainted", false)):
			pts.append(m.center() - global_position)
	if pts.is_empty():
		var f := _med(1 - side, 0)
		return (f.center() - global_position) if f != null else size * 0.5
	var acc := Vector2.ZERO
	for p in pts:
		acc += p
	return acc / float(pts.size())


func _anim_move(e: Dictionary) -> void:
	var side := int(e.get("side", 0))
	var mname := str(e.get("move", ""))
	var mv: Dictionary = DataStore.move(mname)
	var mtype := str(mv.get("type", "normal"))
	var mcol: Color = DataStore.type_color(mtype)
	var cat := str(mv.get("category", "phys"))
	var sub := "%s · %s" % [I18n.type_name(mtype).to_upper(), tr(cat.to_upper())]
	if e.has("target"):
		sub += tr(" · at %s") % str(e["target"])
	elif bool(e.get("spread", false)):
		sub += tr(" · SPREAD")
	_set_caption("%s — %s" % [str(e.get("pokemon", "?")), tr(mname)], mcol, sub)
	var me: Medallion = _med_from_event(e)
	if me == null:
		return
	var aim := _aim_point(e, side)
	var to_foe := aim - (me.center() - global_position)
	match cat:
		"phys":
			var tw := create_tween()
			tw.tween_property(me, "anim_offset", to_foe * 0.42, 0.16)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.tween_property(me, "anim_offset", Vector2.ZERO, 0.24)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_burst(aim, mcol, 7, 26.0, 0.12)
		"spec":
			_projectile(me.center() - global_position, aim, mcol, 8)
			var tw2 := create_tween()
			tw2.tween_property(me, "anim_offset", to_foe.normalized() * 14.0, 0.1)
			tw2.tween_property(me, "anim_offset", Vector2.ZERO, 0.16)
		_:
			_ring(me.center() - global_position, mcol)
			_burst(me.center() - global_position, mcol, 6, 34.0, 0.0, true)


func _anim_damage(e: Dictionary) -> void:
	var m: Medallion = _med_from_event(e)
	if m == null:
		return
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
	var txt := ("-%d" % amount) if not crit else (tr("CRIT -%d") % amount)
	var col := Color("f2f4fa")
	if crit:
		col = Color("e0b050")
	elif recoil:
		col = Color("a884d8")
	var fsize := 15 + int(clampf(float(amount) / maxf(float(e.get("max_hp", 1)), 1.0) * 26.0, 0.0, 13.0))
	_float_text(pos, txt, col, fsize + (4 if crit else 0))
	if not recoil:
		if eff >= 2.0:
			_float_text(pos + Vector2(0, 20), tr("SUPER EFFECTIVE!"), Color("e0b050"), 11)
		elif eff == 0.0:
			_float_text(pos + Vector2(0, 20), tr("IMMUNE"), Color("6a7188"), 11)
		elif eff < 1.0:
			_float_text(pos + Vector2(0, 20), tr("resisted"), Color("6a7188"), 10)


func _anim_miss(e: Dictionary) -> void:
	## event side = the attacker; the targeted defender sidesteps out of the way.
	var side := int(e.get("side", 0))
	var d: Medallion = _med(1 - side, int(e.get("target_slot", 0)))
	if d == null:
		return
	var tw := create_tween()
	tw.tween_property(d, "anim_offset", Vector2(22.0 * (1.0 if 1 - side == 1 else -1.0), -6), 0.12)
	tw.tween_property(d, "anim_offset", Vector2.ZERO, 0.18)
	_float_med(d, tr("MISS"), Color("8b91a8"), 13)


func _anim_faint(e: Dictionary) -> void:
	var m: Medallion = _med_from_event(e)
	if m == null:
		return
	var tw := create_tween()
	tw.tween_property(m, "anim_offset", Vector2(0, 54.0), 0.5)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "modulate:a", 0.35, 0.5)
	_float_med(m, tr("FAINTED"), Color("e06060"), 16)
	_burst(m.center() - global_position, Color("6a7188"), 8, 40.0, 0.0, true)


func _anim_heal(e: Dictionary) -> void:
	var m: Medallion = _med_from_event(e)
	if m == null:
		return
	if bool(e.get("revived", false)):
		m.modulate.a = 1.0
		m.anim_offset = Vector2(0, 40)
		var tw := create_tween()
		tw.tween_property(m, "anim_offset", Vector2.ZERO, 0.4)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_float_med(m, tr("REVIVED!"), Color("57c979"), 15)
	else:
		_float_med(m, "+%d" % int(e.get("amount", 0)), Color("57c979"), 15)
	# rising sparkles
	var base := m.center() - global_position
	for i in 5:
		_spark(base + Vector2(randf_range(-30, 30), randf_range(-6, 16)),
			Color("57c979"), Vector2(0, -randf_range(26, 48)), 0.55)


func _anim_status(e: Dictionary) -> void:
	var st := str(e.get("status", ""))
	var labels := {"burn": tr("BURNED!"), "para": tr("PARALYSED!"), "sleep": tr("ASLEEP!"),
		"poison": tr("POISONED!"), "freeze": tr("FROZEN!"), "confused": tr("CONFUSED!"),
		"cured": tr("CURED!"), "woke": tr("WOKE UP"), "thawed": tr("THAWED")}
	var col: Color = UI.STATUS_COLORS.get(st, Color("57c979") if st in ["cured", "woke", "thawed"] else Color("e0b050"))
	var m: Medallion = _med_from_event(e)
	if m == null:
		return
	_float_med(m, str(labels.get(st, st.to_upper())), col, 14)
	_ring(m.center() - global_position, col)


func _anim_stat(e: Dictionary) -> void:
	var d := int(e.get("delta", 0))
	var names := {"atk": "ATK", "def": "DEF", "spa": "SPA", "spd": "SPD",
		"spe": "SPE", "acc": "ACC", "eva": "EVA"}
	var arrow := "+".repeat(mini(absi(d), 2)) if d > 0 else "−".repeat(mini(absi(d), 2))
	_float_med(_med_from_event(e), "%s %s" % [arrow, tr(str(names.get(str(e["stat"]), str(e["stat"]).to_upper())))],
		Color("57c979") if d > 0 else Color("e06060"), 13)


func _anim_weather_start(e: Dictionary) -> void:
	var kind := str(e.get("kind", ""))
	var caps := {"sun": [tr("THE SUNLIGHT TURNS HARSH"), Color("f0a848")],
		"rain": [tr("RAIN POUNDS THE ARENA"), Color("58a8f0")],
		"sand": [tr("A SANDSTORM KICKS UP"), Color("d8c078")],
		"hail": [tr("HAIL PELTS DOWN"), Color("98d8d8")]}
	var spec: Array = caps.get(kind, [tr("THE WEATHER SHIFTS"), Color("8b91a8")])
	var src := str(e.get("pokemon", ""))
	var sub := ""
	if src != "":
		sub = (tr("%s's ability set it off") if str(e.get("source", "")) == "ability" else tr("summoned by %s")) % src
	_set_caption(spec[0], spec[1], sub)
	# sweep a burst of weather-coloured particles across the sky band
	for i in 7:
		_spark(Vector2(size.x * (0.1 + 0.12 * float(i)), size.y * randf_range(0.08, 0.2)),
			spec[1], Vector2(randf_range(-16, 16), randf_range(18, 44)), 0.7)


func _anim_ability(e: Dictionary) -> void:
	var m: Medallion = _med_from_event(e)
	if m == null:
		return
	var ab := tr(str(e.get("ability_name", e.get("ability", "?")))).to_upper()
	var effect := str(e.get("effect", ""))
	if effect in ["no_recoil"]:
		return  # silent QoL trigger — a floater every hit would be noise
	var col := Color("9a8dff")
	if effect in ["immune", "absorb", "sturdy"]:
		col = Color("e0b050")
	_float_med(m, "• " + ab, col, 12, -30.0)
	_ring(m.center() - global_position, col)
	if effect in ["entry_stat", "weather", "sturdy", "immune", "absorb"]:
		var subs := {"entry_stat": tr("takes the field"), "weather": tr("changes the weather"),
			"sturdy": tr("hangs on at 1 HP"), "immune": tr("no effect"), "absorb": tr("soaks the attack up")}
		_set_caption("%s — %s" % [str(e.get("pokemon", "?")), tr(str(e.get("ability_name", "?")))],
			col, str(subs.get(effect, "")))


func _anim_item(e: Dictionary) -> void:
	var side := int(e["side"])
	var iname := tr(str(e.get("item_name", "Item")))
	_set_caption(tr("ITEM — %s") % iname, Color("9a8dff"), tr("used on %s · costs the turn") % str(e.get("pokemon", "?")))
	var actives: Array = runner.vm["actives"][side]
	var t_idx := int(e.get("target_index", -1))
	var target_slot := actives.find(t_idx)
	var corner := Vector2(size.x * (0.12 if side == 0 else 0.88), size.y * 0.82)
	_float_text(corner, "• %s" % iname, Color("9a8dff"), 14)
	var m: Medallion = _med(side, target_slot) if target_slot >= 0 else null
	if m != null:
		_projectile(corner, m.center() - global_position, Color("9a8dff"), 5)
		_ring(m.center() - global_position, Color("9a8dff"))
	else:
		_float_text(corner + Vector2(0, 18), tr("» %s (bench)") % str(e.get("pokemon", "?")), Color("8b91a8"), 11)


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


func _float_med(m: Medallion, text: String, col: Color, fsize: int, dy := -40.0) -> void:
	if m == null:
		return
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
