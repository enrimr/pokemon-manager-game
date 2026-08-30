extends Control
## Live battle viewer: animated arena stage, replayed MatchRunner events with
## pacing, HP bars, commentary ticker, momentum graph, speed controls and
## touchline instructions. Manual combat (you pick every move / switch / item
## via the engine step API) is the default; auto-pilot delegates to the coach.

signal request_post

const UI := preload("res://screens/match/ui_bits.gd")
const Commentary := preload("res://screens/match/commentary.gd")
const MomentumGraph := preload("res://screens/match/momentum_graph.gd")
const BattleStage := preload("res://screens/match/battle_stage.gd")

var runner  # MatchRunner

var _speed := 1.0            # 0 = paused
var _key_only := false
var _clock := 0.0
var _ticker_idx := 0
var _action_slot := -1       # doubles: which of our slots the action bar is for

# node refs
var _score_label: Label
var _battle_label: Label
var _cards := [{}, {}]       # per displayed column: refs dict
var _stage: Control
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
var _bag_label: Label
var _weather_label: Label
var _tl_row2: Control   # policy row — hidden while the action bar is up (manual mode)

const WEATHER_UI := {
	"sun": ["HARSH SUNLIGHT", Color("f0a848")],
	"rain": ["POURING RAIN", Color("58a8f0")],
	"sand": ["SANDSTORM", Color("d8c078")],
	"hail": ["HAIL", Color("98d8d8")],
}

const DELAYS := {
	"battle_start": 0.9, "turn_start": 0.3, "move_used": 0.6, "damage": 0.75,
	"miss": 0.55, "faint": 1.35, "switch": 0.75, "status_applied": 0.7,
	"status_tick": 0.4, "stat_change": 0.45, "heal": 0.55, "flinch": 0.5,
	"confused_hit": 0.55, "asleep": 0.45, "paralyzed": 0.5,
	"commentary_hook": 0.0, "battle_end": 1.4, "item_used": 1.0, "held_item": 0.5,
	"no_target": 0.55, "ability_triggered": 0.45, "weather_start": 0.8,
	"weather_end": 0.5, "weather_chip": 0.35,
}


func setup(p_runner) -> void:
	runner = p_runner


func _ready() -> void:
	_build()
	_refresh_all()
	if runner != null and runner.has_meta("demo_pause"):
		runner.remove_meta("demo_pause")
		_set_speed(0.0)


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
	left.size_flags_stretch_ratio = 1.9
	root.add_child(left)

	left.add_child(_build_scoreboard())

	var arena := UI.hbox(10)
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(arena)
	arena.add_child(_build_card(0))
	arena.add_child(_build_stage())
	arena.add_child(_build_card(1))

	var gpair: Array = UI.panel("Momentum")
	_graph = MomentumGraph.new()
	_graph.custom_minimum_size = Vector2(0, 70)
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
	right.custom_minimum_size.x = 320
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


func _build_stage() -> Control:
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("141827")
	sb.border_color = UI.COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(0)
	frame.add_theme_stylebox_override("panel", sb)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 2.0
	_stage = BattleStage.new()
	_stage.setup(runner)
	frame.add_child(_stage)
	return frame


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
	_weather_label = UI.label("", 12, UI.COL_WARN)
	_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weather_label.visible = false
	pair[1].add_child(_weather_label)
	return pair[0]


func _build_card(col: int) -> Control:
	## col 0 = home side, col 1 = away side. Holds one block per ACTIVE SLOT
	## (1 in singles, 2 in doubles — rebuilt when the format changes mid-tie).
	var pair: Array = UI.panel(str(runner.club_for_side(col).get("name", "")).to_upper()
		+ ("  ·  YOU" if col == runner.player_side else ""))
	var p: PanelContainer = pair[0]
	var box: VBoxContainer = pair[1]
	p.custom_minimum_size.x = 252
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var blocks_box := UI.vbox(6)
	box.add_child(blocks_box)
	box.add_child(UI.spacer_v())
	box.add_child(UI.label("BENCH", 10, UI.COL_DIM))
	var bench := UI.hbox(5)
	box.add_child(bench)
	_cards[col] = {"blocks_box": blocks_box, "bench": bench, "blocks": []}
	_ensure_card_blocks(col)
	return p


