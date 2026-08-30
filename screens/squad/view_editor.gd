extends RefCounted
## Squad piece: the FM-style column/view editor dialog.
## Add / remove / reorder columns, save the layout onto the current view
## (presets become overridden starting points), Save As a new custom view,
## rename or delete custom views, reset presets. All persistence goes through
## views.gd (inside the career save).

const UI := preload("res://screens/squad/ui_helpers.gd")
const Views := preload("res://screens/squad/views.gd")


## Open the editor for `view_name`. `on_saved(view_name)` runs after any
## change that the squad screen must reflect (saved layout, new view, rename,
## delete, reset) with the name of the view to display afterwards.
static func open(host: Control, view_name: String, on_saved: Callable) -> AcceptDialog:
	var d := AcceptDialog.new()
	d.title = "Customize View — %s" % view_name
	d.min_size = Vector2i(720, 520)
	d.dialog_hide_on_ok = false   # stay up when validation fails
	d.get_ok_button().text = "Save & Apply"
	d.add_cancel_button("Cancel")
	host.add_child(d)
	d.close_requested.connect(d.queue_free)
	d.canceled.connect(d.queue_free)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	d.add_child(body)

	var cols: Array = Views.columns(view_name)   # working copy (already a copy)
	var is_preset := Views.is_preset(view_name)

	# --- header: what is being edited + name field
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)
	var kind := Label.new()
	kind.text = ("Preset view — edits are saved as your override; Reset restores the factory layout."
		if is_preset else "Custom view — yours to shape, rename or delete.")
	kind.add_theme_font_size_override("font_size", 12)
	kind.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(kind)
	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	name_lbl.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	head.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.text = view_name
	name_edit.max_length = Views.MAX_NAME
	name_edit.custom_minimum_size = Vector2(180, 0)
	name_edit.tooltip_text = ("Preset names are fixed — type a new name and use Save As New View."
		if is_preset else "Rename this view (applied on Save) or type a new name for Save As.")
	head.add_child(name_edit)

	# --- dual lists
	var lists := HBoxContainer.new()
	lists.add_theme_constant_override("separation", 10)
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(lists)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists.add_child(left)
	var avail_lbl := Label.new()
	avail_lbl.text = "AVAILABLE COLUMNS"
	avail_lbl.add_theme_font_size_override("font_size", 11)
	avail_lbl.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	left.add_child(avail_lbl)
	var search := LineEdit.new()
	search.placeholder_text = "Search columns..."
	left.add_child(search)
	var avail := ItemList.new()
	avail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avail.allow_reselect = true
	left.add_child(avail)

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	lists.add_child(mid)
	var add_b := Button.new()
	add_b.text = "Add  >"
	add_b.tooltip_text = "Add the selected column to this view (or double-click it)"
	mid.add_child(add_b)
	var rem_b := Button.new()
	rem_b.text = "<  Remove"
	rem_b.tooltip_text = "Remove the selected column (Name always stays)"
	mid.add_child(rem_b)
	var mid_sp := Control.new()
	mid_sp.custom_minimum_size = Vector2(0, 12)
	mid.add_child(mid_sp)
	var up_b := Button.new()
	up_b.text = "Move Up"
	mid.add_child(up_b)
	var down_b := Button.new()
	down_b.text = "Move Down"
	mid.add_child(down_b)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists.add_child(right)
	var cur_lbl := Label.new()
	cur_lbl.text = "THIS VIEW, LEFT TO RIGHT"
	cur_lbl.add_theme_font_size_override("font_size", 11)
	cur_lbl.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	right.add_child(cur_lbl)
	var cur := ItemList.new()
	cur.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cur.allow_reselect = true
	right.add_child(cur)
	var cur_note := Label.new()
	cur_note.add_theme_font_size_override("font_size", 11)
	cur_note.add_theme_color_override("font_color", UI.COL_TEXT_DIM)
	right.add_child(cur_note)

	# --- bottom row: destructive/secondary actions
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	body.add_child(foot)
	var reset_b := Button.new()
	reset_b.text = "Reset To Default"
	reset_b.visible = is_preset
	reset_b.tooltip_text = "Restore this preset's factory columns (drops your override)."
	foot.add_child(reset_b)
	var del_b := Button.new()
	del_b.text = "Delete View"
	del_b.visible = not is_preset
	del_b.add_theme_color_override("font_color", UI.COL_BAD)
	foot.add_child(del_b)
	var err_lbl := Label.new()
	err_lbl.add_theme_font_size_override("font_size", 12)
	err_lbl.add_theme_color_override("font_color", UI.COL_WARN)
	err_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	err_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(err_lbl)
	var saveas_b := Button.new()
	saveas_b.text = "Save As New View"
	saveas_b.tooltip_text = "Save this layout as a brand-new view under the name typed above."
	foot.add_child(saveas_b)

	# --- list plumbing
	var refresh_lists := func() -> void:
		var q := search.text.strip_edges().to_lower()
		avail.clear()
		for cat in Views.CATS:
			var ids: Array = []
			for id in Views.COLS:
				var def: Dictionary = Views.COLS[id]
				if str(def["cat"]) != cat or cols.has(id):
					continue
				if q != "" and not (str(def["title"]).to_lower().contains(q)
						or str(def["desc"]).to_lower().contains(q)):
					continue
				ids.append(id)
			if ids.is_empty():
				continue
			var h := avail.add_item(cat.to_upper(), null, false)
			avail.set_item_disabled(h, true)
			avail.set_item_custom_fg_color(h, UI.COL_TEXT_DIM)
			for id in ids:
				var def2: Dictionary = Views.COLS[id]
				var i := avail.add_item("  " + str(def2["title"]))
				avail.set_item_metadata(i, id)
				avail.set_item_tooltip(i, str(def2["desc"]))
		var keep_sel := cur.get_selected_items()
		cur.clear()
		for ci in cols.size():
			var id2: String = cols[ci]
			var def3: Dictionary = Views.col_def(id2)
			var i2 := cur.add_item("%d.  %s" % [ci + 1, def3["title"]])
			cur.set_item_metadata(i2, id2)
			cur.set_item_tooltip(i2, str(def3["desc"]))
			if id2 == Views.LOCKED_COL:
				cur.set_item_custom_fg_color(i2, UI.COL_TEXT_DIM)
				cur.set_item_tooltip(i2, "Name is part of every view.")
		if not keep_sel.is_empty() and keep_sel[0] < cur.item_count:
			cur.select(keep_sel[0])
		cur_note.text = "%d of %d columns (min %d)" % [cols.size(), Views.MAX_COLS, Views.MIN_COLS]
		err_lbl.text = ""

	var add_sel := func() -> void:
		for i in avail.get_selected_items():
			var id: Variant = avail.get_item_metadata(i)
			if id != null and not cols.has(str(id)) and cols.size() < Views.MAX_COLS:
				cols.append(str(id))
		refresh_lists.call()

	var remove_sel := func() -> void:
		for i in cur.get_selected_items():
			var id: Variant = cur.get_item_metadata(i)
			if id != null and str(id) != Views.LOCKED_COL:
				cols.erase(str(id))
		refresh_lists.call()

	var move_sel := func(delta: int) -> void:
		var sel := cur.get_selected_items()
		if sel.is_empty():
			return
		var i: int = sel[0]
		var j := i + delta
		if j < 0 or j >= cols.size():
			return
		var tmp: String = cols[i]
		cols[i] = cols[j]
		cols[j] = tmp
		refresh_lists.call()
		cur.select(j)

	search.text_changed.connect(func(_t: String) -> void: refresh_lists.call())
	add_b.pressed.connect(add_sel)
	rem_b.pressed.connect(remove_sel)
	up_b.pressed.connect(func() -> void: move_sel.call(-1))
	down_b.pressed.connect(func() -> void: move_sel.call(1))
	avail.item_activated.connect(func(_i: int) -> void: add_sel.call())
	cur.item_activated.connect(func(_i: int) -> void: remove_sel.call())

	# --- save paths
	var finish := func(shown_view: String) -> void:
		if on_saved.is_valid():
			on_saved.call(shown_view)
		d.hide()
		d.queue_free()

	d.confirmed.connect(func() -> void:
		var target := view_name
		var typed := name_edit.text.strip_edges()
		if not Views.is_preset(view_name) and typed != view_name:
			var rerr := Views.rename(view_name, typed)
			if rerr != "":
				err_lbl.text = rerr
				return
			target = typed
		var err := Views.save_columns(target, cols)
		if err != "":
			err_lbl.text = err
			return
		finish.call(target))

	saveas_b.pressed.connect(func() -> void:
		var typed := name_edit.text.strip_edges()
		if typed == view_name:
			err_lbl.text = "Type a new name above, then Save As New View."
			return
		var err := Views.create(typed, cols)
		if err != "":
			err_lbl.text = err
			return
		finish.call(typed))

	reset_b.pressed.connect(func() -> void:
		Views.reset(view_name)
		cols = Views.columns(view_name)
		refresh_lists.call()
		finish.call(view_name))

	del_b.pressed.connect(func() -> void:
		var err := Views.delete_view(view_name)
		if err != "":
			err_lbl.text = err
			return
		finish.call("General"))

	refresh_lists.call()
	d.popup_centered()
	return d
