extends Control
const EvoSvc := preload("res://shared/sim/services/evolution.gd")
## Items screen — FM-facility-style League Store & club storeroom.
## Left: browsable catalog (filters, prices, stock) — buy with club funds.
## Right: item dossier + squad equipment board: equip/unequip held items
## onto your squad's Pokémon (pick item -> pick mon -> Equip).

const RARITY_COLORS := {
	"common": ThemeBuilder.COL_TEXT_DIM,
	"uncommon": ThemeBuilder.COL_GOOD,
	"rare": ThemeBuilder.COL_WARN,
}
const CLASS_LABEL := {"held": "HELD", "usable": "USABLE"}
## Drawn inline arrow for the equip status line (no arrow glyph in the web font).
const ARROW_IMG := "[img=12x12]res://shared/theme/icons/arrow_dim.svg[/img]"
const CLASS_FILTERS := ["All items", "Held (passive in battle)", "Usable (trainer action)", "Evolution stones"]
const RARITY_FILTERS := ["Any rarity", "Common", "Uncommon", "Rare"]

var _search := ""
var _class_filter := 0
var _rarity_filter := 0
var _stock_only := false
var _selected_item := ""
var _selected_uid := ""

var _header_stats: HBoxContainer
var _shop_tree: Tree
var _count_label: Label
var _detail: VBoxContainer
var _squad_tree: Tree
var _equip_btn: Button
var _strip_btn: Button
var _use_btn: Button        # evolution stones: apply from the storeroom
var _equip_hint: RichTextLabel


func _ready() -> void:
	GameState.inventory_changed.connect(_refresh_all)
	GameState.career_started.connect(_refresh_all)
	GameState.date_changed.connect(func(_d): _refresh_all())
	_build_ui()
	_refresh_all()


func on_show() -> void:
	# Dev hook for screenshot verification (env-gated, no effect in normal play):
	# ITEMS_DEV_SELECT="<item_id>:<uid>" preselects a catalog item + squad mon.
	var sel := OS.get_environment("ITEMS_DEV_SELECT")
	if sel.contains(":"):
		_selected_item = sel.get_slice(":", 0)
		_selected_uid = sel.get_slice(":", 1)
	_refresh_all()


# ================================================================== helpers

func _cur() -> String:
	return str(GameState.world["meta"]["currency"])


