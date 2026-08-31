class_name ThemeBuilder
extends RefCounted
## Builds the Football-Manager-style dark theme programmatically.
## Applied once by the shell (res://shell/main.gd) on its root Control;
## every screen instanced under the shell inherits it. Screens must NOT
## override the theme wholesale — add theme_override_* per node if needed.

const COL_BG := Color("11141d")          # window background (near-black navy)
const COL_PANEL := Color("1a1f2e")       # panel / card background
const COL_PANEL_ALT := Color("222840")   # raised panel, table header
const COL_BORDER := Color("2e3550")      # subtle borders
const COL_ACCENT := Color("7b6cff")      # purple-blue accent (FM-like)
const COL_ACCENT_DIM := Color("4c4494")
const COL_TEXT := Color("d6dae6")
const COL_TEXT_DIM := Color("8b91a8")
const COL_GOOD := Color("57c979")
const COL_BAD := Color("e06060")
const COL_WARN := Color("e0b050")


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14

	# --- Panels
	t.set_stylebox("panel", "Panel", _flat(COL_PANEL, COL_BORDER))
	t.set_stylebox("panel", "PanelContainer", _flat(COL_PANEL, COL_BORDER))

	# --- Labels
	t.set_color("font_color", "Label", COL_TEXT)

	# --- Buttons
	var btn := _flat(COL_PANEL_ALT, COL_BORDER, 4, 8, 5)
	var btn_hover := _flat(Color("2a3150"), COL_ACCENT_DIM, 4, 8, 5)
	var btn_pressed := _flat(COL_ACCENT_DIM, COL_ACCENT, 4, 8, 5)
	var btn_disabled := _flat(Color("161a26"), Color("232840"), 4, 8, 5)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_stylebox("focus", "Button", _empty())
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", COL_TEXT_DIM)

	# --- Tree (data tables)
	t.set_stylebox("panel", "Tree", _flat(COL_PANEL, COL_BORDER, 0, 4, 4))
	t.set_color("font_color", "Tree", COL_TEXT)
	t.set_color("title_button_color", "Tree", COL_TEXT_DIM)
	t.set_stylebox("title_button_normal", "Tree", _flat(COL_PANEL_ALT, COL_BORDER, 0, 6, 3))
	t.set_stylebox("title_button_hover", "Tree", _flat(Color("2a3150"), COL_BORDER, 0, 6, 3))
	t.set_stylebox("title_button_pressed", "Tree", _flat(COL_ACCENT_DIM, COL_BORDER, 0, 6, 3))
	t.set_stylebox("selected", "Tree", _flat(COL_ACCENT_DIM, COL_ACCENT_DIM, 0, 2, 1))
	t.set_stylebox("selected_focus", "Tree", _flat(COL_ACCENT_DIM, COL_ACCENT_DIM, 0, 2, 1))
	t.set_color("guide_color", "Tree", Color(COL_BORDER, 0.6))
	t.set_constant("v_separation", "Tree", 6)

	# --- ItemList
	t.set_stylebox("panel", "ItemList", _flat(COL_PANEL, COL_BORDER))
	t.set_color("font_color", "ItemList", COL_TEXT)
	t.set_stylebox("selected", "ItemList", _flat(COL_ACCENT_DIM, COL_ACCENT_DIM, 3, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", _flat(COL_ACCENT_DIM, COL_ACCENT_DIM, 3, 4, 2))

	# --- LineEdit
	t.set_stylebox("normal", "LineEdit", _flat(COL_BG, COL_BORDER, 4, 8, 4))
	t.set_stylebox("focus", "LineEdit", _flat(COL_BG, COL_ACCENT, 4, 8, 4))
	t.set_color("font_color", "LineEdit", COL_TEXT)

	# --- ProgressBar
	t.set_stylebox("background", "ProgressBar", _flat(COL_BG, COL_BORDER, 3, 2, 2))
	t.set_stylebox("fill", "ProgressBar", _flat(COL_ACCENT, COL_ACCENT, 3, 2, 2))

	# --- ScrollContainer / VScrollBar
	# NOTE: a scrollbar's on-screen thickness comes from these styleboxes'
	# content margins. With 0-margin styles the bar renders ~0 px wide —
	# still wheel-scrollable but INVISIBLE and ungrabbable, which reads as
	# "content cut off with no scrollbar" (settings page, tall columns).
	t.set_stylebox("scroll", "VScrollBar", _flat(COL_BG, COL_BG, 3, 4, 0))
	t.set_stylebox("grabber", "VScrollBar", _flat(Color("454e74"), Color("454e74"), 3, 4, 6))
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(COL_ACCENT_DIM, COL_ACCENT_DIM, 3, 4, 6))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(COL_ACCENT, COL_ACCENT, 3, 4, 6))

	# --- TabContainer
	t.set_stylebox("panel", "TabContainer", _flat(COL_PANEL, COL_BORDER))
	t.set_color("font_selected_color", "TabContainer", COL_TEXT)
	t.set_color("font_unselected_color", "TabContainer", COL_TEXT_DIM)

	# --- Tooltips
	t.set_stylebox("panel", "TooltipPanel", _flat(COL_PANEL_ALT, COL_ACCENT_DIM, 4, 8, 5))
	t.set_color("font_color", "TooltipLabel", COL_TEXT)

	return t


