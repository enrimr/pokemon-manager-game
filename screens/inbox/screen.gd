extends Control
const EvoSvc := preload("res://shared/sim/services/evolution.gd")
## Inbox screen — FM-style two-pane inbox + Board & Finances tab.
## Owned by the "inbox" piece. Reads/annotates GameState.inbox, renders rich
## bodies via report_gen.gd, generates deterministic news via news_gen.gd.

const NewsGen := preload("res://screens/inbox/news_gen.gd")
const ReportGen := preload("res://screens/inbox/report_gen.gd")
const BoardRoom := preload("res://screens/inbox/board_room.gd")
const Economy := preload("res://screens/inbox/economy.gd")
const PeopleGen := preload("res://screens/inbox/people_gen.gd")
const EvolutionGen := preload("res://screens/inbox/evolution_gen.gd")

var news: RefCounted
var reports: RefCounted
var board: RefCounted            # board_room.gd — live board request system
var economy: RefCounted          # economy.gd — real operating cash flow
var people: RefCounted           # people_gen.gd — people & media layer
var _bold: FontVariation

var _tab := 0                    # 0 = inbox, 1 = board & finances
var _filter := "all"
var _unread_only := false
var _selected: Dictionary = {}
var _suspend := false
var _action_note := ""           # inline result of the last offer decision
var _action_note_col: Color = ThemeBuilder.COL_TEXT
var _board_note := ""            # inline result of the last board request
var _board_note_col: Color = ThemeBuilder.COL_TEXT

var _tab_inbox: Button
var _tab_board: Button
var _summary_lbl: Label
var _pane_holder: MarginContainer
var _inbox_pane: Control
var _board_pane: Control
var _list_box: VBoxContainer
var _list_scroll: ScrollContainer
var _filter_btns: Dictionary = {}
var _unread_btn: Button
var _read_pane: VBoxContainer
var _row_refs: Array = []        # [{msg, btn, subject_lbl, dot}]


func _ready() -> void:
	news = NewsGen.new()
	economy = Economy.new(news)
	board = BoardRoom.new(news)
	board.economy = economy
	people = PeopleGen.new(news)
	reports = ReportGen.new(news)
	reports.board = board
	reports.economy = economy
	reports.people = people
	reports.evolutions = EvolutionGen.new()
	_bold = FontVariation.new()
	_bold.base_font = ThemeDB.fallback_font
	_bold.variation_embolden = 0.75
	_build_ui()
	_refresh_data()
	_rebuild_all()
	GameState.inbox_updated.connect(_on_inbox_updated)
	# generate news day-by-day while the shell's Continue advances the clock,
	# so urgent items (offers, pre-match briefings) can stop the advance loop
	GameState.date_changed.connect(_on_date_changed)
	# live transfer market: offer stages change from the Transfer Centre too
	var mkt: RefCounted = news.market()
	if mkt != null and mkt.has_signal("market_updated"):
		mkt.market_updated.connect(_on_market_updated)


func _on_market_updated() -> void:
	if _suspend or not is_inside_tree():
		return
	_suspend = true
	news.sync_market_offers()
	_suspend = false
	_rebuild_all()


func _on_date_changed(_d: String) -> void:
	if is_inside_tree():
		_refresh_data()


func on_show() -> void:
	_refresh_data()
	_rebuild_all()


func _on_inbox_updated() -> void:
	if _suspend or not is_inside_tree():
		return
	_rebuild_all()


func _refresh_data() -> void:
	_suspend = true
	news.enrich_existing()
	news.generate()
	people.generate() # rival mind-games, press pieces, coach notes, awards
	economy.tick() # defensive catch-up (GameState settles daily; this renders the ledger)
	board.tick()   # answer any board requests whose deliberation is due
	_suspend = false


# ================================================================= UI BUILD

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# ---- sub-navigation tab bar
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)

	_tab_inbox = _tab_button("Inbox")
	_tab_inbox.pressed.connect(func(): _set_tab(0))
	tabs.add_child(_tab_inbox)
	_tab_board = _tab_button("Board & Finances")
	_tab_board.pressed.connect(func(): _set_tab(1))
	tabs.add_child(_tab_board)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(sp)
	_summary_lbl = Label.new()
	_summary_lbl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_summary_lbl.add_theme_font_size_override("font_size", 13)
	tabs.add_child(_summary_lbl)

	_pane_holder = MarginContainer.new()
	_pane_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_pane_holder)

	_inbox_pane = _build_inbox_pane()
	_pane_holder.add_child(_inbox_pane)
	_board_pane = VBoxContainer.new()
	_pane_holder.add_child(_board_pane)
	_board_pane.visible = false


func _tab_button(txt: String) -> Button:
	var b := Button.new()
	b.text = "  %s  " % tr(txt)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_override("font", _bold)
	return b


func _set_tab(i: int) -> void:
	_tab = i
	_tab_inbox.button_pressed = i == 0
	_tab_board.button_pressed = i == 1
	_inbox_pane.visible = i == 0
	_board_pane.visible = i == 1
	if i == 1:
		_rebuild_board()


# ---------------------------------------------------------- inbox pane

func _build_inbox_pane() -> Control:
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)

	# ---- LEFT: filters + message list
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 470
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)

	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 4)
	left.add_child(frow)
	for cat in ["all", "match", "cup", "media", "staff", "scout", "transfer", "board"]:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_filter.bind(cat))
		frow.add_child(b)
		_filter_btns[cat] = b

	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 6)
	left.add_child(trow)
	_unread_btn = Button.new()
	_unread_btn.toggle_mode = true
	_unread_btn.text = "Unread only"
	_unread_btn.custom_minimum_size = Vector2(0, 26)
	_unread_btn.add_theme_font_size_override("font_size", 12)
	_unread_btn.toggled.connect(func(on): _unread_only = on; _rebuild_list())
	trow.add_child(_unread_btn)
	var tsp := Control.new()
	tsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tsp)
	var mar := Button.new()
	mar.text = "Mark All Read"
	mar.custom_minimum_size = Vector2(0, 26)
	mar.add_theme_font_size_override("font_size", 12)
	mar.pressed.connect(_mark_all_read)
	trow.add_child(mar)
	var dr := Button.new()
	dr.text = "Delete Read"
	dr.custom_minimum_size = Vector2(0, 26)
	dr.add_theme_font_size_override("font_size", 12)
	dr.pressed.connect(_delete_read)
	trow.add_child(dr)

	var list_panel := PanelContainer.new()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_BORDER, 0, 0, 0))
	left.add_child(list_panel)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(_list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 0)
	_list_scroll.add_child(_list_box)

	# ---- RIGHT: reading pane
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_BORDER, 0, 16, 14))
	split.add_child(right_panel)
	_read_pane = VBoxContainer.new()
	_read_pane.add_theme_constant_override("separation", 10)
	right_panel.add_child(_read_pane)
	return split


func _on_filter(cat: String) -> void:
	_filter = cat
	_rebuild_list()


# ================================================================= REBUILD