func _money(v: int) -> String:
	return "%s%s%s" % ["-" if v < 0 else "", _cur(), I18n.number(absi(v))]


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _lbl(txt: String, col: Color = ThemeBuilder.COL_TEXT, size: int = 14, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _section_title(txt: String) -> Label:
	return _lbl(txt, ThemeBuilder.COL_ACCENT, 12)


func _chip(txt: String, bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_lbl(txt, Color(0.05, 0.05, 0.08), 11))
	return p


func _err(msg: String) -> void:
	if msg == "":
		return
	var dlg := AcceptDialog.new()
	dlg.title = tr("League Store")
	dlg.dialog_text = msg
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## Squad members holding a given item id.
func _holders(item_id: String) -> Array:
	var out: Array = []
	for m in GameState.player_club()["squad"]:
		var h: Variant = m.get("held_item")
		if h != null and str(h) == item_id:
			out.append(m)
	return out


func _display_name(inst: Dictionary) -> String:
	return str(inst["nickname"]) if inst.get("nickname") else str(inst["species"])


# ================================================================== UI build

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
	title.text = tr("League Store & Equipment")
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_header_stats = HBoxContainer.new()
	_header_stats.add_theme_constant_override("separation", 22)
	head.add_child(_header_stats)

	# ---- body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)

	# ------ left: catalog
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.35
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	left.add_child(_section_title(tr("LEAGUE STORE — CATALOG & CLUB STOREROOM")))

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	left.add_child(bar)
	var search := LineEdit.new()
	search.placeholder_text = tr("Search items...")
	search.custom_minimum_size.x = 190
	search.text_changed.connect(func(t: String):
		_search = t
		_refresh_shop())
	bar.add_child(search)
	var cls := OptionButton.new()
	for c in CLASS_FILTERS:
		cls.add_item(c)
	cls.item_selected.connect(func(i: int):
		_class_filter = i
		_refresh_shop())
	bar.add_child(cls)
	var rar := OptionButton.new()
	for r in RARITY_FILTERS:
		rar.add_item(r)
	rar.item_selected.connect(func(i: int):
		_rarity_filter = i
		_refresh_shop())
	bar.add_child(rar)
	var stock := CheckBox.new()
	stock.text = tr("In storeroom")
	stock.toggled.connect(func(on: bool):
		_stock_only = on
		_refresh_shop())
	bar.add_child(stock)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	bar.add_child(_count_label)

	_shop_tree = Tree.new()
	_shop_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shop_tree.hide_root = true
	_shop_tree.select_mode = Tree.SELECT_ROW
	_shop_tree.columns = 6
	_shop_tree.set_column_titles_visible(true)
	var titles := ["Item", "Class", "Rarity", "Effect", "Price", "Owned"]
	var widths := [150, 66, 84, 220, 84, 58]
	for i in 6:
		_shop_tree.set_column_title(i, titles[i])
		_shop_tree.set_column_expand(i, i == 3)
		_shop_tree.set_column_custom_minimum_width(i, widths[i])
		_shop_tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT if i >= 4 else HORIZONTAL_ALIGNMENT_LEFT)
	_shop_tree.item_selected.connect(_on_shop_selected)
	_shop_tree.item_activated.connect(func(): _buy(1))  # double-click = buy 1
	left.add_child(_shop_tree)
	left.add_child(_lbl(tr("Double-click a row to buy one. Purchases come out of the board's transfer budget."),
		ThemeBuilder.COL_TEXT_DIM, 11))

	# ------ right: dossier + squad equipment
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	right.add_child(_section_title(tr("ITEM DOSSIER")))
	var dpanel := PanelContainer.new()
	dpanel.custom_minimum_size.y = 236
	right.add_child(dpanel)
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dpanel.add_child(dscroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 5)
	dscroll.add_child(_detail)

	right.add_child(_section_title(tr("SQUAD EQUIPMENT — WHO HOLDS WHAT")))
	_squad_tree = Tree.new()
	_squad_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_squad_tree.hide_root = true
	_squad_tree.select_mode = Tree.SELECT_ROW
	_squad_tree.columns = 4
	_squad_tree.set_column_titles_visible(true)
	var st := ["Pokémon", "Lv", "Type", tr("Held item")]
	var sw := [130, 40, 92, 150]
	for i in 4:
		_squad_tree.set_column_title(i, st[i])
		_squad_tree.set_column_expand(i, i == 0 or i == 3)
		_squad_tree.set_column_custom_minimum_width(i, sw[i])
		_squad_tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	_squad_tree.item_selected.connect(_on_squad_selected)
	right.add_child(_squad_tree)

	var eq_row := HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", 8)
	right.add_child(eq_row)
	_equip_btn = Button.new()
	_equip_btn.text = "Equip"
	# Fixed height: the neighbouring status text may wrap to several lines —
	# the buttons must never stretch with it.
	_equip_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_equip_btn.pressed.connect(_do_equip)
	eq_row.add_child(_equip_btn)
	_strip_btn = Button.new()
	_strip_btn.text = tr("Take item")
	_strip_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_strip_btn.pressed.connect(_do_strip)
	eq_row.add_child(_strip_btn)
	_use_btn = Button.new()
	_use_btn.text = tr("Use stone")
	_use_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_use_btn.visible = false
	_use_btn.pressed.connect(_do_use_stone)
	eq_row.add_child(_use_btn)
	_equip_hint = RichTextLabel.new()
	_equip_hint.bbcode_enabled = true
	_equip_hint.fit_content = true
	_equip_hint.scroll_active = false
	_equip_hint.add_theme_color_override("default_color", ThemeBuilder.COL_TEXT_DIM)
	_equip_hint.add_theme_font_size_override("normal_font_size", 11)
	_equip_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eq_row.add_child(_equip_hint)


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


