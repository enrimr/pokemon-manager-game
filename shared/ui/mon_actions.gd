class_name MonActions
extends RefCounted
## THE global Pokémon context-action layer (FM24 "right-click anyone").
## Any mon uid, anywhere in the UI, gets a live context menu: View Profile,
## View Club, Make Transfer Offer / Approach to Sign, Send Scout, Shortlist,
## Compare with my squad. Every action reuses the transfers market API
## (screens/transfers/market.gd) — no deal logic lives here.
##
## Wiring (any screen):
##   MonActions.attach(control, uid)            # right-click on any Control
##   MonActions.action_button(uid)              # small "..." button (web-safe)
##   MonActions.wire_tree(tree, uid_of)         # right-click + "..." cell buttons
##   MonActions.tree_dots(item, col, uid)       # add the "..." to a Tree cell
##   MonActions.open_menu(host, uid)            # open the menu directly
##
## Knowledge masking is respected: below Part-scouted (50%), bidding/signing
## routes through "Send Scout First" — you cannot negotiate for a rumour.

const Market := preload("res://screens/transfers/market.gd")

const TREE_BTN_ID := 9137          # Tree cell button id reserved for actions
const OFFER_KNOW := 50.0           # market.INTERIM_AT — below this, scout first

# menu item ids
const MI_PROFILE := 1
const MI_CLUB := 2
const MI_NEGOTIATION := 3
const MI_OFFER := 4
const MI_SCOUT_FIRST := 5
const MI_SIGN := 6
const MI_SCOUT := 7
const MI_SHORTLIST := 8
const MI_COMPARE := 9
const MI_SEARCH := 10

static var _dots_cache: Dictionary = {}


static func market() -> RefCounted:
	return Market.instance()


## Horizontal-ellipsis "more actions" texture (engine-drawn, no font glyphs).
static func dots_tex(px: int = 14, col: Color = ThemeBuilder.COL_TEXT_DIM) -> Texture2D:
	var key := "%d|%s" % [px, col.to_html()]
	if _dots_cache.has(key):
		return _dots_cache[key]
	var c := "#" + col.to_html(false)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">' + \
		('<g opacity="%.2f"><circle cx="5" cy="12" r="2.6" fill="%s"/><circle cx="12" cy="12" r="2.6" fill="%s"/><circle cx="19" cy="12" r="2.6" fill="%s"/></g>' % [col.a, c, c, c]) + '</svg>'
	var img := Image.new()
	var t: Texture2D
	if img.load_svg_from_string(svg, float(px) / 24.0) == OK and not img.is_empty():
		t = ImageTexture.create_from_image(img)
	else:
		var fb := Image.create(px, px, false, Image.FORMAT_RGBA8)
		fb.fill(col)
		t = ImageTexture.create_from_image(fb)
	_dots_cache[key] = t
	return t


## True if this uid resolves to a live market/squad entity (menu-able).
static func can_act(uid: String) -> bool:
	return uid != "" and not market().find_target(uid).is_empty()


## Right-click affordance on any Control (labels, links, cards, rows).
static func attach(ctrl: Control, uid: String) -> void:
	if uid == "":
		return
	if ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		ctrl.mouse_filter = Control.MOUSE_FILTER_STOP  # labels ignore mice by default
	ctrl.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			ctrl.accept_event()
			open_menu(ctrl, uid))


## Small flat "..." button that opens the action menu (web users may not
## right-click; this is the visible affordance).
static func action_button(uid: String, px: int = 14, tip: String = "") -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.icon = dots_tex(px)
	b.tooltip_text = tip if tip != "" else I18n.t("Actions")
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(px + 10, 0)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.pressed.connect(func() -> void:
		var r := b.get_global_rect()
		open_menu(b, uid, r.position + Vector2(0.0, r.size.y)))
	return b


## Labelled action pill ("<name>  ...") — used by inbox mails and card lists.
static func action_pill(uid: String, label: String) -> Button:
	var b := Button.new()
	b.text = "  %s  " % label
	b.icon = dots_tex(13, Color.WHITE)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.custom_minimum_size = Vector2(0, 32)
	b.tooltip_text = I18n.t("Actions: offer, scout, shortlist, compare...")
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_stylebox_override("normal",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT_DIM, ThemeBuilder.COL_ACCENT, 4, 12, 6))
	b.add_theme_stylebox_override("hover",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT, ThemeBuilder.COL_ACCENT, 4, 12, 6))
	b.pressed.connect(func() -> void:
		var r := b.get_global_rect()
		open_menu(b, uid, r.position + Vector2(0.0, r.size.y)))
	return b