## Rebuild the per-slot blocks when the active-slot count changes (1 <-> 2).
func _ensure_card_blocks(side: int) -> void:
	var card: Dictionary = _cards[side]
	if card.is_empty():
		return
	var want: int = runner.vm["actives"][side].size()
	if card["blocks"].size() == want:
		return
	for c in card["blocks_box"].get_children():
		c.queue_free()
	card["blocks"] = []
	for k in want:
		card["blocks"].append(_build_slot_block(card["blocks_box"], want > 1, k))


func _build_slot_block(parent: Control, compact: bool, slot: int) -> Dictionary:
	## compact = doubles: two of these must stack in one side card AND leave the
	## action bar on-screen, so every sub-row is folded tight (stages ride the
	## name row, held item rides the HP row, moves form a 2x2 grid).
	var refs := {}
	var box := UI.vbox(2 if compact else 4)
	parent.add_child(box)
	if compact and slot > 0:
		var sep := HSeparator.new()
		box.add_child(sep)
	var name_row := UI.hbox(6 if compact else 8)
	if compact:
		name_row.add_child(UI.label("S%d" % (slot + 1), 10, UI.COL_ACCENT))
	refs["name"] = UI.label("—", 13 if compact else 18, Color.WHITE)
	name_row.add_child(refs["name"])
	refs["level"] = UI.label("", 10 if compact else 12, UI.COL_DIM)
	name_row.add_child(refs["level"])
	name_row.add_child(UI.spacer_h())
	refs["stages"] = UI.label("", 10 if compact else 12, UI.COL_WARN)
	if compact:
		name_row.add_child(refs["stages"])
	box.add_child(name_row)

	refs["types"] = UI.hbox(4)
	box.add_child(refs["types"])

	refs["hp_bar"] = ProgressBar.new()
	refs["hp_bar"].min_value = 0
	refs["hp_bar"].max_value = 1.0
	refs["hp_bar"].value = 1.0
	refs["hp_bar"].show_percentage = false
	refs["hp_bar"].custom_minimum_size = Vector2(0, 10 if compact else 16)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI.COL_GOOD
	fill.set_corner_radius_all(3)
	refs["hp_bar"].add_theme_stylebox_override("fill", fill)
	refs["hp_fill"] = fill
	box.add_child(refs["hp_bar"])

	var hp_row := UI.hbox(6 if compact else 8)
	refs["hp_text"] = UI.label("", 11 if compact else 13, UI.COL_TEXT)
	hp_row.add_child(refs["hp_text"])
	hp_row.add_child(UI.spacer_h())
	refs["status"] = UI.hbox(4)
	hp_row.add_child(refs["status"])
	refs["item"] = UI.label("—", 10 if compact else 12, UI.COL_TEXT)
	refs["item"].mouse_filter = Control.MOUSE_FILTER_STOP
	if compact:
		hp_row.add_child(refs["item"])
	box.add_child(hp_row)

	if not compact:
		box.add_child(refs["stages"])
		# held item chip (hover for the effect popup)
		var item_row := UI.hbox(6)
		item_row.add_child(UI.label("HELD", 10, UI.COL_DIM))
		item_row.add_child(refs["item"])
		box.add_child(item_row)
		box.add_child(UI.label("MOVES", 10, UI.COL_DIM))
		refs["moves"] = UI.vbox(3)
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 1)
		refs["moves"] = grid
	box.add_child(refs["moves"])
	refs["compact"] = compact
	refs["box"] = box
	return refs


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
	skip_b.text = "Sim rest of battle ⏭"
	skip_b.pressed.connect(_on_skip_battle)
	row1.add_child(skip_b)
	var skip_s := Button.new()
	skip_s.text = "Sim to result ⏭⏭"
	skip_s.pressed.connect(_on_skip_series)
	row1.add_child(skip_s)
	row1.add_child(UI.spacer_h())
	_key_toggle = CheckButton.new()
	_key_toggle.text = "Key moments only"
	_key_toggle.add_theme_font_size_override("font_size", 13)
	_key_toggle.toggled.connect(func(v): _key_only = v)
	row1.add_child(_key_toggle)
	_ctl_toggle = CheckButton.new()
	_ctl_toggle.text = "Auto-pilot (coach decides)"
	_ctl_toggle.tooltip_text = "On: the AI coach follows your touchline instructions and may use the bag.\nOff: you call every move, switch and item yourself."
	_ctl_toggle.add_theme_font_size_override("font_size", 13)
	_ctl_toggle.button_pressed = not bool(runner.policy["full_control"])
	_ctl_toggle.toggled.connect(func(v):
		runner.set_policy("full_control", not v)
		runner.add_note("you %s." % ("delegate to the coach" if v else "take charge of every call"))
		_tl_row2.visible = v or not _action_bar.visible
		if v:
			_action_bar.visible = false
			_tl_row2.visible = true)
	row1.add_child(_ctl_toggle)

	var row2 := UI.hbox(10)
	box.add_child(row2)
	_tl_row2 = row2
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
	_bag_label = UI.label("", 12, UI.COL_DIM)
	row2.add_child(_bag_label)
	return pair[0]


