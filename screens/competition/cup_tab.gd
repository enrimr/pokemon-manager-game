extends VBoxContainer
## INDIGO CUP tab — knockout bracket rendered as a real tree with connectors.
## Later rounds are draws of the previous round's winners, so earlier-round ties
## are re-ordered on screen to sit next to the tie their winner feeds into.

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")

const TIE_W := 208.0
const TIE_H := 48.0
const COL_GAP := 40.0

var _bracket: Control
var _links: Array = []       # [{from: Rect2 idx.., to: ..}] as point pairs
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	var title := UI.label("INDIGO CUP", 16, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_status = UI.dim("", 12)
	head.add_child(_status)
	add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_bracket = Control.new()
	_bracket.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bracket.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bracket.draw.connect(_draw_links)
	scroll.add_child(_bracket)


func refresh() -> void:
	for c in _bracket.get_children():
		c.queue_free()
	_links.clear()

	var cup: Array = GameState.fixtures.filter(func(f): return f["comp"] == "cup")
	if cup.is_empty():
		_status.text = "Cup draw not yet made"
		return

	# rounds drawn so far
	var by_round := {}
	var max_round := 0
	for f in cup:
		var r := int(f["round"])
		max_round = maxi(max_round, r)
		if not by_round.has(r):
			by_round[r] = []
		by_round[r].append(f)
	var first_count: int = (by_round[1] as Array).size()      # 8 ties for 16 clubs
	var total_rounds := 1
	var n := first_count
	while n > 1:
		n = n / 2
		total_rounds += 1

	# display ordering: walk backwards so feeders sit beside their next tie
	var ordered := {}
	ordered[max_round] = by_round[max_round]
	for r in range(max_round, 1, -1):
		var prev: Array = by_round[r - 1]
		var new_order: Array = []
		for tie in ordered[r]:
			for cid in [tie["home"], tie["away"]]:
				for pt in prev:
					if Season.fixture_winner(pt) == cid and not new_order.has(pt):
						new_order.append(pt)
		for pt in prev:
			if not new_order.has(pt):
				new_order.append(pt)
		ordered[r - 1] = new_order

	var area_h := maxf(size.y - 60.0, first_count * (TIE_H + 22.0))
	_bracket.custom_minimum_size = Vector2(
		(total_rounds + 1) * (TIE_W + COL_GAP), area_h + 30.0)

	var centers := {}    # "r|i" -> Vector2 right-edge anchor of tie panel
	for r in range(1, total_rounds + 1):
		var x := (r - 1) * (TIE_W + COL_GAP)
		var ties_in_round := first_count / int(pow(2, r - 1))
		var drawn: Array = ordered.get(r, [])

		# round header
		var head := UI.dim("%s · %s" % [Season.cup_round_name(r).to_upper(),
			UI.short_date(Season.cup_round_date(GameState.season_start, r))], 11)
		head.position = Vector2(x, 0)
		_bracket.add_child(head)

		for i in ties_in_round:
			var slot_h := area_h / float(ties_in_round)
			var cy: float
			if r == 1 or drawn.is_empty():
				cy = 24.0 + slot_h * i + slot_h / 2.0
			else:
				# midpoint of the two feeder ties
				var a: Vector2 = centers.get("%d|%d" % [r - 1, i * 2], Vector2(x, 24.0 + slot_h * i + slot_h / 2.0))
				var b: Vector2 = centers.get("%d|%d" % [r - 1, i * 2 + 1], a)
				cy = (a.y + b.y) / 2.0
			var f: Dictionary = drawn[i] if i < drawn.size() else {}
			var panel := _tie_panel(f, r)
			panel.position = Vector2(x, cy - TIE_H / 2.0)
			_bracket.add_child(panel)
			centers["%d|%d" % [r, i]] = Vector2(x + TIE_W, cy)
			if r > 1:
				for k in 2:
					var from: Vector2 = centers.get("%d|%d" % [r - 1, i * 2 + k], Vector2.ZERO)
					if from != Vector2.ZERO:
						_links.append([from, Vector2(x, cy)])

	# champion column
	var final_f: Dictionary = (ordered.get(total_rounds, [{}]) as Array)[0] if ordered.has(total_rounds) else {}
	var champ_x := total_rounds * (TIE_W + COL_GAP)
	var champ_head := UI.dim("CHAMPION", 11)
	champ_head.position = Vector2(champ_x, 0)
	_bracket.add_child(champ_head)
	var final_c: Vector2 = centers.get("%d|0" % total_rounds, Vector2(champ_x - COL_GAP, area_h / 2.0 + 24.0))
	var champ := _champion_panel(final_f)
	champ.position = Vector2(champ_x, final_c.y - TIE_H / 2.0)
	_bracket.add_child(champ)
	_links.append([final_c, Vector2(champ_x, final_c.y)])
	_bracket.queue_redraw()

	# status line
	var current: Array = by_round.get(max_round, [])
	var all_played: bool = not current.any(func(f): return not f["played"])
	if max_round == total_rounds and all_played:
		var champ_club := GameState.club(Season.fixture_winner(current[0]))
		_status.text = "%s are the Indigo Cup champions" % champ_club.get("name", "?")
	else:
		_status.text = "%s · %s" % [Season.cup_round_name(max_round),
			"completed - next draw pending" if all_played else
			"ties on %s" % Season.pretty_date(current[0]["date"])]


func _draw_links() -> void:
	for link in _links:
		var a: Vector2 = link[0]
		var b: Vector2 = link[1]
		var mid_x := (a.x + b.x) / 2.0
		var col := Color(TB.COL_BORDER, 0.9)
		_bracket.draw_line(a, Vector2(mid_x, a.y), col, 1.4)
		_bracket.draw_line(Vector2(mid_x, a.y), Vector2(mid_x, b.y), col, 1.4)
		_bracket.draw_line(Vector2(mid_x, b.y), b, col, 1.4)


func _tie_panel(f: Dictionary, round_no: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(TIE_W, TIE_H)
	p.size = Vector2(TIE_W, TIE_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	p.add_child(v)

	if f.is_empty():
		sb.bg_color = Color(TB.COL_PANEL, 0.45)
		sb.border_color = Color(TB.COL_BORDER, 0.55)
		p.add_theme_stylebox_override("panel", sb)
		var l := UI.dim("Winners of %s" % Season.cup_round_name(round_no - 1), 11)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(l)
		return p

	var winner := Season.fixture_winner(f)
	var involves_player: bool = GameState.is_player_club(f["home"]) or GameState.is_player_club(f["away"])
	if involves_player:
		sb.border_color = TB.COL_ACCENT_DIM
		sb.border_width_left = 3
	p.add_theme_stylebox_override("panel", sb)

	for side in 2:
		var cid: String = f["home"] if side == 0 else f["away"]
		var club: Dictionary = GameState.club(cid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var mono := UI.monogram(club, 16, 8)
		row.add_child(mono)
		var col := TB.COL_TEXT
		if GameState.is_player_club(cid):
			col = TB.COL_ACCENT.lightened(0.35)
		elif winner != "" and cid == winner:
			col = Color.WHITE
		elif winner != "":
			col = TB.COL_TEXT_DIM
		var name := UI.link(str(club.get("name", cid)), 12, col,
			{"kind": "club", "id": cid}, "%s — view club profile" % club.get("name", cid))
		name.clip_text = true   # fixed-width tie panel; don't stretch it
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		if f["played"]:
			var s: int = int(f["score_home"]) if side == 0 else int(f["score_away"])
			var sc := UI.link(str(s), 12,
				Color.WHITE if cid == winner else TB.COL_TEXT_DIM,
				{"kind": "fixture", "id": str(f["id"])}, "Go to match report")
			row.add_child(sc)
		else:
			var sc := UI.link("-", 12, TB.COL_TEXT_DIM,
				{"kind": "fixture", "id": str(f["id"])}, "Go to fixture preview")
			row.add_child(sc)
		v.add_child(row)
	return p


func _champion_panel(final_f: Dictionary) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(TIE_W, TIE_H)
	var sb := StyleBoxFlat.new()
	var gold := Color(0.83, 0.68, 0.21)
	var winner := Season.fixture_winner(final_f) if not final_f.is_empty() else ""
	sb.bg_color = Color(gold.r, gold.g, gold.b, 0.10) if winner != "" else Color(TB.COL_PANEL, 0.45)
	sb.border_color = gold if winner != "" else Color(TB.COL_BORDER, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	if winner == "":
		var l := UI.dim("To be decided", 12)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
	else:
		var club := GameState.club(winner)
		var m := UI.monogram(club, 26, 11)
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(m)
		var l := UI.club_link(club, 13, gold.lightened(0.3))
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
	return p