## Wire a whole Tree: right-click any row (uid_of(item) -> uid or "") and the
## per-cell "..." buttons added with tree_dots().
static func wire_tree(tree: Tree, uid_of: Callable) -> void:
	tree.allow_rmb_select = true   # right-click must reach the action layer
	tree.item_mouse_selected.connect(func(pos: Vector2, btn_index: int) -> void:
		if btn_index != MOUSE_BUTTON_RIGHT:
			return
		var item := tree.get_item_at_position(pos)
		if item == null:
			return
		var uid := str(uid_of.call(item))
		if uid != "":
			open_menu(tree, uid))
	tree.button_clicked.connect(func(item: TreeItem, _col: int, id: int, mbtn: int) -> void:
		if id != TREE_BTN_ID or mbtn != MOUSE_BUTTON_LEFT:
			return
		var uid := str(uid_of.call(item))
		if uid != "":
			open_menu(tree, uid))


## Add the "..." affordance to a Tree cell (pair with wire_tree).
static func tree_dots(item: TreeItem, col: int) -> void:
	item.add_button(col, dots_tex(13), TREE_BTN_ID, false, I18n.t("Actions"))


# ------------------------------------------------------------------ the menu

static func open_menu(host: Control, uid: String, at_global: Vector2 = Vector2(-INF, -INF)) -> void:
	var mkt := market()
	var t: Dictionary = mkt.find_target(uid)
	if t.is_empty():
		return
	var inst: Dictionary = t["inst"]
	var pool := String(t["pool"])
	var club_id := String(t["club_id"])
	var know: float = mkt.knowledge_of(uid)
	var m := PopupMenu.new()
	host.add_child(m)
	m.popup_hide.connect(m.queue_free)

	# header — who this is + what we know (masking honesty up front)
	var where: String
	match pool:
		"mine": where = I18n.t("your squad")
		"fa": where = I18n.t("Free agent")
		"prospect": where = I18n.t("Youth prospect")
		_: where = str(mkt.club_of(club_id).get("name", "?"))
	m.add_item("%s · Lv %d — %s" % [mkt.display_name(inst), int(inst["level"]), where])
	m.set_item_disabled(0, true)
	if pool != "mine":
		var stage: Dictionary = mkt.stage_for(know)
		m.add_item(I18n.t("Scouted: %d%% · %s") % [int(know), I18n.t(str(stage.get("name", "?")))])
		m.set_item_disabled(1, true)
	m.add_separator()

	m.add_icon_item(GlyphIcons.tex("arrow_right", 13, ThemeBuilder.COL_TEXT), I18n.t("View Profile"), MI_PROFILE)
	var club: Dictionary = mkt.club_of(club_id) if club_id != "" else {}
	if not club.is_empty() and not mkt.is_ext_club(club_id):
		m.add_icon_item(GlyphIcons.tex("flag", 13, ThemeBuilder.COL_TEXT), I18n.t("View Club (%s)") % str(club.get("short", "?")), MI_CLUB)

	if pool != "mine":
		m.add_separator()
		var live: Dictionary = mkt.offer_for_target(uid)
		if not live.is_empty():
			m.add_icon_item(GlyphIcons.tex("bag", 13, ThemeBuilder.COL_WARN), I18n.t("Go to Negotiation..."), MI_NEGOTIATION)
		elif pool == "club":
			if know >= OFFER_KNOW:
				m.add_icon_item(GlyphIcons.tex("bag", 13, ThemeBuilder.COL_GOOD), I18n.t("Make Transfer Offer..."), MI_OFFER)
			else:
				m.add_icon_item(GlyphIcons.tex("target", 13, ThemeBuilder.COL_WARN), I18n.t("Make Offer — Scout First..."), MI_SCOUT_FIRST)
				m.set_item_tooltip(m.get_item_index(MI_SCOUT_FIRST),
					I18n.t("We know too little to negotiate (below Part scouted, 50%). Send a scout to build the file first."))
		else:
			if know >= OFFER_KNOW:
				m.add_icon_item(GlyphIcons.tex("bag", 13, ThemeBuilder.COL_GOOD), I18n.t("Approach to Sign..."), MI_SIGN)
			else:
				m.add_icon_item(GlyphIcons.tex("target", 13, ThemeBuilder.COL_WARN), I18n.t("Approach to Sign — Scout First..."), MI_SCOUT_FIRST)
				m.set_item_tooltip(m.get_item_index(MI_SCOUT_FIRST),
					I18n.t("We know too little to negotiate (below Part scouted, 50%). Send a scout to build the file first."))
		var a: Dictionary = mkt.assignment_for_target(uid)
		if a.is_empty():
			m.add_icon_item(GlyphIcons.tex("target", 13, ThemeBuilder.COL_TEXT), I18n.t("Send Scout..."), MI_SCOUT)
		else:
			m.add_icon_item(GlyphIcons.tex("target", 13, ThemeBuilder.COL_TEXT_DIM),
				I18n.t("Scout on the case (~%dd left)") % mkt.assignment_eta(a), MI_SCOUT)
			m.set_item_disabled(m.get_item_index(MI_SCOUT), true)
		if mkt.shortlisted(uid):
			m.add_icon_item(GlyphIcons.tex("star", 13, ThemeBuilder.COL_WARN), I18n.t("Remove from Shortlist"), MI_SHORTLIST)
		else:
			m.add_icon_item(GlyphIcons.tex("star_empty", 13, ThemeBuilder.COL_TEXT), I18n.t("Add to Shortlist"), MI_SHORTLIST)
	m.add_icon_item(GlyphIcons.tex("swap", 13, ThemeBuilder.COL_TEXT), I18n.t("Compare with My Squad..."), MI_COMPARE)
	if pool != "mine":
		m.add_separator()
		m.add_icon_item(GlyphIcons.tex("menu", 13, ThemeBuilder.COL_TEXT_DIM), I18n.t("Open in Transfer Search"), MI_SEARCH)

	m.id_pressed.connect(func(id: int) -> void: _run(host, uid, id))
	if at_global.x == -INF:
		at_global = host.get_global_mouse_position()
	m.position = Vector2i(at_global)
	m.popup()
	# keep the menu on-screen (bottom rows / right edge)
	var vp: Vector2 = host.get_viewport_rect().size
	m.position = Vector2i(
		clampi(m.position.x, 0, maxi(0, int(vp.x) - m.size.x)),
		clampi(m.position.y, 0, maxi(0, int(vp.y) - m.size.y)))