func _build_action_bar() -> Control:
	## Kept deliberately short: in doubles this bar must fit UNDER two stacked
	## battler blocks per side card inside the shell's content area (see
	## _doubles_ui_qa.gd, which asserts its rect is fully on-screen).
	var pair: Array = UI.panel("", true)
	pair[0].visible = false
	var rows := UI.vbox(4)
	pair[1].add_child(rows)
	var head_row := UI.hbox(8)
	rows.add_child(head_row)
	head_row.add_child(UI.label("YOUR CALL", 11, UI.COL_DIM))
	var head := UI.label("", 13, UI.COL_ACCENT)
	head_row.add_child(head)
	head_row.add_child(UI.spacer_h())
	var undo := Button.new()
	undo.text = "↩ redo slot 1"
	undo.visible = false
	undo.custom_minimum_size = Vector2(110, 24)
	undo.add_theme_font_size_override("font_size", 12)
	undo.pressed.connect(_on_undo_slot)
	head_row.add_child(undo)
	var moves_row := UI.hbox(6)
	rows.add_child(moves_row)
	var lower := UI.hbox(6)
	rows.add_child(lower)
	var switch_row := UI.hbox(6)
	switch_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(switch_row)
	var items_row := UI.hbox(6)
	items_row.alignment = BoxContainer.ALIGNMENT_END
	lower.add_child(items_row)
	pair[0].set_meta("head", head)
	pair[0].set_meta("undo", undo)
	pair[0].set_meta("moves_row", moves_row)
	pair[0].set_meta("switch_row", switch_row)
	pair[0].set_meta("items_row", items_row)
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
	_refresh_bag()
	_render_ticker_catchup()
	_set_speed(_speed)
	if _stage != null:
		_stage.sync_actives()
	if runner.live_state == runner.LiveState.BATTLE_OVER and runner.buffered() == 0:
		_show_over_bar()


func _refresh_scoreboard() -> void:
	_score_label.text = "%d – %d" % [runner.wins[0], runner.wins[1]]
	_battle_label.text = "BEST OF 3  ·  BATTLE %d%s  ·  TURN %d  ·  %s" % [
		runner.battle_no, "  ·  2v2 DOUBLES" if runner.doubles_now() else "", runner.turn_now,
		("LEAGUE ROUND %d" % int(runner.fixture["round"])) if runner.fixture["comp"] == "league"
		else Season.cup_round_name(int(runner.fixture["round"])).to_upper() + " (CUP)"]
	var wk := str(runner.vm.get("weather", ""))
	if wk == "" or not WEATHER_UI.has(wk):
		_weather_label.visible = false
	else:
		_weather_label.visible = true
		var spec: Array = WEATHER_UI[wk]
		var turns := int(runner.vm.get("weather_turns", 0))
		_weather_label.text = "◈ %s%s" % [spec[0],
			("  ·  %d turn%s left" % [turns, "" if turns == 1 else "s"]) if turns > 0 else ""]
		_weather_label.add_theme_color_override("font_color", spec[1])


func _refresh_bag() -> void:
	if _bag_label == null:
		return
	var parts: Array = []
	var bag: Dictionary = runner.our_bag()
	for iid in bag:
		parts.append("%s ×%d" % [DataStore.item_name(str(iid)), int(bag[iid])])
	var mine := "empty" if parts.is_empty() else " · ".join(parts)
	_bag_label.text = "MATCH BAG:  %s      |   items used — you %d, them %d" % [
		mine, runner.items_spent(runner.player_side), runner.items_spent(1 - runner.player_side)]


