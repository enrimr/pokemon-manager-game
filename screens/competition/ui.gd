extends RefCounted
## Competition piece: shared UI helpers (colors, monograms, panels, form pips)
## plus the FM-style entity hyperlink system: every club / Pokémon / fixture
## reference on the competition screen is a live link that drills through to a
## profile (see screen.gd `comp_navigate` and profiles.gd).

const TB := preload("res://shared/theme/theme_builder.gd")


## Flat, underline-on-hover hyperlink button (FM entity link affordance).
class Link:
	extends Button
	var link_color: Color = Color.WHITE

	func _init(txt: String, font_size: int, col: Color) -> void:
		text = txt
		link_color = col
		focus_mode = Control.FOCUS_NONE
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_theme_font_size_override("font_size", font_size)
		add_theme_color_override("font_color", col)
		add_theme_color_override("font_hover_color", col.lightened(0.3))
		add_theme_color_override("font_pressed_color", col.lightened(0.3))
		add_theme_color_override("font_hover_pressed_color", col.lightened(0.3))
		add_theme_color_override("font_focus_color", col)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		if not is_hovered():
			return
		var f := get_theme_font("font")
		var fs := get_theme_font_size("font_size")
		var w: float = minf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, size.x)
		var x0 := 0.0
		match alignment:
			HORIZONTAL_ALIGNMENT_CENTER: x0 = (size.x - w) / 2.0
			HORIZONTAL_ALIGNMENT_RIGHT: x0 = size.x - w
		var y := size.y - 2.0
		draw_line(Vector2(x0, y), Vector2(x0 + w, y), link_color.lightened(0.3), 1.0)


## Route an entity context to the competition screen's navigator.
## ctx: {"kind": "club"|"pokemon"|"fixture"|"tab", "id": ...}
static func navigate(from: Node, ctx: Dictionary) -> void:
	var n := from
	while n != null:
		if n.has_method("comp_navigate"):
			n.call("comp_navigate", ctx)
			return
		n = n.get_parent()


## Hyperlink label that navigates to `ctx` when clicked.
static func link(text: String, font_size: int, col: Color, ctx: Dictionary,
		tooltip: String = "") -> Button:
	var b := Link.new(text, font_size, col)
	b.tooltip_text = tooltip if tooltip != "" else _default_tooltip(ctx)
	b.pressed.connect(func(): navigate(b, ctx))
	return b


static func club_link(club: Dictionary, font_size: int = 13,
		col: Color = TB.COL_TEXT) -> Button:
	var cid: String = str(club.get("id", ""))
	return link(str(club.get("name", cid)), font_size, col, {"kind": "club", "id": cid})


static func _default_tooltip(ctx: Dictionary) -> String:
	match str(ctx.get("kind", "")):
		"club": return "Go to club profile"
		"pokemon": return "Go to Pokémon profile"
		"fixture": return "Go to match report"
	return ""


## Make a Tree navigable: cells carrying {"kind","id"} metadata become links
## (left-click follows them; pointer cursor + tooltip signal the affordance).
static func wire_tree_links(tree: Tree) -> void:
	tree.item_mouse_selected.connect(func(pos: Vector2, btn_index: int):
		if btn_index != MOUSE_BUTTON_LEFT:
			return
		var item := tree.get_item_at_position(pos)
		var col := tree.get_column_at_position(pos)
		if item == null or col < 0:
			return
		var md: Variant = item.get_metadata(col)
		if md is Dictionary and md.has("kind"):
			navigate(tree, md))
	tree.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseMotion:
			var item := tree.get_item_at_position(ev.position)
			var col := tree.get_column_at_position(ev.position)
			var is_link: bool = item != null and col >= 0 and item.get_metadata(col) is Dictionary
			tree.mouse_default_cursor_shape = \
				Control.CURSOR_POINTING_HAND if is_link else Control.CURSOR_ARROW)


## Mark one Tree cell as a link to ctx (metadata consumed by wire_tree_links).
static func cell_link(item: TreeItem, col: int, ctx: Dictionary, tooltip: String = "") -> void:
	item.set_metadata(col, ctx)
	item.set_tooltip_text(col, tooltip if tooltip != "" else _default_tooltip(ctx))


## Owning club of a squad member uid ({} if not in any club squad).
static func club_of_uid(uid: String) -> Dictionary:
	for c in GameState.world["clubs"]:
		for inst in c["squad"]:
			if str(inst["uid"]) == uid:
				return c
	return {}


## Squad instance for a uid, searching club squads, free agents and prospects.
static func find_instance(uid: String) -> Dictionary:
	for c in GameState.world["clubs"]:
		for inst in c["squad"]:
			if str(inst["uid"]) == uid:
				return inst
	for inst in GameState.free_agents():
		if str(inst["uid"]) == uid:
			return inst
	for inst in GameState.prospects():
		if str(inst["uid"]) == uid:
			return inst
	return {}


