extends Control
## Pre-match: opponent scout report, both lineups, expected difficulty,
## confirm/adjust the starting six (order matters — slot 1 leads).

signal start_live(manual: bool)
signal instant_result

const UI := preload("res://screens/match/ui_bits.gd")

var runner  # MatchRunner

var _six_list: ItemList
var _res_list: ItemList
var _diff_label: Label
var _diff_blocks: HBoxContainer
var _reserves: Array = []


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
	cols.add_child(_build_lineup_panel())
	cols.add_child(_build_scout_panel())
	cols.add_child(_build_their_panel())

	root.add_child(_build_footer())
	_refresh_lists()
	_refresh_difficulty()


# ------------------------------------------------------------------ header

func _build_header() -> Control:
	var pair: Array = UI.panel("", true)
	var row := UI.hbox(14)
	pair[1].add_child(row)
	var f: Dictionary = runner.fixture
	var comp_txt: String = (tr("League · Round %d") % int(f["round"])) if f["comp"] == "league" \
		else tr("Cup · %s") % I18n.cup_round(int(f["round"]))
	row.add_child(UI.club_crest(runner.home_club, 40))
	var mid := UI.vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UI.wrap_label(tr("%s  vs  %s") % [runner.home_club["name"], runner.away_club["name"]], 21, Color.WHITE)
	mid.add_child(title)
	mid.add_child(UI.wrap_label(tr("MATCH DAY  ·  %s  ·  %s  ·  best of 3 six-a-side battles  ·  %s") % [
		comp_txt, I18n.pretty_date(str(f["date"])),
		tr("home advantage: none — this is about the six you send out") if runner.player_side == 0 else tr("away day")],
		12, UI.COL_DIM))
	if f["comp"] == "cup":
		mid.add_child(UI.wrap_label(tr("CUP FORMAT — game 2 is played 2v2 DOUBLES: two actives per side, ")
			+ tr("spread moves, targeting calls. Order your six with a doubles pair in mind."),
			12, UI.COL_WARN))
	row.add_child(mid)
	row.add_child(UI.spacer_h())
	row.add_child(UI.club_crest(runner.away_club, 40))
	return pair[0]


# ------------------------------------------------------------------ our lineup

func _build_lineup_panel() -> Control:
	var pair: Array = UI.panel(tr("Your starting six  ·  slot 1 leads off"))
	var p: PanelContainer = pair[0]
	var box: VBoxContainer = pair[1]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.25

	_six_list = ItemList.new()
	_six_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_six_list.custom_minimum_size = Vector2(0, 190)
	_six_list.add_theme_font_size_override("font_size", 13)
	box.add_child(_six_list)

	var btns := UI.hbox(6)
	box.add_child(btns)
	for spec in [[tr("Up"), _move_up, "tri_up"], [tr("Down"), _move_down, "tri_down"],
			[tr("Swap with reserve"), _swap, "swap"], [tr("Reset best six"), _reset, ""]]:
		var b := Button.new()
		b.text = spec[0]
		if str(spec[2]) != "":
			b.icon = GlyphIcons.tex(str(spec[2]), 10, ThemeBuilder.COL_TEXT)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(spec[1])
		btns.add_child(b)

	box.add_child(UI.label("RESERVES", 10, UI.COL_DIM))
	_res_list = ItemList.new()
	_res_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_res_list.custom_minimum_size = Vector2(0, 120)
	_res_list.add_theme_font_size_override("font_size", 13)
	box.add_child(_res_list)

	box.add_child(UI.label(tr("MATCH BAG — usable mid-battle (an item spends the turn)"), 10, UI.COL_DIM))
	var bag: Dictionary = runner.usable_only(GameState.player_inventory())
	if bag.is_empty():
		box.add_child(UI.label(tr("Bag is empty — visit the Items screen to stock up on potions and heals."),
			12, UI.COL_WARN))
	else:
		var bag_row := UI.hbox(6)
		for iid in bag:
			var it: Dictionary = DataStore.item(str(iid))
			var chip := UI.label("%s ×%d" % [tr(str(it.get("name", iid))), int(bag[iid])], 12, UI.COL_TEXT)
			chip.tooltip_text = tr(str(it.get("desc", "")))
			chip.mouse_filter = Control.MOUSE_FILTER_STOP
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("222840")
			sb.border_color = UI.COL_BORDER
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(3)
			sb.content_margin_left = 7
			sb.content_margin_right = 7
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			chip.add_theme_stylebox_override("normal", sb)
			bag_row.add_child(chip)
		box.add_child(bag_row)
	return p


