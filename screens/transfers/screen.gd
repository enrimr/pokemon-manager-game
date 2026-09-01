extends Control
## Transfers screen — FM-style Transfer Centre + Scouting hub.
## Tabs: Search (knowledge-masked market browser), Scouting (assignments +
## written reports), Transfer Centre (negotiations, incoming offers, deals log).
## All logic lives in market.gd (persistent singleton, user://transfers.json).

const Market := preload("res://screens/transfers/market.gd")

const POOL_LABELS := ["All pools", "Club Pokémon", "Free agents", "Prospects", "Shortlisted", "Transfer-listed", "Overseas leagues", "Domestic only"]
const STAGE_SHORT := ["—", "Rumour", "Initial", "Partial", "Detailed", "FULL"]
const PRICE_LABELS := ["Any value", "Under 100K", "Under 250K", "Under 500K", "Under 1M"]
const PRICE_CAPS := [0, 100000, 250000, 500000, 1000000]
const STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]
const STAT_NAMES := {"hp": "HP", "atk": "Atk", "def": "Def", "spa": "SpA", "spd": "SpD", "spe": "Spe"}

var market: RefCounted

# --- search state
var _search_text := ""
var _pool_filter := 0
var _type_filter := ""
var _nature_filter := ""    # nature name; matches only targets whose nature scouting revealed
var _ability_filter := ""   # ability id; matches only targets whose ability scouting confirmed
var _min_level := 1
var _price_filter := 0
var _scouted_only := false
var _sort_col := 4
var _sort_desc := true
var _selected_uid := ""

# --- nodes
var _tabs: TabContainer
var _header_stats: HFlowContainer
var _tree: Tree
var _detail: VBoxContainer
var _count_label: Label
var _scout_cards: VBoxContainer
var _assign_list: VBoxContainer
var _report_list: ItemList
var _report_card: RichTextLabel
var _out_box: VBoxContainer
var _in_box: VBoxContainer
var _deals_tree: Tree
var _centre_budget: HFlowContainer
var _window_banner: PanelContainer
# recruitment hub
var _sl_box: VBoxContainer
var _rec_box: VBoxContainer
var _agent_box: VBoxContainer
var _rumour_box: VBoxContainer
var _dof_box: VBoxContainer
var _hub_banner: PanelContainer
# scouting extras
var _market_box: VBoxContainer
var _network_box: VBoxContainer


func _ready() -> void:
	market = Market.instance()
	market.market_updated.connect(_refresh_all)
	GameState.date_changed.connect(_on_date)
	_build_ui()
	_refresh_all()


func on_show() -> void:
	_refresh_all()


const TAB_IDS := ["recruitment", "search", "scouting", "centre"]


func select_tab(tab_id: String) -> void:
	## Shell sub-navigation contract (sidebar sub-items / deep links).
	var i := TAB_IDS.find(tab_id)
	if i >= 0 and _tabs != null:
		_tabs.current_tab = i


func _on_date(_d: String) -> void:
	_refresh_all()


# ================================================================== UI BUILD

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# ---- header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	root.add_child(head)
	var title := Label.new()
	title.text = tr("Transfer Centre")
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	head.add_child(title)
	# Wide-vocabulary locales (es) can make these chips wider than the screen:
	# a flow container wraps them onto extra rows instead of clipping the
	# whole screen at the right edge (the HBox min-width used to propagate
	# up and blow out every tab's layout).
	_header_stats = HFlowContainer.new()
	_header_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_stats.alignment = FlowContainer.ALIGNMENT_END
	_header_stats.add_theme_constant_override("h_separation", 22)
	_header_stats.add_theme_constant_override("v_separation", 4)
	head.add_child(_header_stats)

	# ---- tabs
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_build_recruitment_tab()
	_build_search_tab()
	_build_scouting_tab()
	_build_centre_tab()


func _header_stat(label_txt: String, value_txt: String, col: Color = ThemeBuilder.COL_TEXT) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	var l := Label.new()
	l.text = label_txt.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	vb.add_child(l)
	var v := Label.new()
	v.text = value_txt
	v.add_theme_font_size_override("font_size", 17)
	v.add_theme_color_override("font_color", col)
	vb.add_child(v)
	_header_stats.add_child(vb)


# ------------------------------------------------------------ RECRUITMENT HUB (tab 0)
# The push side of the market: shortlist board, scout recommendation queue,
# agent-offered players, the rumour mill and DoF delegation. Between deals this
# is the page that keeps handing you work — FM's Transfer Centre front page.

func _build_recruitment_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Recruitment"
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)

	_hub_banner = PanelContainer.new()
	tab.add_child(_hub_banner)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	tab.add_child(body)

	# col 1 — shortlist
	var col1 := VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col1.size_flags_stretch_ratio = 1.15
	col1.add_theme_constant_override("separation", 6)
	body.add_child(col1)
	col1.add_child(_section_title(tr("SHORTLIST — OUR TARGET BOARD")))
	var sc1 := ScrollContainer.new()
	sc1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc1.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col1.add_child(sc1)
	_sl_box = VBoxContainer.new()
	_sl_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sl_box.add_theme_constant_override("separation", 8)
	sc1.add_child(_sl_box)

	# col 2 — pushed at us: scout recs + agent offers
	var col2 := VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2.add_theme_constant_override("separation", 6)
	body.add_child(col2)
	col2.add_child(_section_title(tr("SCOUT RECOMMENDATIONS")))
	var sc2 := ScrollContainer.new()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc2.size_flags_stretch_ratio = 1.1
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col2.add_child(sc2)
	_rec_box = VBoxContainer.new()
	_rec_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_box.add_theme_constant_override("separation", 8)
	sc2.add_child(_rec_box)
	col2.add_child(_section_title(tr("AGENT-OFFERED PLAYERS")))
	var sc3 := ScrollContainer.new()
	sc3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc3.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col2.add_child(sc3)
	_agent_box = VBoxContainer.new()
	_agent_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_agent_box.add_theme_constant_override("separation", 8)
	sc3.add_child(_agent_box)

	# col 3 — DoF + rumour mill
	var col3 := VBoxContainer.new()
	col3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col3.add_theme_constant_override("separation", 6)
	body.add_child(col3)
	col3.add_child(_section_title(tr("DIRECTOR OF BATTLING — DELEGATION")))
	var dof_panel := PanelContainer.new()
	col3.add_child(dof_panel)
	_dof_box = VBoxContainer.new()
	_dof_box.add_theme_constant_override("separation", 4)
	dof_panel.add_child(_dof_box)
	col3.add_child(_section_title(tr("RUMOUR MILL")))
	var sc4 := ScrollContainer.new()
	sc4.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc4.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col3.add_child(sc4)
	_rumour_box = VBoxContainer.new()
	_rumour_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rumour_box.add_theme_constant_override("separation", 4)
	sc4.add_child(_rumour_box)


func _refresh_recruitment() -> void:
	if _sl_box == null:
		return
	_refresh_hub_banner()
	_refresh_shortlist_col()
	_refresh_recs_col()
	_refresh_agents_col()
	_refresh_dof_panel()
	_refresh_rumours_col()


func _refresh_hub_banner() -> void:
	_clear(_hub_banner)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.bg_color = Color(0.11, 0.13, 0.18)
	_hub_banner.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_hub_banner.add_child(row)
	var n_new: int = market.new_recs().size()
	var n_agents: int = market.open_agent_offers().size()
	var n_sl: int = market.shortlist_targets().size()
	var listed_sl: int = market.shortlist_targets().filter(func(t): return market.is_listed(String(t["inst"]["uid"]))).size()
	var parts: Array = []
	parts.append(tr("%d target%s shortlisted") % [n_sl, "" if n_sl == 1 else "s"])
	if listed_sl > 0:
		parts.append(tr("%d of them TRANSFER-LISTED — bargain window") % listed_sl)
	parts.append(I18n.np(n_new, "%d new scout recommendation", "%d new scout recommendations"))
	parts.append(tr("%d agent offer%s open") % [n_agents, "" if n_agents == 1 else "s"])
	var lead := _dlabel(tr("RECRUITMENT PIPELINE"), ThemeBuilder.COL_ACCENT, 14)
	lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lead)
	var info := _dlabel("  ·  ".join(parts), ThemeBuilder.COL_TEXT, 13, true)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)


func _refresh_shortlist_col() -> void:
	_clear(_sl_box)
	var targets: Array = market.shortlist_targets()
	for t in targets:
		_sl_box.add_child(_make_shortlist_card(t))
	if targets.is_empty():
		_sl_box.add_child(_dlabel(tr("The shortlist is empty.\n\nThis is your target board: everything on it gets watched for you — listings, rival interest, agent availability and price drops all raise alerts, scouts can auto-cover it, and the DoF can pursue it.\n\nAdd targets from Search, or accept a scout recommendation."), ThemeBuilder.COL_TEXT_DIM, 13, true))


