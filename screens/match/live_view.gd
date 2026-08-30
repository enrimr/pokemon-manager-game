extends Control
## Live battle viewer: replays MatchRunner events with pacing, animated HP
## bars, commentary ticker, momentum graph, speed controls and touchline
## instructions (including full manual control via the engine step API).

signal request_post

const UI := preload("res://screens/match/ui_bits.gd")
const Commentary := preload("res://screens/match/commentary.gd")
const MomentumGraph := preload("res://screens/match/momentum_graph.gd")

var runner  # MatchRunner

var _speed := 1.0            # 0 = paused
var _key_only := false
var _clock := 0.0
var _ticker_idx := 0

# node refs
var _score_label: Label
var _battle_label: Label
var _flash: Label
var _cards := [{}, {}]       # per displayed column: refs dict
var _graph: Control
var _ticker: RichTextLabel
var _action_bar: Control
var _over_bar: Control
var _over_label: Label
var _over_btn: Button
var _speed_btns := {}
var _agg_opt: OptionButton
var _swi_opt: OptionButton
var _force_btn: MenuButton
var _ctl_toggle: CheckButton
var _key_toggle: CheckButton

const DELAYS := {
	"battle_start": 0.9, "turn_start": 0.3, "move_used": 0.55, "damage": 0.7,
	"miss": 0.55, "faint": 1.35, "switch": 0.7, "status_applied": 0.7,
	"status_tick": 0.4, "stat_change": 0.45, "heal": 0.5, "flinch": 0.5,
	"confused_hit": 0.55, "asleep": 0.45, "paralyzed": 0.5,
	"commentary_hook": 0.0, "battle_end": 1.4,
}


func setup(p_runner) -> void:
	runner = p_runner


func _ready() -> void:
	_build()
	_refresh_all()


func _process(delta: float) -> void:
	if runner == null or runner.phase != runner.Phase.LIVE:
		return
	if runner.awaiting_input():
		_show_action_bar()
		return
	if _speed <= 0.0:
		return
	_clock -= delta * _speed
	while _clock <= 0.0:
		var e: Dictionary = runner.consume_next()
		if e.is_empty():
			_on_stream_stalled()
			return
		_after_event(e)
		var d: float = DELAYS.get(str(e.get("t", "")), 0.4)
		if _key_only and not Commentary.is_key_event(e):
			d *= 0.05
		_clock += maxf(d, 0.001)


func _on_stream_stalled() -> void:
	if runner.live_state == runner.LiveState.BATTLE_OVER:
		_show_over_bar()
	elif runner.awaiting_input():
		_show_action_bar()


# ------------------------------------------------------------------ build

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := UI.hbox(10)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var left := UI.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.7
	root.add_child(left)

	left.add_child(_build_scoreboard())

	var arena := UI.hbox(10)
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(arena)
	arena.add_child(_build_card(0))
	arena.add_child(_build_center())
	arena.add_child(_build_card(1))

	var gpair: Array = UI.panel("Momentum")
	_graph = MomentumGraph.new()
	_graph.custom_minimum_size = Vector2(0, 120)
	gpair[1].add_child(_graph)
	left.add_child(gpair[0])

	left.add_child(_build_touchline())
	_action_bar = _build_action_bar()
	left.add_child(_action_bar)
	_over_bar = _build_over_bar()
	left.add_child(_over_bar)

	var right := UI.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.custom_minimum_size.x = 330
	root.add_child(right)
	var cpair: Array = UI.panel("Commentary")
	cpair[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ticker = RichTextLabel.new()
	_ticker.bbcode_enabled = true
	_ticker.scroll_following = true
	_ticker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ticker.add_theme_font_size_override("normal_font_size", 13)
	_ticker.add_theme_constant_override("line_separation", 4)
	cpair[1].add_child(_ticker)
	right.add_child(cpair[0])


func _build_scoreboard() -> Control:
	var pair: Array = UI.panel("", true)
	var row := UI.hbox(14)
	pair[1].add_child(row)
	var home: Dictionary = runner.home_club
	var away: Dictionary = runner.away_club
	row.add_child(UI.monogram(home.get("short", "HOM"), UI.club_color(home), 34))
	var hl := UI.label(home["name"], 16, Color.WHITE if runner.player_side == 0 else UI.COL_TEXT)
	row.add_child(hl)
	row.add_child(UI.spacer_h())
	_score_label = UI.label("0 – 0", 26, Color.WHITE)
	row.add_child(_score_label)
	row.add_child(UI.spacer_h())
	var al := UI.label(away["name"], 16, Color.WHITE if runner.player_side == 1 else UI.COL_TEXT)
	row.add_child(al)
	row.add_child(UI.monogram(away.get("short", "AWY"), UI.club_color(away), 34))
	_battle_label = UI.label("", 12, UI.COL_DIM)
	_battle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pair[1].add_child(_battle_label)
	return pair[0]


func _build_center() -> Control:
	var box := UI.vbox(8)
	box.custom_minimum_size.x = 120
	box.add_child(UI.spacer_v())
	var vs := UI.label("VS", 22, UI.COL_DIM)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(vs)
	_flash = UI.label("", 14, UI.COL_WARN)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_flash)
	box.add_child(UI.spacer_v())
	return box


