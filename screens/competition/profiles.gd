extends VBoxContainer
## Entity profile pages for the competition screen's click-through navigation.
## Club profile (squad, season record, results, staff) and Pokémon profile
## (attributes, moves, season stats, match-by-match log) — every entity
## reference inside a profile is itself a live link, FM-style.

const UI := preload("res://screens/competition/ui.gd")
const TB := preload("res://shared/theme/theme_builder.gd")
const Charts := preload("res://screens/competition/charts.gd")

var _ctx: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func show_ctx(ctx: Dictionary) -> void:
	_ctx = ctx
	refresh()


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	match str(_ctx.get("kind", "")):
		"club":
			_build_club(str(_ctx.get("id", "")))
		"pokemon":
			_build_pokemon(str(_ctx.get("id", "")))


func title_text() -> String:
	match str(_ctx.get("kind", "")):
		"club":
			return str(GameState.club(str(_ctx.get("id", ""))).get("name", "Club"))
		"pokemon":
			var inst := UI.find_instance(str(_ctx.get("id", "")))
			return UI.display_name(inst) if not inst.is_empty() else "Pokémon"
	return ""


# ================================================================ CLUB PROFILE

func _build_club(cid: String) -> void:
	var club := GameState.club(cid)
	if club.is_empty():
		add_child(UI.dim("Unknown club.", 13))
		return
	var fixtures: Array = GameState.fixtures
	# position/record inside the club's OWN championship (clubs span 2 leagues)
	var table: Array = GameState.league_table(GameState.league_of(cid))
	var pos: int = Season.table_positions(table).get(cid, 0)
	var row := {}
	for r in table:
		if r["club_id"] == cid:
			row = r
			break

	add_child(_club_header(club, pos, row))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	cols.add_child(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	left.add_child(_squad_card(club))
	left.add_child(_staff_card(club))
	right.add_child(_club_season_card(club, pos, row, fixtures))
	right.add_child(_club_results_card(club, fixtures))


func _club_header(club: Dictionary, pos: int, row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	var ccol := UI.club_color(club)
	sb.border_color = ccol
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)

	var mono := UI.monogram(club, 44, 16)
	mono.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mono)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.add_child(UI.label(str(club["name"]), 20, Color.WHITE))
	var lg_id := GameState.league_of(str(club["id"]))
	var lg_link := UI.link(GameState.league_name(lg_id), 12,
		UI.league_color(lg_id).lightened(0.25), {"kind": "league", "id": lg_id},
		"Browse the %s" % GameState.league_name(lg_id))
	lg_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(lg_link)
	if GameState.is_player_club(str(club["id"])):
		var yours := UI.label("YOUR CLUB", 10, TB.COL_ACCENT.lightened(0.35))
		yours.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(yours)
	v.add_child(name_row)
	var cur: String = str(GameState.world["meta"].get("currency", "P$"))
	v.add_child(UI.dim("Manager %s  ·  Reputation %d/20  ·  Balance %s%s  ·  Wage budget %s%s/m" % [
		club["manager"], int(club["reputation"]), cur, _thousands(int(club["finances"]["balance"])),
		cur, _thousands(int(club["finances"]["wage_budget"]))], 12))
	h.add_child(v)

	for stat in [
		["POSITION", _ord(pos), TB.COL_TEXT],
		["RECORD", "%d-%d" % [int(row.get("won", 0)), int(row.get("lost", 0))], TB.COL_TEXT],
		["BATTLES", "%d-%d" % [int(row.get("bf", 0)), int(row.get("ba", 0))], TB.COL_TEXT],
		["POINTS", str(int(row.get("points", 0))), Color.WHITE],
	]:
		h.add_child(VSeparator.new())
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 0)
		var val := UI.label(str(stat[1]), 16, stat[2])
		sv.add_child(val)
		sv.add_child(UI.dim(str(stat[0]), 10))
		h.add_child(sv)
	var form := Season.club_form(str(club["id"]), GameState.fixtures, 5)
	if not form.is_empty():
		h.add_child(VSeparator.new())
		var fv := VBoxContainer.new()
		fv.add_theme_constant_override("separation", 2)
		fv.add_child(UI.form_pips(form, 15))
		fv.add_child(UI.dim("FORM", 10))
		h.add_child(fv)
	return panel