func _make_shortlist_card(t: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	var inst: Dictionary = t["inst"]
	var uid: String = String(inst["uid"])
	var know: float = market.knowledge_of(uid)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	head.add_child(GlyphIcons.icon("star", 13, Color(0.88, 0.69, 0.31)))
	head.add_child(_dlabel(market.display_name(inst), Color.WHITE, 14))
	head.add_child(MonActions.action_button(uid))
	MonActions.attach(card, uid)
	var where: String
	match String(t["pool"]):
		"club": where = String(market.club_of(t["club_id"])["short"])
		"fa": where = tr("Free agent")
		_: where = "Prospect"
	head.add_child(_dlabel(tr("Lv %d · %s · %s") % [int(inst["level"]), where, tr(market.region_of(inst))], ThemeBuilder.COL_TEXT_DIM, 11, true))

	var cost_txt: String
	if t["pool"] == "club":
		cost_txt = tr("Ask ~%s") % market.masked_money(uid, "val", market.ask_price(inst, t["club_id"]))
	elif t["pool"] == "prospect":
		cost_txt = tr("Comp ~%s") % market.masked_money(uid, "val", int(round(market.value_of(inst) * 0.35 / 1000.0)) * 1000)
	else:
		cost_txt = tr("Free — wages only")
	vb.add_child(_dlabel(tr("%s  ·  knowledge %d%%") % [cost_txt, int(know)], ThemeBuilder.COL_TEXT, 12))

	# status tags — why this row deserves attention today
	var tags: Array = []
	if market.is_listed(uid):
		tags.append([tr("TRANSFER-LISTED — ask slashed"), ThemeBuilder.COL_GOOD])
	if not market.agent_offer_for(uid).is_empty():
		tags.append([tr("AGENT PUSHING — deal greased"), ThemeBuilder.COL_ACCENT])
	for r in market.rumours_for(uid):
		if String(r["kind"]) == "interest" and not bool(r.get("dud", false)) and not bool(r.get("came_true", false)):
			tags.append([tr("RIVAL RUMOUR: %s") % String(GameState.club(String(r["other_id"]))["short"]), ThemeBuilder.COL_BAD])
			break
	var offer: Dictionary = market.offer_for_target(uid)
	if not offer.is_empty():
		tags.append([(tr("DoF negotiating — ") if bool(offer.get("dof", false)) else tr("In talks — ")) + _stage_text(offer), ThemeBuilder.COL_WARN])
	var assign: Dictionary = market.assignment_for_target(uid)
	if not assign.is_empty():
		var eta: int = market.assignment_eta(assign)
		tags.append([tr("%s scouting — %s%s") % [String(assign["scout"]), String(market.knowledge_stage(uid)["name"]),
			(tr(" · full report ~%dd") % eta) if eta > 0 else ""], ThemeBuilder.COL_TEXT_DIM])
	for tg in tags:
		vb.add_child(_dlabel("· " + tg[0], tg[1], 11, true))

	var btns := HFlowContainer.new()
	btns.add_theme_constant_override("h_separation", 6)
	vb.add_child(btns)
	if offer.is_empty():
		var ob := Button.new()
		if t["pool"] == "club":
			ob.text = tr("Make Offer")
			ob.disabled = not market.window_open()
			ob.pressed.connect(func(): _open_offer_sheet(uid))
		else:
			ob.text = tr("Offer Contract")
			ob.disabled = t["pool"] == "prospect" and not market.window_open()
			ob.pressed.connect(func(): _open_contract_sheet(uid))
		btns.add_child(ob)
	if know < 100.0 and assign.is_empty():
		var sb2 := Button.new()
		sb2.text = "Scout"
		sb2.pressed.connect(func(): _open_scout_dialog(uid))
		btns.add_child(sb2)
	var vb2 := Button.new()
	vb2.text = "View"
	vb2.pressed.connect(func(): _go_to_target(uid))
	btns.add_child(vb2)
	var rb := Button.new()
	rb.text = "Remove"
	rb.pressed.connect(func(): _err(market.toggle_shortlist(uid)))
	btns.add_child(rb)
	return card


func _refresh_recs_col() -> void:
	_clear(_rec_box)
	var fresh: Array = market.new_recs()
	for r in fresh:
		var card := PanelContainer.new()
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		card.add_child(vb)
		var t: Dictionary = market.find_target(String(r["uid"]))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		vb.add_child(head)
		head.add_child(_dlabel("(gone)" if t.is_empty() else market.display_name(t["inst"]), Color.WHITE, 14))
		head.add_child(_dlabel("%s / %s" % [_stars(float(r["ability"])), _stars(float(r["potential"]))], Color(0.88, 0.69, 0.31), 12))
		if not t.is_empty():
			head.add_child(MonActions.action_button(String(r["uid"])))
			MonActions.attach(card, String(r["uid"]))
		vb.add_child(_dlabel(String(r["note"]), ThemeBuilder.COL_TEXT_DIM, 11, true))
		var btns := HFlowContainer.new()
		btns.add_theme_constant_override("h_separation", 6)
		vb.add_child(btns)
		var rid := int(r["id"])
		var ab := Button.new()
		ab.text = "Shortlist"
		ab.pressed.connect(func(): _err(market.rec_accept(rid)))
		btns.add_child(ab)
		var vbtn := Button.new()
		vbtn.text = "View"
		var ruid := String(r["uid"])
		vbtn.pressed.connect(func(): _go_to_target(ruid))
		btns.add_child(vbtn)
		var db := Button.new()
		db.text = "Pass"
		db.pressed.connect(func(): market.rec_dismiss(rid))
		btns.add_child(db)
		_rec_box.add_child(card)
	if fresh.is_empty():
		_rec_box.add_child(_dlabel(tr("No new recommendations.\nScouts push strong finds here as their reports come in — keep someone on a focus assignment and the queue fills itself."), ThemeBuilder.COL_TEXT_DIM, 12, true))


func _refresh_agents_col() -> void:
	_clear(_agent_box)
	var open: Array = market.open_agent_offers()
	for a in open:
		var card := PanelContainer.new()
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		card.add_child(vb)
		var t: Dictionary = market.find_target(String(a["uid"]))
		var inst: Dictionary = t["inst"]
		var uid := String(a["uid"])
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		vb.add_child(head)
		head.add_child(_dlabel(market.display_name(inst), Color.WHITE, 14))
		head.add_child(MonActions.action_button(uid))
		MonActions.attach(card, uid)
		if String(a["kind"]) == "club":
			head.add_child(_dlabel(tr("wants out of %s") % String(market.club_of(t["club_id"])["short"]), ThemeBuilder.COL_ACCENT, 11))
		else:
			head.add_child(_dlabel(tr("free agent"), ThemeBuilder.COL_GOOD, 11))
		vb.add_child(_dlabel(tr("Agent: %s") % String(a["pitch"]), ThemeBuilder.COL_TEXT_DIM, 11, true))
		var ask_txt: String = (tr("Deal near %s — seller softened while this stands") % market.fmt_money(int(a["ask"]))) \
			if String(a["kind"]) == "club" else ("Signs for ~%s/wk, no fee" % market.fmt_money(int(a["ask"])))
		vb.add_child(_dlabel(tr("%s  ·  offer stands until %s") % [ask_txt, I18n.pretty_date(String(a["expires"]))], ThemeBuilder.COL_WARN, 11, true))
		var btns := HFlowContainer.new()
		btns.add_theme_constant_override("h_separation", 6)
		vb.add_child(btns)
		var aid := int(a["id"])
		if market.offer_for_target(uid).is_empty():
			var ob := Button.new()
			ob.text = tr("Open Talks")
			if String(a["kind"]) == "club":
				ob.disabled = not market.window_open()
				ob.pressed.connect(func(): _open_offer_sheet(uid))
			else:
				ob.pressed.connect(func(): _open_contract_sheet(uid))
			btns.add_child(ob)
		if not market.shortlisted(uid):
			var slb := Button.new()
			slb.text = "Shortlist"
			slb.pressed.connect(func(): _err(market.toggle_shortlist(uid)))
			btns.add_child(slb)
		var db := Button.new()
		db.text = tr("Not Interested")
		db.pressed.connect(func(): market.dismiss_agent_offer(aid))
		btns.add_child(db)
		_agent_box.add_child(card)
	if open.is_empty():
		_agent_box.add_child(_dlabel(tr("No agents on the phone right now.\nAgents tout unsettled players and free agents here — their deals come pre-greased."), ThemeBuilder.COL_TEXT_DIM, 12, true))


func _refresh_dof_panel() -> void:
	_clear(_dof_box)
	_dof_box.add_child(_dlabel(tr("Delegate market chores. The DoF acts every day, inside board limits."), ThemeBuilder.COL_TEXT_DIM, 11, true))
	var opts := [
		["handle_bids", tr("Swat lowball bids for our squad")],
		["pursue_shortlist", tr("Pursue shortlist targets (open + close deals)")],
		["auto_scout", tr("Keep idle scouts on the shortlist")],
	]
	for opt in opts:
		var cb := CheckBox.new()
		cb.text = opt[1]
		cb.button_pressed = bool(market.dof.get(opt[0], false))
		var key := String(opt[0])
		cb.toggled.connect(func(on: bool): market.set_dof(key, on))
		_dof_box.add_child(cb)
	var lim := HBoxContainer.new()
	lim.add_theme_constant_override("separation", 8)
	_dof_box.add_child(lim)
	lim.add_child(_dlabel(tr("Max over valuation:"), ThemeBuilder.COL_TEXT_DIM, 11))
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 40
	spin.step = 5
	spin.value = int(market.dof.get("max_over_pct", 10))
	spin.custom_minimum_size.x = 70
	spin.value_changed.connect(func(v: float):
		market.dof["max_over_pct"] = int(v)
		market.save_state())
	lim.add_child(spin)
	lim.add_child(_dlabel("%", ThemeBuilder.COL_TEXT_DIM, 11))
	if not market.dof_log.is_empty():
		_dof_box.add_child(HSeparator.new())
		for e in market.dof_log.slice(0, 5):
			_dof_box.add_child(_dlabel("%s — %s" % [I18n.short_date(String(e["date"])), String(e["text"])], ThemeBuilder.COL_TEXT_DIM, 10, true))


func _refresh_rumours_col() -> void:
	_clear(_rumour_box)
	for r in market.rumours:
		var col: Color
		match String(r["strength"]):
			"Strong": col = ThemeBuilder.COL_WARN
			"Warm": col = ThemeBuilder.COL_TEXT
			_: col = ThemeBuilder.COL_TEXT_DIM
		var suffix := ""
		if bool(r.get("came_true", false)):
			suffix = tr("   • came true")
		elif bool(r.get("dud", false)):
			suffix = tr("   — came to nothing")
		var line := _dlabel("%s  [%s]  %s%s" % [I18n.short_date(String(r["date"])), tr(String(r["strength"])), market.rumour_text(r), suffix],
			ThemeBuilder.COL_GOOD if bool(r.get("came_true", false)) else col, 11, true)
		_rumour_box.add_child(line)
	if market.rumours.is_empty():
		_rumour_box.add_child(_dlabel(tr("The mill is quiet.\nRumours build as the window runs: listings genuinely cut ask prices, interest whispers ripen into real transfers, and links to OUR squad often precede real bids."), ThemeBuilder.COL_TEXT_DIM, 12, true))


func _go_to_target(uid: String) -> void:
	_selected_uid = uid
	_tabs.current_tab = 1
	_refresh_search()
	_refresh_detail()


## Shell deep-link contract: global search results, the mon action menu and
## other screens land here with {"kind":"pokemon","id":uid} (+ optional
## "action": "offer"|"sign"|"scout") — the target opens preselected in Search
## and, when asked, straight into the right deal sheet. No dead ends.
func reveal_search_target(ctx: Dictionary) -> void:
	if str(ctx.get("kind", "")) != "pokemon":
		return
	var uid := str(ctx.get("id", ""))
	if uid == "" or market.find_target(uid).is_empty():
		return
	_go_to_target(uid)
	match str(ctx.get("action", "")):
		"offer":
			_open_offer_sheet(uid)
		"sign", "contract":
			_open_contract_sheet(uid)
		"scout":
			_open_scout_dialog(uid)


# ------------------------------------------------------------ SEARCH TAB

func _build_search_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Search"
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)

	# Flow, not HBox: the filter strip wraps onto extra rows on narrow windows
	# instead of forcing a minimum width wider than the screen.
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 10)
	bar.add_theme_constant_override("v_separation", 4)
	tab.add_child(bar)

	var search := LineEdit.new()
	search.placeholder_text = tr("Search species / nickname...")
	search.custom_minimum_size.x = 150
	search.text_changed.connect(func(t: String):
		_search_text = t
		_refresh_search())
	bar.add_child(search)

	var pool := OptionButton.new()
	for p in POOL_LABELS:
		pool.add_item(p)
	pool.item_selected.connect(func(i: int):
		_pool_filter = i
		_refresh_search())
	bar.add_child(pool)

	var typ := OptionButton.new()
	typ.add_item(tr("Any type"))
	for t in DataStore.types:
		typ.add_item(String(t).capitalize())
	typ.item_selected.connect(func(i: int):
		_type_filter = "" if i == 0 else String(DataStore.types[i - 1])
		_refresh_search())
	bar.add_child(typ)

	var lv_lab := Label.new()
	lv_lab.text = tr("Min Lv")
	lv_lab.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	bar.add_child(lv_lab)
	var lv := SpinBox.new()
	lv.min_value = 1
	lv.max_value = 100
	lv.value = 1
	lv.custom_minimum_size.x = 74
	lv.value_changed.connect(func(v: float):
		_min_level = int(v)
		_refresh_search())
	bar.add_child(lv)

	var price := OptionButton.new()
	for p in PRICE_LABELS:
		price.add_item(p)
	price.item_selected.connect(func(i: int):
		_price_filter = i
		_refresh_search())
	bar.add_child(price)

	var nat_opt := OptionButton.new()
	nat_opt.fit_to_longest_item = false
	nat_opt.clip_text = true
	nat_opt.custom_minimum_size.x = 104
	nat_opt.add_item(tr("Any nature"))
	var nat_names: Array = DataStore.natures.keys()
	nat_names.sort()
	for n in nat_names:
		nat_opt.add_item(market.nature_text(String(n)))
	nat_opt.tooltip_text = tr("Filter by temperament (nature). Scouting reveals a target's nature at Part scouted (50%) — targets whose nature is still unknown never match.")
	nat_opt.item_selected.connect(func(i: int):
		_nature_filter = "" if i == 0 else String(nat_names[i - 1])
		_refresh_search())
	bar.add_child(nat_opt)

	var ab_opt := OptionButton.new()
	ab_opt.fit_to_longest_item = false
	ab_opt.clip_text = true
	ab_opt.custom_minimum_size.x = 104
	ab_opt.add_item(tr("Any ability"))
	var ab_ids: Array = DataStore.abilities.keys()
	ab_ids.sort_custom(func(a, b): return DataStore.ability_name(String(a)) < DataStore.ability_name(String(b)))
	for a in ab_ids:
		ab_opt.add_item(DataStore.ability_name(String(a)))
	ab_opt.tooltip_text = tr("Filter by battle ability. A Detailed watch (75%) confirms it — targets whose ability is unconfirmed never match.")
	ab_opt.item_selected.connect(func(i: int):
		_ability_filter = "" if i == 0 else String(ab_ids[i - 1])
		_refresh_search())
	bar.add_child(ab_opt)

	var scouted := CheckBox.new()
	scouted.text = tr("Fully scouted")
	scouted.toggled.connect(func(on: bool):
		_scouted_only = on
		_refresh_search())
	bar.add_child(scouted)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_count_label.clip_text = true
	_count_label.custom_minimum_size.x = 130
	bar.add_child(_count_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	tab.add_child(body)

	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.columns = 14
	var titles := ["Name", "Type", "Club", "Age", "Lv", "HP", "Atk", "Def", "SpA", "SpD", "Spe", "Value", "Wage", "Knowledge"]
	var widths := [118, 72, 42, 40, 32, 52, 52, 52, 52, 52, 52, 110, 92, 116]
	_tree.set_column_titles_visible(true)
	for i in 14:
		_tree.set_column_title(i, titles[i])
		_tree.set_column_expand(i, i == 0)
		_tree.set_column_custom_minimum_width(i, widths[i])
		_tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT if i < 3 else HORIZONTAL_ALIGNMENT_RIGHT)
	_tree.column_title_clicked.connect(_on_sort_clicked)
	_tree.item_selected.connect(_on_row_selected)
	# Double-click / Enter on a row jumps straight into the deal flow.
	_tree.item_activated.connect(_on_row_activated)
	# Right-click / the row's "..." button: the global mon action menu (the
	# same component every other screen uses — one action grammar everywhere).
	MonActions.wire_tree(_tree, func(item: TreeItem) -> String: return str(item.get_metadata(0)))
	body.add_child(_tree)

	var dpanel := PanelContainer.new()
	dpanel.custom_minimum_size.x = 372
	body.add_child(dpanel)
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dpanel.add_child(dscroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	dscroll.add_child(_detail)


func _on_sort_clicked(col: int, _btn: int) -> void:
	if _sort_col == col:
		_sort_desc = not _sort_desc
	else:
		_sort_col = col
		_sort_desc = col >= 3
	_refresh_search()


func _on_row_selected() -> void:
	var it := _tree.get_selected()
	if it != null:
		_selected_uid = String(it.get_metadata(0))
		_refresh_detail()


func _on_row_activated() -> void:
	## Double-click (or Enter) on a search row: open the right deal flow for
	## the target directly — offer sheet for contracted Pokémon, personal
	## terms for free agents / prospects. Falls back to the detail pane
	## (Transfer Centre for in-progress deals) when no new offer can start.
	var it := _tree.get_selected()
	if it == null:
		return
	_selected_uid = String(it.get_metadata(0))
	_refresh_detail()
	var t: Dictionary = market.find_target(_selected_uid)
	if t.is_empty() or t["pool"] == "mine":
		return
	if not market.offer_for_target(_selected_uid).is_empty():
		_tabs.current_tab = 3   # deal already live — manage it in the Centre
		return
	if t["pool"] == "club":
		if market.window_open():
			_open_offer_sheet(_selected_uid)
	elif t["pool"] == "prospect":
		if market.window_open():
			_open_contract_sheet(_selected_uid)
	else:
		_open_contract_sheet(_selected_uid)   # free agents sign any time


func _filtered_targets() -> Array:
	var out: Array = []
	for t in market.all_targets():
		var inst: Dictionary = t["inst"]
		if _pool_filter == 1 and t["pool"] != "club":
			continue
		if _pool_filter == 2 and t["pool"] != "fa":
			continue
		if _pool_filter == 3 and t["pool"] != "prospect":
			continue
		if _pool_filter == 4 and not market.shortlisted(String(inst["uid"])):
			continue
		if _pool_filter == 5 and not market.is_listed(String(inst["uid"])):
			continue
		if _pool_filter == 6 and not market.is_ext_uid(String(inst["uid"])):
			continue
		if _pool_filter == 7 and market.is_ext_uid(String(inst["uid"])):
			continue
		if int(inst["level"]) < _min_level:
			continue
		if _search_text != "" and not market.display_name(inst).to_lower().contains(_search_text.to_lower()):
			continue
		if _type_filter != "":
			var sp: Dictionary = DataStore.species(int(inst["species_id"]))
			if not (_type_filter in sp["types"]):
				continue
		if _price_filter > 0:
			var cost: int = market.ask_price(inst, t["club_id"]) if t["pool"] == "club" else market.value_of(inst)
			if cost > PRICE_CAPS[_price_filter]:
				continue
		if _nature_filter != "" and market.known_nature(inst) != _nature_filter:
			continue   # unknown nature (< Part scouted) never matches
		if _ability_filter != "" and market.known_ability(inst) != _ability_filter:
			continue   # unconfirmed ability (< Detailed) never matches
		if _scouted_only and market.knowledge_of(inst["uid"]) < 100.0:
			continue
		out.append(t)
	return out


func _sort_value(t: Dictionary) -> Variant:
	var inst: Dictionary = t["inst"]
	var uid: String = inst["uid"]
	match _sort_col:
		0: return market.display_name(inst)
		1: return String(DataStore.species(int(inst["species_id"]))["types"][0])
		2: return _club_short(t)
		3: return int(inst["age_months"])
		4: return int(inst["level"])
		5, 6, 7, 8, 9, 10:
			var k: String = STAT_KEYS[_sort_col - 5]
			var b: Array = market.masked_bounds(uid, k, int(market.battle_stats(inst)[k]))
			return int(b[0]) + int(b[1])
		11: return market.ask_price(inst, t["club_id"]) if t["pool"] == "club" else market.value_of(inst)
		12: return int(inst["contract"]["salary"])
		13: return market.knowledge_of(uid)
	return 0


## +1 if `nature` boosts stat `key`, -1 if it hinders it, 0 otherwise.
func _nature_dir(nature: String, key: String) -> int:
	var nat: Dictionary = DataStore.nature(nature)
	if nat.is_empty():
		return 0
	if str(nat.get("plus")) == key:
		return 1
	if str(nat.get("minus")) == key:
		return -1
	return 0


func _club_short(t: Dictionary) -> String:
	if t["pool"] == "fa":
		return "FA"
	if t["pool"] == "prospect":
		return "YTH"
	return String(market.club_of(t["club_id"])["short"])


func _refresh_search() -> void:
	if _tree == null:
		return
	var rows := _filtered_targets()
	rows.sort_custom(func(a, b):
		var va: Variant = _sort_value(a)
		var vb: Variant = _sort_value(b)
		return (va > vb) if _sort_desc else (va < vb))
	_tree.clear()
	var root := _tree.create_item()
	for t in rows:
		var inst: Dictionary = t["inst"]
		var uid: String = inst["uid"]
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		var know: float = market.knowledge_of(uid)
		var it := _tree.create_item(root)
		it.set_metadata(0, uid)
		var name_txt: String = market.display_name(inst)
		if market.shortlisted(uid):
			it.set_icon(0, GlyphIcons.tex("star", 11, Color(0.88, 0.69, 0.31)))
		it.set_text(0, name_txt)
		it.set_custom_color(0, Color(0.88, 0.69, 0.31) if market.shortlisted(uid) else (Color.WHITE if know >= 100.0 else ThemeBuilder.COL_TEXT))
		var types_txt := I18n.types_join(sp["types"], " / ")
		it.set_text(1, types_txt)
		it.set_custom_color(1, DataStore.type_color(sp["types"][0]))
		it.set_text(2, _club_short(t))
		it.set_custom_color(2, ThemeBuilder.COL_TEXT_DIM)
		it.set_text(3, tr("%dy %dm") % [int(inst["age_months"]) / 12, int(inst["age_months"]) % 12])
		it.set_text(4, str(int(inst["level"])))
		# battle_stats = nature-adjusted, engine-identical (bands bracket the
		# number this target would actually fight with, same as the squad screen)
		var stats: Dictionary = market.battle_stats(inst)
		var kn_nat_row: String = market.known_nature(inst)
		for i in 6:
			var k: String = STAT_KEYS[i]
			it.set_text(5 + i, market.masked_int(uid, k, int(stats[k])))
			if know < 100.0:
				it.set_custom_color(5 + i, ThemeBuilder.COL_TEXT_DIM)
			elif kn_nat_row != "":
				var d := _nature_dir(kn_nat_row, k)
				if d > 0:
					it.set_custom_color(5 + i, ThemeBuilder.COL_GOOD)
				elif d < 0:
					it.set_custom_color(5 + i, ThemeBuilder.COL_BAD)
		var val_txt: String
		if t["pool"] == "club":
			val_txt = market.masked_money(uid, "val", market.ask_price(inst, t["club_id"]))
			if market.is_listed(uid):
				it.set_icon(11, GlyphIcons.tex("tri_down", 10, ThemeBuilder.COL_GOOD))
		elif t["pool"] == "prospect":
			val_txt = market.masked_money(uid, "val", market.value_of(inst))
		else:
			val_txt = "Free"
		it.set_text(11, val_txt)
		if market.is_listed(uid):
			it.set_custom_color(11, ThemeBuilder.COL_GOOD)
			it.set_tooltip_text(11, tr("Transfer-listed — ask price slashed while the listing stands"))
		else:
			it.set_custom_color(11, ThemeBuilder.COL_WARN if t["pool"] == "club" else ThemeBuilder.COL_GOOD)
		var wage_txt: String
		if know < 100.0:
			wage_txt = market.masked_money(uid, "wage", int(inst["contract"]["salary"]))
		else:
			wage_txt = market.fmt_money(int(inst["contract"]["salary"]))
		it.set_text(12, wage_txt)
		it.set_custom_color(12, ThemeBuilder.COL_TEXT_DIM)
		MonActions.tree_dots(it, 0)
		var st_i: int = int(market.stage_for(know)["idx"])
		it.set_text(13, "%s %d%%" % [tr(STAGE_SHORT[st_i]), int(know)] if know > 0.0 else "—")
		it.set_tooltip_text(13, tr("Knowledge stage: %s — unlocks %s") % [
			tr(String(market.stage_for(know)["name"])), tr(String(market.stage_for(know)["unlocks"]))])
		it.set_custom_color(13, ThemeBuilder.COL_GOOD if know >= 100.0 else (ThemeBuilder.COL_WARN if know > 0 else ThemeBuilder.COL_TEXT_DIM))
		for c in range(3, 14):
			it.set_text_alignment(c, HORIZONTAL_ALIGNMENT_RIGHT)
		if uid == _selected_uid:
			it.select(0)
	var n_ext: int = rows.filter(func(t): return market.is_ext_uid(String(t["inst"]["uid"]))).size()
	_count_label.text = tr("%d targets · %d overseas · %d full") % [
		rows.size(), n_ext, market.full_report_count()]
	_count_label.tooltip_text = "%d targets match the filters (%d from overseas leagues/youth pools) · %d fully scouted." % [
		rows.size(), n_ext, market.full_report_count()]


# ------------------------------------------------------------ detail panel

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _dlabel(txt: String, col: Color = ThemeBuilder.COL_TEXT, size: int = 14, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _refresh_detail() -> void:
	if _detail == null:
		return
	_clear(_detail)
	var t: Dictionary = market.find_target(_selected_uid) if _selected_uid != "" else {}
	if t.is_empty() or t["pool"] == "mine":
		_detail.add_child(_dlabel(tr("Select a target from the list.\n\nUnscouted Pokémon show attribute ranges — send a scout to unlock exact figures, a written report and star ratings."), ThemeBuilder.COL_TEXT_DIM, 14, true))
		return
	var inst: Dictionary = t["inst"]
	var uid: String = inst["uid"]
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var know: float = market.knowledge_of(uid)

	# name + badge
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_detail.add_child(top)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(44, 44)
	var sb := StyleBoxFlat.new()
	sb.bg_color = DataStore.type_color(sp["types"][0])
	sb.set_corner_radius_all(6)
	badge.add_theme_stylebox_override("panel", sb)
	var mono := Label.new()
	mono.text = String(inst["species"]).substr(0, 1)
	mono.add_theme_font_size_override("font_size", 24)
	mono.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
	mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(mono)
	top.add_child(badge)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nv)
	nv.add_child(_dlabel(market.display_name(inst), Color.WHITE, 18))
	var where: String
	match String(t["pool"]):
		"club": where = tr("%s  ·  contracted to %s") % [market.club_of(t["club_id"])["name"], I18n.pretty_date(str(inst["contract"]["expiry"]))]
		"fa": where = tr("Free agent — signs on wages alone")
		_: where = tr("Youth prospect — development compensation applies")
	nv.add_child(_dlabel(where, ThemeBuilder.COL_TEXT_DIM, 12, true))

	# types
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 6)
	_detail.add_child(trow)
	for ty in sp["types"]:
		var tl := _dlabel(I18n.type_name(String(ty)).to_upper(), Color(0.05, 0.05, 0.08), 11)
		var tp := PanelContainer.new()
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = DataStore.type_color(ty)
		tsb.set_corner_radius_all(3)
		tsb.content_margin_left = 8
		tsb.content_margin_right = 8
		tsb.content_margin_top = 2
		tsb.content_margin_bottom = 2
		tp.add_theme_stylebox_override("panel", tsb)
		tp.add_child(tl)
		trow.add_child(tp)
	trow.add_child(_dlabel(tr("Lv %d  ·  Age %dy %dm") % [int(inst["level"]),
		int(inst["age_months"]) / 12, int(inst["age_months"]) % 12], ThemeBuilder.COL_TEXT_DIM, 12))

	_detail.add_child(HSeparator.new())

	# stats grid (masked) — battle_stats: nature-adjusted, engine-identical, so
	# the numbers here are the numbers on the squad profile the day one signs
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	_detail.add_child(grid)
	var stats: Dictionary = market.battle_stats(inst)
	var grid_nat: String = market.known_nature(inst)
	for k in STAT_KEYS:
		var h := _dlabel(STAT_NAMES[k], ThemeBuilder.COL_TEXT_DIM, 11)
		grid.add_child(h)
	for k in STAT_KEYS:
		var col: Color = Color.WHITE if know >= 100.0 else ThemeBuilder.COL_WARN
		var tip := "Battle-real figure — nature already folded in, identical to the squad screen and the match engine."
		if know < 100.0:
			tip = tr("Estimated range around the battle-real figure (nature folded in). A Full report (100%) pins it exactly.")
		if grid_nat != "":
			var d := _nature_dir(grid_nat, k)
			if d > 0:
				col = ThemeBuilder.COL_GOOD
				tip += tr("\nBoosted +10%% by its %s nature.") % grid_nat
			elif d < 0:
				col = ThemeBuilder.COL_BAD
				tip += tr("\nHindered −10%% by its %s nature.") % grid_nat
		var v := _dlabel(market.masked_int(uid, k, int(stats[k])), col, 14)
		v.tooltip_text = tip
		v.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(v)
	if know >= 100.0:
		_detail.add_child(_dlabel(tr("Genetics: %d/90 IV  ·  Condition %d%%  ·  Fitness %d%%") % [
			market.iv_total(inst), int(inst["condition"]), int(inst["fitness"])], ThemeBuilder.COL_TEXT_DIM, 12, true))
	else:
		_detail.add_child(_dlabel(tr("Condition %d%%  ·  Fitness %d%%  ·  genetics unknown") % [
			int(inst["condition"]), int(inst["fitness"])], ThemeBuilder.COL_TEXT_DIM, 12, true))

	# moves — unlock at the "Part scouted" stage
	if know >= 50.0:
		_detail.add_child(_dlabel(tr("Moves: ") + ", ".join(inst["moves"]), ThemeBuilder.COL_TEXT, 13, true))
	else:
		_detail.add_child(_dlabel(tr("Move set unknown — reach Part scouted (50%) to reveal."), ThemeBuilder.COL_TEXT_DIM, 13, true))

	# nature + battle ability — staged knowledge (nature at 50%, ability at 75%)
	var kn_nat: String = market.known_nature(inst)
	var kn_ab: String = market.known_ability(inst)
	var na_row := HBoxContainer.new()
	na_row.add_theme_constant_override("separation", 14)
	_detail.add_child(na_row)
	var nat_l := _dlabel("Nature: %s" % (market.nature_text(kn_nat) if kn_nat != "" else "unknown (Part scouted 50%)"),
		ThemeBuilder.COL_TEXT if kn_nat != "" else ThemeBuilder.COL_TEXT_DIM, 12, true)
	nat_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nat_l.tooltip_text = ("Temperament shapes battle stats: +10% to one stat, −10% to another — already folded into the stats above, which match the squad profile and the match engine exactly." if kn_nat != ""
		else tr("A scout reads a target's temperament once knowledge reaches Part scouted (50%). Stats above already include the (still hidden) nature — they are the battle-real figures."))
	na_row.add_child(nat_l)
	var ab_l := _dlabel("Ability: %s" % (DataStore.ability_name(kn_ab) if kn_ab != "" else "unconfirmed (Detailed 75%)"),
		ThemeBuilder.COL_TEXT if kn_ab != "" else ThemeBuilder.COL_TEXT_DIM, 12, true)
	ab_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ab_l.tooltip_text = (String(DataStore.ability(kn_ab).get("desc", "")) if kn_ab != ""
		else tr("The battle ability is only confirmed by a Detailed watch (75% knowledge)."))
	na_row.add_child(ab_l)

	_detail.add_child(HSeparator.new())

	# money block
	if t["pool"] == "club":
		_detail.add_child(_dlabel(tr("Est. value: ") + market.masked_money(uid, "val", market.value_of(inst)), ThemeBuilder.COL_TEXT, 13))
		var imp: float = market.importance_of(inst, market.club_of(t["club_id"]))
		var imp_txt := tr("key battler") if imp >= 1.5 else (tr("first-team regular") if imp >= 1.3 else (tr("squad member") if imp >= 1.1 else tr("fringe battler")))
		_detail.add_child(_dlabel(tr("Status at club: %s") % imp_txt, ThemeBuilder.COL_TEXT_DIM, 12))
	elif t["pool"] == "prospect":
		_detail.add_child(_dlabel(tr("Development compensation: ") + market.masked_money(uid, "val", int(round(market.value_of(inst) * 0.35 / 1000.0)) * 1000), ThemeBuilder.COL_WARN, 13))
		if know >= 100.0 and inst.has("potential"):
			_detail.add_child(_dlabel(tr("Potential rating: %s") % _stars(float(inst["potential"]) / 4.0), ThemeBuilder.COL_GOOD, 13))
		else:
			_detail.add_child(_dlabel(tr("Potential: %s (scout to confirm)") % market.masked_int(uid, "pot", int(inst.get("potential", 10))), ThemeBuilder.COL_TEXT_DIM, 12))
	_detail.add_child(_dlabel(tr("Wage: %s/wk%s") % [
		(market.fmt_money(int(inst["contract"]["salary"])) if know >= 100.0 else market.masked_money(uid, "wage", int(inst["contract"]["salary"]))),
		("" if know >= 100.0 else tr(" (est.)"))], ThemeBuilder.COL_TEXT, 13))

	# knowledge bar + stage ladder
	var stg: Dictionary = market.stage_for(know)
	var krow := HBoxContainer.new()
	krow.add_theme_constant_override("separation", 8)
	_detail.add_child(krow)
	krow.add_child(_dlabel("Knowledge", ThemeBuilder.COL_TEXT_DIM, 12))
	var pb := ProgressBar.new()
	pb.max_value = 100
	pb.value = know
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(140, 12)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	krow.add_child(pb)
	krow.add_child(_dlabel("%d%% · %s" % [int(know), String(stg["name"])],
		ThemeBuilder.COL_GOOD if know >= 100.0 else (ThemeBuilder.COL_WARN if know > 0 else ThemeBuilder.COL_TEXT_DIM), 12))
	if know < 100.0:
		var nxt: Dictionary = market.STAGES[mini(int(stg["idx"]) + 1, market.STAGES.size() - 1)]
		_detail.add_child(_dlabel(tr("Next stage at %d%%: %s — unlocks %s.") % [
			int(nxt["min"]), String(nxt["name"]), String(nxt["unlocks"])], ThemeBuilder.COL_TEXT_DIM, 11, true))
	if market.is_ext_uid(uid):
		_detail.add_child(_dlabel(tr("%s target — %s. Overseas business is permanent-transfer only (no loans), and scouts need the boat: travel costs real days.") % [
			market.region_of(inst), ("plays for " + String(market.club_of(t["club_id"]).get("league", "an overseas league"))) if t["pool"] == "club" else "regional youth intake"],
			ThemeBuilder.COL_ACCENT, 11, true))

	# report teaser
	if market.reports.has(uid):
		var r: Dictionary = market.reports[uid]
		if String(r.get("stage", "full")) == "interim":
			_detail.add_child(_dlabel(tr("Interim report (%s): Ability %s to %s — bands narrow as scouting continues. See Scouting tab.") % [
				r["scout"], _stars_txt(float(r.get("ability_lo", r["ability_stars"]))),
				_stars_txt(float(r.get("ability_hi", r["ability_stars"])))], ThemeBuilder.COL_WARN, 12, true))
		else:
			_detail.add_child(_dlabel(tr("Scout report (%s): Ability %s  Potential %s — see Scouting tab.") % [
				r["scout"], _stars_txt(float(r["ability_stars"])), _stars_txt(float(r["potential_stars"]))], ThemeBuilder.COL_GOOD, 12, true))

	# pipeline intel: listings, agents, rumours
	if market.is_listed(uid):
		_detail.add_child(_dlabel(tr("TRANSFER-LISTED — their club wants them gone; the ask price above is already slashed."), ThemeBuilder.COL_GOOD, 12, true))
	var ag: Dictionary = market.agent_offer_for(uid)
	if not ag.is_empty():
		_detail.add_child(_dlabel(tr("AGENT PUSHING — %s (deal greased until %s)") % [String(ag["pitch"]), I18n.pretty_date(String(ag["expires"]))], ThemeBuilder.COL_ACCENT, 12, true))
	for r in market.rumours_for(uid):
		if String(r["kind"]) == "interest" and not bool(r.get("dud", false)) and not bool(r.get("came_true", false)):
			_detail.add_child(_dlabel(tr("RUMOUR: %s") % market.rumour_text(r), ThemeBuilder.COL_BAD, 12, true))
			break

	# offer state
	var offer: Dictionary = market.offer_for_target(uid)
	if not offer.is_empty():
		_detail.add_child(_dlabel(tr("Active offer: %s — manage it in the Transfer Centre tab.") % _stage_text(offer), ThemeBuilder.COL_WARN, 12, true))

	var assign: Dictionary = market.assignment_for_target(uid)
	if not assign.is_empty():
		var eta2: int = market.assignment_eta(assign)
		var trav: int = int(assign.get("travel_left", 0))
		_detail.add_child(_dlabel(tr("%s is on this target%s — full report in ~%d day%s.") % [
			assign["scout"],
			(tr(" (in transit, %dd to arrive)") % trav) if trav > 0 else "",
			maxi(1, eta2), "" if eta2 == 1 else "s"], ThemeBuilder.COL_WARN, 12, true))

	_detail.add_child(HSeparator.new())

	# action buttons
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	_detail.add_child(brow)
	var sl_btn := Button.new()
	sl_btn.text = "Unshortlist" if market.shortlisted(uid) else tr("Shortlist")
	if not market.shortlisted(uid):
		sl_btn.icon = GlyphIcons.tex("star_empty", 11, ThemeBuilder.COL_TEXT)
	sl_btn.pressed.connect(func(): _err(market.toggle_shortlist(uid)))
	brow.add_child(sl_btn)
	var scout_btn := Button.new()
	scout_btn.text = tr("Send Scout")
	scout_btn.disabled = know >= 100.0 or not assign.is_empty()
	scout_btn.pressed.connect(func(): _open_scout_dialog(uid))
	brow.add_child(scout_btn)
	var locked: bool = not market.window_open()
	if t["pool"] == "club":
		var bid_btn := Button.new()
		bid_btn.text = tr("Make Offer / Loan")
		bid_btn.disabled = not offer.is_empty() or locked
		bid_btn.pressed.connect(func(): _open_offer_sheet(uid))
		brow.add_child(bid_btn)
	else:
		var sign_btn := Button.new()
		sign_btn.text = tr("Offer Contract")
		sign_btn.disabled = not offer.is_empty() or (locked and t["pool"] == "prospect")
		sign_btn.pressed.connect(func(): _open_contract_sheet(uid))
		brow.add_child(sign_btn)
	var cmp_btn := Button.new()
	cmp_btn.text = tr("Compare")
	cmp_btn.tooltip_text = tr("Compare with my squad")
	cmp_btn.pressed.connect(func(): MonActions.open_compare(self, uid))
	brow.add_child(cmp_btn)
	brow.add_child(MonActions.action_button(uid))
	if locked and t["pool"] != "fa":
		_detail.add_child(_dlabel(market.market_locked_reason(), ThemeBuilder.COL_TEXT_DIM, 11, true))
	elif not locked and market.days_to_deadline() <= 7 and t["pool"] == "club":
		var dd: int = market.days_to_deadline()
		_detail.add_child(_dlabel(tr("Window closes in %d day%s — clubs respond faster, rivals circle harder.") % [dd, "" if dd == 1 else "s"]
			if dd > 0 else tr("DEADLINE DAY — clubs respond within hours. Last chance."), ThemeBuilder.COL_WARN, 11, true))