# ================================================================== actions

func _on_shop_selected() -> void:
	var it := _shop_tree.get_selected()
	if it != null:
		_selected_item = str(it.get_metadata(0))
		_refresh_detail()
		_refresh_equip_row()


func _on_squad_selected() -> void:
	var it := _squad_tree.get_selected()
	if it != null:
		_selected_uid = str(it.get_metadata(0))
		_refresh_detail()
		_refresh_equip_row()


func _buy(qty: int) -> void:
	if _selected_item == "":
		return
	_err(GameState.buy_item(_selected_item, qty))


func _sell(qty: int) -> void:
	if _selected_item == "":
		return
	_err(GameState.sell_item(_selected_item, qty))


func _do_equip() -> void:
	if _selected_item == "" or _selected_uid == "":
		return
	_err(GameState.assign_held_item(_selected_uid, _selected_item))


func _do_strip() -> void:
	if _selected_uid == "":
		return
	_err(GameState.unassign_held_item(_selected_uid))


# ------------------------------------------------------- evolution stones

## Is this item an evolution stone/trigger (inert in battle, applied here)?
func _is_stone(it: Dictionary) -> bool:
	for e in it.get("effects", []):
		if str(e).begins_with("evolve:"):
			return true
	return false


## The evolution this stone unlocks for a given squad mon ({} = none).
func _stone_route(item_id: String, m: Dictionary) -> Dictionary:
	var svc: RefCounted = EvoSvc.instance
	if svc == null or m.is_empty() or item_id == "":
		return {}
	for o in svc.chain_of(int(m.get("species_id", 0))):
		if str(o.get("method", "")) == "stone" and str(o.get("stone", "")) == item_id:
			return o
	return {}


## Squad mons this stone would evolve right now.
func _stone_targets(item_id: String) -> Array:
	var out: Array = []
	for m in GameState.player_club()["squad"]:
		if not _stone_route(item_id, m).is_empty():
			out.append(m)
	return out


## Apply the selected stone to the selected mon — evolves it immediately
## (using the stone IS the manager's approval) and consumes one from stock.
func _do_use_stone() -> void:
	var svc: RefCounted = EvoSvc.instance
	if svc == null or _selected_item == "" or _selected_uid == "":
		return
	var m: Dictionary = GameState.squad_member(_selected_uid)
	var old_name := _display_name(m) if not m.is_empty() else "?"
	var err: String = str(svc.use_stone(_selected_uid, _selected_item))
	if err != "":
		_err(err)
		return
	_err(tr("%s evolved into %s! The %s was consumed.") % [old_name,
		str(GameState.squad_member(_selected_uid).get("species", "?")),
		I18n.item_name(_selected_item)])
	_refresh_all()


# ================================================================== refresh

func _refresh_all() -> void:
	if not is_inside_tree() or _shop_tree == null:
		return
	_refresh_header()
	_refresh_shop()
	_refresh_squad()
	_refresh_detail()
	_refresh_equip_row()


func _refresh_header() -> void:
	_clear(_header_stats)
	var pc: Dictionary = GameState.player_club()
	var inv: Dictionary = GameState.player_inventory()
	var stocked := 0
	var value := 0
	for iid in inv:
		stocked += int(inv[iid])
		value += int(inv[iid]) * int(DataStore.item(str(iid)).get("price", 0))
	var equipped := 0
	var eq_value := 0
	for m in pc["squad"]:
		var h: Variant = m.get("held_item")
		if h != null and str(h) != "":
			equipped += 1
			eq_value += int(DataStore.item(str(h)).get("price", 0))
	_header_stat(tr("Transfer budget"), _money(maxi(0, mini(int(pc["finances"]["balance"]),
		int(pc["finances"].get("transfer_budget", 0))))), ThemeBuilder.COL_GOOD)
	_header_stat(tr("Club balance"), _money(int(pc["finances"]["balance"])), ThemeBuilder.COL_TEXT_DIM)
	_header_stat(tr("Storeroom"), tr("%d items · %s") % [stocked, _money(value)])
	_header_stat(tr("Squad equipped"), "%d / %d" % [equipped, pc["squad"].size()],
		ThemeBuilder.COL_GOOD if equipped > 0 else ThemeBuilder.COL_TEXT_DIM)
	_header_stat(tr("Kit on backs"), _money(eq_value), ThemeBuilder.COL_TEXT_DIM)