func _rebuild_all() -> void:
	_rebuild_list()
	_update_summary()
	if _tab == 1:
		_rebuild_board()


func _update_summary() -> void:
	var total := GameState.inbox.size()
	var unread := GameState.unread_inbox_count()
	var urgent := 0
	for m in GameState.inbox:
		if m.get("urgent", false) and (not m.get("read", false) or _needs_decision(m)):
			urgent += 1
	_summary_lbl.text = tr("%d messages · %d unread%s") % [total, unread,
		(tr(" · %d URGENT") % urgent) if urgent > 0 else ""]
	_tab_inbox.text = tr("  Inbox (%d)  ") % unread if unread > 0 else tr("  Inbox  ")
	_tab_board.text = tr("  Board & Finances  ")
	_tab_inbox.button_pressed = _tab == 0
	_tab_board.button_pressed = _tab == 1


func _filtered_messages() -> Array:
	var out: Array = []
	var i := 0
	for m in GameState.inbox:
		var cat: String = m.get("cat", "board")
		if _filter != "all" and cat != _filter:
			i += 1
			continue
		if _unread_only and m.get("read", false):
			i += 1
			continue
		out.append({"m": m, "i": i})
		i += 1
	out.sort_custom(func(a, b):
		if a["m"]["date"] != b["m"]["date"]:
			return str(a["m"]["date"]) > str(b["m"]["date"])
		return a["i"] < b["i"])
	return out.map(func(d): return d["m"])


func _rebuild_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_row_refs.clear()

	# filter button captions with live counts
	var counts := {"all": GameState.inbox.size()}
	for m in GameState.inbox:
		var c: String = m.get("cat", "board")
		counts[c] = int(counts.get(c, 0)) + 1
	var caps := {"all": tr("All"), "match": tr("Match"), "cup": tr("Cup"), "media": tr("Press"),
		"staff": tr("Coach"), "scout": tr("Scout"), "transfer": tr("Transfer"), "board": tr("Board")}
	for cat in _filter_btns:
		var btn: Button = _filter_btns[cat]
		btn.text = "%s %d" % [caps[cat], int(counts.get(cat, 0))]
		btn.button_pressed = cat == _filter

	var msgs := _filtered_messages()
	if msgs.is_empty():
		var empty := Label.new()
		empty.text = tr("\n   No messages match this filter.")
		empty.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_list_box.add_child(empty)
		_selected = {}
		_render_reading_pane()
		return

	if _selected.is_empty() or not msgs.has(_selected):
		# FM-style: open on the item that still needs a decision, else newest
		_selected = msgs[0]
		for m in msgs:
			if m.get("urgent", false) and _needs_decision(m):
				_selected = m
				break
		_mark_read(_selected)

	for m in msgs:
		_list_box.add_child(_make_row(m))
	_render_reading_pane()


func _make_row(m: Dictionary) -> Button:
	var cat: String = m.get("cat", "board")
	var meta: Dictionary = NewsGen.CATS.get(cat, NewsGen.CATS["board"])
	var unread: bool = not m.get("read", false)
	# live offers and unanswered people-mail demand a decision, read or not
	var decision: bool = m.get("urgent", false) and _needs_decision(m)
	var urgent: bool = decision or (m.get("urgent", false) and unread)
	var selected: bool = m == _selected

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 54)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_contents = true
	var bg := ThemeBuilder.COL_PANEL if not selected else Color("343c63")
	var sb := ThemeBuilder._flat(bg, ThemeBuilder.COL_BORDER, 0, 8, 4)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	sb.border_width_bottom = 1
	btn.add_theme_stylebox_override("normal", sb)
	var sbh := ThemeBuilder._flat(Color("262c44") if not selected else Color("343c63"), ThemeBuilder.COL_BORDER, 0, 8, 4)
	sbh.border_width_left = 0
	sbh.border_width_right = 0
	sbh.border_width_top = 0
	sbh.border_width_bottom = 1
	btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	btn.add_theme_stylebox_override("focus", ThemeBuilder._empty())
	btn.pressed.connect(_on_row_pressed.bind(m))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var strip := ColorRect.new()
	strip.custom_minimum_size = Vector2(3, 0)
	strip.color = ThemeBuilder.COL_BAD if urgent else Color(0, 0, 0, 0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(strip)

	row.add_child(_msg_icon(m, meta, 30))

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 1)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)

	var subj := Label.new()
	subj.text = str(m.get("title", ""))
	subj.clip_text = true
	subj.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subj.add_theme_font_size_override("font_size", 14)
	if unread:
		subj.add_theme_font_override("font", _bold)
		subj.add_theme_color_override("font_color", Color("f2f4fb"))
	else:
		subj.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	subj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(subj)

	var sender := Label.new()
	sender.text = str(m.get("sender", ""))
	sender.clip_text = true
	sender.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sender.add_theme_font_size_override("font_size", 12)
	sender.add_theme_color_override("font_color",
		Color("aab0c6") if unread else Color("6b7189"))
	sender.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(sender)

	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 1)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	var date := Label.new()
	date.text = I18n.pretty_date(str(m.get("date", "")))
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.add_theme_font_size_override("font_size", 12)
	date.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	date.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(date)

	var flag_row := HBoxContainer.new()
	flag_row.alignment = BoxContainer.ALIGNMENT_END
	flag_row.add_theme_constant_override("separation", 4)
	flag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flag := Label.new()
	flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	flag.add_theme_font_size_override("font_size", 11)
	if urgent:
		flag.text = tr("DECISION") if decision else tr("URGENT")
		flag.add_theme_color_override("font_color", ThemeBuilder.COL_BAD)
		flag.add_theme_font_override("font", _bold)
	elif unread:
		# drawn dot marker (the web font has no ● glyph)
		flag_row.add_child(GlyphIcons.icon("dot", 8, ThemeBuilder.COL_ACCENT))
		flag.text = tr("NEW")
		flag.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	else:
		flag.text = " "
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag_row.add_child(flag)
	right.add_child(flag_row)

	return btn


## Portraits piece: mail from a PERSON (rival manager, journalist, coach,
## scout, assistant) shows their procedural face; institutional mail (board,
## committee, clubs) keeps the category badge.
func _msg_icon(m: Dictionary, meta: Dictionary, size_px: int) -> Control:
	var cat: String = str(m.get("cat", "board"))
	var sender: String = str(m.get("sender", ""))
	if cat in ["media", "staff", "scout", "match"] \
			and (Portrait.is_person(sender) or TrainerArt.has_art(Portrait.person_key(sender))):
		var who := Portrait.person_key(sender)
		var opts := {}
		var club: Dictionary = Portrait.club_of_manager(who)
		if club.is_empty() and cat != "media":
			club = GameState.player_club()   # own staff wear the club's colours
		if not club.is_empty():
			opts["collar"] = Portrait.club_collar(club)
		var av := Portrait.avatar(who, size_px, opts)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return av
	return _cat_icon(meta, size_px)


