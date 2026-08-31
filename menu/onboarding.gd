extends Control
## NEW-CAREER ONBOARDING (menu piece) — FM-style multi-step wizard:
##   1. Manager identity — name + optional nickname (flows into the world:
##      board mails, press and mind-games all render the player club's
##      "manager" field, which MenuFlow stamps with this name).
##   2. Club selection — league tabs + club rows + detail pane (club_step.gd).
##   3. Confirmation summary -> start (warns before overwriting a save).
##
## Used as a full-screen overlay by BOTH the title screen (then the title
## swaps to the shell scene) and the in-game shell ("New Career" menu item and
## the game-over "start fresh" door). Emits career_created (career is already
## started + saved) or cancelled; frees itself in both cases.

signal career_created
signal cancelled

const ClubStep := preload("res://menu/club_step.gd")
const PANEL_W := 1240.0
const PANEL_H := 800.0

var _font_bold: Font
var _font_semibold: Font
var _font_header: Font

var _step := 0
var _selected: Dictionary = {}      # club summary from club_step

var _content: MarginContainer
var _identity_panel: Control = null
var _club_panel: Control = null
var _name_edit: LineEdit
var _nick_edit: LineEdit
var _back_btn: Button
var _next_btn: Button
var _step_chips: Array = []
var _overwrite_dialog: ConfirmationDialog


func setup(bold: Font, semibold: Font, header: Font) -> void:
	_font_bold = bold
	_font_semibold = semibold
	_font_header = header


func _notification(what: int) -> void:
	# step panels live detached while another step is shown — free them with
	# the wizard so no orphan Controls leak on cancel/start
	if what == NOTIFICATION_PREDELETE:
		for p in [_identity_panel, _club_panel]:
			if p != null and is_instance_valid(p) and not p.is_inside_tree():
				p.free()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if theme == null:
		theme = ThemeBuilder.build()

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	panel.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_ACCENT_DIM, 8, 0, 0))
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)
	root.add_child(_build_header())
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_content.add_theme_constant_override(m, 20)
	root.add_child(_content)
	root.add_child(_build_footer())

	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.title = tr("Overwrite saved career?")
	_overwrite_dialog.ok_button_text = tr("Overwrite and start")
	_overwrite_dialog.confirmed.connect(_do_start)
	add_child(_overwrite_dialog)

	_show_step(0)


func _build_header() -> Control:
	var wrap := PanelContainer.new()
	var sb := ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 0, 22, 14)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	wrap.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = tr("START A NEW CAREER")
	title.add_theme_font_override("font", _font_header)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(title)
	var sub := Label.new()
	sub.text = tr("Create your manager, choose your club, meet the board's expectations.")
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	col.add_child(sub)
	row.add_child(col)
	# step chips: 1 MANAGER · 2 CLUB · 3 CONFIRM
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 3:
		var chip := PanelContainer.new()
		var lbl := Label.new()
		lbl.text = "%d · %s" % [i + 1, [tr("MANAGER"), tr("CLUB"), tr("CONFIRM")][i]]
		lbl.add_theme_font_override("font", _font_header)
		lbl.add_theme_font_size_override("font_size", 11)
		chip.add_child(lbl)
		chips.add_child(chip)
		_step_chips.append([chip, lbl])
	row.add_child(chips)
	wrap.add_child(row)
	return wrap


func _build_footer() -> Control:
	var wrap := PanelContainer.new()
	var sb := ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 0, 18, 12)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	wrap.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var cancel := Button.new()
	cancel.text = tr("Cancel")
	cancel.custom_minimum_size = Vector2(110, 40)
	cancel.pressed.connect(func():
		cancelled.emit()
		queue_free())
	row.add_child(cancel)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_back_btn = Button.new()
	_back_btn.text = tr("Back")
	_back_btn.custom_minimum_size = Vector2(120, 40)
	_back_btn.pressed.connect(func(): _show_step(_step - 1))
	row.add_child(_back_btn)
	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(300, 40)
	_next_btn.add_theme_font_override("font", _font_bold)
	_next_btn.add_theme_font_size_override("font_size", 15)
	_next_btn.pressed.connect(_on_next)
	row.add_child(_next_btn)
	wrap.add_child(row)
	return wrap