static func _flat(bg: Color, border: Color, corner: int = 0, margin_h: int = 10, margin_v: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


static func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## Present a popup dialog clamped to `ratio` of the viewport (default 85% of
## height/width). If `body` is given (the dialog's main content Control,
## parented to the dialog or not yet parented), it is wrapped in an internal
## ScrollContainer so oversized content scrolls while the title bar and the
## action buttons stay pinned on screen. Use this instead of a bare
## `popup_centered()` for every dialog whose content can grow taller than a
## small laptop / browser viewport.
static func popup_fitted(host: Node, dlg: AcceptDialog, body: Control = null, ratio := 0.85) -> void:
	const CHROME_Y := 96.0   # title bar + action-button row + margins
	var scroller: ScrollContainer = null
	if body != null:
		scroller = ScrollContainer.new()
		scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		if body.get_parent() != null:
			body.get_parent().remove_child(body)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroller.add_child(body)
		dlg.add_child(scroller)
	if dlg.get_parent() == null:
		host.add_child(dlg)
	var vp := _viewport_size(host)
	var cap: Vector2 = vp * ratio
	if scroller != null:
		# Width mins are reliable pre-layout; heights of autowrapping labels
		# are NOT (they report height-for-current-width before any layout
		# pass), so open at min(estimate, cap) and shrink-to-fit below.
		var want: Vector2 = body.get_combined_minimum_size()
		scroller.custom_minimum_size = Vector2(
			minf(want.x + 14.0, cap.x - 32.0),
			clampf(want.y + 4.0, 40.0, maxf(cap.y - CHROME_Y, 40.0)))
	dlg.reset_size()
	dlg.popup_centered()
	_clamp_window(dlg, vp, cap)
	if scroller == null:
		return
	# After a layout pass the wrapped labels know their real heights: shrink
	# the scroller to the content (or keep the cap and scroll internally).
	var tree: SceneTree = dlg.get_tree()
	for i in 2:
		if tree == null:
			return
		await tree.process_frame
		if not is_instance_valid(dlg) or not is_instance_valid(body) or not dlg.is_inside_tree():
			return
	var want_y: float = body.get_combined_minimum_size().y + 4.0
	var fit_y: float = clampf(want_y, 40.0, maxf(cap.y - CHROME_Y, 40.0))
	if absf(fit_y - scroller.custom_minimum_size.y) > 1.0:
		scroller.custom_minimum_size.y = fit_y
		dlg.reset_size()
	_clamp_window(dlg, vp, cap)


static func _viewport_size(host: Node) -> Vector2:
	if host is Control and host.is_inside_tree():
		return (host as Control).get_viewport_rect().size
	if host.is_inside_tree() and host.get_viewport() != null:
		return host.get_viewport().get_visible_rect().size
	return Vector2(1600, 900)


static func _clamp_window(dlg: Window, vp: Vector2, cap: Vector2) -> void:
	var sz := Vector2i(mini(dlg.size.x, int(cap.x)), mini(dlg.size.y, int(cap.y)))
	dlg.size = sz
	# Re-center inside the viewport and never hang off the top-left, so the
	# title bar and the action buttons always stay reachable.
	dlg.position = Vector2i(
		maxi(int((vp.x - float(sz.x)) * 0.5), 0),
		maxi(int((vp.y - float(sz.y)) * 0.5), 0))