# ------------------------------------------------------------ SCOUTING TAB

func _build_scouting_tab() -> void:
	var tab := HBoxContainer.new()
	tab.name = "Scouting"
	tab.add_theme_constant_override("separation", 10)
	_tabs.add_child(tab)

	# scouts column (team + hiring market)
	var col1 := VBoxContainer.new()
	col1.custom_minimum_size.x = 340
	col1.add_theme_constant_override("separation", 6)
	tab.add_child(col1)
	col1.add_child(_section_title(tr("SCOUTING TEAM")))
	var sc1 := ScrollContainer.new()
	sc1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc1.size_flags_stretch_ratio = 1.2
	sc1.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col1.add_child(sc1)
	_scout_cards = VBoxContainer.new()
	_scout_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scout_cards.add_theme_constant_override("separation", 8)
	sc1.add_child(_scout_cards)
	col1.add_child(_section_title(tr("SCOUT MARKET — HIRE THIS MONTH")))
	var scm := ScrollContainer.new()
	scm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scm.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col1.add_child(scm)
	_market_box = VBoxContainer.new()
	_market_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_box.add_theme_constant_override("separation", 6)
	scm.add_child(_market_box)

	# assignments + network column
	var col2 := VBoxContainer.new()
	col2.custom_minimum_size.x = 340
	col2.add_theme_constant_override("separation", 6)
	tab.add_child(col2)
	col2.add_child(_section_title(tr("ASSIGNMENTS IN PROGRESS")))
	var sc2 := ScrollContainer.new()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col2.add_child(sc2)
	_assign_list = VBoxContainer.new()
	_assign_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_assign_list.add_theme_constant_override("separation", 8)
	sc2.add_child(_assign_list)
	col2.add_child(_section_title(tr("REGIONAL NETWORK — MARKET KNOWLEDGE")))
	var np := PanelContainer.new()
	col2.add_child(np)
	_network_box = VBoxContainer.new()
	_network_box.add_theme_constant_override("separation", 3)
	np.add_child(_network_box)

	# reports column
	var col3 := VBoxContainer.new()
	col3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col3.add_theme_constant_override("separation", 6)
	tab.add_child(col3)
	col3.add_child(_section_title(tr("SCOUT REPORTS")))
	_report_list = ItemList.new()
	_report_list.custom_minimum_size.y = 190
	_report_list.item_selected.connect(_on_report_selected)
	col3.add_child(_report_list)
	var rp := PanelContainer.new()
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col3.add_child(rp)
	_report_card = RichTextLabel.new()
	_report_card.bbcode_enabled = true
	_report_card.fit_content = false
	_report_card.scroll_active = true
	rp.add_child(_report_card)


