extends Control
## Tactics screen — FM-style battle plan board.
## Left: starting six + ordered bench with per-slot roles & suitability.
## Centre: battle line + offensive/defensive type-coverage matrix.
## Right: team instructions + role guide. Presets persist inside the save
## (world.meta.tactics_state) and the active plan is published into
## GameState.world.meta.tactics — one source of truth, no sidecar.

const Logic := preload("res://screens/tactics/tactics_logic.gd")
const SlotRow := preload("res://screens/tactics/slot_row.gd")
const Brain := preload("res://screens/tactics/tactics_brain.gd")
const Director := preload("res://screens/tactics/tactics_director.gd")


## The shell loads this script at boot for sub-nav discovery; ride that to
## install the TacticsDirector so the saved battle plan commands lineups,
## battle order and touchline AI even in sessions where this screen is never
## opened (mirrors the match piece's boot-hook pattern).
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	Callable(Director, "install").call_deferred()

var _state: Dictionary = {}
var _analyses: Dictionary = {}     # uid -> analysis
var _selected_uid := ""
var _guide_uid := ""

var _rows: Dictionary = {}         # uid -> SlotRow node
var _left_box: VBoxContainer
var _center_box: VBoxContainer
var _right_box: VBoxContainer
var _preset_pick: OptionButton
var _saved_lbl: Label
var _guide_panel: VBoxContainer
var _save_timer: Timer
var _rename_dialog: ConfirmationDialog
var _rename_edit: LineEdit
var _delete_dialog: ConfirmationDialog


func _ready() -> void:
	Director.install()   # defensive: boot hook may have been skipped
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.6
	_save_timer.timeout.connect(_do_save)
	add_child(_save_timer)
	_build_dialogs()
	_state = Logic.load_state()
	_refresh_analyses()
	Logic.save_state(_state)  # stores state in world.meta + publishes the plan
	_build_layout()
	_rebuild_all()


func on_show() -> void:
	pass


# ================================================================= data ops

func _preset() -> Dictionary:
	return Logic.active_preset(_state)


func _refresh_analyses() -> void:
	_analyses.clear()
	for inst in GameState.player_club().get("squad", []):
		_analyses[inst["uid"]] = Logic.analyze(inst)


func _queue_save() -> void:
	_saved_lbl.text = "Saving…"
	_saved_lbl.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
	_save_timer.start()


func _do_save() -> void:
	Logic.save_state(_state)
	# A fixture already waiting in pre-match follows the edit immediately.
	Director.stamp_pending_runner(false, true)
	_saved_lbl.text = "Saved %s  ·  live on the match engine" % Time.get_time_string_from_system().substr(0, 5)
	_saved_lbl.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD)


func _swap(src: String, dst: String) -> void:
	var p := _preset()
	for list_a in [p["lineup"], p["bench"]]:
		for list_b in [p["lineup"], p["bench"]]:
			var i: int = list_a.find(src)
			var j: int = list_b.find(dst)
			if i >= 0 and j >= 0:
				list_a[i] = dst
				list_b[j] = src
				_selected_uid = ""
				_queue_save()
				_rebuild_all()
				return


func _nudge(uid: String, dir: int) -> void:
	var p := _preset()
	for list in [p["lineup"], p["bench"]]:
		var i: int = list.find(uid)
		if i >= 0:
			var j := i + dir
			if j < 0 or j >= list.size():
				return
			var tmp = list[i]
			list[i] = list[j]
			list[j] = tmp
			_queue_save()
			_rebuild_all()
			return


func _on_row_clicked(uid: String) -> void:
	_guide_uid = uid
	if _selected_uid == "":
		_selected_uid = uid
	elif _selected_uid == uid:
		_selected_uid = ""
	else:
		_swap(_selected_uid, uid)
		return
	for u in _rows:
		_rows[u].set_selected(u == _selected_uid)
	_refresh_role_guide()


func _on_role_changed(uid: String, role: String) -> void:
	_preset()["roles"][uid] = role
	_guide_uid = uid
	_queue_save()
	_refresh_battle_line()
	_refresh_role_guide()


# ================================================================= layout

func _build_layout() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_left_box = VBoxContainer.new()
	_left_box.custom_minimum_size.x = 430
	_left_box.add_theme_constant_override("separation", 4)
	body.add_child(_left_box)

	var center_scroll := ScrollContainer.new()
	center_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(center_scroll)
	_center_box = VBoxContainer.new()
	_center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_box.add_theme_constant_override("separation", 5)
	center_scroll.add_child(_center_box)

	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size.x = 308
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right_scroll)
	_right_box = VBoxContainer.new()
	_right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_box.add_theme_constant_override("separation", 8)
	right_scroll.add_child(_right_box)