func _squad_card(club: Dictionary) -> PanelContainer:
	var card := UI.card("Squad · click a Pokémon for its profile")
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stats := Season.season_player_stats(GameState.fixtures)
	var tree := Tree.new()
	tree.hide_root = true
	tree.columns = 8
	tree.column_titles_visible = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 220
	var titles := ["Pokémon", "Lv", "Type", "Age", "Apps", "KOs", "Dmg", "Rat"]
	var widths := [0, 40, 116, 46, 48, 44, 56, 48]
	for i in tree.columns:
		tree.set_column_title(i, titles[i])
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT if i <= 2 else HORIZONTAL_ALIGNMENT_CENTER)
		if widths[i] > 0:
			tree.set_column_expand(i, false)
			tree.set_column_custom_minimum_width(i, widths[i])
	UI.wire_tree_links(tree)
	var root := tree.create_item()
	var squad: Array = club["squad"].duplicate()
	squad.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	for inst in squad:
		var uid: String = str(inst["uid"])
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		var item := root.create_child()
		item.set_text(0, UI.display_name(inst))
		item.set_custom_color(0, Color.WHITE)
		UI.cell_link(item, 0, {"kind": "pokemon", "id": uid},
			"%s — view Pokémon profile" % UI.display_name(inst))
		item.set_text(1, str(int(inst["level"])))
		var types: Array = sp.get("types", [])
		item.set_text(2, "/".join(PackedStringArray(types)))
		if not types.is_empty():
			item.set_custom_color(2, DataStore.type_color(str(types[0])).lightened(0.15))
		item.set_text(3, _age(int(inst.get("age_months", 0))))
		item.set_custom_color(3, TB.COL_TEXT_DIM)
		var s: Dictionary = stats.get(uid, {})
		if s.is_empty():
			item.set_text(4, "0")
			item.set_text(5, "-")
			item.set_text(6, "-")
			item.set_text(7, "-")
			item.set_custom_color(7, TB.COL_TEXT_DIM)
		else:
			var apps := int(s["battles"])
			item.set_text(4, str(apps))
			item.set_text(5, str(int(s["kos"])))
			item.set_text(6, str(int(s["dmg"])))
			var rat := float(s["rating_sum"]) / maxi(apps, 1)
			item.set_text(7, "%.2f" % rat)
			item.set_custom_color(7, _rating_color(rat))
		for c in [1, 3, 4, 5, 6, 7]:
			item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)
	UI.card_body(card).add_child(tree)
	return card


func _staff_card(club: Dictionary) -> PanelContainer:
	var card := UI.card("Staff")
	var body := UI.card_body(card)
	var staff: Array = club.get("staff", [])
	if staff.is_empty():
		body.add_child(UI.dim("No staff registered.", 12))
		return card
	for st in staff:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var role := UI.dim(str(st["role"]).capitalize(), 12)
		role.custom_minimum_size.x = 56
		h.add_child(role)
		var nm := UI.label(str(st["name"]), 13)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var r: Dictionary = st.get("ratings", {})
		var best_k := ""
		var best_v := -1
		for k in r:
			if int(r[k]) > best_v:
				best_v = int(r[k])
				best_k = k
		h.add_child(UI.dim("best: %s %d/20" % [str(best_k).capitalize(), best_v], 12))
		body.add_child(h)
	return card


