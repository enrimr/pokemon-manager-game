extends RefCounted
## Squad piece: shared action UI — the right-click context menu used by the
## squad table and the profile, plus the modal dialogs behind each management
## action (contract negotiation, transfer listing, bids, release, praise /
## discipline, nickname, training focus). All mutations go through SquadService.

const UI := preload("res://screens/squad/ui_helpers.gd")
const SeasonStats := preload("res://screens/squad/season_stats.gd")
const Service := preload("res://screens/squad/squad_service.gd")

const FOCUS_LABELS := {"": "Balanced (no focus)", "hp": "HP", "atk": "Attack",
	"def": "Defence", "spa": "Sp. Attack", "spd": "Sp. Defence", "spe": "Speed"}
const FOCUS_KEYS := ["", "hp", "atk", "def", "spa", "spd", "spe"]

const ID_PROFILE := 1
const ID_CONTRACT := 2
const ID_LIST := 3
const ID_OFFERS := 4
const ID_PRAISE := 5
const ID_DISCIPLINE := 6
const ID_NICKNAME := 7
const ID_RELEASE := 8
const ID_COMPARE := 9
const ID_FOCUS_BASE := 100


# ------------------------------------------------------------------ context menu

## Build and show the management context menu for a squad member.
## `open_profile` may be Callable() when already on the profile.
static func open_menu(host: Control, uid: String, at_screen_pos: Vector2,
		open_profile: Callable = Callable(), compare: Callable = Callable()) -> PopupMenu:
	var svc: Node = Service.ensure()
	var inst: Dictionary = svc.find_instance(uid)
	if inst.is_empty():
		return null
	var name: String = UI.display_name(inst)
	var listed: bool = svc.is_listed(inst)
	var bids: Array = svc.offers_for(uid)

	var menu := PopupMenu.new()
	host.add_child(menu)
	menu.popup_hide.connect(menu.queue_free)

	if open_profile.is_valid():
		menu.add_item("Open Profile", ID_PROFILE)
		menu.add_separator()
	menu.add_item("Offer New Contract...", ID_CONTRACT)
	if svc.talks_locked(uid):
		menu.set_item_disabled(menu.get_item_index(ID_CONTRACT), true)
		menu.set_item_text(menu.get_item_index(ID_CONTRACT),
			"Offer New Contract (talks off until %s)" % Season.pretty_date(svc.talks_locked_until(uid)))
	menu.add_item(("Remove From Transfer List" if listed else "Add To Transfer List..."), ID_LIST)
	if not bids.is_empty():
		menu.add_item("Respond To %d Bid%s..." % [bids.size(), "s" if bids.size() > 1 else ""], ID_OFFERS)
	menu.add_item("Terminate Contract (Release)...", ID_RELEASE)
	menu.add_separator("Interaction")
	menu.add_item("Praise Recent Form", ID_PRAISE)
	menu.add_item("Criticise Recent Form", ID_DISCIPLINE)
	if not svc.can_interact(uid):
		for act_id in [ID_PRAISE, ID_DISCIPLINE]:
			menu.set_item_disabled(menu.get_item_index(act_id), true)
		menu.set_item_text(menu.get_item_index(ID_DISCIPLINE),
			"Criticise Recent Form (next chat %s)" % Season.pretty_date(svc.interaction_available_on(uid)))
	menu.add_separator("Development")
	var focus_menu := PopupMenu.new()
	focus_menu.name = "TrainingFocus"
	var current_focus: String = svc.training_focus(uid)
	for i in FOCUS_KEYS.size():
		var key: String = FOCUS_KEYS[i]
		focus_menu.add_radio_check_item(FOCUS_LABELS[key], ID_FOCUS_BASE + i)
		focus_menu.set_item_checked(i, key == current_focus)
	menu.add_child(focus_menu)
	menu.add_submenu_item("Set Training Focus", "TrainingFocus")
	menu.add_item("Set Nickname...", ID_NICKNAME)
	if compare.is_valid():
		menu.add_separator()
		menu.add_item("Compare With Teammate...", ID_COMPARE)

	var on_id := func(id: int) -> void:
		if id >= ID_FOCUS_BASE:
			svc.set_training_focus(uid, FOCUS_KEYS[id - ID_FOCUS_BASE])
			return
		match id:
			ID_PROFILE:
				if open_profile.is_valid():
					open_profile.call(uid)
			ID_CONTRACT: open_contract_dialog(host, uid)
			ID_LIST:
				if svc.is_listed(svc.find_instance(uid)):
					var err: String = svc.unlist(uid)
					if err != "":
						notice(host, "Transfer list", err)
				else:
					open_list_dialog(host, uid)
			ID_OFFERS: open_offers_dialog(host, uid)
			ID_RELEASE: open_release_dialog(host, uid)
			ID_PRAISE: interact(host, uid, true)
			ID_DISCIPLINE: interact(host, uid, false)
			ID_NICKNAME: open_nickname_dialog(host, uid)
			ID_COMPARE:
				if compare.is_valid():
					compare.call(uid)
	menu.id_pressed.connect(on_id)
	focus_menu.id_pressed.connect(on_id)
	menu.position = Vector2i(at_screen_pos)
	menu.popup()
	# Keep the menu on screen.
	var vp := host.get_viewport_rect().size
	menu.position = Vector2i(
		mini(menu.position.x, int(vp.x) - menu.size.x - 8),
		mini(menu.position.y, int(vp.y) - menu.size.y - 8))
	return menu