func _section_title(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	return l


func _refresh_scouting() -> void:
	if _scout_cards == null:
		return
	_clear(_scout_cards)
	for s in market.player_scouts():
		var card := PanelContainer.new()
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		card.add_child(vb)
		var name_row := HBoxContainer.new()
		vb.add_child(name_row)
		name_row.add_child(_dlabel(s["name"], Color.WHITE, 15))
		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(sp2)
		name_row.add_child(_dlabel(String(s["role"]).to_upper(), ThemeBuilder.COL_ACCENT, 11))
		vb.add_child(_dlabel(tr("Judging Ability %d/20  ·  Judging Potential %d/20") % [
			int(s["ratings"]["judging_ability"]), int(s["ratings"]["judging_potential"])],
			ThemeBuilder.COL_TEXT_DIM, 12, true))
		var wage_txt: String = (tr("  ·  %s/wk") % market.fmt_money(int(s["wage"]))) if s.has("wage") else ""
		var loc: String = market.scout_location(s)
		var loc_txt: String = "" if loc == market.scout_region(s) else tr("  ·  currently in %s") % tr(loc)
		vb.add_child(_dlabel(tr("Home network: %s%s%s") % [tr(market.scout_region(s)), wage_txt, loc_txt], ThemeBuilder.COL_TEXT, 12, true))
		var a: Dictionary = market.assignment_for_scout(s["name"])
		var btns := HFlowContainer.new()
		btns.add_theme_constant_override("h_separation", 6)
		if a.is_empty():
			vb.add_child(_dlabel(tr("Available — assign from Search (Send Scout) or set a focus."), ThemeBuilder.COL_TEXT_DIM, 12, true))
			var fb := Button.new()
			fb.text = tr("Set Focus")
			fb.pressed.connect(func(): _open_focus_dialog(s["name"]))
			btns.add_child(fb)
			if bool(s.get("hired", false)):
				var xb := Button.new()
				xb.text = tr("Release")
				var sn := String(s["name"])
				xb.pressed.connect(func(): _err(market.fire_scout(sn)))
				btns.add_child(xb)
		else:
			var status: String
			var trav: int = int(a.get("travel_left", 0))
			if a["kind"] == "target":
				var tt: Dictionary = market.find_target(a["uid"])
				var nm: String = tr("target") if tt.is_empty() else market.display_name(tt["inst"])
				if trav > 0:
					status = tr("En route to %s (%dd) — then watching %s") % [tr(String(a.get("region", "?"))), trav, nm]
				else:
					var eta: int = market.assignment_eta(a)
					status = tr("Watching %s — %d%% known, full report ~%dd") % [
						nm, int(market.knowledge_of(String(a["uid"]))), maxi(1, eta)]
			else:
				if trav > 0:
					status = tr("Travelling to %s (%dd) for the %s sweep") % [tr(String(a.get("region", "?"))), trav, I18n.type_name(String(a["focus_type"]))]
				else:
					status = tr("Focus: %s — sweeping %d targets/day (caps at %d%%)") % [
						_focus_label(String(a["focus_type"])), market.FOCUS_TARGETS_PER_DAY, int(market.FOCUS_KNOW_CAP)]
			vb.add_child(_dlabel(status, ThemeBuilder.COL_WARN, 12, true))
			var rb := Button.new()
			rb.text = tr("Recall")
			rb.pressed.connect(func(): market.recall_scout(s["name"]))
			btns.add_child(rb)
		vb.add_child(btns)
		_scout_cards.add_child(card)
	if market.player_scouts().is_empty():
		_scout_cards.add_child(_dlabel(tr("No staff with scouting ability at the club."), ThemeBuilder.COL_TEXT_DIM, 14, true))

	_clear(_assign_list)
	for a in market.assignments:
		var card2 := PanelContainer.new()
		var vb2 := VBoxContainer.new()
		vb2.add_theme_constant_override("separation", 4)
		card2.add_child(vb2)
		if a["kind"] == "target":
			var tt2: Dictionary = market.find_target(a["uid"])
			var nm2: String = tr("(unavailable)") if tt2.is_empty() else market.display_name(tt2["inst"])
			var know2: float = market.knowledge_of(String(a["uid"]))
			var stage2: Dictionary = market.stage_for(know2)
			vb2.add_child(_dlabel(nm2, Color.WHITE, 14))
			vb2.add_child(_dlabel(tr("%s · %s · started %s") % [a["scout"], tr(String(a.get("region", ""))),
				I18n.pretty_date(a["started"])], ThemeBuilder.COL_TEXT_DIM, 12, true))
			var trav2: int = int(a.get("travel_left", 0))
			if trav2 > 0:
				vb2.add_child(_dlabel(tr("IN TRANSIT — %s until they reach %s") % [
					I18n.np(trav2, "%d day", "%d days"), tr(String(a.get("region", tr("the patch"))))], ThemeBuilder.COL_WARN, 12, true))
			var pb := ProgressBar.new()
			pb.max_value = 100
			pb.value = know2
			pb.show_percentage = false
			pb.custom_minimum_size.y = 10
			vb2.add_child(pb)
			var eta3: int = market.assignment_eta(a)
			vb2.add_child(_dlabel(tr("%d%% — %s · full report ~%s") % [int(know2), String(stage2["name"]),
				I18n.pretty_date(Season.date_add(GameState.current_date, maxi(1, eta3)))], ThemeBuilder.COL_WARN, 12, true))
		else:
			vb2.add_child(_dlabel(tr("Focus: %s") % tr(String(a["focus_type"]).capitalize()), Color.WHITE, 14))
			vb2.add_child(_dlabel(tr("%s · rolling assignment since %s") % [a["scout"], I18n.pretty_date(a["started"])], ThemeBuilder.COL_TEXT_DIM, 12))
			vb2.add_child(_dlabel(tr("Sweeps %d matching targets a day up to %d%% knowledge (interim reports only) — a dedicated watch is needed for the full book.") % [
				market.FOCUS_TARGETS_PER_DAY, int(market.FOCUS_KNOW_CAP)], ThemeBuilder.COL_TEXT_DIM, 11, true))
		_assign_list.add_child(card2)
	if market.assignments.is_empty():
		_assign_list.add_child(_dlabel(tr("No scouts in the field.\nSelect a target in Search and press Send Scout, or set a type focus."), ThemeBuilder.COL_TEXT_DIM, 14, true))

	# reports
	var sel := _report_list.get_selected_items()
	var sel_uid := ""
	if not sel.is_empty():
		sel_uid = String(_report_list.get_item_metadata(sel[0]))
	_report_list.clear()
	var rlist: Array = market.reports.values()
	rlist.sort_custom(func(a2, b2): return String(a2["date"]) > String(b2["date"]))
	for r in rlist:
		var row_txt: String
		if String(r.get("stage", "full")) == "interim":
			row_txt = tr("[interim] %s  ·  Ability %s to %s  ·  %s") % [
				r["name"], _stars_txt(float(r.get("ability_lo", r["ability_stars"]))),
				_stars_txt(float(r.get("ability_hi", r["ability_stars"]))), I18n.pretty_date(r["date"])]
		else:
			row_txt = tr("%s  ·  Ability %s  Pot %s  ·  %s") % [
				r["name"], _stars_txt(float(r["ability_stars"])), _stars_txt(float(r["potential_stars"])), I18n.pretty_date(r["date"])]
		var idx := _report_list.add_item(row_txt)
		_report_list.set_item_metadata(idx, r["uid"])
		if String(r["uid"]) == sel_uid:
			_report_list.select(idx)
	if rlist.is_empty():
		_report_card.text = tr("[color=#8b91a8]No reports yet. Completed scouting missions produce a written report card here with exact attributes, star ratings and a recommendation.[/color]")
	elif sel_uid == "" and not rlist.is_empty():
		_report_list.select(0)
		_show_report(String(rlist[0]["uid"]))
	elif sel_uid != "":
		_show_report(sel_uid)

	_refresh_scout_market()
	_refresh_network()


func _refresh_scout_market() -> void:
	_clear(_market_box)
	var cands: Array = market.scout_market()
	var slots: int = market.MAX_HIRED_SCOUTS - market.hired_scouts().size()
	_market_box.add_child(_dlabel(tr("Dedicated scouts for hire (%d/%d slots free). New candidates monthly. Wages come off the wage budget.") % [
		slots, market.MAX_HIRED_SCOUTS], ThemeBuilder.COL_TEXT_DIM, 11, true))
	for c in cands:
		var card := PanelContainer.new()
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		card.add_child(vb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		row.add_child(_dlabel(String(c["name"]), Color.WHITE, 13))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		row.add_child(_dlabel("%s/wk" % market.fmt_money(int(c["wage"])), ThemeBuilder.COL_WARN, 12))
		vb.add_child(_dlabel(tr("JA %d · JP %d  ·  network: %s") % [int(c["ja"]), int(c["jp"]), tr(String(c["region"]))],
			ThemeBuilder.COL_TEXT_DIM, 11, true))
		var hb := Button.new()
		hb.text = tr("Hire")
		hb.disabled = slots <= 0
		var cn := String(c["name"])
		hb.pressed.connect(func(): _err(market.hire_scout(cn)))
		vb.add_child(hb)
		_market_box.add_child(card)
	if cands.is_empty():
		_market_box.add_child(_dlabel(tr("No candidates left this month — the pool refreshes on the 1st."), ThemeBuilder.COL_TEXT_DIM, 12, true))


func _refresh_network() -> void:
	_clear(_network_box)
	var cov: Dictionary = market.region_coverage()
	for r in cov:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_network_box.add_child(row)
		var nm := _dlabel(tr(String(r)), ThemeBuilder.COL_TEXT, 11)
		nm.custom_minimum_size.x = 116
		row.add_child(nm)
		var pb := ProgressBar.new()
		pb.max_value = 100
		pb.value = float(cov[r]["know"])
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(90, 10)
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pb)
		row.add_child(_dlabel("%d%%" % int(cov[r]["know"]), ThemeBuilder.COL_TEXT_DIM, 11))
		var ns := int(cov[r]["scouts"])
		row.add_child(_dlabel(I18n.np(ns, "%d scout", "%d scouts"),
			ThemeBuilder.COL_GOOD if ns > 0 else ThemeBuilder.COL_TEXT_DIM, 11))
	_network_box.add_child(_dlabel(tr("Scouts work faster on their home patch; region focuses build knowledge across it."), ThemeBuilder.COL_TEXT_DIM, 10, true))


func _focus_label(ft: String) -> String:
	## Region focuses show the region name; type focuses the localized type.
	return tr(ft) if market.REGIONS.has(ft) else I18n.type_name(ft)


func _on_report_selected(idx: int) -> void:
	_show_report(String(_report_list.get_item_metadata(idx)))


func _show_report(uid: String) -> void:
	if not market.reports.has(uid):
		_report_card.text = ""
		return
	var r: Dictionary = market.reports[uid]
	var types_txt := I18n.types_join(r["types"], " / ")
	var interim: bool = String(r.get("stage", "full")) == "interim"
	var s := tr("[b][font_size=20]%s[/font_size][/b]   [color=#8b91a8]Lv %d · %s[/color]\n") % [r["name"], int(r["level"]), types_txt]
	s += tr("[color=#8b91a8]Filed by %s on %s[/color]\n") % [r["scout"], I18n.pretty_date(r["date"])]
	if interim:
		s += tr("[color=#e0b050][b]INTERIM REPORT[/b] — %d%% scouted. Star ratings are a RANGE; keep the scout on the watch to narrow it.[/color]\n\n") % int(float(r.get("knowledge", 50.0)))
		s += tr("[b]Current ability[/b]   [color=#e0b050]%s — %s[/color]\n") % [
			_stars(float(r.get("ability_lo", r["ability_stars"]))), _stars(float(r.get("ability_hi", r["ability_stars"])))]
		s += tr("[b]Potential[/b]           [color=#e0b050]%s — %s[/color]\n\n") % [
			_stars(float(r.get("potential_lo", r["potential_stars"]))), _stars(float(r.get("potential_hi", r["potential_stars"])))]
	else:
		s += tr("\n[b]Current ability[/b]   [color=#e0b050]%s[/color]\n") % _stars(float(r["ability_stars"]))
		s += tr("[b]Potential[/b]           [color=#e0b050]%s[/color]\n\n") % _stars(float(r["potential_stars"]))
	# temperament + battle ability: live staged knowledge (nature at 50%, ability at 75%)
	var rt: Dictionary = market.find_target(uid)
	if not rt.is_empty():
		var rn: String = market.known_nature(rt["inst"])
		var ra: String = market.known_ability(rt["inst"])
		s += "[b]Nature[/b]  %s\n" % (("[color=#d8dbe6]%s[/color]" % market.nature_text(rn)) if rn != ""
			else tr("[color=#8b91a8]unknown — revealed at Part scouted (50%)[/color]"))
		if ra != "":
			s += tr("[b]Battle ability[/b]  [color=#d8dbe6]%s[/color] [color=#8b91a8]— %s[/color]\n\n") % [
				DataStore.ability_name(ra), String(DataStore.ability(ra).get("desc", ""))]
		else:
			s += tr("[b]Battle ability[/b]  [color=#8b91a8]unconfirmed — a Detailed watch (75%) pins it down[/color]\n\n")
	s += tr("[b]Strengths[/b]\n")
	for p in r["pros"]:
		s += tr("[color=#57c979]  +  %s[/color]\n") % p
	s += tr("\n[b]Weaknesses[/b]\n")
	for c in r["cons"]:
		s += tr("[color=#e06060]  -  %s[/color]\n") % c
	s += tr("\n[b]Verdict:[/b] [i]%s[/i]") % r["verdict"]
	_report_card.text = s


## Star meter for BBCode report cards — drawn SVG icons (no star glyph in
## the bundled web font).
func _stars(v: float) -> String:
	var full := int(v)
	var half := (v - float(full)) >= 0.45
	var s := ""
	for i in full:
		s += "[img=13x13]res://shared/theme/icons/star_warn.svg[/img]"
	if half:
		s += "[img=13x13]res://shared/theme/icons/star_half_warn.svg[/img]"
	for i in maxi(0, 5 - full - (1 if half else 0)):
		s += "[img=13x13]res://shared/theme/icons/star_empty.svg[/img]"
	return s


## Compact numeric meter for plain Labels / list rows ("3½/5").
func _stars_txt(v: float) -> String:
	var full := int(v)
	var half := (v - float(full)) >= 0.45
	return "%d%s/5" % [full, "½" if half else ""]


# ------------------------------------------------------------ TRANSFER CENTRE TAB

func _build_centre_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = tr("Transfer Centre")
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)

	_window_banner = PanelContainer.new()
	tab.add_child(_window_banner)

	_centre_budget = HFlowContainer.new()
	_centre_budget.add_theme_constant_override("h_separation", 26)
	_centre_budget.add_theme_constant_override("v_separation", 2)
	tab.add_child(_centre_budget)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	tab.add_child(body)

	var col1 := VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col1.size_flags_stretch_ratio = 1.1
	col1.add_theme_constant_override("separation", 6)
	body.add_child(col1)
	col1.add_child(_section_title(tr("OUTGOING OFFERS (BIDS WE MADE)")))
	var sc1 := ScrollContainer.new()
	sc1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc1.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col1.add_child(sc1)
	_out_box = VBoxContainer.new()
	_out_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_out_box.add_theme_constant_override("separation", 8)
	sc1.add_child(_out_box)

	var col2 := VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2.size_flags_stretch_ratio = 1.1
	col2.add_theme_constant_override("separation", 6)
	body.add_child(col2)
	col2.add_child(_section_title(tr("INCOMING OFFERS (FOR OUR SQUAD)")))
	var sc2 := ScrollContainer.new()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col2.add_child(sc2)
	_in_box = VBoxContainer.new()
	_in_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_in_box.add_theme_constant_override("separation", 8)
	sc2.add_child(_in_box)

	var col3 := VBoxContainer.new()
	col3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col3.size_flags_stretch_ratio = 1.3
	col3.add_theme_constant_override("separation", 6)
	body.add_child(col3)
	col3.add_child(_section_title(tr("LATEST DEALS AROUND THE LEAGUE")))
	_deals_tree = Tree.new()
	_deals_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_deals_tree.hide_root = true
	_deals_tree.columns = 5
	_deals_tree.set_column_titles_visible(true)
	var dt := ["Date", "Pokémon", "Deal", "Fee", "Structure"]
	var dw := [64, 96, 100, 70, 140]
	for i in 5:
		_deals_tree.set_column_title(i, dt[i])
		_deals_tree.set_column_expand(i, i == 4)
		_deals_tree.set_column_custom_minimum_width(i, dw[i])
	col3.add_child(_deals_tree)