func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "Battle Plan"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	h.add_child(title)

	var club := Label.new()
	club.text = "· %s" % GameState.player_club().get("name", "")
	club.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	club.add_theme_font_size_override("font_size", 14)
	club.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(club)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	_saved_lbl = Label.new()
	_saved_lbl.add_theme_font_size_override("font_size", 11)
	_saved_lbl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_saved_lbl.text = "Loaded · active plan live on the match engine"
	h.add_child(_saved_lbl)

	_preset_pick = OptionButton.new()
	_preset_pick.custom_minimum_size = Vector2(190, 32)
	_preset_pick.fit_to_longest_item = false
	_preset_pick.item_selected.connect(_on_preset_pick)
	h.add_child(_preset_pick)

	for spec in [["New", _on_new_preset], ["Rename", _on_rename_preset],
			["Delete", _on_delete_preset], ["Auto-Pick", _on_auto_pick]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size.y = 32
		b.pressed.connect(spec[1])
		if spec[0] == "Auto-Pick":
			b.tooltip_text = "Re-select the best six by level & condition and assign each battler its most natural role."
		h.add_child(b)
	return h


static func _section(text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var bar := ColorRect.new()
	bar.color = ThemeBuilder.COL_ACCENT
	bar.custom_minimum_size = Vector2(3, 13)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	h.add_child(l)
	return h


# ================================================================= rebuild

func _rebuild_all() -> void:
	_refresh_presets_dropdown()
	_rebuild_left()
	_rebuild_center()
	_rebuild_right()


func _refresh_presets_dropdown() -> void:
	_preset_pick.clear()
	var names: Array = _state["presets"].map(func(p): return p["name"])
	for i in names.size():
		_preset_pick.add_item(names[i], i)
		if names[i] == _state["active"]:
			_preset_pick.select(i)


func _rebuild_left() -> void:
	for c in _left_box.get_children():
		c.queue_free()
	_rows.clear()
	var p := _preset()

	_left_box.add_child(_section("Starting six — battle order"))
	for i in p["lineup"].size():
		_left_box.add_child(_make_row(p["lineup"][i], str(i + 1), true))

	var bench_hdr := _section("Bench — substitution order")
	_left_box.add_child(bench_hdr)
	if p["bench"].is_empty():
		var none := Label.new()
		none.text = "No reserves — entire squad starts."
		none.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_left_box.add_child(none)
	for i in p["bench"].size():
		_left_box.add_child(_make_row(p["bench"][i], "B%d" % (i + 1), false))

	var hint := Label.new()
	hint.text = "Drag a row onto another (or click two rows) to swap. Slot 1 opens the battle."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_left_box.add_child(hint)


func _make_row(uid: String, slot_text: String, starter: bool) -> Control:
	var row = SlotRow.new()
	var a: Dictionary = _analyses[uid]
	row.setup(a, slot_text, _preset()["roles"].get(uid, "pivot"), starter)
	row.row_clicked.connect(_on_row_clicked)
	row.swap_requested.connect(_swap)
	row.role_changed.connect(_on_role_changed)
	row.nudge_requested.connect(_nudge)
	row.set_selected(uid == _selected_uid)
	_rows[uid] = row
	return row


# ----------------------------------------------------------------- centre

func _rebuild_center() -> void:
	for c in _center_box.get_children():
		c.queue_free()
	_center_box.add_child(_section("Battle line"))
	_center_box.add_child(_make_battle_line())
	_center_box.add_child(_make_matchday_panel())
	_center_box.add_child(_section("Type coverage — best move vs each defending type"))
	_center_box.add_child(_make_coverage_grid(true))
	_center_box.add_child(_section("Defensive response — damage taken from each attack type"))
	_center_box.add_child(_make_coverage_grid(false))
	_center_box.add_child(_make_coverage_summary())
	var opp := _make_opponent_panel()
	if opp != null:
		_center_box.add_child(opp)


var _battle_line_holder: HBoxContainer

func _make_battle_line() -> Control:
	_battle_line_holder = HBoxContainer.new()
	_battle_line_holder.add_theme_constant_override("separation", 8)
	_refresh_battle_line()
	return _battle_line_holder


func _refresh_battle_line() -> void:
	if _battle_line_holder == null or not is_instance_valid(_battle_line_holder):
		return
	for c in _battle_line_holder.get_children():
		c.queue_free()
	var p := _preset()
	for i in p["lineup"].size():
		var uid: String = p["lineup"][i]
		var a: Dictionary = _analyses[uid]
		var role: String = p["roles"].get(uid, "pivot")
		var score: int = Logic.role_score(role, a)["score"]
		var b: Array = Logic.band(score)

		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.x = 74
		var sb := StyleBoxFlat.new()
		sb.bg_color = ThemeBuilder.COL_PANEL_ALT
		sb.border_color = DataStore.type_color(a["types"][0])
		sb.set_border_width_all(1)
		sb.border_width_top = 3
		sb.set_corner_radius_all(4)
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		card.add_theme_stylebox_override("panel", sb)
		card.tooltip_text = "%s — slot %d · %s (%s %d)" % [a["battler"]["name"], i + 1,
			Logic.ROLES[role]["name"], b[0], score]

		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(v)

		var slot := Label.new()
		slot.text = "LEAD" if i == 0 else "SLOT %d" % (i + 1)
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_theme_font_size_override("font_size", 9)
		slot.add_theme_color_override("font_color",
			ThemeBuilder.COL_ACCENT if i == 0 else ThemeBuilder.COL_TEXT_DIM)
		v.add_child(slot)

		var mono := Label.new()
		mono.text = str(a["battler"]["species"]).substr(0, 2).to_upper()
		mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mono.add_theme_font_size_override("font_size", 16)
		mono.add_theme_color_override("font_color", DataStore.type_color(a["types"][0]).lightened(0.25))
		v.add_child(mono)

		var nm := Label.new()
		nm.text = a["battler"]["name"]
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.clip_text = true
		nm.add_theme_font_size_override("font_size", 11)
		nm.add_theme_color_override("font_color", Color.WHITE)
		v.add_child(nm)

		var rl := Label.new()
		rl.text = Logic.ROLES[role]["name"]
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.clip_text = true
		rl.add_theme_font_size_override("font_size", 10)
		rl.add_theme_color_override("font_color", b[1])
		v.add_child(rl)
		_battle_line_holder.add_child(card)


func _make_coverage_grid(offensive: bool) -> Control:
	var p := _preset()
	var grid := GridContainer.new()
	grid.columns = DataStore.types.size() + 1
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 1)

	# header row
	var corner := Label.new()
	corner.custom_minimum_size = Vector2(86, 20)
	grid.add_child(corner)
	for t in DataStore.types:
		var th := Label.new()
		th.text = str(t).substr(0, 3).to_upper()
		th.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		th.add_theme_font_size_override("font_size", 9)
		th.add_theme_color_override("font_color", DataStore.type_color(t).lightened(0.2))
		th.custom_minimum_size = Vector2(26, 20)
		th.tooltip_text = str(t).capitalize()
		grid.add_child(th)

	for uid in p["lineup"]:
		var a: Dictionary = _analyses[uid]
		var nm := Label.new()
		nm.text = a["battler"]["name"]
		nm.clip_text = true
		nm.custom_minimum_size = Vector2(86, 19)
		nm.add_theme_font_size_override("font_size", 11)
		grid.add_child(nm)
		for t in DataStore.types:
			if offensive:
				var res: Dictionary = Logic.offense_vs(a, t)
				grid.add_child(_cell(res["mult"], true,
					"%s vs %s: ×%s%s" % [a["battler"]["name"], str(t).capitalize(),
						_fmt_mult(res["mult"]),
						(" (" + str(res["move"]) + ")") if res["move"] != "" else ""]))
			else:
				var mult: float = Logic.def_mult(a, t)
				var tip := "%s attacks take ×%s on %s" % [str(t).capitalize(), _fmt_mult(mult), a["battler"]["name"]]
				if mult != DataStore.effectiveness(t, a["types"]):
					tip += "\n%s: the ability changes this from the raw type chart (×%s)." % [
						a["ability_name"], _fmt_mult(DataStore.effectiveness(t, a["types"]))]
				grid.add_child(_cell(mult, false, tip))

	# team summary row
	var sum_lbl := Label.new()
	sum_lbl.text = "TEAM" if offensive else "THREAT"
	sum_lbl.add_theme_font_size_override("font_size", 10)
	sum_lbl.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	grid.add_child(sum_lbl)
	for t in DataStore.types:
		var count := 0
		var who: Array = []
		for uid in p["lineup"]:
			var a: Dictionary = _analyses[uid]
			if offensive:
				if Logic.offense_vs(a, t)["mult"] >= 2.0:
					count += 1
					who.append(a["battler"]["name"])
			else:
				if Logic.def_mult(a, t) > 1.0:
					count += 1
					who.append(a["battler"]["name"])
		grid.add_child(_team_cell(count, offensive, t, who))

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeBuilder.COL_PANEL
	sb.border_color = ThemeBuilder.COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(grid)
	return panel


func _fmt_mult(m: float) -> String:
	if m >= 4.0: return "4"
	if m >= 2.0: return "2"
	if m >= 1.0: return "1"
	if m >= 0.5: return "½"
	if m >= 0.25: return "¼"
	return "0"


func _cell(mult: float, offensive: bool, tip: String) -> Control:
	var pnl := PanelContainer.new()
	pnl.custom_minimum_size = Vector2(26, 19)
	pnl.tooltip_text = tip
	pnl.mouse_filter = Control.MOUSE_FILTER_STOP
	var good: bool = (mult >= 2.0) if offensive else (mult < 1.0)
	var bad: bool = (mult < 1.0) if offensive else (mult >= 2.0)
	var col: Color
	if mult >= 4.0 or mult <= 0.0:
		col = (ThemeBuilder.COL_GOOD if good else ThemeBuilder.COL_BAD)
	elif good:
		col = ThemeBuilder.COL_GOOD.darkened(0.25)
	elif bad:
		col = ThemeBuilder.COL_BAD.darkened(0.25)
	else:
		col = ThemeBuilder.COL_PANEL_ALT
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.28 if (good or bad) else 0.9)
	sb.border_color = Color(col, 0.7) if (good or bad) else ThemeBuilder.COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	pnl.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = _fmt_mult(mult)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", col.lightened(0.35) if (good or bad) else ThemeBuilder.COL_TEXT_DIM)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pnl.add_child(l)
	return pnl