func _cat_icon(meta: Dictionary, size_px: int) -> Control:
	var icon := Panel.new()
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var isb := StyleBoxFlat.new()
	var col: Color = meta["color"]
	isb.bg_color = Color(col, 0.16)
	isb.border_color = Color(col, 0.85)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(4)
	icon.add_theme_stylebox_override("panel", isb)
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text = str(meta["letter"])
	l.add_theme_font_override("font", _bold)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(l)
	return icon


## Next unread message within the CURRENT filter, scanning down the list
## from the selected one and wrapping ({} if everything is read).
func _next_unread() -> Dictionary:
	var msgs := _filtered_messages()
	if msgs.is_empty():
		return {}
	var start := 0
	for i in msgs.size():
		if msgs[i] == _selected:
			start = i + 1
			break
	for off in msgs.size():
		var m: Dictionary = msgs[(start + off) % msgs.size()]
		if not m.get("read", false) and m != _selected:
			return m
	return {}


func _on_row_pressed(m: Dictionary) -> void:
	if m != _selected:
		_action_note = ""
	_selected = m
	_mark_read(m)
	_rebuild_list()
	_update_summary()


## Items whose urgency means "the manager still owes an answer": live market
## offers, unanswered mind-games, and open squad-welfare complaints.
func _needs_decision(m: Dictionary) -> bool:
	if m.has("offer_id"):
		return true
	if str(m.get("kind", "")) == "evo_ready":
		return str(m.get("decided", "")) == ""
	if str(m.get("academy_kind", "")) == "cull":   # open end-of-season youth review
		return not bool(m.get("resolved", false))
	var uid := str(m.get("uid", ""))
	return (uid.begins_with("mind:") or uid.begins_with("monlow:")) \
		and str(m.get("replied", "")) == ""


func _mark_read(m: Dictionary) -> void:
	# NOTE: reading a live offer does NOT clear its urgency — the flag means
	# "a decision is still required" and only resolving the offer clears it.
	if not m.get("read", false):
		m["read"] = true
		if m.get("cat", "") == "transfer" and not m.has("offer_id"):
			m["urgent"] = false


func _mark_all_read() -> void:
	for m in GameState.inbox:
		_mark_read(m)
	_rebuild_list()
	_update_summary()


func _delete_read() -> void:
	# never sweep away an unresolved decision item
	var keep: Array = GameState.inbox.filter(func(m):
		return not m.get("read", false) or m == _selected \
			or (m.get("urgent", false) and _needs_decision(m)))
	GameState.inbox.assign(keep)
	if not GameState.inbox.has(_selected):
		_selected = {}
	_rebuild_list()
	_update_summary()


func _delete_selected() -> void:
	if _selected.is_empty():
		return
	GameState.inbox.erase(_selected)
	_selected = {}
	_rebuild_list()
	_update_summary()


# ---------------------------------------------------------- reading pane

func _render_reading_pane() -> void:
	for c in _read_pane.get_children():
		c.queue_free()
	if _selected.is_empty():
		var l := Label.new()
		l.text = tr("Select a message to read it.")
		l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		_read_pane.add_child(l)
		return

	var m := _selected
	var meta: Dictionary = NewsGen.CATS.get(m.get("cat", "board"), NewsGen.CATS["board"])

	# header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_read_pane.add_child(head)
	head.add_child(_msg_icon(m, meta, 38))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 2)
	head.add_child(hv)
	var subj := Label.new()
	subj.text = str(m.get("title", ""))
	subj.add_theme_font_size_override("font_size", 19)
	subj.add_theme_font_override("font", _bold)
	subj.add_theme_color_override("font_color", Color("f2f4fb"))
	subj.clip_text = true
	subj.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hv.add_child(subj)
	var fromline := Label.new()
	fromline.text = tr("From: %s   ·   %s   ·   %s") % [str(m.get("sender", "—")),
		I18n.pretty_date(str(m.get("date", ""))), tr(str(meta["label"]))]
	fromline.add_theme_font_size_override("font_size", 12)
	fromline.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	fromline.clip_text = true
	fromline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hv.add_child(fromline)
	if m.get("urgent", false):
		var u := Label.new()
		u.text = tr("DECISION REQUIRED") if _needs_decision(m) else tr("URGENT")
		u.add_theme_font_override("font", _bold)
		u.add_theme_color_override("font_color", ThemeBuilder.COL_BAD)
		head.add_child(u)
	# jump straight to the next unread in the current filter (user request)
	var nxt := Button.new()
	nxt.text = tr("Read next ›")
	nxt.custom_minimum_size = Vector2(0, 26)
	nxt.add_theme_font_size_override("font_size", 12)
	nxt.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT.lightened(0.25))
	var nxt_msg := _next_unread()
	nxt.disabled = nxt_msg.is_empty()
	nxt.pressed.connect(func():
		var n := _next_unread()
		if not n.is_empty():
			_on_row_pressed(n))
	head.add_child(nxt)
	var del := Button.new()
	del.text = "Delete"
	del.custom_minimum_size = Vector2(0, 26)
	del.add_theme_font_size_override("font_size", 12)
	del.pressed.connect(_delete_selected)
	head.add_child(del)

	_read_pane.add_child(HSeparator.new())

	var rendered: Dictionary = reports.render(m)

	# optional match banner
	var banner: Dictionary = rendered.get("banner", {})
	if not banner.is_empty():
		_read_pane.add_child(_make_banner(banner))

	# body
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_read_pane.add_child(scroll)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.selection_enabled = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("bold_font", _bold)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.add_theme_constant_override("line_separation", 4)
	body.text = str(rendered.get("bbcode", ""))
	scroll.add_child(body)

	# actions — decisions (accept/counter/reject call the live transfer
	# market and move real money/squad members) followed by navigation links
	var actions: Array = rendered.get("actions", [])
	if not actions.is_empty() or _action_note != "":
		_read_pane.add_child(HSeparator.new())
		# Flow: decision + navigation buttons wrap onto extra rows instead of
		# forcing the reading pane wider than the window (es labels are long).
		var arow := HFlowContainer.new()
		arow.add_theme_constant_override("h_separation", 8)
		arow.add_theme_constant_override("v_separation", 6)
		_read_pane.add_child(arow)
		for a in actions:
			var kind := str(a.get("kind", "screen"))
			if kind == "mon":
				# live entity button: opens the global Pokémon action menu
				# (offer / scout / shortlist / compare) right from the mail
				if MonActions.can_act(str(a.get("uid", ""))):
					arow.add_child(MonActions.action_pill(str(a["uid"]), str(a.get("label", tr("Actions")))))
				continue
			if kind == "screen":
				var target: String = a["screen"]
				if target != "@board" and not _shell_has_screen(target):
					continue
				var b := Button.new()
				b.text = "  %s  " % tr(a["label"])
				b.custom_minimum_size = Vector2(0, 32)
				b.add_theme_color_override("font_color", Color.WHITE)
				b.add_theme_stylebox_override("normal",
					ThemeBuilder._flat(ThemeBuilder.COL_ACCENT_DIM, ThemeBuilder.COL_ACCENT, 4, 12, 6))
				b.add_theme_stylebox_override("hover",
					ThemeBuilder._flat(ThemeBuilder.COL_ACCENT, ThemeBuilder.COL_ACCENT, 4, 12, 6))
				b.pressed.connect(_on_action.bind(a))
				arow.add_child(b)
			else:
				arow.add_child(_decision_button(a))
		if _action_note != "":
			var note := Label.new()
			note.text = _action_note
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.add_theme_font_size_override("font_size", 13)
			note.add_theme_font_override("font", _bold)
			note.add_theme_color_override("font_color", _action_note_col)
			_read_pane.add_child(note)