func _build_card(col: int) -> Control:
	## col 0 = home side, col 1 = away side.
	var pair: Array = UI.panel(str(runner.club_for_side(col).get("name", "")).to_upper()
		+ ("  ·  YOU" if col == runner.player_side else ""))
	var p: PanelContainer = pair[0]
	var box: VBoxContainer = pair[1]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var refs := {}

	var name_row := UI.hbox(8)
	refs["name"] = UI.label("—", 19, Color.WHITE)
	name_row.add_child(refs["name"])
	refs["level"] = UI.label("", 13, UI.COL_DIM)
	name_row.add_child(refs["level"])
	name_row.add_child(UI.spacer_h())
	box.add_child(name_row)

	refs["types"] = UI.hbox(4)
	box.add_child(refs["types"])

	refs["hp_bar"] = ProgressBar.new()
	refs["hp_bar"].min_value = 0
	refs["hp_bar"].max_value = 1.0
	refs["hp_bar"].value = 1.0
	refs["hp_bar"].show_percentage = false
	refs["hp_bar"].custom_minimum_size = Vector2(0, 16)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI.COL_GOOD
	fill.set_corner_radius_all(3)
	refs["hp_bar"].add_theme_stylebox_override("fill", fill)
	refs["hp_fill"] = fill
	box.add_child(refs["hp_bar"])

	var hp_row := UI.hbox(8)
	refs["hp_text"] = UI.label("", 13, UI.COL_TEXT)
	hp_row.add_child(refs["hp_text"])
	hp_row.add_child(UI.spacer_h())
	refs["status"] = UI.hbox(4)
	hp_row.add_child(refs["status"])
	box.add_child(hp_row)

	refs["stages"] = UI.label("", 13, UI.COL_WARN)
	box.add_child(refs["stages"])

	box.add_child(UI.spacer_v())
	box.add_child(UI.label("BENCH", 10, UI.COL_DIM))
	refs["bench"] = UI.hbox(5)
	box.add_child(refs["bench"])

	_cards[col] = refs
	return p