func _stage_text(o: Dictionary) -> String:
	match String(o["stage"]):
		"bid_pending": return tr("Awaiting response — due %s") % I18n.pretty_date(o["respond_on"])
		"countered":
			if o["kind"] == "loan":
				return tr("Loan countered — they want: %s") % market.describe_loan(o.get("loan_ask", {}))
			return tr("Countered — they propose: %s") % market.describe_package(o.get("ask_package", {}))
		"fee_agreed": return tr("Package agreed — wage demand %s/wk") % market.fmt_money(int(o.get("contract_demand", {}).get("wage", 0)))
		"wage_pending": return tr("Contract offered — reply due %s") % I18n.pretty_date(o["respond_on"])
		"wage_countered": return tr("Wants %s/wk to sign") % market.fmt_money(int(o.get("contract_demand", {}).get("wage", 0)))
		"completed": return tr("Deal completed")
		"rejected": return tr("Offer rejected")
		"withdrawn": return "Withdrawn"
		"collapsed": return tr("Talks collapsed")
		"hijacked": return tr("HIJACKED — a rival club completed the deal")
	return String(o["stage"])


func _stage_color(stage: String) -> Color:
	if stage in ["completed", "fee_agreed", "agreed"]:
		return ThemeBuilder.COL_GOOD
	if stage in ["rejected", "withdrawn", "collapsed", "expired", "hijacked"]:
		return ThemeBuilder.COL_BAD
	return ThemeBuilder.COL_WARN