func _decision_button(a: Dictionary) -> Button:
	var col: Color
	match str(a.get("style", "")):
		"good": col = ThemeBuilder.COL_GOOD
		"bad": col = ThemeBuilder.COL_BAD
		_: col = ThemeBuilder.COL_WARN
	var b := Button.new()
	b.text = "  %s  " % tr(a["label"])
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_override("font", _bold)
	b.add_theme_color_override("font_color", Color("f2f4fb"))
	b.add_theme_stylebox_override("normal", ThemeBuilder._flat(Color(col, 0.20), col, 4, 12, 6))
	b.add_theme_stylebox_override("hover", ThemeBuilder._flat(Color(col, 0.38), col, 4, 12, 6))
	b.add_theme_stylebox_override("pressed", ThemeBuilder._flat(Color(col, 0.5), col, 4, 12, 6))
	if str(a.get("kind", "")) == "reply":
		b.pressed.connect(_on_people_reply.bind(a))
	elif str(a.get("kind", "")).begins_with("evo_"):
		b.pressed.connect(_on_evolution_decision.bind(a))
	elif str(a.get("kind", "")).begins_with("challenge_"):
		b.pressed.connect(_on_challenge_decision.bind(a))
	else:
		b.pressed.connect(_on_offer_decision.bind(a))
	return b


## Street challenge (challenges piece): spin up the exhibition and go pitch-side.
func _on_challenge_decision(a: Dictionary) -> void:
	var svc = ChallengeService.instance
	if svc == null:
		return
	if str(a["kind"]) == "challenge_accept":
		var err := str(svc.accept())
		if err != "":
			_action_note = err
			_action_note_col = ThemeBuilder.COL_BAD
			_rebuild_all()
			return
		_on_action({"screen": "match", "label": "Match"})
	else:
		svc.decline()
	_rebuild_all()


## A reply to a person (rival manager, coach note) — moves real morale values.
func _on_people_reply(a: Dictionary) -> void:
	if _selected.is_empty():
		return
	var res: Dictionary = people.apply_reply(_selected, a)
	_action_note = str(res.get("note", ""))
	_action_note_col = ThemeBuilder.COL_GOOD if res.get("good", true) else ThemeBuilder.COL_WARN
	_refresh_data()
	_rebuild_all()


## Execute an evolution decision against the live evolution service.
## Approving genuinely transforms the squad instance; stones are consumed.
func _on_evolution_decision(a: Dictionary) -> void:
	var svc: RefCounted = EvoSvc.instance
	if svc == null:
		return
	var uid := str(a.get("evo_uid", ""))
	var before: Dictionary = GameState.squad_member(uid)
	var old_name: String = str(before.get("species", "?")) if not before.is_empty() else "?"
	var err := ""
	var ok_note := ""
	match str(a.get("kind", "")):
		"evo_approve":
			err = svc.approve(uid)
			if err == "":
				ok_note = tr("Approved — %s has evolved into %s (+%d morale).") % \
					[old_name, str(GameState.squad_member(uid).get("species", "?")),
					EvoSvc.EVOLVE_MORALE_BOOST]
		"evo_postpone":
			err = svc.postpone(uid)
			if err == "":
				ok_note = tr("Postponed — the offer returns in %d days if still eligible (-%d morale).") % \
					[EvoSvc.REOFFER_DAYS, EvoSvc.POSTPONE_MORALE_COST]
		"evo_stone":
			err = svc.use_stone(uid, str(a.get("item", "")))
			if err == "":
				ok_note = tr("%s consumed — %s has evolved into %s.") % \
					[tr(DataStore.item_name(str(a.get("item", "")))), old_name,
					str(GameState.squad_member(uid).get("species", "?"))]
	if err != "":
		_action_note = err
		_action_note_col = ThemeBuilder.COL_BAD
	else:
		_action_note = ok_note
		_action_note_col = ThemeBuilder.COL_GOOD
	_refresh_data()
	_rebuild_all()


## Execute an offer decision against the transfers market's live ledger.
## Accepting genuinely moves the squad member and credits the fee.
func _on_offer_decision(a: Dictionary) -> void:
	var mkt: RefCounted = news.market()
	if mkt == null:
		return
	var oid := int(a.get("offer_id", -1))
	var err := ""
	var ok_note := ""
	var pc: Dictionary = GameState.player_club()
	match str(a.get("kind", "")):
		"accept":
			var before := int(pc["finances"]["balance"])
			err = str(mkt.accept_offer_in(oid))
			if err == "":
				ok_note = tr("Sale completed — %s credited (balance now %s).") % [
					news.money(int(pc["finances"]["balance"]) - before),
					news.money(int(pc["finances"]["balance"]))]
		"reject":
			mkt.reject_offer_in(oid)
			ok_note = tr("Offer rejected. They have been informed.")
		"counter":
			err = str(mkt.counter_offer_in(oid, int(a.get("ask", 0))))
			if err == "":
				ok_note = tr("Demand of %s sent — expect an answer within a couple of days.") % \
					news.money(int(a.get("ask", 0)))
	if err != "":
		_action_note = err
		_action_note_col = ThemeBuilder.COL_BAD
	else:
		_action_note = ok_note
		_action_note_col = ThemeBuilder.COL_GOOD
	_refresh_data()
	_rebuild_all()


func _make_banner(banner: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var won: bool = banner.get("won", false)
	var edge := ThemeBuilder.COL_GOOD if won else ThemeBuilder.COL_BAD
	var sb := ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, edge, 4, 16, 10)
	sb.border_width_left = 4
	sb.border_width_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var hl := Label.new()
	hl.text = str(banner["home"])
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hl.add_theme_font_size_override("font_size", 18)
	hl.add_theme_font_override("font", _bold)
	hl.add_theme_color_override("font_color", Color("f2f4fb"))
	row.add_child(hl)
	var score := Label.new()
	score.text = "%d - %d" % [int(banner["sh"]), int(banner["sa"])]
	score.add_theme_font_size_override("font_size", 30)
	score.add_theme_font_override("font", _bold)
	score.add_theme_color_override("font_color", edge)
	row.add_child(score)
	var al := Label.new()
	al.text = str(banner["away"])
	al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	al.add_theme_font_size_override("font_size", 18)
	al.add_theme_font_override("font", _bold)
	al.add_theme_color_override("font_color", Color("f2f4fb"))
	row.add_child(al)
	var comp := Label.new()
	comp.text = str(banner.get("comp", ""))
	comp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	comp.add_theme_font_size_override("font_size", 12)
	comp.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(comp)
	var res := Label.new()
	res.text = tr("FULL TIME · ") + (tr("WIN") if won else tr("DEFEAT"))
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.add_theme_font_size_override("font_size", 12)
	res.add_theme_font_override("font", _bold)
	res.add_theme_color_override("font_color", edge)
	v.add_child(res)
	return panel