func _club_season_card(club: Dictionary, pos: int, row: Dictionary, fixtures: Array) -> PanelContainer:
	var card := UI.card("Season")
	var body := UI.card_body(card)
	var cid: String = str(club["id"])
	var lg_id := GameState.league_of(cid)
	body.add_child(UI.kv_row("%s position" % GameState.league_name(lg_id), _ord(pos),
		TB.COL_ACCENT.lightened(0.35) if GameState.is_player_club(cid) else TB.COL_TEXT))
	body.add_child(UI.kv_row("Record (W-L)", "%d-%d" % [int(row.get("won", 0)), int(row.get("lost", 0))]))
	var diff := int(row.get("bf", 0)) - int(row.get("ba", 0))
	body.add_child(UI.kv_row("Battle diff", ("+%d" % diff) if diff > 0 else str(diff),
		UI.COL_WIN if diff > 0 else (UI.COL_LOSS if diff < 0 else TB.COL_TEXT)))
	body.add_child(UI.kv_row("Points", str(int(row.get("points", 0))), Color.WHITE))
	body.add_child(UI.kv_row("Cup", _cup_status(cid, fixtures)))
	# position-over-time sparkline within the club's own league
	var lg_ids: Array = GameState.league_club_ids(lg_id)
	var hist: Dictionary = Season.position_history(lg_ids,
		Season.league_fixtures(fixtures, lg_id))
	var vals: Array = hist.get(cid, [])
	if vals.size() >= 2:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var cap := UI.dim("Position trend", 12)
		cap.custom_minimum_size.x = 96
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(cap)
		var spark = Charts.Sparkline.new()
		spark.invert = true   # position: 1 at the top
		spark.v_min = 1.0
		spark.v_max = float(lg_ids.size())
		spark.color = UI.club_color(club)
		spark.custom_minimum_size = Vector2(0, 26)
		spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var labels: Array = []
		for i in vals.size():
			labels.append("After MD %d" % (i + 1))
		spark.set_data(vals, labels)
		h.add_child(spark)
		var trend := UI.dim("%s → %s" % [_ord(int(vals[0])), _ord(int(vals[vals.size() - 1]))], 11)
		trend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(trend)
		body.add_child(h)
	# top performers, cross-linked
	var stats := Season.season_player_stats(fixtures)
	var best_rat := {}
	var best_ko := {}
	for inst in club["squad"]:
		var s: Dictionary = stats.get(str(inst["uid"]), {})
		if s.is_empty():
			continue
		var rat := float(s["rating_sum"]) / maxi(int(s["battles"]), 1)
		if best_rat.is_empty() or rat > best_rat["v"]:
			best_rat = {"uid": str(inst["uid"]), "n": UI.display_name(inst), "v": rat}
		if best_ko.is_empty() or int(s["kos"]) > best_ko["v"]:
			best_ko = {"uid": str(inst["uid"]), "n": UI.display_name(inst), "v": int(s["kos"])}
	if not best_rat.is_empty():
		body.add_child(UI.kv_link_row("Best rated", "%s (%.2f)" % [best_rat["n"], best_rat["v"]],
			{"kind": "pokemon", "id": best_rat["uid"]}))
	if not best_ko.is_empty():
		body.add_child(UI.kv_link_row("Most KOs", "%s (%d)" % [best_ko["n"], best_ko["v"]],
			{"kind": "pokemon", "id": best_ko["uid"]}))
	return card


func _cup_status(cid: String, fixtures: Array) -> String:
	var ties := fixtures.filter(func(f):
		return f["comp"] == "cup" and (f["home"] == cid or f["away"] == cid))
	if ties.is_empty():
		return "Awaiting draw"
	var out := ""
	for f in ties:
		if f["played"] and Season.fixture_winner(f) != cid:
			return "Out in %s" % Season.cup_round_name(int(f["round"]))
		out = Season.cup_round_name(int(f["round"]))
	var max_round := 0
	for f in ties:
		max_round = maxi(max_round, int(f["round"]))
	# champions only if the FINAL is won (round count derives from the draw size)
	var first_count: int = fixtures.filter(func(f):
		return f["comp"] == "cup" and int(f["round"]) == 1).size()
	var total_rounds := 1
	var n := first_count
	while n > 1:
		n = n / 2
		total_rounds += 1
	if max_round >= total_rounds and ties.back()["played"]:
		return "CHAMPIONS"
	return "In the %s" % out


