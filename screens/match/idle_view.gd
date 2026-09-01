extends Control
## Shown when no player match is due: next fixture preview, recent results,
## league context. Dense, all live data.

const UI := preload("res://screens/match/ui_bits.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := UI.vbox(10)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(UI.label(tr("MATCH DAY CENTRE"), 20, Color.WHITE))
	var cols := UI.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	cols.add_child(_build_next_fixture())
	cols.add_child(_build_recent())


func _build_next_fixture() -> Control:
	var pair: Array = UI.panel(tr("Next fixture"))
	var p: PanelContainer = pair[0]
	var box: VBoxContainer = pair[1]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.1
	var f: Dictionary = GameState.next_player_fixture()
	if f.is_empty():
		box.add_child(UI.label(tr("No upcoming fixture — the season is done."), 14, UI.COL_DIM))
		return p
	var home: Dictionary = GameState.club(f["home"])
	var away: Dictionary = GameState.club(f["away"])
	var opp: Dictionary = away if GameState.is_player_club(f["home"]) else home

	var row := UI.hbox(12)
	row.add_child(UI.club_crest(home, 40))
	row.add_child(UI.label(tr("%s  vs  %s") % [home["name"], away["name"]], 18, Color.WHITE))
	row.add_child(UI.spacer_h())
	row.add_child(UI.club_crest(away, 40))
	box.add_child(row)

	var days := _days_until(str(f["date"]))
	var comp_txt: String = (tr("League · Round %d") % int(f["round"])) if f["comp"] == "league" \
		else tr("Cup · %s") % I18n.cup_round(int(f["round"]))
	box.add_child(UI.label("%s  ·  %s  ·  %s" % [comp_txt, I18n.pretty_date(str(f["date"])),
		(tr("today — press Continue") if days <= 0 else (tr("tomorrow") if days == 1 else tr("in %d days") % days))],
		13, UI.COL_WARN if days <= 1 else UI.COL_DIM))
	box.add_child(HSeparator.new())

	# opponent snapshot
	var pos := 0
	var pts := 0
	var table: Array = GameState.league_table()
	for i in table.size():
		if table[i]["club_id"] == opp["id"]:
			pos = i + 1
			pts = int(table[i]["points"])
	box.add_child(UI.label(tr("OPPONENT SNAPSHOT"), 10, UI.COL_DIM))
	box.add_child(UI.label(tr("%s — managed by %s") % [opp["name"], opp.get("manager", "?")], 13))
	box.add_child(UI.label(tr("League position: %d · %d pts · reputation %d/20") %
		[pos, pts, int(opp.get("reputation", 10))], 13))
	var form_row := UI.hbox(4)
	form_row.add_child(UI.label("Form:", 13, UI.COL_DIM))
	var any := false
	for w in _recent_form(str(opp["id"]), 5):
		form_row.add_child(UI.result_chip(w))
		any = true
	if not any:
		form_row.add_child(UI.label(tr("no matches yet"), 13, UI.COL_DIM))
	box.add_child(form_row)
	box.add_child(HSeparator.new())
	box.add_child(UI.label(tr("THEIR LIKELY SIX"), 10, UI.COL_DIM))
	for b in Season.pick_team(opp):
		var brow := UI.hbox(6)
		brow.add_child(UI.label("%s" % b["name"], 13, Color.WHITE))
		brow.add_child(UI.label(tr("Lv%d") % int(b["level"]), 12, UI.COL_DIM))
		brow.add_child(UI.spacer_h())
		for t in b["types"]:
			brow.add_child(UI.type_badge(str(t), 10))
		box.add_child(brow)
	box.add_child(UI.spacer_v())
	box.add_child(UI.label("Press Continue in the top bar — the game stops here on match day\nfor team selection, live battles and touchline control.", 12, UI.COL_DIM))
	return p


func _build_recent() -> Control:
	var pair: Array = UI.panel(tr("Recent results"))
	var p: PanelContainer = pair[0]
	var box: VBoxContainer = pair[1]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var played: Array = GameState.player_fixtures().filter(func(f): return f["played"])
	if played.is_empty():
		box.add_child(UI.label(tr("No matches played yet this season."), 13, UI.COL_DIM))
	var pid: String = GameState.world["meta"]["player_club_id"]
	var recent := played.slice(maxi(0, played.size() - 8))
	recent.reverse()
	for f in recent:
		var home: bool = f["home"] == pid
		var us: int = f["score_home"] if home else f["score_away"]
		var them: int = f["score_away"] if home else f["score_home"]
		var opp: Dictionary = GameState.club(f["away"] if home else f["home"])
		var row := UI.hbox(8)
		row.add_child(UI.result_chip(us > them))
		row.add_child(UI.label("%d–%d" % [us, them], 14, Color.WHITE))
		row.add_child(UI.label("%s %s" % ["vs" if home else "@", opp["name"]], 13))
		row.add_child(UI.spacer_h())
		row.add_child(UI.label("%s · %s" % [tr("League R%d") % int(f["round"]) if f["comp"] == "league"
			else tr("Cup"), I18n.pretty_date(str(f["date"]))], 12, UI.COL_DIM))
		box.add_child(row)
	box.add_child(HSeparator.new())
	var posn := GameState.player_table_position()
	var played0 := true
	for r in GameState.league_table():
		if GameState.is_player_club(r["club_id"]):
			played0 = int(r.get("played", 0)) == 0
	box.add_child(UI.label((tr("Current league position: — (season not started)") if played0
		else tr("Current league position: %d of %d") % [posn, GameState.league_table().size()]),
		13, UI.COL_TEXT))
	box.add_child(HSeparator.new())
	box.add_child(UI.label(tr("YOUR STARTING SIX"), 10, UI.COL_DIM))
	for b in _our_planned_six():
		var brow := UI.hbox(6)
		brow.add_child(UI.label("%s" % b["name"], 13, Color.WHITE))
		brow.add_child(UI.label(tr("Lv%d") % int(b["level"]), 12, UI.COL_DIM))
		brow.add_child(UI.spacer_h())
		brow.add_child(UI.label(tr("HP %d · Spe %d") % [int(b["stats"]["hp"]), int(b["stats"]["spe"])],
			11, UI.COL_DIM))
		for t in b["types"]:
			brow.add_child(UI.type_badge(str(t), 10))
		box.add_child(brow)
	box.add_child(UI.spacer_v())
	return p


## Our six in the tactic plan's battle order when a plan exists (the same
## lineup the Tactics screen and the match runner use); level order otherwise.
func _our_planned_six() -> Array:
	var club := GameState.player_club()
	var tac: Variant = GameState.world.get("meta", {}).get("tactics")
	if tac is Dictionary and not (tac as Dictionary).get("lineup", []).is_empty() \
			and ResourceLoader.exists("res://screens/tactics/tactics_logic.gd"):
		var logic: GDScript = load("res://screens/tactics/tactics_logic.gd")
		var out: Array = []
		for inst in logic.lineup_instances(tac, club):
			var b: Dictionary = DataStore.make_battler(inst)
			if not b.is_empty():
				out.append(b)
		if not out.is_empty():
			return out
	return Season.pick_team(club)


func _recent_form(club_id: String, n: int) -> Array:
	var played: Array = GameState.fixtures.filter(func(f):
		return f["played"] and (f["home"] == club_id or f["away"] == club_id))
	var out: Array = []
	for f in played.slice(maxi(0, played.size() - n)):
		var home: bool = f["home"] == club_id
		out.append((f["score_home"] if home else f["score_away"]) > (f["score_away"] if home else f["score_home"]))
	return out


func _days_until(date: String) -> int:
	var d := 0
	var cur: String = GameState.current_date
	while cur < date and d < 999:
		cur = Season.date_add(cur, 1)
		d += 1
	return d