func _on_action(a: Dictionary) -> void:
	var target := str(a["screen"])
	if target == "@board":
		_set_tab(1)
		return
	var n: Node = get_parent()
	while n != null and not n.has_method("navigate_to"):
		n = n.get_parent()
	if n == null:
		return
	var tab := str(a.get("tab", ""))
	if tab != "":
		n.call("navigate_to", target, {"kind": "tab", "tab": tab, "label": str(a["label"])})
	else:
		n.call("navigate_to", target)


func _shell_has_screen(target: String) -> bool:
	var n: Node = get_parent()
	while n != null and not n.has_method("navigate_to"):
		n = n.get_parent()
	if n == null:
		return false
	var scr: Variant = n.get("screens")
	return typeof(scr) == TYPE_DICTIONARY and scr.has(target)


# ================================================================= BOARD TAB

func _rebuild_board() -> void:
	for c in _board_pane.get_children():
		c.queue_free()
	var conf: Dictionary = news.board_confidence()
	var fin: Dictionary = news.finance_summary()

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_pane.add_child(cols)
	_board_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var left := _board_column(cols)
	var right := _board_column(cols)

	left.add_child(_board_confidence_panel(conf))
	left.add_child(_requests_panel())
	left.add_child(_expectations_panel(conf))
	left.add_child(_results_panel())
	right.add_child(_finances_panel(fin))
	right.add_child(_cashflow_panel())
	right.add_child(_ledger_panel())
	right.add_child(_earners_panel(fin))


func _board_column(cols: HBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)
	return col


func _panel(title: String) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_BORDER, 0, 16, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_font_override("font", _bold)
	t.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	v.add_child(t)
	v.add_child(HSeparator.new())
	return [p, v]


func _bar(fraction: float, color: Color, height: int = 14) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, height)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := ColorRect.new()
	bg.color = ThemeBuilder.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(fraction, 0.0, 1.0)
	holder.add_child(fill)
	return holder


func _kv_row(parent: VBoxContainer, key: String, value: String, val_color: Color = ThemeBuilder.COL_TEXT) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	k.add_theme_font_size_override("font_size", 13)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", val_color)
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_font_override("font", _bold)
	row.add_child(v)


func _board_confidence_panel(conf: Dictionary) -> Control:
	var pv := _panel("BOARD CONFIDENCE")
	var v: VBoxContainer = pv[1]

	# the people behind the statements (portraits piece): stable per club
	var pc := GameState.player_club()
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 18)
	v.add_child(brow)
	for member in Portrait.board_members(pc):
		var mcol := HBoxContainer.new()
		mcol.add_theme_constant_override("separation", 7)
		mcol.add_child(Portrait.avatar(str(member["name"]), 34,
			{"collar": Portrait.club_collar(pc), "age": int(member["age"])}))
		var mtxt := VBoxContainer.new()
		mtxt.alignment = BoxContainer.ALIGNMENT_CENTER
		mtxt.add_theme_constant_override("separation", 0)
		var mn := Label.new()
		mn.text = str(member["name"])
		mn.add_theme_font_size_override("font_size", 12)
		mn.add_theme_color_override("font_color", Color("e8ebf5"))
		mtxt.add_child(mn)
		var mr := Label.new()
		mr.text = tr("Chair") if str(member["role"]) == "Chair" else tr("Director")
		mr.add_theme_font_size_override("font_size", 10)
		mr.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		mtxt.add_child(mr)
		mcol.add_child(mtxt)
		brow.add_child(mcol)
	v.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var word := Label.new()
	word.text = tr(str(conf["word"])).to_upper()
	word.add_theme_font_size_override("font_size", 30)
	word.add_theme_font_override("font", _bold)
	word.add_theme_color_override("font_color", conf["color"])
	row.add_child(word)
	var pct := Label.new()
	pct.text = "%d%%" % int(conf["score"])
	pct.add_theme_font_size_override("font_size", 18)
	pct.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	pct.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(pct)

	v.add_child(_bar(conf["score"] / 100.0, conf["color"], 18))

	var stmt := Label.new()
	stmt.text = tr(str(conf["statement"]))
	stmt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stmt.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	v.add_child(stmt)

	v.add_child(HSeparator.new())

	# component breakdown
	var pos: int = conf["pos"]
	var e: int = conf["expected"]
	var league_delta := e - pos
	var league_word := tr("On track")
	var league_col := ThemeBuilder.COL_TEXT
	if conf["played"] == 0:
		league_word = tr("Season not started")
		league_col = ThemeBuilder.COL_TEXT_DIM
	elif league_delta >= 3:
		league_word = tr("Exceeding")
		league_col = ThemeBuilder.COL_GOOD
	elif league_delta >= 0:
		league_word = tr("Meeting")
		league_col = ThemeBuilder.COL_GOOD
	elif league_delta >= -3:
		league_word = tr("Below par")
		league_col = ThemeBuilder.COL_WARN
	else:
		league_word = tr("Failing")
		league_col = ThemeBuilder.COL_BAD
	_kv_row(v, tr("League performance  (%s, expected ~%s)") %
		["—" if int(conf["played"]) == 0 else _ord(pos), _ord(e)], league_word, league_col)

	var cs: Dictionary = news.cup_status()
	var cup_col: Color = ThemeBuilder.COL_GOOD if cs["alive"] else \
		(ThemeBuilder.COL_WARN if int(cs["round"]) >= 2 else ThemeBuilder.COL_BAD)
	_kv_row(v, tr("Cup progress"), tr(str(cs["text"])), cup_col)

	# form chips
	var form: Array = news.recent_results(5)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	v.add_child(frow)
	var fl := Label.new()
	fl.text = tr("Recent form (newest first)")
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	fl.add_theme_font_size_override("font_size", 13)
	frow.add_child(fl)
	if form.is_empty():
		var none := Label.new()
		none.text = tr("no matches yet")
		none.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		none.add_theme_font_size_override("font_size", 13)
		frow.add_child(none)
	for r in form:
		frow.add_child(_form_chip(r["won"]))
	return pv[0]


func _form_chip(won: bool) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(24, 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ThemeBuilder.COL_GOOD, 0.22) if won else Color(ThemeBuilder.COL_BAD, 0.22)
	sb.border_color = ThemeBuilder.COL_GOOD if won else ThemeBuilder.COL_BAD
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text = "W" if won else "L"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_font_override("font", _bold)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_GOOD if won else ThemeBuilder.COL_BAD)
	p.add_child(l)
	return p