func _refresh_window_banner() -> void:
	_clear(_window_banner)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var lead: Label
	var info: Label
	var w: Dictionary = market.current_window()
	if not w.is_empty():
		var d: int = market.days_to_deadline()
		if d == 0:
			sb.bg_color = Color(0.42, 0.10, 0.10)
			lead = _dlabel(tr("DEADLINE DAY"), Color.WHITE, 18)
			info = _dlabel(tr("The %s slams shut tonight. Clubs reply within hours — every unfinished deal dies at midnight.") % String(w["name"]).to_lower(), Color(1, 0.85, 0.8), 13, true)
		else:
			sb.bg_color = Color(0.32, 0.22, 0.06) if d <= 7 else Color(0.08, 0.24, 0.13)
			lead = _dlabel(tr("%s OPEN") % String(w["name"]).to_upper(), Color.WHITE, 16)
			info = _dlabel(tr("Deadline day %s  ·  %d day%s remaining  ·  market: %s") % [
				I18n.pretty_date(String(w["close"])), d, "" if d == 1 else "s", market.temperature_label()],
				ThemeBuilder.COL_TEXT, 13, true)
	else:
		sb.bg_color = Color(0.13, 0.14, 0.18)
		var nw: Dictionary = market.next_window()
		lead = _dlabel(tr("TRANSFER WINDOW CLOSED"), ThemeBuilder.COL_TEXT_DIM, 16)
		info = _dlabel(tr("Market locked — reopens %s (%s, %d days). Free agents can still be signed; scouting never stops.") % [
			I18n.pretty_date(String(nw["open"])), String(nw["name"]), market.days_to_open()],
			ThemeBuilder.COL_TEXT_DIM, 13, true)
	lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lead)
	row.add_child(info)
	_window_banner.add_theme_stylebox_override("panel", sb)
	_window_banner.add_child(row)