static func _run(host: Control, uid: String, id: int) -> void:
	var mkt := market()
	match id:
		MI_PROFILE:
			view_profile(host, uid)
		MI_CLUB:
			var t: Dictionary = mkt.find_target(uid)
			_navigate(host, "competition", {"kind": "club", "id": str(t.get("club_id", "")),
				"label": str(mkt.club_of(str(t.get("club_id", ""))).get("name", ""))})
		MI_NEGOTIATION:
			_navigate(host, "transfers", {"kind": "tab", "tab": "centre", "label": I18n.t("Transfer Centre")})
		MI_OFFER:
			open_offer_sheet(host, uid)
		MI_SIGN:
			open_contract_sheet(host, uid)
		MI_SCOUT_FIRST, MI_SCOUT:
			open_scout_dialog(host, uid)
		MI_SHORTLIST:
			var was: bool = mkt.shortlisted(uid)
			var msg: String = mkt.toggle_shortlist(uid)
			if msg != "":
				_err(host, msg)
			else:
				_toast(host, I18n.t("Removed from shortlist") if was else I18n.t("Added to shortlist — see Transfers » Recruitment"))
		MI_COMPARE:
			open_compare(host, uid)
		MI_SEARCH:
			_navigate(host, "transfers", {"kind": "pokemon", "id": uid, "tab": "search"})