func _inst_row(inst: Dictionary, slot: int = -1) -> String:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var types: String = I18n.types_join(sp.get("types", []))
	var prefix := ("%d.  " % (slot + 1)) if slot >= 0 else ""
	var nick: String = inst.get("nickname") if inst.get("nickname") else str(inst.get("species", sp.get("name", "?")))
	var held := str(inst.get("held_item", "") if inst.get("held_item") != null else "")
	return tr("%s%-14s Lv%-3d %-16s cond %d%%  fit %d%%  mor %d%%  %s") % [
		prefix, nick, int(inst["level"]), types,
		int(inst.get("condition", 100)), int(inst.get("fitness", 100)), int(inst.get("morale", 70)),
		("• " + I18n.item_name(held)) if held != "" else "—"]


func _refresh_lists() -> void:
	_six_list.clear()
	for i in runner.starting_six.size():
		_six_list.add_item(_inst_row(runner.starting_six[i], i))
	var six_uids: Array = runner.starting_six.map(func(x): return x.get("uid", ""))
	_reserves = runner.player_club()["squad"].filter(func(x): return not six_uids.has(x.get("uid", "")))
	_res_list.clear()
	for inst in _reserves:
		_res_list.add_item(_inst_row(inst))
	_refresh_difficulty()


func _sel(list: ItemList) -> int:
	var s := list.get_selected_items()
	return s[0] if s.size() > 0 else -1


func _move_up() -> void:
	var i := _sel(_six_list)
	if i > 0:
		var tmp = runner.starting_six[i - 1]
		runner.starting_six[i - 1] = runner.starting_six[i]
		runner.starting_six[i] = tmp
		_refresh_lists()
		_six_list.select(i - 1)


func _move_down() -> void:
	var i := _sel(_six_list)
	if i >= 0 and i < runner.starting_six.size() - 1:
		var tmp = runner.starting_six[i + 1]
		runner.starting_six[i + 1] = runner.starting_six[i]
		runner.starting_six[i] = tmp
		_refresh_lists()
		_six_list.select(i + 1)


func _swap() -> void:
	var i := _sel(_six_list)
	var j := _sel(_res_list)
	if i < 0 or j < 0 or j >= _reserves.size():
		return
	runner.starting_six[i] = _reserves[j]
	_refresh_lists()
	_six_list.select(i)


func _reset() -> void:
	runner.starting_six = runner.default_six(runner.player_club())
	_refresh_lists()


# ------------------------------------------------------------------ scout report

func _build_scout_panel() -> Control:
	var opp: Dictionary = runner.opponent_club()
	var pair: Array = UI.panel(tr("Scout report · %s") % opp["name"])
	var p: PanelContainer = pair[0]
	var box: VBoxContainer = pair[1]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0

	var pos := 0
	var pts := 0
	var table: Array = GameState.league_table()
	for i in table.size():
		if table[i]["club_id"] == opp["id"]:
			pos = i + 1
			pts = int(table[i]["points"])
	box.add_child(UI.label(tr("Manager: %s") % opp.get("manager", "?"), 13))
	box.add_child(UI.label(tr("Reputation: %d / 20") % int(opp.get("reputation", 10)), 13))
	box.add_child(UI.label(tr("League: %s · %d pts") % [_ordinal(pos), pts], 13))

	var form_row := UI.hbox(4)
	form_row.add_child(UI.label("Form:", 13, UI.COL_DIM))
	var form := _recent_form(opp["id"], 5)
	if form.is_empty():
		form_row.add_child(UI.label(tr("no matches yet"), 13, UI.COL_DIM))
	for w in form:
		form_row.add_child(UI.result_chip(w))
	box.add_child(form_row)
	box.add_child(HSeparator.new())

	box.add_child(UI.label(tr("EXPECTED DIFFICULTY"), 10, UI.COL_DIM))
	_diff_blocks = UI.hbox(3)
	box.add_child(_diff_blocks)
	_diff_label = UI.label("", 14, Color.WHITE)
	box.add_child(_diff_label)
	box.add_child(HSeparator.new())

	box.add_child(UI.label(tr("KEY THREATS"), 10, UI.COL_DIM))
	for threat in _threats():
		var trow := UI.hbox(6)
		trow.add_child(UI.label(tr("%s  Lv%d") % [threat["name"], threat["level"]], 13, Color.WHITE))
		for t in threat["types"]:
			trow.add_child(UI.type_badge(str(t), 10))
		box.add_child(trow)
		box.add_child(UI.label("    " + threat["note"], 12, UI.COL_DIM))
	box.add_child(UI.spacer_v())
	return p