static func display_name(inst: Dictionary) -> String:
	var nick: Variant = inst.get("nickname")
	if nick != null and str(nick) != "":
		return str(nick)
	return str(inst.get("species", "?"))


## Small type-colored chip ("WATER", "PSYCHIC"...) for Pokémon profiles.
static func type_chip(type_name: String) -> Control:
	var col: Color = DataStore.type_color(type_name)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.2)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = type_name.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", col.lightened(0.3))
	p.add_child(l)
	return p

const COL_WIN := Color("57c979")
const COL_LOSS := Color("e06060")
const COL_TITLE_ZONE := Color(0.83, 0.68, 0.21, 0.16)     # champions gold tint
const COL_PROMO_ZONE := Color(0.34, 0.79, 0.47, 0.10)     # continental green tint
const COL_RELEG_ZONE := Color(0.88, 0.38, 0.38, 0.10)     # relegation red tint
const COL_PLAYER_ROW := Color(0.48, 0.42, 1.0, 0.16)

static var _club_colors: Dictionary = {}
static var _badge_cache: Dictionary = {}


## Club identity color = dominant primary type across its squad.
static func club_color(club: Dictionary) -> Color:
	var id: String = club.get("id", "")
	if _club_colors.has(id):
		return _club_colors[id]
	var counts := {}
	for inst in club.get("squad", []):
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		if sp.is_empty():
			continue
		var t: String = sp["types"][0]
		counts[t] = int(counts.get(t, 0)) + 1
	var best := ""
	var best_n := -1
	for t in counts:
		if counts[t] > best_n:
			best_n = counts[t]
			best = t
	var col: Color = DataStore.type_color(best) if best != "" else TB.COL_ACCENT
	_club_colors[id] = col
	return col


## Small square swatch texture in the club color (used as Tree row icon).
static func badge_texture(color: Color, size: int = 12) -> ImageTexture:
	var key := "%s|%d" % [color.to_html(), size]
	if _badge_cache.has(key):
		return _badge_cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in size:
			var edge: bool = x == 0 or y == 0 or x == size - 1 or y == size - 1
			img.set_pixel(x, y, color.darkened(0.35) if edge else color)
	var tex := ImageTexture.create_from_image(img)
	_badge_cache[key] = tex
	return tex


## Type-colored monogram panel with the club's initials (no copyrighted art).
static func monogram(club: Dictionary, size: int = 26, font_size: int = 11) -> Control:
	var col := club_color(club)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.22)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	var short: String = str(club.get("short", "??"))
	l.text = short.substr(0, 3)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col.lightened(0.35))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Titled FM-style card. Returns the PanelContainer; body VBox is metadata "body".
static func card(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TB.COL_PANEL
	sb.border_color = TB.COL_BORDER
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	if title != "":
		var t := Label.new()
		t.text = title.to_upper()
		t.add_theme_font_size_override("font_size", 11)
		t.add_theme_color_override("font_color", TB.COL_TEXT_DIM)
		v.add_child(t)
		var sep := HSeparator.new()
		sep.add_theme_color_override("separator", TB.COL_BORDER)
		v.add_child(sep)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	p.set_meta("body", body)
	return p


static func card_body(p: PanelContainer) -> VBoxContainer:
	return p.get_meta("body")


static func label(text: String, size: int = 14, color: Color = TB.COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func dim(text: String, size: int = 12) -> Label:
	return label(text, size, TB.COL_TEXT_DIM)


## Key/value row for overview cards.
static func kv_row(key: String, value: String, val_color: Color = TB.COL_TEXT) -> HBoxContainer:
	var h := HBoxContainer.new()
	var k := dim(key, 12)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	var v := label(value, 13, val_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


## Key/value row whose value is an entity hyperlink.
static func kv_link_row(key: String, value: String, ctx: Dictionary,
		val_color: Color = TB.COL_TEXT) -> HBoxContainer:
	var h := HBoxContainer.new()
	var k := dim(key, 12)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	var v := link(value, 13, val_color, ctx)
	v.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


## Row of W/L form pips, oldest -> newest.
static func form_pips(form: Array, pip: int = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	for r in form:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(pip, pip)
		var sb := StyleBoxFlat.new()
		var col: Color = COL_WIN if r == "W" else COL_LOSS
		sb.bg_color = Color(col.r, col.g, col.b, 0.24)
		sb.border_color = col
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		p.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = str(r)
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", col.lightened(0.3))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
		h.add_child(p)
	return h


static func vspace(px: int = 6) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	return c


## "12 Sep" short date.
static func short_date(date_str: String) -> String:
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var parts := date_str.split("-")
	return "%d %s" % [int(parts[2]), months[int(parts[1]) - 1]]


static func weekday(date_str: String) -> String:
	var parts := date_str.split("-")
	var dict := {"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 12, "minute": 0, "second": 0}
	var unix := Time.get_unix_time_from_datetime_dict(dict)
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var names := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	return names[int(d["weekday"])]