func _team_cell(count: int, offensive: bool, t: String, who: Array) -> Control:
	var pnl := PanelContainer.new()
	pnl.custom_minimum_size = Vector2(26, 19)
	pnl.mouse_filter = Control.MOUSE_FILTER_STOP
	var col: Color
	if offensive:
		col = ThemeBuilder.COL_BAD if count == 0 else (ThemeBuilder.COL_GOOD if count >= 3 else ThemeBuilder.COL_WARN)
		pnl.tooltip_text = ("Nobody hits %s super-effectively!" % str(t).capitalize()) if count == 0 \
			else "%d hit %s super-effectively:\n%s" % [count, str(t).capitalize(), ", ".join(who)]
	else:
		col = ThemeBuilder.COL_GOOD if count == 0 else (ThemeBuilder.COL_WARN if count <= 2 else ThemeBuilder.COL_BAD)
		pnl.tooltip_text = ("No starter is weak to %s." % str(t).capitalize()) if count == 0 \
			else "%d weak to %s:\n%s" % [count, str(t).capitalize(), ", ".join(who)]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.4)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	pnl.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = str(count)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pnl.add_child(l)
	return pnl


func _make_coverage_summary() -> Control:
	var p := _preset()
	var uncovered: Array = []
	var weak_counts: Dictionary = {}
	for t in DataStore.types:
		var hits := 0
		var weak := 0
		for uid in p["lineup"]:
			var a: Dictionary = _analyses[uid]
			if Logic.offense_vs(a, t)["mult"] >= 2.0:
				hits += 1
			if Logic.def_mult(a, t) > 1.0:
				weak += 1
		if hits == 0:
			uncovered.append(str(t).capitalize())
		if weak >= 3:
			weak_counts[str(t).capitalize()] = weak
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 11)
	var bits: Array = []
	if uncovered.is_empty():
		bits.append("Every type is hit super-effectively by at least one starter.")
	else:
		bits.append("No super-effective answer to: %s." % ", ".join(uncovered))
	if weak_counts.is_empty():
		bits.append("No attack type threatens 3+ of your starters.")
	else:
		var ws: Array = []
		for k in weak_counts:
			ws.append("%s (%d weak)" % [k, weak_counts[k]])
		bits.append("Dangerous incoming types: %s." % ", ".join(ws))
	l.text = "  ".join(bits)
	l.add_theme_color_override("font_color",
		ThemeBuilder.COL_TEXT_DIM if uncovered.is_empty() and weak_counts.is_empty() else ThemeBuilder.COL_WARN)
	return l