func _expectations_panel(conf: Dictionary) -> Control:
	var pv := _panel("SEASON EXPECTATIONS")
	var v: VBoxContainer = pv[1]
	var pc: Dictionary = GameState.player_club()

	var s1 := Label.new()
	s1.text = tr("\"%s expect the club to %s and to %s.\"") % \
		[pc["name"], tr(news.league_expectation_text()), tr(news.cup_expectation_text())]
	s1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s1.add_theme_color_override("font_color", Color("f2f4fb"))
	s1.add_theme_font_override("font", _bold)
	v.add_child(s1)

	var src := Label.new()
	src.text = tr("— Board of Directors, %s") % I18n.pretty_date(GameState.season_start)
	src.add_theme_font_size_override("font_size", 12)
	src.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(src)

	v.add_child(HSeparator.new())
	_kv_row(v, "Club reputation", "%d / 20" % int(pc["reputation"]))
	_kv_row(v, "Expected league position", tr("~%s of %d") % [_ord(conf["expected"]), GameState.world["clubs"].size()])
	_kv_row(v, "Current league position",
		_ord(conf["pos"]) if conf["played"] > 0 else tr("season not started"),
		ThemeBuilder.COL_GOOD if conf["pos"] <= conf["expected"] and conf["played"] > 0 else ThemeBuilder.COL_TEXT)
	_kv_row(v, "League matches played", str(conf["played"]))
	var row: Dictionary = {}
	for r in GameState.league_table():
		if GameState.is_player_club(r["club_id"]):
			row = r
	if not row.is_empty():
		_kv_row(v, "Record (W-L)", tr("%d-%d   ·   %d pts") % [int(row["won"]), int(row["lost"]), int(row["points"])])
		_kv_row(v, "Battles for / against", "%d / %d" % [int(row["bf"]), int(row["ba"])])
	return pv[0]


func _results_panel() -> Control:
	var pv := _panel("LATEST RESULTS")
	var v: VBoxContainer = pv[1]
	var results: Array = news.recent_results(6)
	if results.is_empty():
		var l := Label.new()
		l.text = tr("No competitive matches played yet.")
		l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		v.add_child(l)
		return pv[0]
	for r in results:
		var f: Dictionary = r["f"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var d := Label.new()
		d.text = I18n.pretty_date(str(f["date"]))
		d.custom_minimum_size.x = 90
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		row.add_child(d)
		var comp := Label.new()
		comp.text = "LGE" if f["comp"] == "league" else "CUP"
		comp.custom_minimum_size.x = 34
		comp.add_theme_font_size_override("font_size", 11)
		comp.add_theme_color_override("font_color",
			ThemeBuilder.COL_ACCENT if f["comp"] == "cup" else ThemeBuilder.COL_TEXT_DIM)
		row.add_child(comp)
		var opp := Label.new()
		var we_home: bool = GameState.is_player_club(f["home"])
		opp.text = "%s %s" % ["vs" if we_home else "at", r["opp"]]
		opp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opp.clip_text = true
		opp.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		opp.add_theme_font_size_override("font_size", 13)
		row.add_child(opp)
		var score := Label.new()
		score.text = "%d-%d" % [int(r["us"]), int(r["them"])]
		score.add_theme_font_size_override("font_size", 13)
		score.add_theme_font_override("font", _bold)
		score.add_theme_color_override("font_color",
			ThemeBuilder.COL_GOOD if r["won"] else ThemeBuilder.COL_BAD)
		row.add_child(score)
		row.add_child(_form_chip(r["won"]))
	return pv[0]


func _finances_panel(fin: Dictionary) -> Control:
	var pv := _panel("FINANCES")
	var v: VBoxContainer = pv[1]

	var bal := Label.new()
	bal.text = news.money(fin["balance"])
	bal.add_theme_font_size_override("font_size", 30)
	bal.add_theme_font_override("font", _bold)
	bal.add_theme_color_override("font_color",
		ThemeBuilder.COL_GOOD if fin["balance"] >= 0 else ThemeBuilder.COL_BAD)
	v.add_child(bal)
	var bal_sub := Label.new()
	bal_sub.text = tr("Bank balance  ·  league average %s") % news.money(fin["league_avg_balance"])
	bal_sub.add_theme_font_size_override("font_size", 12)
	bal_sub.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(bal_sub)
	v.add_child(_bar(float(fin["balance"]) / maxf(1.0, float(fin["league_max_balance"])), ThemeBuilder.COL_ACCENT, 10))
	var tb := maxi(0, mini(int(fin["balance"]), int(fin.get("transfer_budget", 0))))
	_kv_row(v, "Transfer budget (released by the board)", news.money(tb),
		ThemeBuilder.COL_GOOD if tb > 0 else ThemeBuilder.COL_WARN)

	v.add_child(HSeparator.new())

	# wage bill vs budget
	var over: bool = fin["wage_bill"] > fin["wage_budget"]
	var frac := float(fin["wage_bill"]) / maxf(1.0, float(fin["wage_budget"]))
	var wl := Label.new()
	wl.text = tr("Wage bill vs budget")
	wl.add_theme_font_size_override("font_size", 13)
	wl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(wl)
	v.add_child(_bar(frac, ThemeBuilder.COL_BAD if over else ThemeBuilder.COL_GOOD, 14))
	_kv_row(v, tr("Monthly wage bill (%d battlers)") % int(fin["squad_size"]),
		tr("%s of %s  (%d%%)") % [news.money(fin["wage_bill"]), news.money(fin["wage_budget"]), int(frac * 100)],
		ThemeBuilder.COL_BAD if over else ThemeBuilder.COL_GOOD)
	_kv_row(v, "Wage budget headroom",
		news.money(fin["wage_budget"] - fin["wage_bill"]),
		ThemeBuilder.COL_BAD if over else ThemeBuilder.COL_TEXT)
	var op30 := int(economy.operating_net(30))
	_kv_row(v, "Operating cash flow — last 30 days",
		("+%s" % news.money(op30)) if op30 >= 0 else news.money(op30),
		ThemeBuilder.COL_GOOD if op30 >= 0 else ThemeBuilder.COL_BAD)

	v.add_child(HSeparator.new())

	# transfer spend
	var spend: int = fin["transfer_spend"]
	var tl := Label.new()
	tl.text = tr("Transfer activity this season")
	tl.add_theme_font_size_override("font_size", 13)
	tl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(tl)
	var spend_frac := absf(float(spend)) / maxf(1.0, float(fin["initial_balance"]))
	v.add_child(_bar(spend_frac, ThemeBuilder.COL_WARN if spend > 0 else ThemeBuilder.COL_GOOD, 10))
	if spend > 0:
		_kv_row(v, "Net transfer spend", news.money(spend), ThemeBuilder.COL_WARN)
	elif spend < 0:
		_kv_row(v, "Net transfer income", news.money(-spend), ThemeBuilder.COL_GOOD)
	else:
		_kv_row(v, "Net transfer spend", tr("%s (no deals completed)") % news.money(0))
	_kv_row(v, "Balance at season start", news.money(fin["initial_balance"]))
	_kv_row(v, "Projected 12-month wage commitment", news.money(fin["wage_bill"] * 12))
	return pv[0]


func _earners_panel(fin: Dictionary) -> Control:
	var pv := _panel("TOP EARNERS — WAGE COMMITMENTS")
	var v: VBoxContainer = pv[1]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 5)
	v.add_child(grid)
	for h in ["BATTLER", "LV", "WAGE / MO", "CONTRACT ENDS"]:
		var hl := Label.new()
		hl.text = h
		hl.add_theme_font_size_override("font_size", 11)
		hl.add_theme_font_override("font", _bold)
		hl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		if h == "BATTLER":
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(hl)
	var top_wage := 1
	var earners: Array = fin["earners"]
	if not earners.is_empty():
		top_wage = int(earners[0]["salary"])
	for e in earners.slice(0, 6):
		var n := Label.new()
		n.text = str(e["name"]) if e["name"] == e["species"] else "%s  (%s)" % [e["name"], e["species"]]
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.add_theme_font_size_override("font_size", 13)
		grid.add_child(n)
		var lv := Label.new()
		lv.text = str(e["level"])
		lv.add_theme_font_size_override("font_size", 13)
		lv.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		grid.add_child(lv)
		var w := Label.new()
		w.text = news.money(int(e["salary"]))
		w.add_theme_font_size_override("font_size", 13)
		w.add_theme_font_override("font", _bold)
		w.add_theme_color_override("font_color", Color("f2f4fb"))
		grid.add_child(w)
		var x := Label.new()
		x.text = I18n.pretty_date(str(e["expiry"]))
		x.add_theme_font_size_override("font_size", 13)
		x.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		grid.add_child(x)
	var note := Label.new()
	var pct := 0
	if fin["wage_bill"] > 0 and not earners.is_empty():
		var top3 := 0
		for e in earners.slice(0, 3):
			top3 += int(e["salary"])
		pct = int(100.0 * top3 / fin["wage_bill"])
	note.text = tr("Top 3 earners account for %d%% of the wage bill.") % pct
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(note)
	return pv[0]