func _refresh_card(side: int, animate: bool) -> void:
	var card: Dictionary = _cards[side]
	if card.is_empty():
		return
	var team: Array = runner.vm["teams"][side]
	if team.is_empty():
		return
	_ensure_card_blocks(side)
	var actives: Array = runner.vm["actives"][side]
	for k in card["blocks"].size():
		var refs: Dictionary = card["blocks"][k]
		var idx: int = int(actives[k]) if k < actives.size() else -1
		if idx < 0 or idx >= team.size():
			refs["box"].visible = false
			continue
		refs["box"].visible = true
		_refresh_block(refs, team[idx], animate)
	# bench pips
	var bench: Control = card["bench"]
	for c in bench.get_children():
		c.queue_free()
	for i in team.size():
		var m: Dictionary = team[i]
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(30, 12)
		var held := str(m.get("item", ""))
		pip.tooltip_text = "%s  Lv%d  %d/%d HP%s%s" % [m["name"], int(m["level"]), int(m["hp"]),
			int(m["max_hp"]), ("  " + str(m["status"]).to_upper()) if str(m["status"]) != "" else "",
			("\nHolds: " + DataStore.item_name(held)) if held != "" else ""]
		var sb := StyleBoxFlat.new()
		var mf := float(m["hp"]) / maxf(float(m["max_hp"]), 1.0)
		sb.bg_color = Color("242a3d") if m["fainted"] else UI.hp_color(mf) * Color(1, 1, 1, 0.55 + 0.45 * mf)
		if actives.has(i):
			sb.border_color = Color.WHITE
			sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		pip.add_theme_stylebox_override("panel", sb)
		bench.add_child(pip)