# ------------------------------------------------------------------ small helpers

static func notice(host: Control, title: String, message: String) -> void:
	var d := AcceptDialog.new()
	d.title = title
	d.dialog_text = message
	d.dialog_autowrap = true
	d.min_size = Vector2i(420, 0)
	host.add_child(d)
	d.close_requested.connect(d.queue_free)
	d.confirmed.connect(d.queue_free)
	d.popup_centered()


static func interact(host: Control, uid: String, is_praise: bool) -> void:
	var svc: Node = Service.ensure()
	var res: Dictionary = svc.praise(uid) if is_praise else svc.discipline(uid)
	notice(host, "Praise" if is_praise else "Criticism", str(res["message"]))


static func _dialog(title: String) -> Array:
	# Returns [AcceptDialog, VBoxContainer body]. Caller parents + pops it up.
	var d := AcceptDialog.new()
	d.title = title
	d.min_size = Vector2i(470, 0)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	d.add_child(body)
	d.close_requested.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	return [d, body]


static func _kv(grid: GridContainer, key: String, value: String, col: Color = UI.COL_TEXT) -> Label:
	var k := Label.new()
	k.text = key
	k.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	grid.add_child(k)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_color_override("font_color", col)
	grid.add_child(v)
	return v


# ------------------------------------------------------------------ contract negotiation