func _club_results_card(club: Dictionary, fixtures: Array) -> PanelContainer:
	var cid: String = str(club["id"])
	var card := UI.card("Fixtures & Results · click a score for the match report")
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 180
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 1)
	scroll.add_child(list)
	var ours := fixtures.filter(func(f): return f["home"] == cid or f["away"] == cid)
	ours.sort_custom(func(a, b): return a["date"] < b["date"])
	var first_upcoming: Control = null
	for f in ours:
		var we_home: bool = f["home"] == cid
		var opp := GameState.club(f["away"] if we_home else f["home"])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var d := UI.dim(UI.short_date(f["date"]), 11)
		d.custom_minimum_size.x = 46
		h.add_child(d)
		var comp := UI.dim("LGE %d" % int(f["round"]) if f["comp"] == "league"
			else Season.cup_round_name(int(f["round"])).left(5).to_upper(), 11)
		comp.custom_minimum_size.x = 56
		h.add_child(comp)
		var ha := UI.dim("H" if we_home else "A", 11)
		ha.custom_minimum_size.x = 14
		h.add_child(ha)
		var opp_link := UI.club_link(opp, 12)
		opp_link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(opp_link)
		if f["played"]:
			var us := int(f["score_home"]) if we_home else int(f["score_away"])
			var them := int(f["score_away"]) if we_home else int(f["score_home"])
			var res := UI.link("%s %d-%d" % ["W" if us > them else "L", us, them], 12,
				UI.COL_WIN if us > them else UI.COL_LOSS, {"kind": "fixture", "id": str(f["id"])})
			res.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			res.custom_minimum_size.x = 52
			h.add_child(res)
		else:
			var pv := UI.link("preview", 11, TB.COL_TEXT_DIM,
				{"kind": "fixture", "id": str(f["id"])}, "Go to fixture preview")
			pv.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			pv.custom_minimum_size.x = 52
			h.add_child(pv)
			if first_upcoming == null:
				first_upcoming = h
		list.add_child(h)
	UI.card_body(card).add_child(scroll)
	if first_upcoming != null:
		var target := first_upcoming
		scroll.call_deferred("ensure_control_visible", target)
	return card


# ============================================================= POKÉMON PROFILE

func _build_pokemon(uid: String) -> void:
	var inst := UI.find_instance(uid)
	if inst.is_empty():
		add_child(UI.dim("This Pokémon is no longer registered with any club.", 13))
		return
	var club := UI.club_of_uid(uid)
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var stats: Dictionary = Season.season_player_stats(GameState.fixtures).get(uid, {})

	add_child(_pokemon_header(inst, sp, club, stats))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.35
	cols.add_child(right)

	var attr_row := HBoxContainer.new()
	attr_row.add_theme_constant_override("separation", 10)
	attr_row.add_child(_attributes_card(inst, sp))
	attr_row.add_child(_moves_card(inst))
	for c in attr_row.get_children():
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(attr_row)
	left.add_child(_condition_card(inst))
	right.add_child(_pokemon_season_card(uid, club, stats))
	right.add_child(_match_log_card(uid, club))


func _pokemon_header(inst: Dictionary, sp: Dictionary, club: Dictionary, stats: Dictionary) -> Control:
	var types: Array = sp.get("types", [])
	var tcol: Color = DataStore.type_color(str(types[0])) if not types.is_empty() else TB.COL_ACCENT
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	sb.border_color = tcol
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)

	# species initial monogram in primary-type color
	var mono := PanelContainer.new()
	mono.custom_minimum_size = Vector2(44, 44)
	mono.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(tcol.r, tcol.g, tcol.b, 0.22)
	msb.border_color = tcol
	msb.set_border_width_all(1)
	msb.set_corner_radius_all(4)
	mono.add_theme_stylebox_override("panel", msb)
	var ml := UI.label(str(inst["species"]).left(1), 20, tcol.lightened(0.35))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mono.add_child(ml)
	h.add_child(mono)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(UI.label(UI.display_name(inst), 20, Color.WHITE))
	var lv_txt := "Lv %d" % int(inst["level"])
	if UI.display_name(inst) != str(inst["species"]):
		lv_txt += " %s" % inst["species"]
	var lv := UI.dim(lv_txt, 13)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(lv)
	for t in types:
		var chip := UI.type_chip(str(t))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(chip)
	v.add_child(name_row)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 6)
	if club.is_empty():
		sub.add_child(UI.dim("Unattached", 12))
	else:
		var cl := UI.club_link(club, 12, TB.COL_TEXT_DIM)
		sub.add_child(cl)
	var cur: String = str(GameState.world["meta"].get("currency", "P$"))
	var contract: Dictionary = inst.get("contract", {})
	sub.add_child(UI.dim("·  Age %s  ·  %s%s/m until %s" % [
		_age(int(inst.get("age_months", 0))), cur,
		_thousands(int(contract.get("salary", 0))),
		str(contract.get("expiry", "?"))], 12))
	v.add_child(sub)
	h.add_child(v)

	var apps := int(stats.get("battles", 0))
	var rat: float = (float(stats.get("rating_sum", 0.0)) / maxi(apps, 1)) if apps > 0 else 0.0
	for stat in [
		["APPS", str(apps), TB.COL_TEXT],
		["KOs", str(int(stats.get("kos", 0))), TB.COL_TEXT],
		["AVG RATING", "%.2f" % rat if apps > 0 else "-",
			_rating_color(rat) if apps > 0 else TB.COL_TEXT_DIM],
	]:
		h.add_child(VSeparator.new())
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 0)
		sv.add_child(UI.label(str(stat[1]), 16, stat[2]))
		sv.add_child(UI.dim(str(stat[0]), 10))
		h.add_child(sv)
	return panel