func _refresh_block(refs: Dictionary, b: Dictionary, animate: bool) -> void:
	var compact := bool(refs.get("compact", false))
	refs["name"].text = str(b["name"])
	if compact:
		refs["level"].text = "Lv %d" % int(b["level"])
	else:
		refs["level"].text = "Lv %d  %s" % [int(b["level"]), str(b["species"]) if b["species"] != b["name"] else ""]
	for c in refs["types"].get_children():
		c.queue_free()
	for t in b["types"]:
		refs["types"].add_child(UI.type_badge(str(t), 9 if compact else 11))
	var frac := float(b["hp"]) / maxf(float(b["max_hp"]), 1.0)
	refs["hp_fill"].bg_color = UI.hp_color(frac)
	if animate:
		var tw := create_tween()
		tw.tween_property(refs["hp_bar"], "value", frac, 0.35).set_trans(Tween.TRANS_CUBIC)
	else:
		refs["hp_bar"].value = frac
	if compact:
		refs["hp_text"].text = "%d/%d" % [int(b["hp"]), int(b["max_hp"])]
	else:
		refs["hp_text"].text = "%d / %d HP  (%d%%)" % [int(b["hp"]), int(b["max_hp"]), int(round(frac * 100))]
	for c in refs["status"].get_children():
		c.queue_free()
	if str(b["status"]) != "":
		refs["status"].add_child(UI.status_chip(str(b["status"]), 9 if compact else 11))
	if b["confused"]:
		refs["status"].add_child(UI.status_chip("confused", 9 if compact else 11))
	refs["stages"].text = UI.stage_text(b["stages"])
	# held item chip
	var iid := str(b.get("item", ""))
	if iid == "":
		refs["item"].text = "—" if compact else "nothing"
		refs["item"].add_theme_color_override("font_color", UI.COL_DIM)
		refs["item"].tooltip_text = "No held item."
	else:
		var it: Dictionary = DataStore.item(iid)
		var consumed := bool(b.get("item_consumed", false))
		refs["item"].text = "◆ %s%s" % [str(it.get("name", iid)),
			("*" if compact else "  (spent)") if consumed else ""]
		refs["item"].add_theme_color_override("font_color", UI.COL_DIM if consumed else UI.COL_WARN)
		refs["item"].tooltip_text = "%s\n%s%s" % [str(it.get("name", iid)), str(it.get("desc", "")),
			"\n(already spent this battle)" if consumed else ""]
	# live move list with PP
	for c in refs["moves"].get_children():
		c.queue_free()
	for mname in b["moves"]:
		var mv: Dictionary = DataStore.move(str(mname))
		var pp_left := int(b.get("pp", {}).get(str(mname), -1))
		var out_of_pp := pp_left == 0
		var pw := int(mv.get("power", 0))
		var meta_txt := ("pw %d" % pw) if pw > 0 else str(mv.get("category", ""))
		if compact:
			# 2x2 grid cell: type-coloured move name + PP count (tooltip = detail)
			var cell := UI.hbox(4)
			var ml := UI.label(str(mname), 10,
				UI.COL_DIM if out_of_pp else DataStore.type_color(str(mv.get("type", "?"))).lightened(0.25))
			ml.mouse_filter = Control.MOUSE_FILTER_STOP
			ml.tooltip_text = "%s · %s · %s · %s PP left" % [str(mv.get("type", "?")).to_upper(),
				str(mv.get("category", "?")), meta_txt, str(pp_left) if pp_left >= 0 else "?"]
			cell.add_child(ml)
			cell.add_child(UI.label("·%s" % (str(pp_left) if pp_left >= 0 else "?"), 9,
				UI.COL_BAD if out_of_pp else UI.COL_DIM))
			refs["moves"].add_child(cell)
			continue
		var mrow := UI.hbox(6)
		mrow.add_child(UI.type_badge(str(mv.get("type", "?")), 9))
		var ml2 := UI.label(str(mname), 12, UI.COL_DIM if out_of_pp else UI.COL_TEXT)
		mrow.add_child(ml2)
		mrow.add_child(UI.spacer_h())
		mrow.add_child(UI.label("%s · %s PP" % [meta_txt, str(pp_left) if pp_left >= 0 else "?"],
			11, UI.COL_BAD if out_of_pp else UI.COL_DIM))
		refs["moves"].add_child(mrow)


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
	if _stage != null:
		_stage.play_event(e)
	match t:
		"turn_start":
			_refresh_scoreboard()
			_refresh_graph()
		"damage", "heal", "status_tick", "confused_hit", "weather_chip":
			_refresh_card(int(e["side"]), true)
		"weather_start", "weather_end":
			_refresh_scoreboard()
		"ability_triggered":
			_refresh_card(int(e.get("side", 0)), false)
		"switch", "faint", "status_applied", "stat_change", "flinch", "held_item", "move_used":
			_refresh_card(int(e.get("side", 0)), t != "switch")
			if t == "faint":
				_refresh_graph()
		"item_used":
			_refresh_card(int(e["side"]), true)
			_refresh_bag()
		"battle_start":
			for side in 2:
				_refresh_card(side, false)
			_refresh_scoreboard()
			_refresh_bag()
		"battle_end":
			_refresh_scoreboard()
			_refresh_graph()
			_show_over_bar()
	_append_new_ticker_lines()


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
	_action_slot = -1
	_tl_row2.visible = true
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
	if _speed <= 0.0:
		_set_speed(1.0)


func _fill_force_menu() -> void:
	var pop := _force_btn.get_popup()
	pop.clear()
	var team: Array = runner.vm["teams"][runner.player_side]
	for i in team.size():
		var b: Dictionary = team[i]
		if b["fainted"] or runner.vm["actives"][runner.player_side].has(i):
			continue
		pop.add_item("%s  Lv%d  %d%%" % [b["name"], int(b["level"]),
			int(round(100.0 * float(b["hp"]) / maxf(float(b["max_hp"]), 1.0)))], i)


func _on_force_switch(id: int) -> void:
	runner.force_switch(id)
	var b: Dictionary = runner.vm["teams"][runner.player_side][id]
	runner.add_note("force switch — %s will come in." % str(b["name"]))
	_append_new_ticker_lines()


# ------------------------------------------------------------------ action bar (manual combat)

