extends VBoxContainer
## Mobile Inbox (mobile piece): list -> detail, reusing the desktop inbox's
## generator + renderer objects untouched (news/people/economy/board/reports),
## so every mail body, decision button and morale-moving reply behaves
## EXACTLY like the desktop screen — only the presentation is phone-shaped.

const NewsGen := preload("res://screens/inbox/news_gen.gd")
const ReportGen := preload("res://screens/inbox/report_gen.gd")
const BoardRoom := preload("res://screens/inbox/board_room.gd")
const Economy := preload("res://screens/inbox/economy.gd")
const PeopleGen := preload("res://screens/inbox/people_gen.gd")
const EvolutionGen := preload("res://screens/inbox/evolution_gen.gd")
const EvoSvc := preload("res://shared/sim/services/evolution.gd")

var news: RefCounted
var reports: RefCounted
var board: RefCounted
var economy: RefCounted
var people: RefCounted

var _selected: Dictionary = {}
var _action_note := ""
var _action_good := true


func _init() -> void:
	add_theme_constant_override("separation", 6)
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


func _ready() -> void:
	# generate day-by-day while Continue advances, exactly like the desktop
	# screen, so urgent items exist the moment the loop stops
	GameState.date_changed.connect(func(_d): _generate())


func go_root() -> void:
	_selected = {}
	refresh()


func refresh() -> void:
	_generate()
	for c in get_children():
		c.queue_free()
	if _selected.is_empty():
		_build_list()
	else:
		_build_detail()


func _generate() -> void:
	news.enrich_existing()
	news.generate()
	people.generate()
	economy.tick()
	board.tick()


# ---------------------------------------------------------------- list

func _build_list() -> void:
	var unread := 0
	for m in GameState.inbox:
		if not m.get("read", false):
			unread += 1
	var head := HBoxContainer.new()
	add_child(head)
	head.add_child(MUI.title(tr("Inbox"), 17))
	head.add_child(MUI.hspacer())
	var sum := MUI.dim(tr("%d unread") % unread, 11)
	sum.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sum)

	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]
	v.add_theme_constant_override("separation", 4)
	var shown := 0
	for m in GameState.inbox:
		v.add_child(_row(m))
		shown += 1
		if shown >= 120:
			break


## The rival club a transfer mail speaks for ({} when it is our own transfer
## department or no club matches the sender).
func _sender_club(sender: String) -> Dictionary:
	if sender == "":
		return {}
	for c in GameState.world.get("clubs", []):
		if str(c.get("name", "")) == sender and not GameState.is_player_club(str(c["id"])):
			return c
	return {}


func _row(m: Dictionary) -> Control:
	var r := MUI.row(func():
		_selected = m
		m["read"] = true
		refresh())
	var btn: Button = r[0]
	var h: HBoxContainer = r[1]
	var sender := str(m.get("sender", ""))
	var cat := str(m.get("cat", "board"))
	var rc: Dictionary = _sender_club(sender) if cat == "transfer" else {}
	if Portrait.is_person(sender) or TrainerArt.has_art(Portrait.person_key(sender)):
		h.add_child(Portrait.avatar(Portrait.person_key(sender), 30))
	elif cat == "cup":
		h.add_child(TrophyArt.icon(30))
	elif cat == "board":
		var pc := GameState.player_club()
		var chair: Dictionary = Portrait.board_members(pc)[0]
		h.add_child(Portrait.avatar(str(chair["name"]), 30,
			{"collar": Portrait.club_collar(pc), "age": int(chair["age"])}))
	elif not rc.is_empty():
		h.add_child(Crest.icon(rc, 30))
	else:
		var chip := PanelContainer.new()
		var col := ThemeBuilder.COL_ACCENT_DIM
		chip.add_theme_stylebox_override("panel", ThemeBuilder._flat(Color(col, 0.4), col, 6, 8, 6))
		chip.custom_minimum_size = Vector2(30, 30)
		var cl := MUI.label(str(m.get("cat", "b")).substr(0, 1).to_upper(), 12, Color.WHITE)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(cl)
		h.add_child(chip)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 0)
	var read: bool = m.get("read", false)
	var t := MUI.label(str(m.get("title", "")), 13,
		ThemeBuilder.COL_TEXT_DIM if read else Color.WHITE)
	if not read:
		t.add_theme_font_override("font", MUI.bold())
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(t)
	mid.add_child(MUI.dim(sender, 10))
	h.add_child(mid)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 1)
	var d := MUI.dim(I18n.short_date(str(m.get("date", ""))), 10)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(d)
	if m.get("urgent", false):
		side.add_child(MUI.label(tr("DECISION"), 9, ThemeBuilder.COL_BAD))
	h.add_child(side)
	return btn