func _attributes_card(inst: Dictionary, sp: Dictionary) -> PanelContainer:
	var card := UI.card("Attributes · base (IV)")
	var body := UI.card_body(card)
	var base: Dictionary = sp.get("base", {})
	var ivs: Dictionary = inst.get("ivs", {})
	var names := {"hp": "HP", "atk": "Attack", "def": "Defence",
		"spa": "Sp. Atk", "spd": "Sp. Def", "spe": "Speed"}
	for k in ["hp", "atk", "def", "spa", "spd", "spe"]:
		var b := int(base.get(k, 0))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var lab := UI.dim(names[k], 12)
		lab.custom_minimum_size.x = 56
		h.add_child(lab)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 160
		bar.value = b
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = _stat_color(b)
		bar.add_theme_stylebox_override("fill", fill)
		h.add_child(bar)
		var val := UI.label("%d" % b, 12, Color.WHITE)
		val.custom_minimum_size.x = 30
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(val)
		var iv := UI.dim("(%d)" % int(ivs.get(k, 0)), 11)
		iv.custom_minimum_size.x = 28
		h.add_child(iv)
		body.add_child(h)
	return card


func _moves_card(inst: Dictionary) -> PanelContainer:
	var card := UI.card("Moves")
	var body := UI.card_body(card)
	for mname in inst.get("moves", []):
		var m: Dictionary = DataStore.move(str(mname))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var nm := UI.label(str(mname), 13, Color.WHITE)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		if m.is_empty():
			body.add_child(h)
			continue
		var chip := UI.type_chip(str(m.get("type", "Normal")))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(chip)
		var cat: String = str(m.get("category", "status"))
		var cat_l := UI.dim(cat.to_upper().left(4), 10)
		cat_l.custom_minimum_size.x = 34
		h.add_child(cat_l)
		var pw := int(m.get("power", 0))
		var pw_l := UI.label(str(pw) if pw > 0 else "-", 12,
			Color.WHITE if pw > 0 else TB.COL_TEXT_DIM)
		pw_l.custom_minimum_size.x = 26
		pw_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(pw_l)
		var acc := int(m.get("accuracy", 0))
		var acc_l := UI.dim(("%d%%" % acc) if acc > 0 else "—", 11)
		acc_l.custom_minimum_size.x = 34
		acc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(acc_l)
		body.add_child(h)
	return card


func _condition_card(inst: Dictionary) -> PanelContainer:
	var card := UI.card("Condition")
	var body := UI.card_body(card)
	for entry in [["Condition", int(inst.get("condition", 0))],
			["Fitness", int(inst.get("fitness", 0))], ["Morale", int(inst.get("morale", 0))]]:
		var v := int(entry[1])
		var col: Color = UI.COL_WIN if v >= 85 else (TB.COL_WARN if v >= 60 else UI.COL_LOSS)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var lab := UI.dim(str(entry[0]), 12)
		lab.custom_minimum_size.x = 66
		h.add_child(lab)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = v
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		bar.add_theme_stylebox_override("fill", fill)
		h.add_child(bar)
		var val := UI.label("%d%%" % v, 12, col)
		val.custom_minimum_size.x = 36
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(val)
		body.add_child(h)
	return card


