class_name MUI
extends Object
## Shared UI helpers for the mobile-first portrait shell (mobile piece).
## Design width is ~440 units (Settings picks the stretch factor so a phone
## in portrait shows exactly that); everything here sizes for touch.

const COL_BG := Color("11141d")
const ROW_H := 52.0          # minimum touch row height

static var _bold: Font = null
static var _bolder: Font = null


static func bold() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
		f.font_weight = 700
		_bold = f
	return _bold


static func label(text: String, size: int = 14, col: Color = ThemeBuilder.COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func dim(text: String, size: int = 12) -> Label:
	return label(text, size, ThemeBuilder.COL_TEXT_DIM)


static func title(text: String, size: int = 16) -> Label:
	var l := label(text, size, Color.WHITE)
	l.add_theme_font_override("font", bold())
	return l


static func vgap(px: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	return c


static func hspacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func hline() -> Control:
	var line := ColorRect.new()
	line.color = ThemeBuilder.COL_BORDER
	line.custom_minimum_size.y = 1
	return line


## Card panel — the mobile building block.
static func card() -> Array:   # [PanelContainer, VBoxContainer]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_BORDER, 6, 12, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return [p, v]


## Touch-sized action button.
static func button(text: String, col: Color = ThemeBuilder.COL_ACCENT_DIM,
		border: Color = ThemeBuilder.COL_ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", bold())
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color("f2f4fb"))
	b.add_theme_stylebox_override("normal", ThemeBuilder._flat(col, border, 6, 12, 8))
	b.add_theme_stylebox_override("hover", ThemeBuilder._flat(border, border, 6, 12, 8))
	b.add_theme_stylebox_override("pressed", ThemeBuilder._flat(border.lightened(0.15), border, 6, 12, 8))
	return b


## Full-width tappable list row (content added by the caller).
static func row(on_tap: Callable = Callable()) -> Array:   # [Button, HBoxContainer]
	var b := Button.new()
	b.custom_minimum_size.y = ROW_H
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_BORDER, 5, 10, 6))
	b.add_theme_stylebox_override("hover",
		ThemeBuilder._flat(Color("232941"), ThemeBuilder.COL_BORDER, 5, 10, 6))
	b.add_theme_stylebox_override("pressed",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT_DIM, ThemeBuilder.COL_ACCENT, 5, 10, 6))
	if not on_tap.is_null():
		b.pressed.connect(on_tap)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	return [b, h]


## Small type chip, matching the desktop type pills.
static func type_chip(t: String) -> Control:
	var p := PanelContainer.new()
	var col: Color = DataStore.type_color(t)
	p.add_theme_stylebox_override("panel", ThemeBuilder._flat(col.darkened(0.35), col, 4, 6, 2))
	var l := label(I18n.t(t.capitalize()).to_upper(), 9, Color("f0f2fa"))
	l.add_theme_font_override("font", bold())
	p.add_child(l)
	return p


## Scrollable page container: [ScrollContainer, VBoxContainer]
static func page() -> Array:
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return [sc, v]