func _refresh_shop() -> void:
	if _shop_tree == null:
		return
	var inv: Dictionary = GameState.player_inventory()
	_shop_tree.clear()
	var root := _shop_tree.create_item()
	var shown := 0
	for it in DataStore.items_list():
		var iid: String = str(it["id"])
		var owned := int(inv.get(iid, 0))
		if _class_filter == 1 and str(it["class"]) != "held":
			continue
		if _class_filter == 2 and (str(it["class"]) != "usable" or _is_stone(it)):
			continue
		if _class_filter == 3 and not _is_stone(it):
			continue
		if _rarity_filter > 0 and str(it["rarity"]) != RARITY_FILTERS[_rarity_filter].to_lower():
			continue
		if _stock_only and owned <= 0:
			continue
		if _search != "" and not I18n.item_name(iid).to_lower().contains(_search.to_lower()) \
				and not str(it["name"]).to_lower().contains(_search.to_lower()):
			continue
		shown += 1
		var row := _shop_tree.create_item(root)
		row.set_metadata(0, iid)
		row.set_text(0, I18n.item_name(iid))
		row.set_custom_color(0, Color.WHITE if owned > 0 else ThemeBuilder.COL_TEXT)
		row.set_text(1, CLASS_LABEL.get(str(it["class"]), "?"))
		row.set_custom_color(1, ThemeBuilder.COL_ACCENT if str(it["class"]) == "held" else ThemeBuilder.COL_WARN)
		row.set_text(2, str(it["rarity"]).capitalize())
		row.set_custom_color(2, RARITY_COLORS.get(str(it["rarity"]), ThemeBuilder.COL_TEXT))
		row.set_text(3, tr(str(it["desc"])))
		row.set_tooltip_text(3, tr(str(it["desc"])))
		row.set_custom_color(3, ThemeBuilder.COL_TEXT_DIM)
		row.set_text(4, _money(int(it["price"])))
		row.set_custom_color(4, ThemeBuilder.COL_TEXT)
		row.set_text(5, str(owned) if owned > 0 else "—")
		row.set_custom_color(5, ThemeBuilder.COL_GOOD if owned > 0 else ThemeBuilder.COL_TEXT_DIM)
		for c in [4, 5]:
			row.set_text_alignment(c, HORIZONTAL_ALIGNMENT_RIGHT)
		if iid == _selected_item:
			row.select(0)
	_count_label.text = tr("%d of %d items") % [shown, DataStore.items.size()]


func _refresh_squad() -> void:
	if _squad_tree == null:
		return
	_squad_tree.clear()
	var root := _squad_tree.create_item()
	var squad: Array = GameState.player_club()["squad"].duplicate()
	squad.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	for m in squad:
		var sp: Dictionary = DataStore.species(int(m["species_id"]))
		var row := _squad_tree.create_item(root)
		row.set_metadata(0, str(m["uid"]))
		row.set_text(0, _display_name(m))
		row.set_custom_color(0, Color.WHITE)
		row.set_text(1, str(int(m["level"])))
		row.set_custom_color(1, ThemeBuilder.COL_TEXT_DIM)
		var types_txt := " / ".join(sp["types"].map(func(x): return tr(str(x).capitalize())))
		row.set_text(2, types_txt)
		row.set_custom_color(2, DataStore.type_color(sp["types"][0]))
		var h: Variant = m.get("held_item")
		if h != null and str(h) != "":
			var it: Dictionary = DataStore.item(str(h))
			row.set_text(3, I18n.item_name(str(h)))
			row.set_custom_color(3, ThemeBuilder.COL_GOOD)
			row.set_tooltip_text(3, tr(str(it.get("desc", ""))))
		else:
			row.set_text(3, tr("— bare —"))
			row.set_custom_color(3, ThemeBuilder.COL_TEXT_DIM)
		if str(m["uid"]) == _selected_uid:
			row.select(0)