func _make_opponent_panel() -> Control:
	var fx: Dictionary = GameState.next_player_fixture()
	if fx.is_empty():
		return null
	var we_home: bool = GameState.is_player_club(fx["home"])
	var opp: Dictionary = GameState.club(fx["away"] if we_home else fx["home"])
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 4)
	holder.add_child(_section("Scout report — next opponent: %s (%s) · %s · %s" % [
		opp.get("name", "?"), "H" if we_home else "A",
		Season.pretty_date(fx["date"]), str(fx["comp"]).capitalize()]))

	var squad: Array = opp.get("squad", []).duplicate()
	squad.sort_custom(func(x, y):
		if int(x["level"]) != int(y["level"]):
			return int(x["level"]) > int(y["level"])
		return int(x.get("condition", 100)) > int(y.get("condition", 100)))
	var mine: Array = _preset()["lineup"].map(func(u): return _analyses[u])

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	for hdr in ["THEIR LIKELY SIX", "TYPES", "OUR BEST ANSWER", "THEY THREATEN"]:
		var h := Label.new()
		h.text = hdr
		h.add_theme_font_size_override("font_size", 9)
		h.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		grid.add_child(h)
	for inst in squad.slice(0, 6):
		var oa: Dictionary = Logic.analyze(inst)
		var nm := Label.new()
		nm.text = "%s  Lv %d" % [oa["battler"]["name"], int(oa["battler"]["level"])]
		nm.add_theme_font_size_override("font_size", 11)
		nm.add_theme_color_override("font_color", Color.WHITE)
		grid.add_child(nm)

		var tp := Label.new()
		tp.text = "/".join(oa["types"].map(func(t): return str(t).to_upper().substr(0, 3)))
		tp.add_theme_font_size_override("font_size", 10)
		tp.add_theme_color_override("font_color", DataStore.type_color(oa["types"][0]).lightened(0.2))
		grid.add_child(tp)

		# our best answer: max effectiveness of any starter's damaging move vs their typing
		var best_m := 0.0
		var best_who := ""
		var best_move := ""
		for a in mine:
			for atk_t in a["attack_types"]:
				var m := DataStore.effectiveness(atk_t, oa["types"])
				if m > best_m:
					best_m = m
					best_who = a["battler"]["name"]
					best_move = a["attack_types"][atk_t]
		var ans := Label.new()
		ans.text = "%s · %s ×%s" % [best_who, best_move, _fmt_mult(best_m)] if best_who != "" else "—"
		ans.add_theme_font_size_override("font_size", 11)
		ans.add_theme_color_override("font_color",
			ThemeBuilder.COL_GOOD if best_m >= 2.0 else (ThemeBuilder.COL_TEXT if best_m >= 1.0 else ThemeBuilder.COL_BAD))
		grid.add_child(ans)

		# their biggest threat vs our six
		var thr_m := 0.0
		var thr_tgt := ""
		var thr_move := ""
		for atk_t in oa["attack_types"]:
			for a in mine:
				var m := DataStore.effectiveness(atk_t, a["types"])
				if m > thr_m:
					thr_m = m
					thr_tgt = a["battler"]["name"]
					thr_move = oa["attack_types"][atk_t]
		var thr := Label.new()
		thr.text = "%s ×%s vs %s" % [thr_move, _fmt_mult(thr_m), thr_tgt] if thr_tgt != "" else "—"
		thr.add_theme_font_size_override("font_size", 11)
		thr.add_theme_color_override("font_color",
			ThemeBuilder.COL_BAD if thr_m >= 2.0 else ThemeBuilder.COL_TEXT_DIM)
		grid.add_child(thr)

	var panel := PanelContainer.new()
	panel.add_child(grid)
	holder.add_child(panel)
	return holder