# ---------------------------------------------------------------- detail

func _build_detail() -> void:
	var m := _selected
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	var back := MUI.button("‹ " + tr("Inbox"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(go_root)
	head.add_child(back)
	# straight to the next unread (user request) — thumb never leaves the top
	var nxt_msg := _next_unread()
	if not nxt_msg.is_empty():
		var nxt := MUI.button(tr("Read next ›"))
		nxt.custom_minimum_size = Vector2(0, 38)
		nxt.add_theme_font_size_override("font_size", 12)
		nxt.pressed.connect(func():
			var n := _next_unread()
			if not n.is_empty():
				_selected = n
				n["read"] = true
				_action_note = ""
				refresh())
		head.add_child(nxt)
	head.add_child(MUI.hspacer())
	head.add_child(MUI.dim(I18n.pretty_date(str(m.get("date", ""))), 11))

	var title := MUI.title(str(m.get("title", "")), 15)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	add_child(MUI.dim(tr("From: %s") % str(m.get("sender", "")), 11))
	add_child(MUI.hline())

	var rendered: Dictionary = reports.render(m)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 13)
	body.add_theme_constant_override("line_separation", 4)
	# entity deep-links (shim depth on mobile: club -> league, mon -> squad)
	body.text = EntityLinks.linkify(str(rendered.get("bbcode", "")))
	body.meta_clicked.connect(func(meta: Variant):
		var entry := EntityLinks.resolve(str(meta))
		if entry.is_empty():
			return
		var n: Node = get_parent()
		while n != null and not n.has_method("navigate_to"):
			n = n.get_parent()
		if n != null:
			n.call("navigate_to", str(entry["screen"]), entry))
	sc.add_child(body)

	var actions: Array = rendered.get("actions", [])
	if not actions.is_empty() or _action_note != "":
		var arow := HFlowContainer.new()
		arow.add_theme_constant_override("h_separation", 6)
		arow.add_theme_constant_override("v_separation", 6)
		add_child(arow)
		for a in actions:
			var kind := str(a.get("kind", "screen"))
			if kind == "mon":
				if MonActions.can_act(str(a.get("uid", ""))):
					arow.add_child(MonActions.action_pill(str(a["uid"]), str(a.get("label", tr("Actions")))))
			elif kind == "screen":
				var b := MUI.button(tr(str(a["label"])))
				b.custom_minimum_size.y = 38
				b.pressed.connect(_on_screen_action.bind(a))
				arow.add_child(b)
			else:
				arow.add_child(_decision_button(a))
		if _action_note != "":
			var note := MUI.label(_action_note, 12,
				ThemeBuilder.COL_GOOD if _action_good else ThemeBuilder.COL_WARN)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			add_child(note)


func _decision_button(a: Dictionary) -> Button:
	var col: Color
	match str(a.get("style", "")):
		"good": col = ThemeBuilder.COL_GOOD
		"bad": col = ThemeBuilder.COL_BAD
		_: col = ThemeBuilder.COL_WARN
	var b := MUI.button(tr(str(a["label"])), Color(col, 0.22), col)
	b.custom_minimum_size.y = 40
	var kind := str(a.get("kind", ""))
	if kind == "reply":
		b.pressed.connect(_on_people_reply.bind(a))
	elif kind.begins_with("evo_"):
		b.pressed.connect(_on_evolution_decision.bind(a))
	elif kind.begins_with("challenge_"):
		b.pressed.connect(_on_challenge_decision.bind(a))
	else:
		b.pressed.connect(_on_offer_decision.bind(a))
	return b


func _on_challenge_decision(a: Dictionary) -> void:
	var svc = ChallengeService.instance
	if svc == null:
		return
	if str(a["kind"]) == "challenge_accept":
		var err := str(svc.accept())
		if err != "":
			_note(err, false)
			refresh()
			return
		var n: Node = get_parent()
		while n != null and not n.has_method("open_battle"):
			n = n.get_parent()
		if n != null:
			n.call("open_battle")
	else:
		svc.decline()
		refresh()


func _on_screen_action(a: Dictionary) -> void:
	var target := str(a["screen"])
	if target == "@board":
		_note(tr("Board & Finances lives in landscape — rotate the phone."), true)
		refresh()
		return
	var n: Node = get_parent()
	while n != null and not n.has_method("navigate_to"):
		n = n.get_parent()
	if n != null:
		n.call("navigate_to", target)


func _on_people_reply(a: Dictionary) -> void:
	var res: Dictionary = people.apply_reply(_selected, a)
	_note(str(res.get("note", "")), bool(res.get("good", true)))
	GameState.save_game()
	refresh()


func _on_evolution_decision(a: Dictionary) -> void:
	var svc: RefCounted = EvoSvc.instance
	if svc == null:
		return
	var uid := str(a.get("evo_uid", ""))
	var before: Dictionary = GameState.squad_member(uid)
	var old_name: String = str(before.get("species", "?")) if not before.is_empty() else "?"
	match str(a.get("kind", "")):
		"evo_approve":
			var err: String = svc.approve(uid)
			if err == "":
				_note(tr("Approved — %s has evolved into %s.") % [old_name,
					str(GameState.squad_member(uid).get("species", "?"))], true)
			else:
				_note(err, false)
		"evo_postpone":
			var err2: String = svc.postpone(uid)
			if err2 == "":
				_note(tr("Postponed — the offer returns in %d days if still eligible (-%d morale).") % \
					[EvoSvc.REOFFER_DAYS, EvoSvc.POSTPONE_MORALE_COST], true)
			else:
				_note(err2, false)
		"evo_stone":
			var err3: String = svc.use_stone(uid, str(a.get("item", "")))
			if err3 == "":
				_note(tr("%s consumed — %s has evolved into %s.") % \
					[tr(DataStore.item_name(str(a.get("item", "")))), old_name,
					str(GameState.squad_member(uid).get("species", "?"))], true)
			else:
				_note(err3, false)
	_selected["read"] = true
	GameState.save_game()
	refresh()


func _on_offer_decision(a: Dictionary) -> void:
	var mkt: RefCounted = news.market()
	if mkt == null:
		return
	var oid := int(a.get("offer_id", -1))
	var pc: Dictionary = GameState.player_club()
	match str(a.get("kind", "")):
		"accept":
			var before := int(pc["finances"]["balance"])
			var err := str(mkt.accept_offer_in(oid))
			if err == "":
				_note(tr("Sale completed — %s credited.") % news.money(
					int(pc["finances"]["balance"]) - before), true)
			else:
				_note(err, false)
		"reject":
			mkt.reject_offer_in(oid)
			_note(tr("Offer rejected. They have been informed."), true)
		"counter":
			var cerr := str(mkt.counter_offer_in(oid, int(a.get("ask", 0))))
			if cerr == "":
				_note(tr("Demand of %s sent — expect an answer within a couple of days.") % \
					news.money(int(a.get("ask", 0))), true)
			else:
				_note(cerr, false)
	GameState.save_game()
	refresh()


## Next unread, scanning down the inbox from the open message and wrapping.
func _next_unread() -> Dictionary:
	var start := 0
	for i in GameState.inbox.size():
		if GameState.inbox[i] == _selected:
			start = i + 1
			break
	for off in GameState.inbox.size():
		var msg: Dictionary = GameState.inbox[(start + off) % GameState.inbox.size()]
		if not msg.get("read", false) and msg != _selected:
			return msg
	return {}


func _note(text: String, good: bool) -> void:
	_action_note = text
	_action_good = good