func _recent_form(club_id: String, n: int) -> Array:
	var played: Array = GameState.fixtures.filter(func(f):
		return f["played"] and (f["home"] == club_id or f["away"] == club_id))
	var out: Array = []
	for f in played.slice(maxi(0, played.size() - n)):
		var home: bool = f["home"] == club_id
		var us: int = f["score_home"] if home else f["score_away"]
		var them: int = f["score_away"] if home else f["score_home"]
		out.append(us > them)
	return out


func _threats() -> Array:
	var our_types: Array = []
	for inst in runner.starting_six:
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		our_types.append(sp.get("types", []))
	var scored: Array = []
	for b in runner.opp_six:
		var worst := 0.0
		var worst_move := ""
		for m in b["moves"]:
			var mv: Dictionary = DataStore.move(str(m))
			if mv.is_empty() or str(mv.get("category", "")) == "status":
				continue
			for dt in our_types:
				var eff: float = DataStore.effectiveness(str(mv["type"]), dt) * float(mv.get("power", 0))
				if eff > worst:
					worst = eff
					worst_move = str(m)
		scored.append({"name": b["name"], "level": int(b["level"]), "types": b["types"],
			"score": worst + float(b["level"]) * 2.0,
			"note": (tr("%s punishes your lineup") % I18n.move_name(worst_move)) if worst >= 160.0
				else (tr("watch out for %s") % I18n.move_name(worst_move)) if worst_move != "" else tr("no obvious edge")})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	return scored.slice(0, 3)


func _refresh_difficulty() -> void:
	if _diff_label == null:
		return
	var our_avg := 0.0
	for inst in runner.starting_six:
		our_avg += float(inst["level"])
	our_avg /= maxf(runner.starting_six.size(), 1.0)
	var their_avg := 0.0
	for b in runner.opp_six:
		their_avg += float(b["level"])
	their_avg /= maxf(runner.opp_six.size(), 1.0)
	var rep_d := float(runner.opponent_club().get("reputation", 10)) - float(runner.player_club().get("reputation", 10))
	var score := (their_avg - our_avg) * 0.8 + rep_d * 0.3
	var verdict: String
	var col: Color
	var blocks: int
	if score <= -3.0:
		verdict = tr("Strong favourites")
		col = UI.COL_GOOD
		blocks = 1
	elif score <= -1.0:
		verdict = tr("Favourites")
		col = UI.COL_GOOD
		blocks = 2
	elif score < 1.0:
		verdict = tr("Even contest")
		col = UI.COL_WARN
		blocks = 3
	elif score < 3.0:
		verdict = tr("Underdogs")
		col = UI.COL_BAD
		blocks = 4
	else:
		verdict = tr("Big underdogs")
		col = UI.COL_BAD
		blocks = 5
	_diff_label.text = tr("%s  ·  avg level %s vs %s") % [verdict, I18n.decimal(our_avg, 1), I18n.decimal(their_avg, 1)]
	_diff_label.add_theme_color_override("font_color", col)
	for c in _diff_blocks.get_children():
		c.queue_free()
	for i in 5:
		var blk := Panel.new()
		blk.custom_minimum_size = Vector2(34, 10)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col if i < blocks else Color("242a3d")
		sb.set_corner_radius_all(2)
		blk.add_theme_stylebox_override("panel", sb)
		_diff_blocks.add_child(blk)