# ----------------------------------------------------------- matchday link

var _rehearsal_box: VBoxContainer
var _rehearsal_runs := 0

const REHEARSAL_TIES := 5


func _make_matchday_panel() -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 4)
	holder.add_child(_section("Matchday link — this plan commands the engine"))

	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	holder.add_child(panel)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)

	var linked := Director.installed()
	var chip := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(ThemeBuilder.COL_GOOD if linked else ThemeBuilder.COL_BAD, 0.22)
	csb.border_color = ThemeBuilder.COL_GOOD if linked else ThemeBuilder.COL_BAD
	csb.set_border_width_all(1)
	csb.set_corner_radius_all(3)
	csb.content_margin_left = 8
	csb.content_margin_right = 8
	csb.content_margin_top = 2
	csb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", csb)
	var cl := Label.new()
	cl.text = "ENGINE LINK ACTIVE" if linked else "ENGINE LINK OFFLINE"
	cl.add_theme_font_size_override("font_size", 10)
	cl.add_theme_color_override("font_color",
		(ThemeBuilder.COL_GOOD if linked else ThemeBuilder.COL_BAD).lightened(0.25))
	chip.add_child(cl)
	chip.tooltip_text = "TacticsDirector stamps this plan onto every match-day squad sheet\nand resolves instant sims with it (deterministic per fixture)."
	head.add_child(chip)

	var what := Label.new()
	what.text = "Slot order = battle order · slot 1 opens · instructions drive every AI turn"
	what.add_theme_font_size_override("font_size", 10)
	what.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	head.add_child(what)

	var fx: Dictionary = GameState.next_player_fixture()
	if fx.is_empty():
		var none := Label.new()
		none.text = "No upcoming fixture to rehearse against."
		none.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		none.add_theme_font_size_override("font_size", 11)
		v.add_child(none)
		return holder

	var opp_id: String = fx["away"] if GameState.is_player_club(fx["home"]) else fx["home"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var rl := Label.new()
	rl.text = "REHEARSAL vs %s · %s" % [GameState.club(opp_id).get("name", "?"), Season.pretty_date(fx["date"])]
	rl.add_theme_font_size_override("font_size", 11)
	rl.add_theme_color_override("font_color", Color.WHITE)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rl)
	var rerun := Button.new()
	rerun.text = "Re-run rehearsal"
	rerun.tooltip_text = "Plays %d fresh full-strength best-of-3 ties with this plan (unsaved edits included)\nagainst the opponent's likely six, on new seeds." % REHEARSAL_TIES
	rerun.pressed.connect(func():
		_rehearsal_runs += 1
		_run_rehearsal(fx))
	row.add_child(rerun)

	_rehearsal_box = VBoxContainer.new()
	_rehearsal_box.add_theme_constant_override("separation", 2)
	v.add_child(_rehearsal_box)
	var wait := Label.new()
	wait.text = "Rehearsing…"
	wait.add_theme_font_size_override("font_size", 11)
	wait.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_rehearsal_box.add_child(wait)
	_run_rehearsal.call_deferred(fx)
	return holder