## Profile routing: my mon -> Squad; a league club's mon -> Competition
## profile; free agents / prospects / overseas -> Transfer Search detail.
static func view_profile(host: Control, uid: String) -> void:
	var mkt := market()
	var t: Dictionary = mkt.find_target(uid)
	if t.is_empty():
		return
	var pool := String(t["pool"])
	var label: String = mkt.display_name(t["inst"])
	if pool == "mine":
		_navigate(host, "squad", {"kind": "pokemon", "id": uid, "label": label})
	elif pool == "club" and not mkt.is_ext_club(String(t["club_id"])):
		_navigate(host, "competition", {"kind": "pokemon", "id": uid, "label": label})
	else:
		_navigate(host, "transfers", {"kind": "pokemon", "id": uid, "tab": "search", "label": label})


# ------------------------------------------------------------------ plumbing

static func _shell(host: Node) -> Node:
	var n: Node = host
	while n != null:
		if n.has_method("navigate_to"):
			return n
		n = n.get_parent()
	return null


static func _navigate(host: Control, screen: String, ctx: Dictionary) -> void:
	var sh := _shell(host)
	if sh != null:
		sh.call("navigate_to", screen, ctx)


static func _toast(host: Control, msg: String) -> void:
	var sh := _shell(host)
	if sh != null and sh.has_method("toast"):
		sh.call("toast", msg)


static func _err(host: Control, msg: String) -> void:
	if msg == "":
		return
	var dlg := AcceptDialog.new()
	dlg.title = I18n.t("Transfer Centre")
	dlg.dialog_text = msg
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	ThemeBuilder.popup_fitted(host, dlg)


