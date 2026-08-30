extends Control
## Post-match: result, per-Pokémon ratings, key-events timeline, series
## summary, full momentum chart, continue back to the game.

signal done

const UI := preload("res://screens/match/ui_bits.gd")
const MomentumGraph := preload("res://screens/match/momentum_graph.gd")

var runner  # MatchRunner


func setup(p_runner) -> void:
	runner = p_runner


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := UI.vbox(10)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_header())

	var cols := UI.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	cols.add_child(_build_ratings(runner.player_side, "Your ratings"))
	cols.add_child(_build_timeline())
	cols.add_child(_build_ratings(1 - runner.player_side, "%s ratings" % runner.opponent_club().get("short", "OPP")))

	root.add_child(_build_momentum())
	root.add_child(_build_footer())


func _build_header() -> Control:
	var pair: Array = UI.panel("", true)
	var row := UI.hbox(14)
	pair[1].add_child(row)
	row.add_child(UI.monogram(runner.home_club.get("short", "H"), UI.club_color(runner.home_club), 44))
	var mid := UI.vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var won: bool = runner.player_won()
	var big := UI.label("%s  %d – %d  %s" % [runner.home_club["name"], runner.wins[0],
		runner.wins[1], runner.away_club["name"]], 24, Color.WHITE)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(big)
	var f: Dictionary = runner.fixture
	var comp_txt: String = ("League Round %d" % int(f["round"])) if f["comp"] == "league" \
		else "Cup %s" % Season.cup_round_name(int(f["round"]))
	var verdict := UI.label("FULL TIME  ·  %s  ·  %s  ·  %s" % [comp_txt,
		Season.pretty_date(str(f["date"])), "VICTORY" if won else "DEFEAT"],
		13, UI.COL_GOOD if won else UI.COL_BAD)
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(verdict)
	# per-battle chips + MOTM
	var chips := UI.hbox(8)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in runner.battles.size():
		var b: Dictionary = runner.battles[i]
		var mine: bool = int(b["winner"]) == runner.player_side
		chips.add_child(UI.label("B%d" % (i + 1), 12, UI.COL_DIM))
		chips.add_child(UI.result_chip(mine))
		chips.add_child(UI.label("%s · %d turns" % [runner.shorts()[int(b["winner"])], int(b["turns"])],
			12, UI.COL_TEXT))
		if i < runner.battles.size() - 1:
			chips.add_child(UI.label("  ", 12))
	var motm: Dictionary = runner.man_of_the_match()
	if not motm.is_empty():
		chips.add_child(UI.label("    ★ Player of the match: %s (%.1f)" % [motm["name"], motm["rating"]],
			12, UI.COL_WARN))
	mid.add_child(chips)
	# items spent across the series (deducted from each club's store)
	var us_items: int = runner.items_spent(runner.player_side)
	var them_items: int = runner.items_spent(1 - runner.player_side)
	if us_items > 0 or them_items > 0:
		var parts: Array = []
		for iid in runner.used_items[runner.player_side]:
			parts.append("%dx %s" % [int(runner.used_items[runner.player_side][iid]),
				DataStore.item_name(str(iid))])
		var mine := ("none" if parts.is_empty() else ", ".join(parts))
		var il := UI.label("Bag: you used %s  ·  they used %d item%s  ·  stock updated" %
			[mine, them_items, "" if them_items == 1 else "s"], 12, UI.COL_DIM)
		il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(il)
	row.add_child(mid)
	row.add_child(UI.monogram(runner.away_club.get("short", "A"), UI.club_color(runner.away_club), 44))
	return pair[0]


func _build_ratings(side: int, title: String) -> Control:
	var pair: Array = UI.panel(title)
	var p: PanelContainer = pair[0]
	var box: VBoxContainer = pair[1]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)
	for h in ["POKÉMON", "LV", "DMG OUT", "DMG IN", "KO", "RATING"]:
		grid.add_child(UI.label(h, 10, UI.COL_DIM))
	for r in runner.rating_rows(side):
		grid.add_child(UI.label(str(r["name"]) + ("  ✝" if int(r["fainted"]) > 0 else ""), 13,
			Color.WHITE if int(r["fainted"]) == 0 else UI.COL_DIM))
		grid.add_child(UI.label(str(r["level"]), 12, UI.COL_DIM))
		grid.add_child(UI.label(str(r["dealt"]), 12, UI.COL_TEXT))
		grid.add_child(UI.label(str(r["taken"]), 12, UI.COL_TEXT))
		grid.add_child(UI.label(str(r["kos"]), 12, UI.COL_TEXT))
		var rating := float(r["rating"])
		var col := UI.COL_GOOD if rating >= 7.5 else (UI.COL_WARN if rating >= 6.5 else
			(UI.COL_TEXT if rating >= 6.0 else UI.COL_BAD))
		var rl := UI.label("%.1f" % rating, 13, Color("11141d"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		rl.add_theme_stylebox_override("normal", sb)
		grid.add_child(rl)
	box.add_child(UI.spacer_v())
	return p


func _build_timeline() -> Control:
	var pair: Array = UI.panel("Key moments")
	var p: PanelContainer = pair[0]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.3
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_constant_override("line_separation", 5)
	var last_battle := 0
	for k in runner.key_events:
		if int(k["battle"]) != last_battle:
			last_battle = int(k["battle"])
			rt.append_text("[color=#8b91a8]— BATTLE %d —[/color]\n" % last_battle)
		rt.append_text("[color=#3d4358]T%02d[/color]  %s\n" % [int(k["turn"]), str(k["text"])])
	if runner.key_events.is_empty():
		rt.append_text("[color=#8b91a8]A quiet affair — no defining moments.[/color]")
	pair[1].add_child(rt)
	return p


func _build_momentum() -> Control:
	var pair: Array = UI.panel("Momentum — full series")
	var g := MomentumGraph.new()
	g.custom_minimum_size = Vector2(0, 110)
	g.set_data(runner.momentum, runner.faint_marks, runner.shorts(), runner.player_side)
	pair[1].add_child(g)
	return pair[0]


func _build_footer() -> Control:
	var pair: Array = UI.panel("", true)
	var row := UI.hbox(10)
	pair[1].add_child(row)
	var us: int = runner.wins[runner.player_side]
	var them: int = runner.wins[1 - runner.player_side]
	row.add_child(UI.label("Result recorded — %d-%d vs %s. A full report is waiting in your inbox." %
		[us, them, runner.opponent_club()["name"]], 13, UI.COL_DIM))
	row.add_child(UI.spacer_h())
	var btn := Button.new()
	btn.text = "Continue  ▶"
	btn.custom_minimum_size = Vector2(180, 38)
	btn.add_theme_color_override("font_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.COL_ACCENT * Color(1, 1, 1, 0.85)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	btn.add_theme_stylebox_override("normal", sb)
	btn.pressed.connect(func(): done.emit())
	row.add_child(btn)
	return pair[0]