## Plays REHEARSAL_TIES real best-of-3 ties (TacticsBrain commanding our side
## with the CURRENT, possibly unsaved plan) against the next opponent and
## summarises the evidence. Uses seeds disjoint from the real fixture seed so
## the rehearsal never spoils the actual result.
func _run_rehearsal(fx: Dictionary) -> void:
	if _rehearsal_box == null or not is_instance_valid(_rehearsal_box):
		return
	for c in _rehearsal_box.get_children():
		c.queue_free()
	var tac := Logic.plan_from_preset(_preset())
	var we_home: bool = GameState.is_player_club(fx["home"])
	var home: Dictionary = GameState.club(fx["home"])
	var away: Dictionary = GameState.club(fx["away"])
	var our_side := 0 if we_home else 1
	var wins := 0
	var scorelines: Array = []
	var our_faints := 0
	var their_faints := 0
	var faint_by := {}
	var ties := 0
	for k in REHEARSAL_TIES:
		var seed_v: int = GameState.career_seed + absi(str(fx["id"]).hash()) % 1000000 \
			+ 51427 + (k + _rehearsal_runs * REHEARSAL_TIES) * 104729
		var r: Dictionary = Brain.run_fixture(home, away, our_side, tac, seed_v)
		if r.is_empty():
			continue
		ties += 1
		var us: int = r["score_home"] if we_home else r["score_away"]
		var them: int = r["score_away"] if we_home else r["score_home"]
		if us > them:
			wins += 1
		scorelines.append("%d-%d" % [us, them])
		our_faints += int(r["our_faints"])
		their_faints += int(r["their_faints"])
		for nm in r["faint_by"]:
			faint_by[nm] = int(faint_by.get(nm, 0)) + int(r["faint_by"][nm])
	if ties == 0:
		var err := Label.new()
		err.text = "Rehearsal unavailable (no valid teams)."
		err.add_theme_color_override("font_color", ThemeBuilder.COL_BAD)
		_rehearsal_box.add_child(err)
		return

	var head := Label.new()
	head.text = "Won %d of %d ties  (%s)" % [wins, ties, ", ".join(scorelines)]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color",
		ThemeBuilder.COL_GOOD if wins * 2 > ties else (ThemeBuilder.COL_WARN if wins * 2 == ties else ThemeBuilder.COL_BAD))
	_rehearsal_box.add_child(head)

	var worst := ""
	var worst_n := 0
	for nm in faint_by:
		if int(faint_by[nm]) > worst_n:
			worst_n = int(faint_by[nm])
			worst = str(nm)
	var det := Label.new()
	det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_theme_font_size_override("font_size", 10)
	det.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	var bits := ["Battlers lost per tie: us %.1f, them %.1f." %
		[float(our_faints) / ties, float(their_faints) / ties]]
	if worst != "":
		bits.append("Most exposed: %s (down %d times)." % [worst, worst_n])
	bits.append("Every turn chosen from this plan's instructions — edit a slider and re-run.")
	det.text = "  ".join(bits)
	_rehearsal_box.add_child(det)


# ----------------------------------------------------------------- right

func _rebuild_right() -> void:
	for c in _right_box.get_children():
		c.queue_free()
	_right_box.add_child(_section("Team instructions"))
	_right_box.add_child(_make_instructions())
	_right_box.add_child(_section("Role guide"))
	_guide_panel = VBoxContainer.new()
	_guide_panel.add_theme_constant_override("separation", 4)
	var gp := PanelContainer.new()
	gp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gp.add_child(_guide_panel)
	_right_box.add_child(gp)
	_refresh_role_guide()