# ------------------------------------------------------------------ steps

func _show_step(i: int) -> void:
	_step = clampi(i, 0, 2)
	for child in _content.get_children():
		_content.remove_child(child)
		if child != _identity_panel and child != _club_panel:
			child.queue_free()
	match _step:
		0:
			if _identity_panel == null:
				_identity_panel = _build_identity()
			_content.add_child(_identity_panel)
			_name_edit.grab_focus.call_deferred()
		1:
			if _club_panel == null:
				_club_panel = ClubStep.new()
				_club_panel.setup(_font_bold, _font_semibold, _font_header)
				_club_panel.club_selected.connect(func(s: Dictionary):
					_selected = s
					_refresh_footer())
				_club_panel.club_confirmed.connect(func():
					if not _selected.is_empty():
						_show_step(2))
			_content.add_child(_club_panel)
		2:
			_content.add_child(_build_summary())
	_refresh_footer()
	_refresh_chips()


func _refresh_chips() -> void:
	for i in _step_chips.size():
		var chip: PanelContainer = _step_chips[i][0]
		var lbl: Label = _step_chips[i][1]
		var active: bool = i == _step
		var done: bool = i < _step
		chip.add_theme_stylebox_override("panel", ThemeBuilder._flat(
			ThemeBuilder.COL_ACCENT_DIM if active else ThemeBuilder.COL_PANEL,
			ThemeBuilder.COL_ACCENT if active else ThemeBuilder.COL_BORDER, 5, 12, 5))
		lbl.add_theme_color_override("font_color",
			Color.WHITE if active else (ThemeBuilder.COL_ACCENT if done else ThemeBuilder.COL_TEXT_DIM))


func _refresh_footer() -> void:
	_back_btn.visible = _step > 0
	match _step:
		0:
			_next_btn.text = tr("Next: choose your club")
			_next_btn.disabled = _manager_name() == ""
		1:
			_next_btn.text = tr("Next: summary")
			_next_btn.disabled = _selected.is_empty()
		2:
			_next_btn.text = tr("Start career at %s") % str(_selected.get("name", ""))
			_next_btn.disabled = false


func _on_next() -> void:
	if _step < 2:
		_show_step(_step + 1)
		return
	# step 3: start — warn before overwriting an existing save (FM-style)
	if MenuFlow.has_save():
		var s := MenuFlow.save_summary()
		_overwrite_dialog.dialog_text = "%s\n%s" % [
			tr("A saved career already exists: %s · %s — %s, %s.") % [str(s.get("club", "?")),
				str(s.get("manager", "?")), I18n.pretty_date(str(s.get("date", ""))),
				tr("Season %d") % int(s.get("season", 1))],
			tr("Starting a new career will permanently overwrite it.")]
		_overwrite_dialog.popup_centered()
		return
	_do_start()


func _do_start() -> void:
	if _selected.is_empty() or _manager_name() == "":
		return
	MenuFlow.start_career(str(_selected["id"]), _manager_name(), _nick_edit.text)
	AudioManager.play("confirm")
	career_created.emit()
	queue_free()


func _manager_name() -> String:
	return _name_edit.text.strip_edges() if _name_edit != null else ""


# ------------------------------------------------------------------ step 1: identity

func _build_identity() -> Control:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 560
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var head := Label.new()
	head.text = tr("WHO IS IN THE DUGOUT?")
	head.add_theme_font_override("font", _font_header)
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(head)
	var sub := Label.new()
	sub.text = tr("The board, the press and rival managers will address you by this name.")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	col.add_child(sub)
	col.add_child(_vgap(14))

	col.add_child(_field_label(tr("Manager name")))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("e.g. Alex Serrano")
	_name_edit.max_length = 40
	_name_edit.custom_minimum_size.y = 42
	_name_edit.text_changed.connect(func(_t): _refresh_footer())
	_name_edit.text_submitted.connect(func(_t): _on_next())
	col.add_child(_name_edit)
	col.add_child(_vgap(8))

	col.add_child(_field_label(tr("Nickname (optional)")))
	_nick_edit = LineEdit.new()
	_nick_edit.placeholder_text = tr("What the fans chant from the stands")
	_nick_edit.max_length = 24
	_nick_edit.custom_minimum_size.y = 42
	_nick_edit.text_submitted.connect(func(_t): _on_next())
	col.add_child(_nick_edit)
	return center


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_semibold)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	return l