# -------------------------------------------------- board requests (two-way)
## FM-style "Make a request of the board". Submitting creates a real pending
## request in board_room; the board's answer (days later) mutates the club's
## actual wage budget / balance / prospect knowledge and arrives as urgent mail.

func _requests_panel() -> Control:
	var pv := _panel("REQUEST FROM THE BOARD")
	var v: VBoxContainer = pv[1]

	var pending: Dictionary = board.pending_request()
	if not pending.is_empty():
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel",
			ThemeBuilder._flat(Color(ThemeBuilder.COL_WARN, 0.10), ThemeBuilder.COL_WARN, 4, 12, 8))
		v.add_child(box)
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 2)
		box.add_child(bv)
		var t := Label.new()
		t.text = tr("UNDER CONSIDERATION — %s") % tr(str(pending["label"])).to_upper()
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_font_override("font", _bold)
		t.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
		bv.add_child(t)
		var d := Label.new()
		d.text = tr("Asked for %s on %s · the board will answer by %s.") % \
			[news.money(int(pending["amount"])), I18n.pretty_date(str(pending["date"])),
			I18n.pretty_date(str(pending["decide_on"]))]
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
		bv.add_child(d)
	else:
		for def in board.request_defs():
			v.add_child(_request_row(def))

	if _board_note != "":
		var note := Label.new()
		note.text = _board_note
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_font_override("font", _bold)
		note.add_theme_color_override("font_color", _board_note_col)
		v.add_child(note)

	# recent verdicts — the paper trail of past negotiations with the board
	var resolved: Array = board.resolved_requests()
	if not resolved.is_empty():
		v.add_child(HSeparator.new())
		for r in resolved.slice(0, 3):
			var col := ThemeBuilder.COL_BAD
			var word := tr("REFUSED")
			if str(r["status"]) == "granted":
				col = ThemeBuilder.COL_GOOD
				word = tr("GRANTED")
			elif str(r["status"]) == "partial":
				col = ThemeBuilder.COL_WARN
				word = tr("PARTIAL (%s)") % news.money(int(r["granted"]))
			_kv_row(v, "%s · %s (%s)" % [I18n.pretty_date(str(r["decided_on"])),
				tr(str(r["label"])), news.money(int(r["amount"]))], word, col)
	var recent := int(board.recent_request_count(60))
	if recent >= 2:
		var warn := Label.new()
		warn.text = tr("%d requests inside 60 days — the board tires of frequent demands.") % recent
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color", ThemeBuilder.COL_WARN)
		v.add_child(warn)
	return pv[0]