func _make_instructions() -> Control:
	var instr: Dictionary = _preset()["instructions"]
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	# --- aggression
	var ag_val := Label.new()
	v.add_child(_instr_title("Aggression", ag_val))
	var ag := HSlider.new()
	ag.min_value = 0
	ag.max_value = 4
	ag.step = 1
	ag.tick_count = 5
	ag.ticks_on_borders = true
	ag.value = int(instr["aggression"])
	ag_val.text = Logic.AGGRESSION_LABELS[int(instr["aggression"])]
	ag.value_changed.connect(func(val):
		instr["aggression"] = int(val)
		ag_val.text = Logic.AGGRESSION_LABELS[int(val)]
		_queue_save())
	v.add_child(ag)
	v.add_child(_instr_desc("Aggressive sides stay in and trade blows; cautious sides pivot out of even matchups."))

	# --- switch threshold
	var sw_val := Label.new()
	v.add_child(_instr_title("Switch-out threshold", sw_val))
	var sw := HSlider.new()
	sw.min_value = 0
	sw.max_value = 60
	sw.step = 5
	sw.value = int(instr["switch_threshold"])
	sw_val.text = "%d%% HP" % int(instr["switch_threshold"])
	sw.value_changed.connect(func(val):
		instr["switch_threshold"] = int(val)
		sw_val.text = "%d%% HP" % int(val)
		_queue_save())
	v.add_child(sw)
	v.add_child(_instr_desc("Battlers look for an exit once their HP drops below this line."))

	# --- status priority
	var sp_val := Label.new()
	v.add_child(_instr_title("Status-move priority", sp_val))
	var sp := HSlider.new()
	sp.min_value = 0
	sp.max_value = 2
	sp.step = 1
	sp.tick_count = 3
	sp.ticks_on_borders = true
	sp.value = int(instr["status_priority"])
	sp_val.text = Logic.STATUS_LABELS[int(instr["status_priority"])]
	sp.value_changed.connect(func(val):
		instr["status_priority"] = int(val)
		sp_val.text = Logic.STATUS_LABELS[int(val)]
		_queue_save())
	v.add_child(sp)
	v.add_child(_instr_desc("High: fish for sleep/paralysis early. Low: just click the strongest attack."))

	v.add_child(HSeparator.new())

	for spec in [
			["protect_lead", "Protect the lead",
				"Pull the Lead out of losing matchups instead of sacrificing it."],
			["preserve_last", "Preserve the last battler",
				"Never leave your final battler in a hopeless matchup — play for the turn cap."],
			["revenge_switch", "Revenge switching",
				"After a faint, send the Revenge Killer (or fastest battler) rather than next in order."]]:
		var cb := CheckButton.new()
		cb.text = spec[1]
		cb.button_pressed = bool(instr[spec[0]])
		cb.add_theme_font_size_override("font_size", 13)
		cb.tooltip_text = spec[2]
		var key: String = spec[0]
		cb.toggled.connect(func(on):
			instr[key] = on
			_queue_save())
		v.add_child(cb)
		v.add_child(_instr_desc(spec[2]))
	return panel


func _instr_title(text: String, value_lbl: Label) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	value_lbl.add_theme_font_size_override("font_size", 12)
	value_lbl.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	h.add_child(value_lbl)
	return h