func _pokemon_season_card(uid: String, club: Dictionary, stats: Dictionary) -> PanelContainer:
	var card := UI.card("Season %s" % GameState.season_start.split("-")[0])
	var body := UI.card_body(card)
	if stats.is_empty():
		body.add_child(UI.dim("No competitive appearances yet this season.", 12))
		return card
	var apps := int(stats["battles"])
	var wins := int(stats["wins"])
	var rat := float(stats["rating_sum"]) / maxi(apps, 1)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	var hits := int(stats.get("hits", 0))
	var misses := int(stats.get("misses", 0))
	for pair in [
		["Battle apps", str(apps)],
		["Battles won", "%d (%d%%)" % [wins, int(round(100.0 * wins / maxi(apps, 1)))]],
		["KOs", str(int(stats["kos"]))],
		["KOs / app", "%.2f" % (float(stats["kos"]) / maxi(apps, 1))],
		["Damage dealt", str(int(stats["dmg"]))],
		["Damage taken", str(int(stats["taken"]))],
		["Times fainted", str(int(stats["faints"]))],
		["Avg rating", "%.2f" % rat],
		["Accuracy", "%d%% (%d of %d)" % [roundi(100.0 * hits / maxf(hits + misses, 1.0)),
			hits, hits + misses]],
		["Super-effective", "%d hits (%d%%)" % [int(stats.get("se", 0)),
			roundi(100.0 * float(stats.get("se", 0)) / maxf(hits, 1.0))]],
	]:
		var row := UI.kv_row(str(pair[0]), str(pair[1]),
			_rating_color(rat) if pair[0] == "Avg rating" else TB.COL_TEXT)
		row.custom_minimum_size.x = 190
		grid.add_child(row)
	body.add_child(grid)

	# rating trend sparkline over the match log (dashed line = 6.8 par)
	if not club.is_empty():
		var log := Season.pokemon_match_log(uid, str(club["id"]), GameState.fixtures)
		if log.size() >= 2:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 8)
			var cap := UI.dim("Rating trend", 12)
			cap.custom_minimum_size.x = 96
			cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(cap)
			var spark = Charts.Sparkline.new()
			spark.ref_value = 6.8
			spark.v_min = 4.5
			spark.v_max = 10.0
			spark.color = _rating_color(rat)
			spark.custom_minimum_size = Vector2(0, 26)
			spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var vals: Array = []
			var labels: Array = []
			for e in log:
				vals.append(float(e["rating"]))
				var opp := GameState.club(str(e["opp"]))
				labels.append("%s %s" % [UI.short_date(str(e["date"])), opp.get("short", "?")])
			spark.set_data(vals, labels)
			h.add_child(spark)
			body.add_child(h)

	# league percentile context (FM Data-Hub-style pizza slice, as bars)
	var pct := _pokemon_percentiles(uid)
	if not pct.is_empty():
		body.add_child(UI.vspace(2))
		body.add_child(UI.dim("VS THE LEAGUE · percentile among all Pokémon with an appearance", 10))
		for entry in [["rating", "Avg rating"], ["ko_app", "KOs / app"],
				["dmg_app", "Damage / app"], ["surv", "Survival %"], ["acc", "Accuracy"]]:
			if not pct.has(entry[0]):
				continue
			var p: float = float(pct[entry[0]])
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 8)
			var lab := UI.dim(str(entry[1]), 11)
			lab.custom_minimum_size.x = 96
			h.add_child(lab)
			var bar = Charts.PercentileBar.new()
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.set_pct(p)
			h.add_child(bar)
			var v := UI.label(Charts.ordinal(roundi(p * 100.0)), 11, Charts.pct_color(p))
			v.custom_minimum_size.x = 34
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(v)
			body.add_child(h)
	return card