# ------------------------------------------------------------------ their lineup

func _build_their_panel() -> Control:
	var pair: Array = UI.panel(tr("Their expected six"))
	var p: PanelContainer = pair[0]
	var box: VBoxContainer = pair[1]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0
	for i in runner.opp_six.size():
		var b: Dictionary = runner.opp_six[i]
		var row := UI.hbox(6)
		row.add_child(UI.label("%d." % (i + 1), 13, UI.COL_DIM))
		row.add_child(UI.label("%s" % b["name"], 14, Color.WHITE))
		row.add_child(UI.label(tr("Lv%d") % int(b["level"]), 12, UI.COL_DIM))
		row.add_child(UI.spacer_h())
		for t in b["types"]:
			row.add_child(UI.type_badge(str(t), 10))
		box.add_child(row)
		var hp := int(b["stats"]["hp"])
		box.add_child(UI.wrap_label(tr("     HP %d · Atk %d · Def %d · SpA %d · SpD %d · Spe %d") % [
			hp, int(b["stats"]["atk"]), int(b["stats"]["def"]), int(b["stats"]["spa"]),
			int(b["stats"]["spd"]), int(b["stats"]["spe"])], 11, UI.COL_DIM))
		var held := str(b.get("held_item", "") if b.get("held_item") != null else "")
		if held != "":
			var hl := UI.wrap_label(tr("     • holds %s") % I18n.item_name(held), 11, UI.COL_WARN)
			hl.tooltip_text = I18n.item_desc(held)
			hl.mouse_filter = Control.MOUSE_FILTER_STOP
			box.add_child(hl)
	box.add_child(UI.spacer_v())
	box.add_child(UI.wrap_label(tr("Six picked by level and condition — expect this exact\nlineup in every battle of the series."), 11, UI.COL_DIM))
	return p


# ------------------------------------------------------------------ footer

func _build_footer() -> Control:
	var pair: Array = UI.panel("", true)
	var row := UI.hbox(10)
	pair[1].add_child(row)
	row.add_child(UI.wrap_label(tr("Play it yourself — every move, switch and item is your call —\nor delegate: watch the coach run it, or take the instant result."), 12, UI.COL_DIM))
	var instant := Button.new()
	instant.text = tr("Instant result")
	instant.icon = GlyphIcons.tex("fast_forward", 12, ThemeBuilder.COL_TEXT)
	instant.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	instant.tooltip_text = tr("Simulate the whole tie and jump to the report.")
	instant.custom_minimum_size = Vector2(150, 38)
	instant.pressed.connect(func(): instant_result.emit())
	row.add_child(instant)
	var watch := Button.new()
	watch.text = tr("Watch — coach decides")
	watch.icon = GlyphIcons.tex("tri_right_hollow", 12, ThemeBuilder.COL_TEXT)
	watch.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	watch.tooltip_text = tr("Sit back on the touchline: the AI coach picks moves under your instructions.\nYou can still force switches, change instructions or take over at any time.")
	watch.custom_minimum_size = Vector2(200, 38)
	watch.pressed.connect(func(): start_live.emit(false))
	row.add_child(watch)
	var go := Button.new()
	go.text = tr("PLAY THE MATCH — you call every turn")
	go.icon = GlyphIcons.tex("tri_right", 12, Color.WHITE)
	go.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	go.tooltip_text = tr("Interactive battle: choose attacks, switches and bag items each turn.")
	go.custom_minimum_size = Vector2(310, 38)
	go.add_theme_color_override("font_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.COL_ACCENT * Color(1, 1, 1, 0.85)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	go.add_theme_stylebox_override("normal", sb)
	go.pressed.connect(func(): start_live.emit(true))
	row.add_child(go)
	return pair[0]


func _ordinal(n: int) -> String:
	if n <= 0:
		return "—"
	return I18n.ordinal(n)