func _request_row(def: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	row.add_child(top)
	var name := Label.new()
	name.text = tr(str(def["title"]))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_font_size_override("font_size", 13)
	name.add_theme_font_override("font", _bold)
	name.add_theme_color_override("font_color", Color("f2f4fb"))
	top.add_child(name)
	# receptiveness hint from a deterministic dry-run of the board's own model
	var hint: Dictionary = def["options"][0].get("hint", {})
	if not hint.is_empty():
		var h := Label.new()
		h.text = tr("board: %s") % tr(str(hint["word"]))
		h.add_theme_font_size_override("font_size", 11)
		h.add_theme_color_override("font_color", hint["color"])
		top.add_child(h)
	for o in def["options"]:
		var b := Button.new()
		b.text = "  %s  " % tr(str(o["label"]))
		b.custom_minimum_size = Vector2(0, 26)
		b.add_theme_font_size_override("font_size", 12)
		var oc: Color = (o.get("hint", {}) as Dictionary).get("color", ThemeBuilder.COL_ACCENT)
		b.add_theme_stylebox_override("normal", ThemeBuilder._flat(Color(oc, 0.14), oc, 4, 8, 4))
		b.add_theme_stylebox_override("hover", ThemeBuilder._flat(Color(oc, 0.32), oc, 4, 8, 4))
		b.pressed.connect(_on_board_request.bind(str(def["kind"]), int(o["amount"])))
		top.add_child(b)
	var desc := Label.new()
	desc.text = tr(str(def["desc"]))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	row.add_child(desc)
	return row


func _on_board_request(kind: String, amount: int) -> void:
	var err: String = board.submit(kind, amount)
	if err != "":
		_board_note = err
		_board_note_col = ThemeBuilder.COL_BAD
	else:
		var pending: Dictionary = board.pending_request()
		_board_note = tr("Request submitted — the board will answer by %s. Watch your inbox.") % \
			I18n.pretty_date(str(pending.get("decide_on", "")))
		_board_note_col = ThemeBuilder.COL_GOOD
	_rebuild_all()


const LEDGER_CATS := {
	"gate":      "Gate receipts",
	"prize":     "Prize money",
	"sponsor":   "Sponsorship",
	"broadcast": "Broadcast & merit",
	"sale":      "Player sales",
	"injection": "Board injections",
	"wages":     "Squad wages",
	"upkeep":    "Facilities & staff",
	"ops":       "Matchday operations",
	"travel":    "Team travel",
	"signing":   "Transfer fees",
	"scouting":  "Scouting network",
}


func _ledger_panel() -> Control:
	var pv := _panel("INCOME & EXPENDITURE — THIS SEASON")
	var v: VBoxContainer = pv[1]
	var all_rows: Array = board.ledger_rows(9999)
	if all_rows.is_empty():
		var l := Label.new()
		l.text = tr("No cash transactions recorded yet — sell, sign or squeeze the board.")
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		v.add_child(l)
		return pv[0]

	# ---- season totals by category (every line here really moved the bank)
	var cat_in: Dictionary = {}
	var cat_out: Dictionary = {}
	var total_in := 0
	var total_out := 0
	for r in all_rows:
		var amt := int(r["amount"])
		if amt == 0:
			continue
		var label: String = tr(LEDGER_CATS.get(str(r["kind"]), "Other"))
		if amt > 0:
			cat_in[label] = int(cat_in.get(label, 0)) + amt
			total_in += amt
		else:
			cat_out[label] = int(cat_out.get(label, 0)) - amt
			total_out -= amt
	var peak := 1
	for k in cat_in:
		peak = maxi(peak, int(cat_in[k]))
	for k in cat_out:
		peak = maxi(peak, int(cat_out[k]))

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	v.add_child(split)
	split.add_child(_cat_column(tr("INCOME"), cat_in, total_in, peak, ThemeBuilder.COL_GOOD, true))
	split.add_child(_cat_column(tr("EXPENDITURE"), cat_out, total_out, peak, ThemeBuilder.COL_BAD, false))

	var net := total_in - total_out
	_kv_row(v, "Net cash movement this season",
		("+%s" % news.money(net)) if net >= 0 else news.money(net),
		ThemeBuilder.COL_GOOD if net >= 0 else ThemeBuilder.COL_BAD)

	# ---- most recent transactions
	v.add_child(HSeparator.new())
	var rt := Label.new()
	rt.text = tr("RECENT TRANSACTIONS")
	rt.add_theme_font_size_override("font_size", 11)
	rt.add_theme_font_override("font", _bold)
	rt.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	v.add_child(rt)
	for r in all_rows.slice(0, 7):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var d := Label.new()
		d.text = I18n.pretty_date(str(r["date"]))
		d.custom_minimum_size.x = 90
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		row.add_child(d)
		var t := Label.new()
		t.text = str(r["text"])
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.add_theme_font_size_override("font_size", 12)
		row.add_child(t)
		var a := Label.new()
		var amt := int(r["amount"])
		a.text = ("+%s" % news.money(amt)) if amt > 0 else (news.money(amt) if amt < 0 else "budget")
		a.add_theme_font_size_override("font_size", 12)
		a.add_theme_font_override("font", _bold)
		a.add_theme_color_override("font_color",
			ThemeBuilder.COL_GOOD if amt > 0 else (ThemeBuilder.COL_BAD if amt < 0 else ThemeBuilder.COL_TEXT_DIM))
		row.add_child(a)
	return pv[0]


## One side of the I&E statement: category rows with proportional bars.
func _cat_column(title: String, cats: Dictionary, total: int, peak: int, col: Color, income: bool) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	box.add_child(head)
	var t := Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 11)
	t.add_theme_font_override("font", _bold)
	t.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	head.add_child(t)
	var tot := Label.new()
	tot.text = ("+%s" if income else "-%s") % news.money(total)
	tot.add_theme_font_size_override("font_size", 12)
	tot.add_theme_font_override("font", _bold)
	tot.add_theme_color_override("font_color", col)
	head.add_child(tot)
	var keys: Array = cats.keys()
	keys.sort_custom(func(a, b): return int(cats[a]) > int(cats[b]))
	for k in keys:
		var amt := int(cats[k])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var nl := Label.new()
		nl.text = str(k)
		nl.custom_minimum_size.x = 128
		nl.clip_text = true
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
		row.add_child(nl)
		var bar := _bar(float(amt) / float(peak), Color(col, 0.75), 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var al := Label.new()
		al.text = news.money(amt)
		al.custom_minimum_size.x = 74
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		al.add_theme_font_size_override("font_size", 12)
		al.add_theme_color_override("font_color", col)
		row.add_child(al)
	if keys.is_empty():
		var none := Label.new()
		none.text = tr("— nothing yet")
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		box.add_child(none)
	return box


## Month-by-month operating P&L — FM's "living finances" at a glance.
func _cashflow_panel() -> Control:
	var pv := _panel("MONTHLY CASH FLOW")
	var v: VBoxContainer = pv[1]
	var all_rows: Array = board.ledger_rows(9999)

	# month keys from season start to the current month, oldest first
	var months: Array = []
	var mk := str(GameState.season_start).substr(0, 7)
	var now_mk := str(GameState.current_date).substr(0, 7)
	var cursor := "%s-01" % mk
	while mk <= now_mk and months.size() < 14:
		months.append(mk)
		cursor = Season.date_add(cursor, 32)
		cursor = "%s-01" % cursor.substr(0, 7)
		mk = cursor.substr(0, 7)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for h in ["MONTH", "INCOME", "EXPENDITURE", "NET"]:
		var hl := Label.new()
		hl.text = tr(h)
		hl.add_theme_font_size_override("font_size", 11)
		hl.add_theme_font_override("font", _bold)
		hl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		if h == "MONTH":
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(hl)
	var season_net := 0
	for m in months:
		var inc := 0
		var exp := 0
		for r in all_rows:
			if not str(r["date"]).begins_with(m):
				continue
			var amt := int(r["amount"])
			if amt > 0:
				inc += amt
			else:
				exp += -amt
		var net := inc - exp
		season_net += net
		var open_month: bool = m == now_mk
		var ml := Label.new()
		ml.text = "%s %s%s" % [tr(economy.MONTH_NAMES[int(m.split("-")[1])]), m.substr(0, 4),
			tr("  (so far)") if open_month else ""]
		ml.add_theme_font_size_override("font_size", 12)
		ml.add_theme_color_override("font_color",
			Color("f2f4fb") if open_month else ThemeBuilder.COL_TEXT)
		grid.add_child(ml)
		grid.add_child(_money_cell("+%s" % news.money(inc), ThemeBuilder.COL_GOOD))
		grid.add_child(_money_cell("-%s" % news.money(exp), ThemeBuilder.COL_BAD))
		grid.add_child(_money_cell(("+%s" % news.money(net)) if net >= 0 else news.money(net),
			ThemeBuilder.COL_GOOD if net >= 0 else ThemeBuilder.COL_BAD, true))
	v.add_child(HSeparator.new())
	_kv_row(v, "Season to date", ("+%s" % news.money(season_net)) if season_net >= 0 else news.money(season_net),
		ThemeBuilder.COL_GOOD if season_net >= 0 else ThemeBuilder.COL_BAD)
	return pv[0]


func _money_cell(txt: String, col: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", _bold)
	return l


func _ord(n: int) -> String:
	if n <= 0:
		return "—"
	return I18n.ordinal(n)