func _show_action_bar() -> void:
	var doubles: bool = runner.doubles_now()
	var slot := 0
	if doubles:
		var waiting: Array = runner.slots_awaiting()
		if waiting.is_empty():
			return
		slot = int(waiting[0])
	if _action_bar.visible and _action_slot == slot:
		return
	_action_slot = slot
	_over_bar.visible = false
	_action_bar.visible = true
	_tl_row2.visible = false  # policies are moot while you call every turn
	var head: Label = _action_bar.get_meta("head")
	var undo: Button = _action_bar.get_meta("undo")
	undo.visible = false
	if doubles:
		var me: Dictionary = runner.engine.slot_battler(runner.player_side, slot)
		head.text = "DOUBLES — SLOT %d/%d: %s.  Pick a move AND its target, switch, or use an item." % [
			slot + 1, runner.engine.slot_count(), str(me.get("name", "?"))]
		if not runner.slot_actions.is_empty():
			var prev_slot: int = runner.slot_actions.keys()[0]
			undo.text = "↩ redo slot %d" % (int(prev_slot) + 1)
			undo.visible = true
	else:
		head.text = "Attack, switch or use an item (items cost the turn)."
	var moves_row: HBoxContainer = _action_bar.get_meta("moves_row")
	var switch_row: HBoxContainer = _action_bar.get_meta("switch_row")
	var items_row: HBoxContainer = _action_bar.get_meta("items_row")
	for c in moves_row.get_children():
		c.queue_free()
	for c in switch_row.get_children():
		c.queue_free()
	for c in items_row.get_children():
		c.queue_free()
	var item_groups := {}   # item_id -> [action dicts]
	var acts: Array = runner.available_actions_slot(slot) if doubles else runner.available_actions()
	for a in acts:
		if a["type"] == "move":
			if doubles and str(a.get("targeting", "")) == "single" \
					and a.get("targets", []).size() > 1:
				moves_row.add_child(_move_target_menu(a))
			else:
				moves_row.add_child(_move_button(a))
		elif a["type"] == "switch":
			switch_row.add_child(_switch_button(a))
		elif a["type"] == "use_item":
			var iid := str(a["item"])
			if not item_groups.has(iid):
				item_groups[iid] = []
			item_groups[iid].append(a)
	for iid in item_groups:
		items_row.add_child(_item_menu(str(iid), item_groups[iid]))


func _on_undo_slot() -> void:
	if runner.slot_actions.is_empty():
		return
	runner.retract_slot_action(int(runner.slot_actions.keys()[0]))
	_action_slot = -1
	_action_bar.visible = false
	_show_action_bar()


static func _eff_text(mv: Dictionary, pv: Dictionary, spread: bool) -> String:
	var eff := float(pv.get("eff", 1.0))
	var est := int(round(float(pv.get("est_frac", 0.0)) * 100))
	if str(mv.get("category", "")) == "status":
		return "status"
	var t := "~%d%% dmg" % est
	if eff >= 2.0:
		t += " ▲▲"
	elif eff == 0.0:
		t = "immune ✕"
	elif eff < 1.0:
		t += " ▼"
	if spread:
		t += " · EACH"
	return t


func _move_button(a: Dictionary) -> Button:
	var btn := Button.new()
	var mv: Dictionary = DataStore.move(str(a["move"]))
	var tg := str(a.get("targeting", ""))
	var spread := tg == "spread_foes" or tg == "spread_all"
	var pv: Dictionary = a.get("preview", {})
	var action := {"type": "move", "index": int(a["index"])}
	if tg == "single" and a.get("targets", []).size() == 1:
		var t: Dictionary = a["targets"][0]
		pv = t.get("preview", pv)
		action["target"] = {"side": int(t["side"]), "slot": int(t["slot"])}
	var eff := float(pv.get("eff", 1.0))
	var eff_txt := _eff_text(mv, pv, spread)
	var pow_txt := "—" if int(mv.get("power", 0)) <= 0 else str(int(mv["power"]))
	var acc_v := int(mv.get("accuracy", 100))
	var acc_txt := "—" if acc_v <= 0 else "%d%%" % acc_v
	var tail := eff_txt
	if spread:
		tail = ("HITS BOTH FOES%s · " % (" + ALLY" if tg == "spread_all" else "")) + eff_txt
	btn.text = "%s\n%s · pw %s · acc %s · %d PP\n%s" % [str(a["move"]),
		str(mv.get("type", "?")).to_upper(), pow_txt, acc_txt, int(a["pp"]), tail]
	btn.tooltip_text = "Type %s · %s · power %s · accuracy %s · %d PP left%s" % [
		str(mv.get("type", "?")), str(mv.get("category", "?")), pow_txt, acc_txt, int(a["pp"]),
		"\nSpread: hits every target at 75% power." if spread else ""]
	btn.add_theme_color_override("font_color",
		UI.COL_GOOD if eff >= 2.0 else (UI.COL_BAD if eff == 0.0 else UI.COL_TEXT))
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(_on_player_action.bind(action))
	btn.custom_minimum_size = Vector2(120, 46)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn


