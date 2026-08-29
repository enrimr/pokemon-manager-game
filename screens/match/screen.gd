extends Control
## Match screen STUB — owned by the "match" piece (which also owns
## res://shared/sim/battle_engine.gd). Will become the live match/replay UI
## driven by BattleEngine.step_turn() and the event log.


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "Match"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Stub — the match piece will build the live battle viewer on BattleEngine's step API."
	hint.add_theme_color_override("font_color", Color("8b91a8"))
	box.add_child(hint)
	box.add_child(HSeparator.new())

	var fx: Dictionary = GameState.next_player_fixture()
	var info := Label.new()
	if fx.is_empty():
		info.text = "No upcoming fixture."
	else:
		var home: Dictionary = GameState.club(fx["home"])
		var away: Dictionary = GameState.club(fx["away"])
		info.text = "Next fixture: %s vs %s  ·  %s  ·  %s round %d" % [
			home["name"], away["name"], Season.pretty_date(fx["date"]), fx["comp"], fx["round"]]
	box.add_child(info)

	var last := Label.new()
	var played := GameState.player_fixtures().filter(func(f): return f["played"])
	if played.is_empty():
		last.text = "No matches played yet."
	else:
		var f: Dictionary = played.back()
		last.text = "Last result: %s %d - %d %s" % [
			GameState.club(f["home"])["name"], f["score_home"],
			f["score_away"], GameState.club(f["away"])["name"]]
	box.add_child(last)