static func _dlabel(txt: String, col: Color = ThemeBuilder.COL_TEXT, size: int = 14, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 440
	return l


static func _sheet_spin(minv: int, maxv: int, step: int, val: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minv
	spin.max_value = maxv
	spin.step = step
	spin.value = val
	spin.custom_minimum_size.x = 150
	return spin


static func _sheet_row(grid: GridContainer, label_txt: String, ctl: Control, note: String = "") -> void:
	grid.add_child(_dlabel(label_txt, ThemeBuilder.COL_TEXT, 13))
	if note == "":
		grid.add_child(ctl)
	else:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.add_child(ctl)
		hb.add_child(_dlabel(note, ThemeBuilder.COL_TEXT_DIM, 11))
		grid.add_child(hb)


# ------------------------------------------------------- the offer sheet
# Ported from the transfers screen so EVERY screen shares one negotiation UI;
# the transfers screen now delegates here. All maths/validation = market API.

static func open_offer_sheet(host: Control, uid: String, offer_id: int = -1) -> void:
	var mkt := market()
	var t: Dictionary = mkt.find_target(uid)
	if t.is_empty() or t["pool"] != "club":
		return
	var inst: Dictionary = t["inst"]
	var existing: Dictionary = mkt._offer_out(offer_id) if offer_id >= 0 else {}
	var locked_kind := "" if existing.is_empty() else String(existing["kind"])

	var dlg := ConfirmationDialog.new()
	dlg.title = (I18n.t("Offer for %s") if existing.is_empty() else I18n.t("Revise offer — %s")) % mkt.display_name(inst)
	dlg.min_size = Vector2i(520, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	dlg.add_child(vb)

	vb.add_child(_dlabel(I18n.t("Selling club: %s   ·   their likely valuation: %s") % [
		mkt.club_of(t["club_id"])["name"],
		mkt.masked_money(uid, "val", mkt.ask_price(inst, t["club_id"]))], ThemeBuilder.COL_TEXT_DIM, 13, true))
	vb.add_child(_dlabel(I18n.t("Transfer budget: %s   ·   wage room: %s/wk") % [
		mkt.fmt_money_full(maxi(0, mkt.spendable_budget())), mkt.fmt_money(mkt.wage_room())],
		ThemeBuilder.COL_TEXT_DIM, 13))
	var dd: int = mkt.days_to_deadline()
	if dd == 0:
		vb.add_child(_dlabel(I18n.t("DEADLINE DAY — they will answer within hours. This deal completes today or never."), ThemeBuilder.COL_BAD, 12, true))
	elif dd >= 1 and dd <= 7:
		vb.add_child(_dlabel(I18n.t("Window closes in %d day%s. Unfinished deals collapse at the deadline, and rival clubs are circling.") % [dd, "" if dd == 1 else "s"], ThemeBuilder.COL_WARN, 12, true))

	var mode := OptionButton.new()
	mode.add_item(I18n.t("Permanent transfer"))
	mode.add_item(I18n.t("Season loan"))
	if locked_kind != "":
		mode.selected = 1 if locked_kind == "loan" else 0
		mode.disabled = true
	vb.add_child(mode)
	vb.add_child(HSeparator.new())

	var pgrid := GridContainer.new()
	pgrid.columns = 2
	pgrid.add_theme_constant_override("h_separation", 16)
	pgrid.add_theme_constant_override("v_separation", 4)
	vb.add_child(pgrid)
	var pre: Dictionary = mkt.blank_package(mini(maxi(0, mkt.spendable_budget()), mkt.value_of(inst)))
	if not existing.is_empty() and existing["kind"] == "buy":
		pre = existing["ask_package"] if not existing.get("ask_package", {}).is_empty() else existing["package"]
	var up_spin := _sheet_spin(0, 10000000, 1000, int(pre.get("upfront", 0)))
	_sheet_row(pgrid, I18n.t("Up-front fee"), up_spin, I18n.t("cash now, from our transfer budget"))
	var inst_spin := _sheet_spin(0, 10000000, 1000, int(pre.get("inst_amount", 0)))
	_sheet_row(pgrid, I18n.t("Installments (total)"), inst_spin, I18n.t("paid yearly — they discount deferred money"))
	var years_opt := OptionButton.new()
	for y in [1, 2, 3]:
		years_opt.add_item(I18n.t("over %d year%s") % [y, "" if y == 1 else "s"])
	years_opt.selected = clampi(int(pre.get("inst_years", 2)), 1, 3) - 1
	_sheet_row(pgrid, I18n.t("Installment term"), years_opt)
	var sellon_spin := _sheet_spin(0, 50, 5, int(pre.get("sell_on", 0)))
	_sheet_row(pgrid, I18n.t("Sell-on clause %"), sellon_spin, I18n.t("% of the NEXT sale fee they keep"))

	var lgrid := GridContainer.new()
	lgrid.columns = 2
	lgrid.add_theme_constant_override("h_separation", 16)
	lgrid.add_theme_constant_override("v_separation", 4)
	vb.add_child(lgrid)
	var lpre := {"wage_split": 100, "option_fee": 0}
	if not existing.is_empty() and existing["kind"] == "loan":
		lpre = existing["loan_ask"] if not existing.get("loan_ask", {}).is_empty() else existing["loan_terms"]
	var split_spin := _sheet_spin(0, 100, 10, int(lpre.get("wage_split", 100)))
	_sheet_row(lgrid, I18n.t("Wages we cover %"), split_spin, I18n.t("of their %s/wk") % mkt.masked_money(uid, "wage", int(inst["contract"]["salary"])))
	var opt_spin := _sheet_spin(0, 10000000, 1000, int(lpre.get("option_fee", 0)))
	_sheet_row(lgrid, I18n.t("Option to buy fee"), opt_spin, I18n.t("buy them outright mid-loan"))
	vb.add_child(_dlabel(I18n.t("Loan runs until %s.") % I18n.pretty_date(mkt.loan_until()), ThemeBuilder.COL_TEXT_DIM, 11))

	var summary := _dlabel("", ThemeBuilder.COL_TEXT, 13, true)
	vb.add_child(summary)
	var hint := _dlabel("", ThemeBuilder.COL_WARN, 12, true)
	hint.custom_minimum_size.x = 470
	vb.add_child(hint)

	var refresh := func() -> void:
		var is_loan: bool = mode.selected == 1
		pgrid.visible = not is_loan
		lgrid.visible = is_loan
		lgrid.get_parent().get_child(lgrid.get_index() + 1).visible = is_loan  # loan-until note
		if is_loan:
			summary.text = mkt.describe_loan({"wage_split": int(split_spin.value), "option_fee": int(opt_spin.value)})
			hint.text = mkt.loan_hint(uid)
		else:
			var pkg := {"upfront": int(up_spin.value), "inst_amount": int(inst_spin.value),
				"inst_years": years_opt.selected + 1, "sell_on": int(sellon_spin.value)}
			summary.text = I18n.t("Package: %s   (headline %s)") % [mkt.describe_package(pkg), mkt.fmt_money(mkt.package_total(pkg))]
			hint.text = mkt.offer_hint(uid, pkg)
	mode.item_selected.connect(func(_i): refresh.call())
	for s in [up_spin, inst_spin, sellon_spin, split_spin, opt_spin]:
		s.value_changed.connect(func(_v): refresh.call())
	years_opt.item_selected.connect(func(_i): refresh.call())
	refresh.call()

	dlg.get_ok_button().text = I18n.t("Submit Offer")
	dlg.confirmed.connect(func() -> void:
		var msg: String
		if mode.selected == 1:
			if offer_id >= 0:
				msg = mkt.revise_loan(offer_id, int(split_spin.value), int(opt_spin.value))
			else:
				msg = mkt.make_loan_offer(uid, int(split_spin.value), int(opt_spin.value))
		else:
			var pkg := {"upfront": int(up_spin.value), "inst_amount": int(inst_spin.value),
				"inst_years": years_opt.selected + 1, "sell_on": int(sellon_spin.value)}
			if offer_id >= 0:
				msg = mkt.revise_offer(offer_id, pkg)
			else:
				msg = mkt.make_offer(uid, pkg)
		if msg == "":
			_toast(host, I18n.t("Offer submitted — track it in the Transfer Centre"))
		_err(host, msg)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	ThemeBuilder.popup_fitted(host, dlg, vb)


# ------------------------------------------------------- personal terms sheet

static func open_contract_sheet(host: Control, uid: String, offer_id: int = -1) -> void:
	var mkt := market()
	var t: Dictionary = mkt.find_target(uid)
	if t.is_empty():
		return
	var inst: Dictionary = t["inst"]
	var existing: Dictionary = mkt._offer_out(offer_id) if offer_id >= 0 else {}
	var demand: Dictionary = {} if existing.is_empty() else existing.get("contract_demand", {})
	var known_wage := int(demand.get("wage", 0))

	var dlg := ConfirmationDialog.new()
	dlg.title = I18n.t("Personal terms — %s") % mkt.display_name(inst)
	dlg.min_size = Vector2i(520, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	dlg.add_child(vb)

	if known_wage > 0:
		vb.add_child(_dlabel(I18n.t("Their demand: %s/wk (prefers a %d-year deal as %s)") % [
			mkt.fmt_money(known_wage), int(demand.get("years", 3)), String(demand.get("status", I18n.t("First team")))],
			ThemeBuilder.COL_WARN, 13, true))
	else:
		vb.add_child(_dlabel(I18n.t("Estimated wage demand: %s/wk") % mkt.masked_money(uid, "wage", int(inst["contract"]["salary"])),
			ThemeBuilder.COL_TEXT_DIM, 13))
	if t["pool"] == "prospect":
		vb.add_child(_dlabel(I18n.t("Development compensation due: %s") % mkt.fmt_money(int(round(mkt.value_of(inst) * 0.35 / 1000.0)) * 1000),
			ThemeBuilder.COL_WARN, 13))
	vb.add_child(_dlabel(I18n.t("Our wage room: %s/wk   ·   transfer budget: %s") % [
		mkt.fmt_money(mkt.wage_room()), mkt.fmt_money(maxi(0, mkt.spendable_budget()))],
		ThemeBuilder.COL_TEXT_DIM, 13))
	vb.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	var def_wage := known_wage if known_wage > 0 else int(float(inst["contract"]["salary"]) * 1.2)
	var wage_spin := _sheet_spin(0, 100000, 10, def_wage)
	_sheet_row(grid, I18n.t("Weekly wage"), wage_spin)
	var years_opt := OptionButton.new()
	for y in [1, 2, 3, 4]:
		years_opt.add_item(I18n.t("%d year%s") % [y, "" if y == 1 else "s"])
	years_opt.selected = clampi(int(demand.get("years", 3)), 1, 4) - 1
	_sheet_row(grid, I18n.t("Contract length"), years_opt, I18n.t("longer = security, they take less/wk"))
	var bonus_spin := _sheet_spin(0, 2000000, 500, 0)
	_sheet_row(grid, I18n.t("Signing bonus"), bonus_spin, I18n.t("one-off cash, sweetens low wages"))
	var status_opt := OptionButton.new()
	for st in mkt.SQUAD_STATUSES:
		status_opt.add_item(st)
	status_opt.selected = maxi(0, mkt.SQUAD_STATUSES.find(String(demand.get("status", I18n.t("First team")))))
	_sheet_row(grid, I18n.t("Promised role"), status_opt, I18n.t("a bigger promise trims the wage"))

	var hint := _dlabel("", ThemeBuilder.COL_WARN, 12, true)
	hint.custom_minimum_size.x = 470
	vb.add_child(hint)
	var build_con := func() -> Dictionary:
		return {"wage": int(wage_spin.value), "years": years_opt.selected + 1,
			"bonus": int(bonus_spin.value), "status": mkt.SQUAD_STATUSES[status_opt.selected]}
	var refresh := func() -> void:
		hint.text = mkt.contract_hint(uid, build_con.call(), known_wage)
	wage_spin.value_changed.connect(func(_v): refresh.call())
	bonus_spin.value_changed.connect(func(_v): refresh.call())
	years_opt.item_selected.connect(func(_i): refresh.call())
	status_opt.item_selected.connect(func(_i): refresh.call())
	refresh.call()

	dlg.get_ok_button().text = I18n.t("Offer Contract")
	dlg.confirmed.connect(func() -> void:
		var con: Dictionary = build_con.call()
		var msg: String
		if offer_id >= 0:
			msg = mkt.offer_contract(offer_id, con)
		else:
			msg = mkt.sign_free_agent(uid, con)
		if msg == "":
			_toast(host, I18n.t("Contract offered — track it in the Transfer Centre"))
		_err(host, msg)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	ThemeBuilder.popup_fitted(host, dlg, vb)


# ------------------------------------------------------------ scout dialog

static func open_scout_dialog(host: Control, uid: String) -> void:
	var mkt := market()
	var idle: Array = mkt.player_scouts().filter(func(s): return mkt.assignment_for_scout(s["name"]).is_empty())
	if idle.is_empty():
		_err(host, I18n.t("All scouts are on assignment. Recall one from the Scouting tab first."))
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = I18n.t("Assign scout")
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var t: Dictionary = mkt.find_target(uid)
	vb.add_child(_dlabel(I18n.t("Target: %s") % ("" if t.is_empty() else mkt.display_name(t["inst"])), ThemeBuilder.COL_TEXT, 14))
	if not t.is_empty() and mkt.knowledge_of(uid) < OFFER_KNOW and mkt.offer_for_target(uid).is_empty():
		vb.add_child(_dlabel(I18n.t("Negotiations unlock at Part scouted (50%) — the report also prices the deal honestly."),
			ThemeBuilder.COL_WARN, 11, true))
	var opt := OptionButton.new()
	var treg: String = "" if t.is_empty() else mkt.region_of(t["inst"])
	if not t.is_empty():
		vb.add_child(_dlabel(I18n.t("Region: %s · a full report takes real days — travel first, then fieldwork; home-patch scouts read faster and truer.") % treg,
			ThemeBuilder.COL_TEXT_DIM, 11, true))
	for s in idle:
		var home: String = I18n.t(" · home patch") if mkt.scout_region(s) == treg else ""
		var trav: int = mkt.travel_days(mkt.scout_location(s), treg)
		opt.add_item(I18n.t("%s (JA %d · ~%d days to full%s%s)") % [s["name"], int(s["ratings"]["judging_ability"]),
			mkt.scout_days_for(s, uid), (I18n.t(" · %dd travel") % trav) if trav > 0 else "", home])
	vb.add_child(opt)
	dlg.add_child(vb)
	dlg.get_ok_button().text = I18n.t("Send")
	dlg.confirmed.connect(func() -> void:
		var msg: String = mkt.assign_scout_to_target(idle[opt.selected]["name"], uid)
		if msg == "":
			_toast(host, I18n.t("Scout dispatched — reports land in your inbox"))
		_err(host, msg)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	ThemeBuilder.popup_fitted(host, dlg, vb)


# ------------------------------------------------------------ compare dialog

static func open_compare(host: Control, uid: String) -> void:
	var mkt := market()
	var t: Dictionary = mkt.find_target(uid)
	if t.is_empty():
		return
	_compare_dialog(host, t["inst"], uid)


## Compare an instance you fully know (own academy juvenile, own squad mon)
## against the first team — no market registration needed.
static func open_compare_inst(host: Control, inst: Dictionary) -> void:
	_compare_dialog(host, inst, "")


const _STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]

static func _compare_dialog(host: Control, inst: Dictionary, uid: String) -> void:
	var mkt := market()
	var dlg := AcceptDialog.new()
	dlg.title = I18n.t("Compare with my squad — %s") % mkt.display_name(inst)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	dlg.add_child(vb)
	var know: float = 100.0 if uid == "" else mkt.knowledge_of(uid)
	if know < 100.0:
		vb.add_child(_dlabel(I18n.t("Scouted %d%% — their numbers are our scouts' estimated ranges, not facts.") % int(know),
			ThemeBuilder.COL_WARN, 12, true))
	vb.add_child(_dlabel(I18n.t("Battle-real stats (nature applied) — the same numbers the engine fights with."),
		ThemeBuilder.COL_TEXT_DIM, 11, true))

	var tree := Tree.new()
	tree.hide_root = true
	tree.columns = 9
	tree.column_titles_visible = true
	tree.custom_minimum_size = Vector2(760, 320)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titles := [I18n.t("POKÉMON"), "LV", "HP", "ATK", "DEF", "SPA", "SPD", "SPE", "TOT"]
	for i in titles.size():
		tree.set_column_title(i, titles[i])
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER)
		if i > 0:
			tree.set_column_expand(i, false)
			tree.set_column_custom_minimum_width(i, 42 if i == 1 else (74 if i < 8 else 66))
	var root := tree.create_item()

	# target row (masked below full knowledge) + midpoint estimates to tint vs
	var exact: Dictionary = mkt.battle_stats(inst)
	var mid := {}
	var tot_mid := 0
	var it := tree.create_item(root)
	it.set_text(0, "%s (Lv %d)" % [mkt.display_name(inst), int(inst["level"])])
	it.set_custom_color(0, ThemeBuilder.COL_ACCENT)
	it.set_text(1, str(int(inst["level"])))
	for i in _STAT_KEYS.size():
		var k: String = _STAT_KEYS[i]
		var ex := int(exact[k])
		if uid == "" or know >= 100.0:
			it.set_text(i + 2, str(ex))
			mid[k] = ex
		else:
			var b: Array = mkt.masked_bounds(uid, k, ex)
			it.set_text(i + 2, "%d-%d" % [int(b[0]), int(b[1])] if int(b[0]) != int(b[1]) else str(ex))
			mid[k] = int(round((float(b[0]) + float(b[1])) / 2.0))
		tot_mid += int(mid[k])
		it.set_text_alignment(i + 2, HORIZONTAL_ALIGNMENT_CENTER)
		it.set_custom_color(i + 2, ThemeBuilder.COL_ACCENT)
	it.set_text(8, str(tot_mid) if know >= 100.0 or uid == "" else ("~%d" % tot_mid))
	it.set_text_alignment(8, HORIZONTAL_ALIGNMENT_CENTER)
	it.set_custom_color(8, ThemeBuilder.COL_ACCENT)

	# my squad, strongest first — green where we already beat them
	var squad: Array = GameState.player_club()["squad"].duplicate()
	squad.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	for sm in squad:
		var row := tree.create_item(root)
		var ms: Dictionary = mkt.battle_stats(sm)
		row.set_text(0, mkt.display_name(sm))
		row.set_text(1, str(int(sm["level"])))
		row.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
		var tot := 0
		for i in _STAT_KEYS.size():
			var k: String = _STAT_KEYS[i]
			var v := int(ms[k])
			tot += v
			row.set_text(i + 2, str(v))
			row.set_text_alignment(i + 2, HORIZONTAL_ALIGNMENT_CENTER)
			row.set_custom_color(i + 2, ThemeBuilder.COL_GOOD if v >= int(mid[k]) else ThemeBuilder.COL_BAD)
		row.set_text(8, str(tot))
		row.set_text_alignment(8, HORIZONTAL_ALIGNMENT_CENTER)
		row.set_custom_color(8, ThemeBuilder.COL_GOOD if tot >= tot_mid else ThemeBuilder.COL_BAD)
	vb.add_child(tree)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	ThemeBuilder.popup_fitted(host, dlg, vb)