static func open_contract_dialog(host: Control, uid: String) -> AcceptDialog:
	var svc: Node = Service.ensure()
	var inst: Dictionary = svc.find_instance(uid)
	if inst.is_empty():
		return null
	var opened: Dictionary = svc.open_talks(uid)
	if opened.has("error"):
		notice(host, "Contract talks", str(opened["error"]))
		return null
	var name: String = UI.display_name(inst)

	var pk := _dialog("Contract talks — %s" % name)
	var d: AcceptDialog = pk[0]
	var body: VBoxContainer = pk[1]
	d.get_ok_button().text = "Leave Talks"

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	_kv(grid, "Current deal", "%s/wk to %s" % [UI.money(int(inst["contract"]["salary"])),
		Season.pretty_date(inst["contract"]["expiry"])])
	_kv(grid, "Estimated value", UI.money(UI.est_value(inst)))
	var demand_lbl := _kv(grid, "Their demand",
		"%s/wk on a %d-year deal" % [UI.money(int(opened["wage"])), int(opened["years"])], UI.COL_WARN)
	var bill_lbl := _kv(grid, "Wage bill if agreed", "", UI.COL_TEXT)

	for f in opened.get("factors", []):
		var fl := Label.new()
		fl.text = "· " + str(f)
		fl.add_theme_font_size_override("font_size", 12)
		fl.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
		body.add_child(fl)

	body.add_child(HSeparator.new())

	# --- offer controls
	var offer_grid := GridContainer.new()
	offer_grid.columns = 2
	offer_grid.add_theme_constant_override("v_separation", 6)
	offer_grid.add_theme_constant_override("h_separation", 12)
	body.add_child(offer_grid)

	var wage_l := Label.new()
	wage_l.text = "Weekly wage"
	wage_l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	offer_grid.add_child(wage_l)
	var wage := SpinBox.new()
	wage.min_value = 50
	wage.max_value = 20000
	wage.step = 10
	wage.value = int(opened["wage"])
	wage.custom_minimum_size = Vector2(160, 0)
	wage.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	offer_grid.add_child(wage)

	var len_l := Label.new()
	len_l.text = "Contract length"
	len_l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	offer_grid.add_child(len_l)
	var years := OptionButton.new()
	for y in [1, 2, 3]:
		years.add_item("%d year%s" % [y, "s" if y > 1 else ""], y)
	years.selected = clampi(int(opened["years"]) - 1, 0, 2)
	years.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	offer_grid.add_child(years)

	var bonus_l := Label.new()
	bonus_l.text = "Signing bonus (one-off)"
	bonus_l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	offer_grid.add_child(bonus_l)
	var bonus := SpinBox.new()
	bonus.min_value = 0
	bonus.max_value = maxf(float(svc.balance()), 0.0)
	bonus.step = 250
	bonus.value = 0
	bonus.custom_minimum_size = Vector2(160, 0)
	bonus.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	offer_grid.add_child(bonus)

	var round_lbl := Label.new()
	round_lbl.add_theme_font_size_override("font_size", 12)
	round_lbl.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	round_lbl.text = "Round %d of %d" % [int(opened["round"]) + 1, Service.MAX_TALK_ROUNDS]
	body.add_child(round_lbl)

	var response := Label.new()
	response.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	response.custom_minimum_size = Vector2(430, 56)
	response.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	response.add_theme_color_override("font_color", UI.COL_TEXT)
	response.text = "%s's agent is listening. Meet the demand or get close with a bonus." % name
	body.add_child(response)

	var submit := d.add_button("Submit Offer", true, "submit")
	var update_bill := func() -> void:
		var new_bill: int = svc.wage_bill() - int(inst["contract"]["salary"]) + int(wage.value)
		bill_lbl.text = "%s/wk of %s/wk budget" % [UI.money(new_bill), UI.money(svc.wage_budget())]
		bill_lbl.add_theme_color_override("font_color",
			UI.COL_BAD if new_bill > svc.wage_budget() else UI.COL_GOOD)
	update_bill.call()
	wage.value_changed.connect(func(_v: float) -> void: update_bill.call())

	d.custom_action.connect(func(action: StringName) -> void:
		if action != "submit":
			return
		var res: Dictionary = svc.negotiate_contract(uid, int(wage.value),
			years.get_selected_id(), int(bonus.value))
		response.text = str(res["message"])
		match str(res["status"]):
			"accepted":
				response.add_theme_color_override("font_color", UI.COL_GOOD)
				submit.disabled = true
				d.get_ok_button().text = "Done"
				round_lbl.text = "Agreed"
			"countered":
				response.add_theme_color_override("font_color", UI.COL_WARN)
				demand_lbl.text = "%s/wk on a %d-year deal" % [UI.money(int(res["wage"])), int(res["years"])]
				var again: Dictionary = svc.open_talks(uid)
				round_lbl.text = "Round %d of %d" % [int(again.get("round", 0)) + 1, Service.MAX_TALK_ROUNDS]
			"walked":
				response.add_theme_color_override("font_color", UI.COL_BAD)
				submit.disabled = true
				d.get_ok_button().text = "Done"
				round_lbl.text = "Talks collapsed"
			_:
				response.add_theme_color_override("font_color", UI.COL_BAD)
		update_bill.call())
	d.confirmed.connect(d.queue_free)
	host.add_child(d)
	d.popup_centered()
	return d


# ------------------------------------------------------------------ transfer list

static func open_list_dialog(host: Control, uid: String) -> void:
	var svc: Node = Service.ensure()
	var inst: Dictionary = svc.find_instance(uid)
	if inst.is_empty():
		return
	var value := UI.est_value(inst)
	var pk := _dialog("Transfer list — %s" % UI.display_name(inst))
	var d: AcceptDialog = pk[0]
	var body: VBoxContainer = pk[1]
	d.get_ok_button().text = "List For Sale"
	d.add_cancel_button("Cancel")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	_kv(grid, "Estimated value", UI.money(value))
	_kv(grid, "Current wage", UI.money(int(inst["contract"]["salary"])) + "/wk")

	var ask_row := HBoxContainer.new()
	ask_row.add_theme_constant_override("separation", 10)
	body.add_child(ask_row)
	var ask_l := Label.new()
	ask_l.text = "Asking price"
	ask_l.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	ask_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ask_row.add_child(ask_l)
	var ask := SpinBox.new()
	ask.min_value = 250
	ask.max_value = float(value) * 4.0
	ask.step = 250
	ask.value = value
	ask.custom_minimum_size = Vector2(160, 0)
	ask_row.add_child(ask)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ask_row.add_child(hint)
	var update_hint := func() -> void:
		var ratio: float = ask.value / maxf(float(value), 1.0)
		hint.text = "Bids likely within days" if ratio <= 1.0 else \
			("Some interest expected" if ratio <= 1.35 else "Priced to scare buyers off")
	update_hint.call()
	ask.value_changed.connect(func(_v: float) -> void: update_hint.call())

	var warn := Label.new()
	warn.text = "Listing hurts morale (-8). Rival clubs will bid against this price;\nbids arrive in the inbox and are answered from this screen."
	warn.add_theme_font_size_override("font_size", 12)
	warn.add_theme_color_override("font_color", UI.COL_WARN)
	body.add_child(warn)

	d.confirmed.connect(func() -> void:
		var err: String = svc.set_listed(uid, int(ask.value))
		if err != "":
			notice(host, "Transfer list", err)
		d.queue_free())
	host.add_child(d)
	d.popup_centered()