func _refresh_detail() -> void:
	if _detail == null:
		return
	_clear(_detail)
	var it: Dictionary = DataStore.item(_selected_item) if _selected_item != "" else {}
	if it.is_empty():
		_detail.add_child(_lbl(tr("Select an item from the catalog.\n\nHELD items work passively while a Pokémon carries them — equip below.\nUSABLE items go into the matchday bag: using one in battle costs that Pokémon's turn, exactly like the real thing."),
			ThemeBuilder.COL_TEXT_DIM, 13, true))
		return
	var inv: Dictionary = GameState.player_inventory()
	var owned := int(inv.get(_selected_item, 0))

	var toprow := HBoxContainer.new()
	toprow.add_theme_constant_override("separation", 8)
	_detail.add_child(toprow)
	toprow.add_child(_lbl(I18n.item_name(_selected_item), Color.WHITE, 19))
	toprow.add_child(_chip(CLASS_LABEL.get(str(it["class"]), "?"),
		ThemeBuilder.COL_ACCENT if str(it["class"]) == "held" else ThemeBuilder.COL_WARN))
	toprow.add_child(_chip(str(it["rarity"]).to_upper(),
		RARITY_COLORS.get(str(it["rarity"]), ThemeBuilder.COL_TEXT)))
	_detail.add_child(_lbl(tr(str(it["desc"])), ThemeBuilder.COL_TEXT, 13, true))
	_detail.add_child(_lbl(tr("Engine effects: %s") % ", ".join(it.get("effects", [])),
		ThemeBuilder.COL_TEXT_DIM, 11, true))
	_detail.add_child(HSeparator.new())
	_detail.add_child(_lbl(tr("Price %s   ·   sells back for %s   ·   in storeroom: %d") % [
		_money(int(it["price"])), _money(int(int(it["price"]) * 0.5)), owned],
		ThemeBuilder.COL_TEXT, 13))
	if str(it["class"]) == "held":
		var holders := _holders(_selected_item)
		if holders.is_empty():
			_detail.add_child(_lbl(tr("Currently held by: nobody in the squad."), ThemeBuilder.COL_TEXT_DIM, 12))
		else:
			_detail.add_child(_lbl(tr("Currently held by: %s") % ", ".join(
				holders.map(func(m): return tr("%s (Lv %d)") % [_display_name(m), int(m["level"])])),
				ThemeBuilder.COL_GOOD, 12, true))
	elif _is_stone(it):
		var targets := _stone_targets(_selected_item)
		if targets.is_empty():
			_detail.add_child(_lbl(tr("Evolution stone — applied from the storeroom, never in battle. Nobody in the current squad evolves with it."),
				ThemeBuilder.COL_TEXT_DIM, 12, true))
		else:
			var lines: Array = []
			for m in targets:
				var route := _stone_route(_selected_item, m)
				lines.append(tr("%s (Lv %d) evolves into %s") % [_display_name(m), int(m["level"]),
					str(DataStore.species(int(route["to"])).get("name", "?"))])
			_detail.add_child(_lbl(tr("Would evolve: %s") % ", ".join(PackedStringArray(lines)),
				ThemeBuilder.COL_GOOD, 12, true))
			_detail.add_child(_lbl(tr("Pick the Pokémon below and press Use — evolution is immediate and permanent; using the stone is the approval."),
				ThemeBuilder.COL_TEXT_DIM, 11, true))
	else:
		_detail.add_child(_lbl(tr("Usable items are consumed as a battle turn — the engine exposes them as \"use_item\" actions from your matchday bag."),
			ThemeBuilder.COL_TEXT_DIM, 11, true))

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	_detail.add_child(btns)
	var fin: Dictionary = GameState.player_club()["finances"]
	var bal := mini(int(fin["balance"]), int(fin.get("transfer_budget", 0)))
	var b1 := Button.new()
	b1.text = tr("Buy 1  (%s)") % _money(int(it["price"]))
	b1.disabled = bal < int(it["price"])
	b1.pressed.connect(func(): _buy(1))
	btns.add_child(b1)
	var b5 := Button.new()
	b5.text = tr("Buy 5")
	b5.disabled = bal < int(it["price"]) * 5
	b5.pressed.connect(func(): _buy(5))
	btns.add_child(b5)
	var bs := Button.new()
	bs.text = tr("Sell 1")
	bs.disabled = owned <= 0
	bs.pressed.connect(func(): _sell(1))
	btns.add_child(bs)