## Doubles two-step: the move button opens a target picker (per-target preview).
func _move_target_menu(a: Dictionary) -> MenuButton:
	var mb := MenuButton.new()
	var mv: Dictionary = DataStore.move(str(a["move"]))
	var pow_txt := "—" if int(mv.get("power", 0)) <= 0 else str(int(mv["power"]))
	var acc_v := int(mv.get("accuracy", 100))
	var acc_txt := "—" if acc_v <= 0 else "%d%%" % acc_v
	mb.text = "%s  🎯▾\n%s · pw %s · acc %s · %d PP\npick a target" % [str(a["move"]),
		str(mv.get("type", "?")).to_upper(), pow_txt, acc_txt, int(a["pp"])]
	mb.flat = false
	mb.add_theme_font_size_override("font_size", 12)
	mb.custom_minimum_size = Vector2(120, 46)
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mb.tooltip_text = "Single-target move — choose which foe to hit."
	var targets: Array = a.get("targets", [])
	var pop := mb.get_popup()
	for i in targets.size():
		var t: Dictionary = targets[i]
		var pv: Dictionary = t.get("preview", {})
		pop.add_item("→ %s   (%s)" % [str(t.get("name", "?")), _eff_text(mv, pv, false)], i)
	pop.id_pressed.connect(func(id: int):
		var t: Dictionary = targets[id]
		_on_player_action({"type": "move", "index": int(a["index"]),
			"target": {"side": int(t["side"]), "slot": int(t["slot"])}}))
	return mb


func _switch_button(a: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = "⇄ %s · %d%% HP" % [str(a["pokemon"]),
		int(round(100.0 * float(a["hp"]) / maxf(float(a["max_hp"]), 1.0)))]
	btn.add_theme_color_override("font_color", UI.COL_ACCENT)
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(_on_player_action.bind({"type": "switch", "index": int(a["index"])}))
	btn.custom_minimum_size = Vector2(90, 26)
	return btn


func _item_menu(iid: String, actions: Array) -> MenuButton:
	## One button per distinct item in the bag; the popup picks the target.
	var mb := MenuButton.new()
	var first: Dictionary = actions[0]
	mb.text = "🧰 %s ×%d ▾" % [str(first.get("name", iid)), int(first.get("count", 1))]
	mb.flat = false
	mb.add_theme_color_override("font_color", UI.COL_WARN)
	mb.add_theme_font_size_override("font_size", 12)
	mb.tooltip_text = "%s — using an item costs this turn." % str(first.get("desc", ""))
	mb.custom_minimum_size = Vector2(110, 26)
	var pop := mb.get_popup()
	for i in actions.size():
		var a: Dictionary = actions[i]
		var status := str(a.get("target_status", ""))
		var hp := int(a.get("target_hp", 0))
		var desc: String
		if hp <= 0:
			desc = "fainted"
		else:
			desc = "%d/%d HP" % [hp, int(a.get("target_max", 1))]
			if status != "":
				desc += " · " + status.to_upper()
		pop.add_item("→ %s   (%s)" % [str(a.get("target_name", "?")), desc], i)
	pop.id_pressed.connect(func(id: int):
		var a: Dictionary = actions[id]
		_on_player_action({"type": "use_item", "item": str(a["item"]), "target": int(a["target"])}))
	return mb


func _on_player_action(action: Dictionary) -> void:
	if runner.doubles_now():
		runner.submit_slot_action(_action_slot, action)
		_action_slot = -1
		if runner.awaiting_input() and not runner.slots_awaiting().is_empty():
			_action_bar.visible = false
			_show_action_bar()   # step two: the other slot's call
			return
		_action_bar.visible = false
		_tl_row2.visible = true
		if _speed <= 0.0:
			_set_speed(1.0)
		return
	_action_bar.visible = false
	_action_slot = -1
	_tl_row2.visible = true
	runner.submit_action(action)
	if _speed <= 0.0:
		_set_speed(1.0)