func _refresh_centre() -> void:
	if _out_box == null:
		return
	_refresh_window_banner()
	# budget strip
	_clear(_centre_budget)
	var pc: Dictionary = GameState.player_club()
	var bill: int = market.wage_bill(pc)
	_centre_budget.add_child(_dlabel(tr("Transfer budget:  %s") % market.fmt_money_full(maxi(0, market.spendable_budget())), ThemeBuilder.COL_GOOD, 15))
	_centre_budget.add_child(_dlabel(tr("Bank balance:  %s") % market.fmt_money_full(int(pc["finances"]["balance"])), ThemeBuilder.COL_TEXT_DIM, 15))
	_centre_budget.add_child(_dlabel(tr("Wage bill:  %s / %s per wk") % [
		market.fmt_money_full(bill), market.fmt_money_full(int(pc["finances"]["wage_budget"]))],
		ThemeBuilder.COL_TEXT, 15))
	var room: int = market.wage_room()
	_centre_budget.add_child(_dlabel(tr("Wage room:  %s/wk") % market.fmt_money_full(room),
		ThemeBuilder.COL_GOOD if room > 0 else ThemeBuilder.COL_BAD, 15))
	var committed: int = market.committed_installments()
	var incoming: int = market.incoming_installments()
	if committed > 0 or incoming > 0:
		_centre_budget.add_child(_dlabel(tr("Installments:  %s owed · %s due in") % [
			market.fmt_money(committed), market.fmt_money(incoming)],
			ThemeBuilder.COL_WARN if committed > 0 else ThemeBuilder.COL_TEXT_DIM, 15))
	_centre_budget.add_child(_dlabel(tr("Squad size:  %d") % pc["squad"].size(), ThemeBuilder.COL_TEXT_DIM, 15))

	# outgoing
	_clear(_out_box)
	for inst in market.loaned_in():
		_out_box.add_child(_make_loan_card(inst))
	var live: Array = market.offers_out.filter(func(o): return not (String(o["stage"]) in market.DEAD_STAGES))
	var dead: Array = market.offers_out.filter(func(o): return String(o["stage"]) in market.DEAD_STAGES)
	dead.reverse()
	for o in live:
		_out_box.add_child(_make_out_card(o, true))
	for o in dead.slice(0, 4):
		_out_box.add_child(_make_out_card(o, false))
	if live.is_empty() and dead.is_empty() and market.loaned_in().is_empty():
		_out_box.add_child(_dlabel(tr("No outgoing offers.\nFind a target in Search and press Make Offer to build a package — up-front fee, installments, a sell-on clause, or a loan with wage split and option to buy. Clubs respond within a couple of days and counter with structures of their own."), ThemeBuilder.COL_TEXT_DIM, 14, true))

	# incoming
	_clear(_in_box)
	var live_in: Array = market.offers_in.filter(func(o): return String(o["stage"]) in ["open", "counter_pending", "agreed"])
	var dead_in: Array = market.offers_in.filter(func(o): return not (String(o["stage"]) in ["open", "counter_pending", "agreed"]))
	dead_in.reverse()
	for o in live_in:
		_in_box.add_child(_make_in_card(o, true))
	for o in dead_in.slice(0, 3):
		_in_box.add_child(_make_in_card(o, false))
	if live_in.is_empty() and dead_in.is_empty():
		_in_box.add_child(_dlabel(tr("No incoming offers right now.\nRival clubs bid for your squad as the season runs — accept, reject or hold out for more."), ThemeBuilder.COL_TEXT_DIM, 14, true))

	# deals log
	_deals_tree.clear()
	var droot := _deals_tree.create_item()
	for d in market.deals:
		var it := _deals_tree.create_item(droot)
		it.set_text(0, I18n.short_date(String(d["date"])))
		it.set_custom_color(0, ThemeBuilder.COL_TEXT_DIM)
		it.set_text(1, String(d["name"]))
		it.set_custom_color(1, Color.WHITE)
		it.set_text(2, "%s » %s" % [_short_club_name(String(d["from"])), _short_club_name(String(d["to"]))])
		it.set_tooltip_text(2, "%s » %s" % [String(d["from"]), String(d["to"])])
		it.set_custom_color(2, ThemeBuilder.COL_TEXT_DIM)
		it.set_text(3, market.fmt_money(int(d["fee"])) if int(d["fee"]) > 0 else "Free")
		var kind := String(d["kind"])
		it.set_custom_color(3, ThemeBuilder.COL_GOOD if kind == "sale" else (ThemeBuilder.COL_WARN if kind in ["buy", "fa_in", "loan"] else ThemeBuilder.COL_TEXT_DIM))
		var terms := String(d.get("terms", ""))
		it.set_text(4, terms)
		it.set_tooltip_text(4, terms)
		it.set_custom_color(4, ThemeBuilder.COL_TEXT_DIM)
	if market.deals.is_empty():
		var it2 := _deals_tree.create_item(droot)
		it2.set_text(2, tr("No completed deals yet this season."))
		it2.set_custom_color(2, ThemeBuilder.COL_TEXT_DIM)


func _short_club_name(full: String) -> String:
	for c in GameState.world["clubs"]:
		if String(c["name"]) == full:
			return String(c["short"])
	for c in market.ext_clubs():
		if String(c["name"]) == full:
			return String(c["short"])
	if full == "Free agency":
		return tr("Free agent")
	return full


func _make_out_card(o: Dictionary, live: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var who: String
	if o["kind"] == "buy":
		who = tr("%s  ·  from %s") % [String(o["name"]), market.club_of(o["club_id"])["short"]]
	elif o["kind"] == "loan":
		who = tr("%s  ·  loan from %s") % [String(o["name"]), market.club_of(o["club_id"])["short"]]
	elif o["kind"] == "prospect":
		who = tr("%s  ·  youth prospect") % String(o["name"])
	else:
		who = tr("%s  ·  free agent") % String(o["name"])
	var who_l := _dlabel(who, Color.WHITE if live else ThemeBuilder.COL_TEXT_DIM, 14, true)
	who_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who_l)
	var stage := _dlabel(_stage_text(o), _stage_color(String(o["stage"])), 12)
	stage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(stage)
	# rival club circling this deal
	var rv: Dictionary = o.get("rival", {})
	if live and not rv.is_empty():
		vb.add_child(_dlabel(tr("RIVAL BID: %s have ~%s on the table — %s decide by %s. Beat it or lose the deal.") % [
			String(rv["club"]), market.fmt_money(int(rv["value"])),
			market.club_of(String(o["club_id"]))["short"], I18n.pretty_date(String(rv["decides_on"]))],
			ThemeBuilder.COL_BAD, 12, true))
	# our current terms on the table
	var terms := ""
	if o["kind"] == "loan":
		terms = market.describe_loan(o.get("loan_terms", {}))
	elif market.package_total(o.get("package", {})) > 0 or int(o.get("package", {}).get("sell_on", 0)) > 0:
		terms = tr("Our package: %s") % market.describe_package(o["package"])
	if not o.get("contract", {}).is_empty() and int(o["contract"].get("wage", 0)) > 0:
		terms += ("   ·   " if terms != "" else "") + market.describe_contract(o["contract"])
	if terms != "":
		vb.add_child(_dlabel(terms, ThemeBuilder.COL_TEXT_DIM, 12, true))
	# structured alternative the seller floated
	if live and String(o["stage"]) == "countered" and o["kind"] == "buy" and not o.get("alt_package", {}).is_empty():
		vb.add_child(_dlabel(tr("…or structured: %s") % market.describe_package(o["alt_package"]), ThemeBuilder.COL_WARN, 12, true))
	if live and String(o["stage"]) == "wage_countered" and not o.get("contract_demand", {}).is_empty():
		var alt: Dictionary = market._contract_alternative(o["contract_demand"], _offer_inst(o))
		if not alt.is_empty():
			vb.add_child(_dlabel(tr("…or would take: %s") % market.describe_contract(alt), ThemeBuilder.COL_WARN, 12, true))
	if not o["log"].is_empty():
		var last: Dictionary = o["log"][o["log"].size() - 1]
		vb.add_child(_dlabel("%s — %s" % [I18n.short_date(String(last["date"])), String(last["text"])], ThemeBuilder.COL_TEXT_DIM, 11, true))
	if live:
		var btns := HFlowContainer.new()
		btns.add_theme_constant_override("h_separation", 6)
		vb.add_child(btns)
		var oid := int(o["id"])
		var uid := String(o["uid"])
		match String(o["stage"]):
			"countered":
				if o["kind"] == "loan":
					var bl := Button.new()
					bl.text = tr("Accept Terms")
					bl.pressed.connect(func(): _err(market.accept_package(oid)))
					btns.add_child(bl)
					var bl2 := Button.new()
					bl2.text = tr("Adjust Loan")
					bl2.pressed.connect(func(): _open_offer_sheet(uid, oid))
					btns.add_child(bl2)
				else:
					var b1 := Button.new()
					b1.text = tr("Accept Proposal")
					b1.pressed.connect(func(): _err(market.accept_package(oid, "ask")))
					btns.add_child(b1)
					if not o.get("alt_package", {}).is_empty():
						var b2 := Button.new()
						b2.text = tr("Take Structured")
						b2.pressed.connect(func(): _err(market.accept_package(oid, "alt")))
						btns.add_child(b2)
					var b3 := Button.new()
					b3.text = tr("Adjust Offer")
					b3.pressed.connect(func(): _open_offer_sheet(uid, oid))
					btns.add_child(b3)
			"fee_agreed", "wage_countered":
				var b4 := Button.new()
				b4.text = tr("Offer Contract")
				b4.pressed.connect(func(): _open_contract_sheet(uid, oid))
				btns.add_child(b4)
		var bw := Button.new()
		bw.text = "Withdraw offer"
		bw.pressed.connect(func(): market.withdraw_offer(oid))
		btns.add_child(bw)
	return card


