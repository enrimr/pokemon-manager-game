extends VBoxContainer
## Mobile Items (mobile piece): the bag + the league store, phone-shaped.
## Buy with the transfer budget, equip held items onto the squad (swaps go
## back to stock), pop evolution stones on eligible battlers — all the same
## GameState/EvolutionService calls the desktop Items screen makes.

const EvoSvc := preload("res://shared/sim/services/evolution.gd")

var _mode := ""          # "" | "equip" | "use"
var _item := ""          # the item being equipped/used


func _init() -> void:
	add_theme_constant_override("separation", 6)


func go_root() -> void:
	_mode = ""
	_item = ""
	refresh()


func refresh() -> void:
	for c in get_children():
		c.queue_free()

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	var back := MUI.button("‹ " + tr("More"), Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(func():
		if _mode != "":
			go_root()
		else:
			_shell().call("open_tab", "more"))
	head.add_child(back)
	head.add_child(MUI.hspacer())
	var fin: Dictionary = GameState.player_club()["finances"]
	var bud := MUI.dim(tr("Budget %s%s") % [str(GameState.world["meta"].get("currency", "P$")),
		I18n.number(mini(int(fin["balance"]), int(fin.get("transfer_budget", 0))))], 11)
	bud.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bud)

	if _mode != "":
		_build_target_picker()
		return

	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]

	# ---- the bag
	var inv: Dictionary = GameState.player_inventory()
	var bagc := MUI.card()
	v.add_child(bagc[0])
	var bagv: VBoxContainer = bagc[1]
	bagv.add_child(MUI.dim(tr("THE BAG").to_upper(), 10))
	if inv.is_empty():
		bagv.add_child(MUI.dim(tr("Empty. The store below restocks it."), 11))
	var inv_ids: Array = inv.keys()
	inv_ids.sort()
	for iid_v in inv_ids:
		var iid := str(iid_v)
		var it: Dictionary = DataStore.item(iid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		bagv.add_child(row)
		var nm := MUI.label("%s ×%d" % [I18n.item_name(iid), int(inv[iid])], 13, Color.WHITE)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.tooltip_text = I18n.item_desc(iid)
		row.add_child(nm)
		if str(it.get("class", "")) == "held":
			row.add_child(_mini_btn(tr("Equip…"), func():
				_mode = "equip"
				_item = iid
				refresh()))
		elif _is_stone(it):
			row.add_child(_mini_btn(tr("Use…"), func():
				_mode = "use"
				_item = iid
				refresh()))
		else:
			var hint := MUI.dim(tr("battle bag"), 10)
			hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(hint)

	# ---- the store, grouped like the games' marts
	var groups := [
		[tr("EVOLUTION STONES & TRIGGERS"), func(it): return _is_stone(it)],
		[tr("HELD ITEMS"), func(it): return str(it.get("class", "")) == "held"],
		[tr("BATTLE CONSUMABLES"), func(it): return str(it.get("class", "")) == "usable" and not _is_stone(it)],
	]
	for g in groups:
		var sc := MUI.card()
		v.add_child(sc[0])
		var sv: VBoxContainer = sc[1]
		sv.add_child(MUI.dim(str(g[0]), 10))
		var ids: Array = DataStore.items.keys()
		ids.sort_custom(func(a, b): return int(DataStore.items[a]["price"]) < int(DataStore.items[b]["price"]))
		for iid_v in ids:
			var iid := str(iid_v)
			var it: Dictionary = DataStore.items[iid]
			if not (g[1] as Callable).call(it):
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			sv.add_child(row)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", 0)
			col.add_child(MUI.label(I18n.item_name(iid), 12, Color.WHITE))
			var d := MUI.dim(I18n.item_desc(iid), 9)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(d)
			row.add_child(col)
			var buy := _mini_btn("%s%s" % [str(GameState.world["meta"].get("currency", "P$")),
				I18n.number(int(it["price"]))], func():
				var err := str(GameState.buy_item(iid))
				_shell().call("toast", err if err != "" else tr("%s added to the bag.") % I18n.item_name(iid))
				refresh())
			row.add_child(buy)


## Equip/use target picker: the squad, with what each battler holds.
func _build_target_picker() -> void:
	var title := MUI.title(tr("Equip %s on…") % I18n.item_name(_item) if _mode == "equip"
		else tr("Use %s on…") % I18n.item_name(_item), 15)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	var pg := MUI.page()
	pg[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pg[0])
	var v: VBoxContainer = pg[1]
	v.add_theme_constant_override("separation", 4)
	for inst in GameState.player_club().get("squad", []):
		var uid := str(inst.get("uid", ""))
		var r := MUI.row(func():
			var err := ""
			if _mode == "equip":
				err = str(GameState.assign_held_item(uid, _item))
			else:
				var svc: RefCounted = EvoSvc.instance
				err = str(svc.use_stone(uid, _item)) if svc != null else tr("Service unavailable.")
			_shell().call("toast", err if err != "" else tr("Done!"))
			GameState.save_game()
			go_root())
		var h: HBoxContainer = r[1]
		h.add_child(PokeArt.icon(int(inst.get("species_id", 0)), 34))
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.alignment = BoxContainer.ALIGNMENT_CENTER
		mid.add_theme_constant_override("separation", 0)
		mid.add_child(MUI.label(str(inst.get("species", "?")), 13, Color.WHITE))
		var held: Variant = inst.get("held_item")
		mid.add_child(MUI.dim(tr("holds %s") % I18n.item_name(str(held)) if held != null and str(held) != ""
			else tr("holds nothing"), 10))
		h.add_child(mid)
		if _mode == "equip" and held != null and str(held) != "":
			h.add_child(_mini_btn(tr("Unequip"), func():
				GameState.unassign_held_item(uid)
				GameState.save_game()
				refresh()))
		v.add_child(r[0])


static func _is_stone(it: Dictionary) -> bool:
	for fx in it.get("effects", []):
		if str(fx).begins_with("evolve:"):
			return true
	return false


func _mini_btn(text: String, cb: Callable) -> Button:
	var b := MUI.button(text, Color(ThemeBuilder.COL_PANEL_ALT, 1.0), ThemeBuilder.COL_BORDER)
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b


func _shell() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("open_tab"):
		n = n.get_parent()
	return n