func _instr_desc(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	return l


func _refresh_role_guide() -> void:
	if _guide_panel == null or not is_instance_valid(_guide_panel):
		return
	for c in _guide_panel.get_children():
		c.queue_free()
	var p := _preset()
	var uid := _guide_uid
	if uid == "" or not _analyses.has(uid):
		uid = p["lineup"][0] if not p["lineup"].is_empty() else ""
	if uid == "":
		return
	var a: Dictionary = _analyses[uid]
	var role: String = p["roles"].get(uid, "pivot")
	var res: Dictionary = Logic.role_score(role, a)
	var b: Array = Logic.band(res["score"])

	var title := Label.new()
	title.text = "%s — %s" % [a["battler"]["name"], Logic.ROLES[role]["name"]]
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color.WHITE)
	_guide_panel.add_child(title)

	var fit := Label.new()
	fit.text = "%s (%d/100)" % [b[0], res["score"]]
	fit.add_theme_font_size_override("font_size", 12)
	fit.add_theme_color_override("font_color", b[1])
	_guide_panel.add_child(fit)

	var desc := Label.new()
	desc.text = Logic.ROLES[role]["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	_guide_panel.add_child(desc)

	var wants := Label.new()
	wants.text = "Key attributes: %s" % Logic.ROLES[role]["wants"]
	wants.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wants.add_theme_font_size_override("font_size", 10)
	wants.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_guide_panel.add_child(wants)

	_guide_panel.add_child(HSeparator.new())
	var why_hdr := Label.new()
	why_hdr.text = "WHY THIS RATING"
	why_hdr.add_theme_font_size_override("font_size", 10)
	why_hdr.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_guide_panel.add_child(why_hdr)
	for w in res["why"]:
		var wl := Label.new()
		wl.text = "· %s" % w
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wl.add_theme_font_size_override("font_size", 11)
		wl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
		_guide_panel.add_child(wl)

	_guide_panel.add_child(HSeparator.new())
	var alt_hdr := Label.new()
	alt_hdr.text = "ALL ROLES FOR %s" % str(a["battler"]["name"]).to_upper()
	alt_hdr.add_theme_font_size_override("font_size", 10)
	alt_hdr.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_guide_panel.add_child(alt_hdr)
	for rid in Logic.ROLE_ORDER:
		var sc: int = Logic.role_score(rid, a)["score"]
		var bb: Array = Logic.band(sc)
		var h := HBoxContainer.new()
		var rn := Label.new()
		rn.text = Logic.ROLES[rid]["name"]
		rn.add_theme_font_size_override("font_size", 11)
		rn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rn.add_theme_color_override("font_color",
			Color.WHITE if rid == role else ThemeBuilder.COL_TEXT)
		h.add_child(rn)
		var rs := Label.new()
		rs.text = "%d  %s" % [sc, bb[0]]
		rs.add_theme_font_size_override("font_size", 11)
		rs.add_theme_color_override("font_color", bb[1])
		h.add_child(rs)
		_guide_panel.add_child(h)


# ================================================================= presets

func _on_preset_pick(idx: int) -> void:
	_state["active"] = _state["presets"][idx]["name"]
	_selected_uid = ""
	_guide_uid = ""
	_queue_save()
	_rebuild_all()


func _unique_name(base: String) -> String:
	var names: Array = _state["presets"].map(func(p): return p["name"])
	if not names.has(base):
		return base
	var n := 2
	while names.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


func _on_new_preset() -> void:
	var cur := _preset()
	var np := {
		"name": _unique_name("New Plan"),
		"lineup": cur["lineup"].duplicate(),
		"bench": cur["bench"].duplicate(),
		"roles": cur["roles"].duplicate(),
		"instructions": cur["instructions"].duplicate(),
	}
	_state["presets"].append(np)
	_state["active"] = np["name"]
	_queue_save()
	_rebuild_all()
	_on_rename_preset()


func _on_rename_preset() -> void:
	_rename_edit.text = _state["active"]
	_rename_dialog.popup_centered()
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _do_rename() -> void:
	var new_name := _rename_edit.text.strip_edges()
	if new_name == "" or new_name == _state["active"]:
		return
	new_name = _unique_name(new_name)
	_preset()["name"] = new_name
	_state["active"] = new_name
	_queue_save()
	_rebuild_all()


func _on_delete_preset() -> void:
	if _state["presets"].size() <= 1:
		_saved_lbl.text = "Cannot delete the only tactic"
		_saved_lbl.add_theme_color_override("font_color", ThemeBuilder.COL_BAD)
		return
	_delete_dialog.dialog_text = "Delete tactic \"%s\"?" % _state["active"]
	_delete_dialog.popup_centered()


func _do_delete() -> void:
	_state["presets"] = _state["presets"].filter(func(p): return p["name"] != _state["active"])
	_state["active"] = _state["presets"][0]["name"]
	_queue_save()
	_rebuild_all()


func _on_auto_pick() -> void:
	var fresh := Logic.default_preset(_state["active"], GameState.player_club().get("squad", []))
	var p := _preset()
	p["lineup"] = fresh["lineup"]
	p["bench"] = fresh["bench"]
	p["roles"] = fresh["roles"]
	_selected_uid = ""
	_queue_save()
	_rebuild_all()


func _build_dialogs() -> void:
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename tactic"
	_rename_dialog.ok_button_text = "Rename"
	_rename_edit = LineEdit.new()
	_rename_edit.custom_minimum_size = Vector2(280, 34)
	_rename_edit.placeholder_text = "Tactic name"
	_rename_dialog.add_child(_rename_edit)
	_rename_dialog.register_text_enter(_rename_edit)
	_rename_dialog.confirmed.connect(_do_rename)
	add_child(_rename_dialog)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Delete tactic"
	_delete_dialog.ok_button_text = "Delete"
	_delete_dialog.confirmed.connect(_do_delete)
	add_child(_delete_dialog)