func _build_touchline() -> Control:
	var pair: Array = UI.panel("Touchline")
	var box: VBoxContainer = pair[1]

	var row1 := UI.hbox(6)
	box.add_child(row1)
	for spec in [["⏸", 0.0], ["1x", 1.0], ["2x", 2.0], ["4x", 4.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(44, 30)
		b.pressed.connect(_set_speed.bind(float(spec[1])))
		row1.add_child(b)
		_speed_btns[float(spec[1])] = b
	var skip_b := Button.new()
	skip_b.text = "Skip battle ⏭"
	skip_b.pressed.connect(_on_skip_battle)
	row1.add_child(skip_b)
	var skip_s := Button.new()
	skip_s.text = "Skip to result ⏭⏭"
	skip_s.pressed.connect(_on_skip_series)
	row1.add_child(skip_s)
	row1.add_child(UI.spacer_h())
	_key_toggle = CheckButton.new()
	_key_toggle.text = "Key moments only"
	_key_toggle.add_theme_font_size_override("font_size", 13)
	_key_toggle.toggled.connect(func(v): _key_only = v)
	row1.add_child(_key_toggle)

	var row2 := UI.hbox(10)
	box.add_child(row2)
	row2.add_child(UI.label("Aggression", 12, UI.COL_DIM))
	_agg_opt = OptionButton.new()
	for o in ["Balanced", "Attacking", "Cautious"]:
		_agg_opt.add_item(o)
	_agg_opt.select(["balanced", "attacking", "cautious"].find(str(runner.policy["aggression"])))
	_agg_opt.item_selected.connect(func(i):
		runner.set_policy("aggression", ["balanced", "attacking", "cautious"][i])
		runner.add_note("aggression set to %s." % ["Balanced", "Attacking", "Cautious"][i]))
	row2.add_child(_agg_opt)
	row2.add_child(UI.label("Switching", 12, UI.COL_DIM))
	_swi_opt = OptionButton.new()
	for o in ["Normal", "Hold the line", "Rotate freely"]:
		_swi_opt.add_item(o)
	_swi_opt.select(["normal", "stay", "eager"].find(str(runner.policy["switching"])))
	_swi_opt.item_selected.connect(func(i):
		runner.set_policy("switching", ["normal", "stay", "eager"][i])
		runner.add_note("switch policy set to %s." % ["Normal", "Hold the line", "Rotate freely"][i]))
	row2.add_child(_swi_opt)
	_force_btn = MenuButton.new()
	_force_btn.text = "Force switch ▾"
	_force_btn.flat = false
	_force_btn.about_to_popup.connect(_fill_force_menu)
	_force_btn.get_popup().id_pressed.connect(_on_force_switch)
	row2.add_child(_force_btn)
	row2.add_child(UI.spacer_h())
	_ctl_toggle = CheckButton.new()
	_ctl_toggle.text = "Take full control"
	_ctl_toggle.add_theme_font_size_override("font_size", 13)
	_ctl_toggle.button_pressed = bool(runner.policy["full_control"])
	_ctl_toggle.toggled.connect(func(v):
		runner.set_policy("full_control", v)
		runner.add_note("you %s control of every move." % ("take" if v else "hand back"))
		if not v:
			_action_bar.visible = false)
	row2.add_child(_ctl_toggle)
	return pair[0]


func _build_action_bar() -> Control:
	var pair: Array = UI.panel("Your call — pick a move or switch", true)
	pair[0].visible = false
	var rows := UI.vbox(6)
	pair[1].add_child(rows)
	var moves_row := UI.hbox(6)
	rows.add_child(moves_row)
	var switch_row := UI.hbox(6)
	rows.add_child(switch_row)
	pair[0].set_meta("moves_row", moves_row)
	pair[0].set_meta("switch_row", switch_row)
	return pair[0]


func _build_over_bar() -> Control:
	var pair: Array = UI.panel("", true)
	pair[0].visible = false
	var row := UI.hbox(10)
	pair[1].add_child(row)
	_over_label = UI.label("", 15, Color.WHITE)
	row.add_child(_over_label)
	row.add_child(UI.spacer_h())
	_over_btn = Button.new()
	_over_btn.custom_minimum_size = Vector2(200, 34)
	_over_btn.pressed.connect(_on_over_pressed)
	row.add_child(_over_btn)
	return pair[0]


# ------------------------------------------------------------------ refresh

func _refresh_all() -> void:
	_refresh_scoreboard()
	for side in 2:
		_refresh_card(side, false)
	_refresh_graph()
	_render_ticker_catchup()
	_set_speed(_speed)
	if runner.live_state == runner.LiveState.BATTLE_OVER and runner.buffered() == 0:
		_show_over_bar()


func _refresh_scoreboard() -> void:
	_score_label.text = "%d – %d" % [runner.wins[0], runner.wins[1]]
	_battle_label.text = "BEST OF 3  ·  BATTLE %d  ·  TURN %d  ·  %s" % [
		runner.battle_no, runner.turn_now,
		("LEAGUE ROUND %d" % int(runner.fixture["round"])) if runner.fixture["comp"] == "league"
		else Season.cup_round_name(int(runner.fixture["round"])).to_upper() + " (CUP)"]


func _refresh_card(side: int, animate: bool) -> void:
	var refs: Dictionary = _cards[side]
	if refs.is_empty():
		return
	var team: Array = runner.vm["teams"][side]
	if team.is_empty():
		return
	var b: Dictionary = team[runner.vm["active"][side]]
	refs["name"].text = str(b["name"])
	refs["level"].text = "Lv %d  %s" % [int(b["level"]), str(b["species"]) if b["species"] != b["name"] else ""]
	for c in refs["types"].get_children():
		c.queue_free()
	for t in b["types"]:
		refs["types"].add_child(UI.type_badge(str(t)))
	var frac := float(b["hp"]) / maxf(float(b["max_hp"]), 1.0)
	refs["hp_fill"].bg_color = UI.hp_color(frac)
	if animate:
		var tw := create_tween()
		tw.tween_property(refs["hp_bar"], "value", frac, 0.35).set_trans(Tween.TRANS_CUBIC)
	else:
		refs["hp_bar"].value = frac
	refs["hp_text"].text = "%d / %d HP  (%d%%)" % [int(b["hp"]), int(b["max_hp"]), int(round(frac * 100))]
	for c in refs["status"].get_children():
		c.queue_free()
	if str(b["status"]) != "":
		refs["status"].add_child(UI.status_chip(str(b["status"])))
	if b["confused"]:
		refs["status"].add_child(UI.status_chip("confused"))
	refs["stages"].text = UI.stage_text(b["stages"])
	# bench pips
	for c in refs["bench"].get_children():
		c.queue_free()
	for i in team.size():
		var m: Dictionary = team[i]
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(30, 12)
		pip.tooltip_text = "%s  Lv%d  %d/%d HP%s" % [m["name"], int(m["level"]), int(m["hp"]),
			int(m["max_hp"]), ("  " + str(m["status"]).to_upper()) if str(m["status"]) != "" else ""]
		var sb := StyleBoxFlat.new()
		var mf := float(m["hp"]) / maxf(float(m["max_hp"]), 1.0)
		sb.bg_color = Color("242a3d") if m["fainted"] else UI.hp_color(mf) * Color(1, 1, 1, 0.55 + 0.45 * mf)
		if i == runner.vm["active"][side]:
			sb.border_color = Color.WHITE
			sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		pip.add_theme_stylebox_override("panel", sb)
		refs["bench"].add_child(pip)


func _refresh_graph() -> void:
	_graph.set_data(runner.momentum, runner.faint_marks, runner.shorts(), runner.player_side)


func _render_ticker_catchup() -> void:
	_ticker.clear()
	_ticker_idx = 0
	_append_new_ticker_lines()


func _append_new_ticker_lines() -> void:
	while _ticker_idx < runner.ticker.size():
		var l: Dictionary = runner.ticker[_ticker_idx]
		_ticker.append_text("[color=#3d4358]B%d·T%02d[/color]  %s\n" %
			[int(l["battle"]), int(l["turn"]), str(l["text"])])
		_ticker_idx += 1


# ------------------------------------------------------------------ event reactions

func _after_event(e: Dictionary) -> void:
	var t := str(e.get("t", ""))
	match t:
		"turn_start":
			_refresh_scoreboard()
			_refresh_graph()
		"damage", "heal", "status_tick", "confused_hit":
			_refresh_card(int(e["side"]), true)
			if t == "damage" and not e.get("recoil", false):
				var frac := float(e.get("amount", 0)) / maxf(float(e.get("max_hp", 1)), 1.0)
				if bool(e.get("crit", false)):
					_flash_text("CRIT! %s" % str(e.get("move", "")), UI.COL_WARN)
				elif frac >= 0.4:
					_flash_text("%s!" % str(e.get("move", "")), UI.COL_BAD)
		"switch", "faint", "status_applied", "stat_change", "flinch":
			_refresh_card(int(e.get("side", 0)), t != "switch")
			if t == "faint":
				_flash_text("%s FAINTED" % str(e["pokemon"]).to_upper(),
					UI.COL_BAD if int(e["side"]) == runner.player_side else UI.COL_GOOD)
				_refresh_graph()
		"move_used":
			_flash_text("%s → %s" % [str(e["pokemon"]), str(e["move"])], UI.COL_TEXT)
		"battle_start":
			for side in 2:
				_refresh_card(side, false)
			_refresh_scoreboard()
		"battle_end":
			_refresh_scoreboard()
			_refresh_graph()
			_show_over_bar()
	_append_new_ticker_lines()


func _flash_text(text: String, col: Color) -> void:
	_flash.text = text
	_flash.add_theme_color_override("font_color", col)


# ------------------------------------------------------------------ controls

func _set_speed(s: float) -> void:
	_speed = s
	for k in _speed_btns:
		_speed_btns[k].button_pressed = is_equal_approx(float(k), s)


func _on_skip_battle() -> void:
	runner.skip_battle()
	_finish_skip_refresh()


func _on_skip_series() -> void:
	runner.skip_series()
	if runner.phase == runner.Phase.POST:
		request_post.emit()


func _finish_skip_refresh() -> void:
	_refresh_all()
	for side in 2:
		_refresh_card(side, false)
	if runner.series_decided():
		_show_over_bar()


func _show_over_bar() -> void:
	_action_bar.visible = false
	_over_bar.visible = true
	var s: Array = runner.shorts()
	if runner.series_decided():
		_over_label.text = "FULL TIME — %s %d-%d %s" % [s[0], runner.wins[0], runner.wins[1], s[1]]
		_over_btn.text = "Full-time report  ▶"
	else:
		_over_label.text = "Battle %d goes to %s.  Series: %d–%d." % [
			runner.battle_no, s[runner.battles.back()["winner"]], runner.wins[0], runner.wins[1]]
		_over_btn.text = "Start battle %d  ▶" % (runner.battle_no + 1)


func _on_over_pressed() -> void:
	if runner.series_decided():
		runner.to_post()
		request_post.emit()
		return
	_over_bar.visible = false
	runner.next_battle()
	_refresh_all()
	_flash_text("", UI.COL_TEXT)
	if _speed <= 0.0:
		_set_speed(1.0)


func _fill_force_menu() -> void:
	var pop := _force_btn.get_popup()
	pop.clear()
	var team: Array = runner.vm["teams"][runner.player_side]
	for i in team.size():
		var b: Dictionary = team[i]
		if b["fainted"] or i == runner.vm["active"][runner.player_side]:
			continue
		pop.add_item("%s  Lv%d  %d%%" % [b["name"], int(b["level"]),
			int(round(100.0 * float(b["hp"]) / maxf(float(b["max_hp"]), 1.0)))], i)


func _on_force_switch(id: int) -> void:
	runner.force_switch(id)
	var b: Dictionary = runner.vm["teams"][runner.player_side][id]
	runner.add_note("force switch — %s will come in." % str(b["name"]))
	_append_new_ticker_lines()


func _show_action_bar() -> void:
	if _action_bar.visible:
		return
	_over_bar.visible = false
	_action_bar.visible = true
	var moves_row: HBoxContainer = _action_bar.get_meta("moves_row")
	var switch_row: HBoxContainer = _action_bar.get_meta("switch_row")
	for c in moves_row.get_children():
		c.queue_free()
	for c in switch_row.get_children():
		c.queue_free()
	for a in runner.available_actions():
		var btn := Button.new()
		if a["type"] == "move":
			var mv: Dictionary = DataStore.move(str(a["move"]))
			var pv: Dictionary = a.get("preview", {})
			var eff := float(pv.get("eff", 1.0))
			var est := int(round(float(pv.get("est_frac", 0.0)) * 100))
			var eff_txt := ""
			if str(mv.get("category", "")) == "status":
				eff_txt = "status"
			else:
				eff_txt = "~%d%% dmg" % est
				if eff >= 2.0:
					eff_txt += " ▲▲"
				elif eff == 0.0:
					eff_txt = "immune ✕"
				elif eff < 1.0:
					eff_txt += " ▼"
			btn.text = "%s\n%s · %d PP · %s" % [str(a["move"]), str(mv.get("type", "?")).to_upper(),
				int(a["pp"]), eff_txt]
			btn.add_theme_color_override("font_color",
				UI.COL_GOOD if eff >= 2.0 else (UI.COL_BAD if eff == 0.0 else UI.COL_TEXT))
			btn.pressed.connect(_on_player_action.bind({"type": "move", "index": int(a["index"])}))
			btn.custom_minimum_size = Vector2(120, 46)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			moves_row.add_child(btn)
		else:
			btn.text = "⇄ %s · %d%% HP" % [str(a["pokemon"]),
				int(round(100.0 * float(a["hp"]) / maxf(float(a["max_hp"]), 1.0)))]
			btn.add_theme_color_override("font_color", UI.COL_ACCENT)
			btn.pressed.connect(_on_player_action.bind({"type": "switch", "index": int(a["index"])}))
			btn.custom_minimum_size = Vector2(90, 30)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			switch_row.add_child(btn)


func _on_player_action(action: Dictionary) -> void:
	_action_bar.visible = false
	runner.submit_action(action)
	if _speed <= 0.0:
		_set_speed(1.0)