# ------------------------------------------------------------------ bids

static func open_offers_dialog(host: Control, uid: String = "") -> void:
	var svc: Node = Service.ensure()
	var pk := _dialog("Transfer bids")
	var d: AcceptDialog = pk[0]
	var body: VBoxContainer = pk[1]
	d.get_ok_button().text = "Close"
	d.min_size = Vector2i(560, 0)

	var rebuild: Array = [null]
	rebuild[0] = func() -> void:
		for c in body.get_children():
			c.queue_free()
		var live: Array = svc.offers_for(uid) if uid != "" else svc.active_offers()
		if live.is_empty():
			var none := Label.new()
			none.text = "No live bids."
			none.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
			body.add_child(none)
			return
		for o in live:
			var inst: Dictionary = svc.find_instance(str(o["uid"]))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			body.add_child(row)
			var who := Label.new()
			var ask_note := ""
			if not inst.is_empty() and inst.has("asking_price"):
				ask_note = "  (asking %s)" % UI.money(int(inst["asking_price"]))
			who.text = "%s bid %s for %s%s — expires %s" % [
				GameState.club(str(o["club_id"])).get("short", "?"), UI.money(int(o["bid"])),
				o["name"], ask_note, Season.pretty_date(str(o["expires_on"]))]
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(who)
			var acc := Button.new()
			acc.text = "Accept"
			var offer_id := int(o["id"])
			acc.pressed.connect(func() -> void:
				var err: String = svc.accept_offer(offer_id)
				if err != "":
					notice(host, "Sale", err)
				rebuild[0].call())
			row.add_child(acc)
			var rej := Button.new()
			rej.text = "Reject"
			rej.pressed.connect(func() -> void:
				svc.reject_offer(offer_id)
				rebuild[0].call())
			row.add_child(rej)
	rebuild[0].call()
	d.confirmed.connect(d.queue_free)
	host.add_child(d)
	d.popup_centered()


# ------------------------------------------------------------------ release

static func open_release_dialog(host: Control, uid: String) -> void:
	var svc: Node = Service.ensure()
	var inst: Dictionary = svc.find_instance(uid)
	if inst.is_empty():
		return
	var comp: int = svc.release_compensation(inst)
	var d := ConfirmationDialog.new()
	d.title = "Terminate contract"
	d.dialog_text = "Release %s?\n\nRemaining contract: %s/wk to %s.\nCompensation payout: %s (from balance %s).\nThey join the free-agent pool and squad morale dips." % [
		UI.display_name(inst), UI.money(int(inst["contract"]["salary"])),
		Season.pretty_date(inst["contract"]["expiry"]),
		UI.money(comp), UI.money(svc.balance())]
	d.get_ok_button().text = "Release"
	d.confirmed.connect(func() -> void:
		var err: String = svc.release(uid)
		if err != "":
			notice(host, "Release", err)
		d.queue_free())
	d.close_requested.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	host.add_child(d)
	d.popup_centered()


# ------------------------------------------------------------------ nickname

static func open_nickname_dialog(host: Control, uid: String) -> void:
	var svc: Node = Service.ensure()
	var inst: Dictionary = svc.find_instance(uid)
	if inst.is_empty():
		return
	var pk := _dialog("Set nickname — %s" % str(inst["species"]))
	var d: AcceptDialog = pk[0]
	var body: VBoxContainer = pk[1]
	d.get_ok_button().text = "Save"
	d.add_cancel_button("Cancel")
	var edit := LineEdit.new()
	edit.text = str(inst["nickname"]) if inst.get("nickname") else ""
	edit.placeholder_text = "Leave empty to use the species name"
	edit.max_length = 14
	body.add_child(edit)
	d.confirmed.connect(func() -> void:
		svc.set_nickname(uid, edit.text)
		d.queue_free())
	host.add_child(d)
	d.popup_centered()
	edit.grab_focus()