func _refresh_equip_row() -> void:
	if _equip_btn == null:
		return
	var it: Dictionary = DataStore.item(_selected_item) if _selected_item != "" else {}
	var m: Dictionary = GameState.squad_member(_selected_uid) if _selected_uid != "" else {}
	var owned := int(GameState.player_inventory().get(_selected_item, 0))
	var is_held: bool = not it.is_empty() and str(it["class"]) == "held"
	_equip_btn.disabled = not (is_held and owned > 0 and not m.is_empty())
	var iname := I18n.item_name(_selected_item) if not it.is_empty() else ""
	_equip_btn.text = I18n.t("Equip %s") % iname if is_held else "Equip"
	var cur: Variant = m.get("held_item") if not m.is_empty() else null
	_strip_btn.disabled = m.is_empty() or cur == null or str(cur) == ""
	# evolution stones: the Use path (apply from storeroom -> evolves NOW)
	var is_stone := not it.is_empty() and _is_stone(it)
	var route: Dictionary = _stone_route(_selected_item, m) if is_stone else {}
	_use_btn.visible = is_stone
	_use_btn.disabled = route.is_empty() or owned <= 0
	_use_btn.text = I18n.t("Use %s") % iname if is_stone else "Use stone"
	if is_stone:
		if m.is_empty():
			_equip_hint.text = I18n.t("Pick a Pokémon below to apply the %s — stones evolve certain species instantly (never used in battle).") % iname
		elif route.is_empty():
			_equip_hint.text = I18n.t("The %s has no effect on %s.") % [iname, _display_name(m)]
		elif owned <= 0:
			_equip_hint.text = tr("%s would evolve into %s — buy a %s first.") % [_display_name(m),
				str(DataStore.species(int(route["to"])).get("name", "?")), iname]
		else:
			_equip_hint.text = tr("%s evolves %s into %s. Permanent — using the stone is the approval.") % \
				[iname, _display_name(m),
				str(DataStore.species(int(route["to"])).get("name", "?"))]
		return
	if m.is_empty():
		_equip_hint.text = tr("Pick an item above and a Pokémon here, then Equip. Swapping returns the old item to the storeroom.")
	elif is_held and owned > 0:
		# "Item -> Mon": the arrow is drawn (bundled web font has no arrow glyph).
		_equip_hint.text = "%s %s %s%s" % [iname, ARROW_IMG, _display_name(m),
			(tr("  (replaces %s)") % I18n.item_name(str(cur))) if cur != null and str(cur) != "" else ""]
	elif is_held and owned <= 0:
		_equip_hint.text = I18n.t("No %s in the storeroom — buy one first.") % iname
	elif cur != null and str(cur) != "":
		_equip_hint.text = I18n.t("%s is holding %s.") % [_display_name(m), I18n.item_name(str(cur))]
	else:
		_equip_hint.text = tr("%s is not holding anything.") % _display_name(m)
