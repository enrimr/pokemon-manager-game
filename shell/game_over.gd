extends Control
## Game-over overlay (shell-owned): the board has SACKED the manager.
## A proper FM career moment — the dismissal, the career summary (seasons,
## honours, record), and the way forward: offers from lesser clubs
## (GameState.accept_job_offer) or a fresh career. Opened by the shell when
## GameState.game_over fires or a loaded save carries world.meta.game_over.

signal offer_accepted(club_id: String)
signal start_fresh

const TB := preload("res://shared/theme/theme_builder.gd")
const GOLD := Color("e8c35a")
const PANEL_W := 940.0

var _font_bold: Font
var _font_header: Font
var _info: Dictionary = {}
var _note: Label


func setup(bold: Font, _semibold: Font, header: Font) -> void:
	_font_bold = bold
	_font_header = header


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # modal: nothing behind is clickable
	_info = GameState.game_over_info()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	sb.border_color = TB.COL_BAD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_build_header(box)
	_build_record(box)
	_build_offers(box)


func _lbl(text: String, size: int = 14, color: Color = TB.COL_TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:   # wrapped labels need a real width or containers collapse them
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(PANEL_W - 60.0, 0)
	return l


func _build_header(box: VBoxContainer) -> void:
	var kicker := _lbl("THE BOARDROOM HAS SPOKEN", 12, TB.COL_TEXT_DIM)
	if _font_header != null:
		kicker.add_theme_font_override("font", _font_header)
	box.add_child(kicker)
	var title := _lbl("SACKED", 34, TB.COL_BAD)
	if _font_bold != null:
		title.add_theme_font_override("font", _font_bold)
	box.add_child(title)
	box.add_child(_lbl(tr("%s have terminated your contract: %s.") % [
		str(_info.get("club", tr("The club"))), tr(str(_info.get("reason", "results were not good enough")))],
		15, TB.COL_TEXT, true))
	box.add_child(HSeparator.new())


## Career record: one row per season stint + totals + honours roll.
func _build_record(box: VBoxContainer) -> void:
	var summary: Dictionary = _info.get("summary", {})
	box.add_child(_lbl("YOUR CAREER", 12, TB.COL_TEXT_DIM))
	var hist: Array = GameState.manager_history()
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 2)
	for h in ["Season", "Club", "League pos", "Points", "Record (W-L)", "Cup"]:
		grid.add_child(_lbl(tr(h), 12, TB.COL_TEXT_DIM))
	if hist.size() > 10:   # long careers: the recent decade tells the story
		hist = hist.slice(hist.size() - 10)
	for st in hist:
		grid.add_child(_lbl("S%d" % int(st.get("season", 0)), 13))
		grid.add_child(_lbl(str(st.get("club", "?")), 13))
		var pos := int(st.get("pos", 0))
		grid.add_child(_lbl(I18n.ordinal(pos) if pos > 0 else "—", 13,
			TB.COL_GOOD if pos > 0 and pos <= 4 else (TB.COL_BAD if pos >= 14 else TB.COL_TEXT)))
		grid.add_child(_lbl(str(int(st.get("points", 0))), 13))
		grid.add_child(_lbl("%d-%d" % [int(st.get("wins", 0)), int(st.get("losses", 0))], 13))
		grid.add_child(_lbl(str(st.get("cup", "—")), 13, TB.COL_TEXT_DIM))
	box.add_child(grid)
	var totals := _lbl(tr("%d season%s managed   ·   %d-%d in matches   ·   best finish %s") % [
		int(summary.get("seasons", hist.size())),
		"" if int(summary.get("seasons", hist.size())) == 1 else "s",
		int(summary.get("wins", 0)), int(summary.get("losses", 0)),
		I18n.ordinal(int(summary.get("best_pos", 0))) if int(summary.get("best_pos", 0)) > 0 else "—"],
		14, TB.COL_TEXT)
	box.add_child(totals)
	var honours: Array = summary.get("honours", [])
	box.add_child(_lbl(tr("Honours: %s") % (", ".join(honours.map(func(h): return tr(str(h)))) if not honours.is_empty()
		else tr("none — perhaps that was the problem")), 14,
		GOLD if not honours.is_empty() else TB.COL_TEXT_DIM, true))
	box.add_child(HSeparator.new())


static func _ord(n: int) -> String:
	return I18n.ordinal(n)


## The way forward: offers from lesser clubs, or a clean slate.
func _build_offers(box: VBoxContainer) -> void:
	var offers: Array = _info.get("offers", [])
	box.add_child(_lbl("WHAT NEXT?", 12, TB.COL_TEXT_DIM))
	if offers.is_empty():
		box.add_child(_lbl(tr("No club is calling. Time for a clean slate."), 14, TB.COL_TEXT_DIM))
	elif offers.size() == 1:
		box.add_child(_lbl(tr("Word travels fast — a club lower down the pyramid wants to talk:"), 14))
	else:
		box.add_child(_lbl(tr("Word travels fast — %d clubs lower down the pyramid want to talk:") % offers.size(), 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for o in offers:
		row.add_child(_offer_card(o))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	box.add_child(foot)
	var fresh := Button.new()
	fresh.text = "Start a fresh career"
	fresh.custom_minimum_size = Vector2(200, 40)
	fresh.pressed.connect(func(): start_fresh.emit())
	foot.add_child(fresh)
	_note = _lbl("Accepting an offer keeps this world — your history, rivals and record all carry on.",
		12, TB.COL_TEXT_DIM)
	_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_note)


func _offer_card(o: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL.lightened(0.04)
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	v.add_child(_lbl(str(o.get("name", "?")), 17))
	v.add_child(_lbl(tr("%s   ·   reputation %d/20") % [
		tr(str(o.get("league", ""))), int(o.get("reputation", 0))], 12, TB.COL_TEXT_DIM))
	var btn := Button.new()
	btn.text = "Take over"
	btn.custom_minimum_size = Vector2(0, 34)
	btn.pressed.connect(func(): offer_accepted.emit(str(o.get("club_id", ""))))
	v.add_child(btn)
	return card