func _vgap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	return c


# ------------------------------------------------------------------ step 3: summary

func _build_summary() -> Control:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(680, 0)
	card.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 8, 26, 22))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	card.add_child(col)

	var head := Label.new()
	head.text = tr("CONTRACT SUMMARY")
	head.add_theme_font_override("font", _font_header)
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(head)
	col.add_child(_hline())

	# who
	var who := Label.new()
	var nick := _nick_edit.text.strip_edges()
	who.text = (tr("%s “%s” — manager") % [_manager_name(), nick]) if nick != "" \
		else (tr("%s — manager") % _manager_name())
	who.add_theme_font_override("font", _font_bold)
	who.add_theme_font_size_override("font_size", 17)
	who.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(who)

	# where
	var club_row := HBoxContainer.new()
	club_row.add_theme_constant_override("separation", 12)
	if _club_panel != null:
		club_row.add_child(_club_panel._crest(_selected, 46))
	var club_col := VBoxContainer.new()
	club_col.alignment = BoxContainer.ALIGNMENT_CENTER
	club_col.add_theme_constant_override("separation", 0)
	var cname := Label.new()
	cname.text = str(_selected.get("name", ""))
	cname.add_theme_font_override("font", _font_bold)
	cname.add_theme_font_size_override("font_size", 16)
	cname.add_theme_color_override("font_color", Color.WHITE)
	club_col.add_child(cname)
	var cleague := Label.new()
	cleague.text = "%s · %s" % [tr(_club_panel.league_name_of(str(_selected.get("league", "")))),
		tr("season starts %s") % I18n.pretty_date(_club_panel.season_start)]
	cleague.add_theme_font_size_override("font_size", 11)
	cleague.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	club_col.add_child(cleague)
	club_row.add_child(club_col)
	col.add_child(club_row)
	col.add_child(_hline())

	var exp := Label.new()
	exp.text = tr("\"%s expect the club to %s and to %s.\"") % [str(_selected.get("name", "")),
		tr(_club_panel.expectation_key(int(_selected.get("expected", 8)))),
		tr(_club_panel.cup_expectation_key(int(_selected.get("expected", 8))))]
	exp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	exp.add_theme_font_override("font", _font_bold)
	exp.add_theme_font_size_override("font_size", 13)
	exp.add_theme_color_override("font_color", Color("f2f4fb"))
	col.add_child(exp)

	var stars_n := clampi(int(_selected.get("stars", 3)), 1, 5)
	var facts := Label.new()
	facts.text = "%s   ·   %s   ·   %s" % [
		"★".repeat(stars_n) + "☆".repeat(5 - stars_n),
		tr("Bank: P$ %s") % I18n.number(int(_selected.get("balance", 0))),
		tr("Wages: P$ %s/w") % I18n.number(int(_selected.get("wage_budget", 0)))]
	facts.add_theme_font_size_override("font_size", 13)
	facts.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	col.add_child(facts)

	if MenuFlow.has_save():
		col.add_child(_hline())
		var warn := Label.new()
		var s := MenuFlow.save_summary()
		warn.text = tr("⚠ Starting this career overwrites your saved one (%s, %s).") \
			% [str(s.get("club", "?")), I18n.pretty_date(str(s.get("date", "")))]
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", 12)
		warn.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
		col.add_child(warn)
	return center


func _hline() -> Control:
	var line := ColorRect.new()
	line.color = ThemeBuilder.COL_BORDER
	line.custom_minimum_size.y = 1
	return line


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancelled.emit()
		queue_free()
		accept_event()