func _offer_inst(o: Dictionary) -> Dictionary:
	var t: Dictionary = market.find_target(String(o["uid"]))
	return {} if t.is_empty() else t["inst"]


func _make_loan_card(inst: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	var lo: Dictionary = inst["loan"]
	var owner: Dictionary = GameState.club(String(lo["owner"]))
	vb.add_child(_dlabel(tr("%s  ·  ON LOAN from %s") % [market.display_name(inst), owner["short"]], ThemeBuilder.COL_ACCENT, 14))
	var opt := int(lo.get("option_fee", 0))
	vb.add_child(_dlabel(tr("Until %s · we pay %d%% of %s/wk%s") % [
		I18n.pretty_date(String(lo["until"])), int(lo.get("wage_split", 100)),
		market.fmt_money(int(inst["contract"]["salary"])),
		(tr(" · option to buy %s") % market.fmt_money(opt)) if opt > 0 else ""],
		ThemeBuilder.COL_TEXT_DIM, 12, true))
	if opt > 0:
		var btns := HFlowContainer.new()
		vb.add_child(btns)
		var b := Button.new()
		b.text = tr("Exercise Option (%s)") % market.fmt_money(opt)
		var uid := String(inst["uid"])
		b.pressed.connect(func(): _err(market.exercise_loan_option(uid)))
		btns.add_child(b)
	return card


func _make_in_card(o: Dictionary, live: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	var buyer: Dictionary = GameState.club(o["club_id"])
	vb.add_child(_dlabel(tr("%s  ·  bid from %s") % [String(o["name"]), buyer["name"]], Color.WHITE if live else ThemeBuilder.COL_TEXT_DIM, 14, true))
	var t: Dictionary = market.find_target(o["uid"])
	var val_txt := "" if t.is_empty() else tr("   ·   our valuation %s") % market.fmt_money(market.value_of(t["inst"]))
	vb.add_child(_dlabel(tr("Offer: %s%s") % [market.describe_package(o.get("package", {})), val_txt], ThemeBuilder.COL_WARN, 13, true))
	match String(o["stage"]):
		"open":
			vb.add_child(_dlabel(tr("Expires %s") % I18n.pretty_date(String(o.get("expires_on", ""))), ThemeBuilder.COL_TEXT_DIM, 11))
		"counter_pending":
			var so := int(o.get("ask_sell_on", 0))
			vb.add_child(_dlabel(tr("We demanded %s%s — their reply due %s") % [
				market.fmt_money(int(o["ask"])), (tr(" + %d%% sell-on") % so) if so > 0 else "",
				I18n.pretty_date(String(o["respond_on"]))], ThemeBuilder.COL_WARN, 11, true))
		"agreed":
			var so2 := int(o.get("ask_sell_on", 0))
			vb.add_child(_dlabel(tr("They agreed: %s%s — confirm to complete.") % [
				market.fmt_money(int(o["ask"])), (tr(" + %d%% sell-on") % so2) if so2 > 0 else ""], ThemeBuilder.COL_GOOD, 11, true))
		_:
			if not o["log"].is_empty():
				var last: Dictionary = o["log"][o["log"].size() - 1]
				vb.add_child(_dlabel(String(last["text"]), ThemeBuilder.COL_TEXT_DIM, 11, true))
	if live:
		var btns := HFlowContainer.new()
		btns.add_theme_constant_override("h_separation", 6)
		vb.add_child(btns)
		var oid := int(o["id"])
		if String(o["stage"]) in ["open", "agreed"]:
			var ba := Button.new()
			ba.text = "Confirm Sale" if String(o["stage"]) == "agreed" else "Accept"
			ba.pressed.connect(func(): _err(market.accept_offer_in(oid)))
			btns.add_child(ba)
		if String(o["stage"]) == "open":
			var bn := Button.new()
			bn.text = tr("Ask More")
			bn.pressed.connect(func(): _open_counter_in_dialog(oid))
			btns.add_child(bn)
		var br := Button.new()
		br.text = "Reject"
		br.pressed.connect(func(): market.reject_offer_in(oid))
		btns.add_child(br)
	return card


# ------------------------------------------------------------ dialogs

func _err(msg: String) -> void:
	if msg == "":
		return
	var dlg := AcceptDialog.new()
	dlg.title = tr("Transfer Centre")
	dlg.dialog_text = msg
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	ThemeBuilder.popup_fitted(self, dlg)


func _sheet_spin(minv: int, maxv: int, step: int, val: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minv
	spin.max_value = maxv
	spin.step = step
	spin.value = val
	spin.custom_minimum_size.x = 150
	return spin


func _sheet_row(grid: GridContainer, label_txt: String, ctl: Control, note: String = "") -> void:
	grid.add_child(_dlabel(label_txt, ThemeBuilder.COL_TEXT, 13))
	if note == "":
		grid.add_child(ctl)
	else:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.add_child(ctl)
		hb.add_child(_dlabel(note, ThemeBuilder.COL_TEXT_DIM, 11))
		grid.add_child(hb)


func _open_offer_sheet(uid: String, offer_id: int = -1) -> void:
	## Delegated to the GLOBAL action layer (shared/ui/mon_actions.gd) so the
	## exact same negotiation sheet opens from ANY screen's context menu.
	MonActions.open_offer_sheet(self, uid, offer_id)


func _open_contract_sheet(uid: String, offer_id: int = -1) -> void:
	## Delegated to the global action layer (see _open_offer_sheet).
	MonActions.open_contract_sheet(self, uid, offer_id)


func _open_counter_in_dialog(offer_id: int) -> void:
	var o: Dictionary = market._offer_in(offer_id)
	if o.is_empty():
		return
	var t: Dictionary = market.find_target(o["uid"])
	var val: int = 0 if t.is_empty() else market.value_of(t["inst"])
	var dlg := ConfirmationDialog.new()
	dlg.title = tr("Negotiate — %s") % String(o["name"])
	dlg.min_size = Vector2i(480, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	dlg.add_child(vb)
	vb.add_child(_dlabel(tr("Their bid: %s   ·   our valuation: %s") % [
		market.describe_package(o.get("package", {})), market.fmt_money(val)], ThemeBuilder.COL_TEXT_DIM, 13, true))
	vb.add_child(_dlabel(tr("Demand a fee and, optionally, a sell-on clause — they weigh both and may meet you, improve their cash bid, or walk away."), ThemeBuilder.COL_TEXT_DIM, 12, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	var fee_spin := _sheet_spin(0, 10000000, 1000, int(float(maxi(val, market.package_total(o.get("package", {})))) * 1.15))
	_sheet_row(grid, tr("Fee demand"), fee_spin)
	var so_spin := _sheet_spin(0, 50, 5, 0)
	_sheet_row(grid, tr("Sell-on clause %"), so_spin, tr("we keep % of THEIR next sale"))
	dlg.get_ok_button().text = tr("Send Demands")
	dlg.confirmed.connect(func():
		_err(market.counter_offer_in(offer_id, int(fee_spin.value), int(so_spin.value)))
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	ThemeBuilder.popup_fitted(self, dlg, vb)


func _open_scout_dialog(uid: String) -> void:
	## Delegated to the global action layer (see _open_offer_sheet).
	MonActions.open_scout_dialog(self, uid)


func _open_focus_dialog(scout_name: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = tr("Scouting focus — %s") % scout_name
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var expl := _dlabel(tr("A focus is a broad sweep: %d matching targets a day gain knowledge, capped at %d%% (interim intel only). Region focuses require travelling there. Use a dedicated target watch for a full report.") % [
		market.FOCUS_TARGETS_PER_DAY, int(market.FOCUS_KNOW_CAP)], ThemeBuilder.COL_TEXT_DIM, 12, true)
	expl.custom_minimum_size.x = 360
	vb.add_child(expl)
	var opt := OptionButton.new()
	var choices: Array = ["Any", "Prospects", "Free agents", "Shortlist"]
	for rg in market.REGIONS:
		choices.append(String(rg))
	for ty in DataStore.types:
		choices.append(String(ty))
	for c in choices:
		opt.add_item(tr(String(c).capitalize()))
	vb.add_child(opt)
	dlg.add_child(vb)
	dlg.get_ok_button().text = tr("Assign")
	dlg.confirmed.connect(func():
		_err(market.assign_scout_to_focus(scout_name, String(choices[opt.selected])))
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	ThemeBuilder.popup_fitted(self, dlg, vb)


# ------------------------------------------------------------ refresh

func _refresh_all() -> void:
	if not is_inside_tree():
		return
	_refresh_header()
	_refresh_recruitment()
	_refresh_search()
	_refresh_detail()
	_refresh_scouting()
	_refresh_centre()


func _refresh_header() -> void:
	_clear(_header_stats)
	# Window countdown — the market's heartbeat, always visible.
	var w: Dictionary = market.current_window()
	if not w.is_empty():
		var d: int = market.days_to_deadline()
		if d == 0:
			_header_stat(String(w["name"]) + tr(" · OPEN"), tr("DEADLINE DAY"), ThemeBuilder.COL_BAD)
		elif d <= 7:
			_header_stat(String(w["name"]) + tr(" · OPEN"), tr("%d day%s to deadline") % [d, "" if d == 1 else "s"], ThemeBuilder.COL_WARN)
		else:
			_header_stat(String(w["name"]) + tr(" · OPEN"), tr("closes in %d days") % d, ThemeBuilder.COL_GOOD)
	else:
		var nw: Dictionary = market.next_window()
		_header_stat(tr("Window CLOSED"), tr("opens %s (%dd)") % [I18n.pretty_date(String(nw["open"])), market.days_to_open()], ThemeBuilder.COL_TEXT_DIM)
	_header_stat(tr("Transfer budget"), market.fmt_money(maxi(0, market.spendable_budget())), ThemeBuilder.COL_GOOD)
	var room: int = market.wage_room()
	_header_stat(tr("Wage room"), market.fmt_money(room) + tr("/wk"), ThemeBuilder.COL_GOOD if room > 0 else ThemeBuilder.COL_BAD)
	var live_out: int = market.offers_out.filter(func(o): return not (String(o["stage"]) in market.DEAD_STAGES)).size()
	var live_in: int = market.active_offers_in().size()
	_header_stat(tr("Active offers"), tr("%d out · %d in") % [live_out, live_in],
		ThemeBuilder.COL_WARN if (live_out + live_in) > 0 else ThemeBuilder.COL_TEXT)
	_header_stat(tr("Scouts in field"), "%d / %d" % [market.assignments.size(), market.player_scouts().size()])
	var n_recs: int = market.new_recs().size()
	var n_agents: int = market.open_agent_offers().size()
	_header_stat(tr("Pushed to us"), tr("%d recs · %d agents") % [n_recs, n_agents],
		ThemeBuilder.COL_ACCENT if (n_recs + n_agents) > 0 else ThemeBuilder.COL_TEXT)
	_header_stat(tr("Shortlist"), tr("%d targets") % market.shortlist_targets().size())
	_header_stat(tr("Market"), tr("%d targets · %d full books") % [market.all_targets().size(), market.full_report_count()],
		ThemeBuilder.COL_TEXT_DIM)