## This Pokémon's league percentile (0..1) for key per-appearance rates,
## computed over every Pokémon with at least one appearance this season.
func _pokemon_percentiles(uid: String) -> Dictionary:
	var stats: Dictionary = Season.season_player_stats(GameState.fixtures)
	if not stats.has(uid):
		return {}
	var derive := func(s: Dictionary) -> Dictionary:
		var apps := maxi(int(s.get("battles", 0)), 1)
		var hits := int(s.get("hits", 0))
		return {
			"rating": float(s.get("rating_sum", 0.0)) / apps,
			"ko_app": float(s.get("kos", 0)) / apps,
			"dmg_app": float(s.get("dmg", 0)) / apps,
			"surv": float(apps - int(s.get("faints", 0))) / apps,
			"acc": float(hits) / maxf(float(hits + int(s.get("misses", 0))), 1.0),
		}
	var pop: Array = []
	for k in stats:
		if int(stats[k].get("battles", 0)) > 0:
			pop.append(derive.call(stats[k]))
	if pop.size() < 2:
		return {}
	var mine: Dictionary = derive.call(stats[uid])
	var out := {}
	for key in mine:
		var below := 0
		var equal := -1   # exclude self from the tie count
		for row in pop:
			if float(row[key]) < float(mine[key]):
				below += 1
			elif is_equal_approx(float(row[key]), float(mine[key])):
				equal += 1
		out[key] = clampf((float(below) + float(equal) * 0.5) / float(pop.size() - 1), 0.0, 1.0)
	return out


func _match_log_card(uid: String, club: Dictionary) -> PanelContainer:
	var card := UI.card("Match Log · click an opponent or result to follow it")
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := UI.card_body(card)
	if club.is_empty():
		body.add_child(UI.dim("No club — no fixtures.", 12))
		return card
	var entries := Season.pokemon_match_log(uid, str(club["id"]), GameState.fixtures)
	if entries.is_empty():
		body.add_child(UI.dim("Has not appeared in a competitive match yet.", 12))
		return card
	var tree := Tree.new()
	tree.hide_root = true
	tree.columns = 7
	tree.column_titles_visible = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 200
	var titles := ["Date", "Comp", "Opponent", "Res", "KOs", "Dmg", "Rat"]
	var widths := [64, 52, 0, 56, 42, 52, 46]
	for i in tree.columns:
		tree.set_column_title(i, titles[i])
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT if i == 2 else HORIZONTAL_ALIGNMENT_CENTER)
		if widths[i] > 0:
			tree.set_column_expand(i, false)
			tree.set_column_custom_minimum_width(i, widths[i])
	UI.wire_tree_links(tree)
	var root := tree.create_item()
	entries.reverse()   # newest first
	for e in entries:
		var opp := GameState.club(str(e["opp"]))
		var item := root.create_child()
		item.set_text(0, UI.short_date(str(e["date"])))
		item.set_custom_color(0, TB.COL_TEXT_DIM)
		item.set_text(1, "LGE" if e["comp"] == "league" else "CUP")
		item.set_custom_color(1, TB.COL_TEXT_DIM)
		item.set_text(2, "%s %s" % ["vs" if e["we_home"] else "at", opp.get("name", e["opp"])])
		item.set_custom_color(2, TB.COL_TEXT)
		UI.cell_link(item, 2, {"kind": "club", "id": str(e["opp"])},
			"%s — view club profile" % opp.get("name", "?"))
		item.set_text(3, "%s %d-%d" % ["W" if e["won"] else "L", int(e["us"]), int(e["them"])])
		item.set_custom_color(3, UI.COL_WIN if e["won"] else UI.COL_LOSS)
		UI.cell_link(item, 3, {"kind": "fixture", "id": str(e["fid"])}, "Go to match report")
		item.set_text(4, str(int(e["kos"])))
		item.set_text(5, str(int(e["dmg"])))
		item.set_text(6, "%.1f" % float(e["rating"]))
		item.set_custom_color(6, _rating_color(float(e["rating"])))
		for c in [0, 1, 3, 4, 5, 6]:
			item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(tree)
	return card


# ------------------------------------------------------------------- helpers

func _rating_color(r: float) -> Color:
	if r >= 7.6:
		return Color(0.95, 0.83, 0.4)
	if r >= 7.0:
		return UI.COL_WIN
	if r < 6.2:
		return UI.COL_LOSS
	return Color.WHITE


func _stat_color(v: int) -> Color:
	if v >= 110:
		return UI.COL_WIN
	if v >= 75:
		return TB.COL_ACCENT
	if v >= 50:
		return TB.COL_WARN
	return UI.COL_LOSS


func _age(months: int) -> String:
	return "%dy %dm" % [int(months / 12.0), months % 12]


func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out


func _ord(n: int) -> String:
	if n <= 0:
		return "-"
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
