extends Control
## FM-style chrome: grouped sidebar nav + club identity, top bar with date /
## next fixture / balance / global search / Continue flow, breadcrumb bar,
## save-load menu, keyboard shortcuts, screen fade transitions.
##
## Screens are discovered BY CONVENTION at startup: every folder under
## res://screens/ that contains screen.tscn + screen.json becomes a nav entry.
## screen.json: {"title": "Squad", "order": 10, "icon_letter": "S"}
##
## OWNERSHIP: the "shell" piece owns res://shell/. Screen pieces never edit
## this file — they just drop their folder into res://screens/.
##
## Every entity reference in the chrome is a live hyperlink (FM-style):
## breadcrumb segments (league -> competition, club -> squad), the top-bar
## NEXT MATCH / BALANCE / DATE blocks, and the sidebar club identity block.
## A back/forward history stack (with context) backs the arrow buttons in the
## breadcrumb bar, Alt+Left/Right, Cmd/Ctrl+[ ], and mouse side buttons.
##
## SUB-NAVIGATION (FM24-style sidebar flyout/expandable sub-items):
## Every screen's internal tabs are first-class shell destinations. The sidebar
## renders them as indented sub-items under the parent entry; clicking one calls
## navigate_to(screen, {"tab": id}) — the same deep-link context that global
## search results, top-bar blocks and breadcrumb hyperlinks now carry.
## Tab discovery, in priority order (screen owners can adopt 1 without asking):
##   1. screen.json  "tabs": [{"id":"fixtures","title":"Fixtures & Results"}, ...]
##      (also accepts ["id","Title"] pairs or bare "Title" strings)
##   2. screen.gd script constants: TABS ([[id,title],..]) or PRESETS (dict keys)
##   3. SUBNAV_FALLBACK below (shell-owned nav config for screens whose tab bars
##      are built inline today; a screen.json declaration overrides it)
## Tab application, in priority order (adopt 1 for a guaranteed contract):
##   1. public select_tab(id)/set_tab(id)/show_tab(id) on the screen root
##   2. the screen's existing selector: _select_tab(id) / _switch_tab(id) /
##      _on_preset(id) / _set_tab(index)
##   3. a TabContainer anywhere under the screen root (current_tab = index)
## The shell also *reads back* the live tab (see _read_current_tab) on a short
## poll, so sub-item highlight + breadcrumb stay honest even when the user
## clicks the screen's own tab bar.
##
## Public API (used by tools/screenshots.gd and screens):
##   navigate_to(name: String, context: Dictionary = {}) -> bool
##     context (optional) is handed to the screen via reveal_search_target /
##     focus_search / on_search — e.g. {"kind":"club","id":...,"label":...}
##     context["tab"] (optional) deep-links to a subsection (see above).
##   go_back() / go_forward()
##   screens: Dictionary  (name -> {title, order, icon_letter, path, tabs})
##   current_screen_name: String / current_tab_id: String

const SIDEBAR_W := 232
const ADVANCE_CAP := 14
const NAV_GROUPS := [
	{"label": "COMMUNICATION", "screens": ["inbox"]},
	{"label": "SQUAD", "screens": ["squad", "tactics", "training"]},
	{"label": "MATCHDAY", "screens": ["match", "competition"]},
	{"label": "CLUB", "screens": ["transfers"]},
]
const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

## Shell-owned sub-nav config for screens whose tab bars are built inline in
## code today (no const / no screen.json declaration to discover). A "tabs"
## key in the screen's screen.json always overrides this — that is the screen
## owner's upgrade path, no shell edit needed.
const SUBNAV_FALLBACK := {
	"inbox": [
		{"id": "inbox", "title": "Inbox"},
		{"id": "board", "title": "Board & Finances"},
	],
	"training": [
		{"id": "schedule", "title": "Schedule"},
		{"id": "individual", "title": "Individual"},
		{"id": "coaches", "title": "Coaches"},
		{"id": "development", "title": "Development"},
	],
	"transfers": [
		{"id": "search", "title": "Search"},
		{"id": "scouting", "title": "Scouting"},
		{"id": "centre", "title": "Transfer Centre"},
	],
}

var screens: Dictionary = {}
var current_screen_name: String = ""
var current_tab_id: String = ""

# chrome nodes
var _content: MarginContainer
var _nav_box: VBoxContainer
var _nav_buttons: Dictionary = {}       # name -> Button
var _nav_badges: Dictionary = {}        # name -> Label (pill badge)
var _nav_order: Array = []              # visual order, for number shortcuts
var _nav_sub_boxes: Dictionary = {}     # name -> VBoxContainer (sub-item list)
var _nav_sub_buttons: Dictionary = {}   # name -> {tab_id -> Button}
var _nav_expanders: Dictionary = {}     # name -> Button (chevron)
var _nav_pinned: Dictionary = {}        # name -> bool (user pinned open)
var _crest_holder: Control
var _club_name_label: Label
var _club_sub_label: Label
var _mgr_face_holder: Control
var _club_sub2_label: Label
var _date_value: Label
var _date_caption: Label
var _fixture_value: Label
var _fixture_caption: Label
var _balance_value: Label
var _balance_caption: Label
var _continue_btn: Button
var _continue_main: Label
var _continue_sub: Label
var _crumb_title: Label
var _crumb_tab_sep: Label
var _crumb_tab_label: Label
var _crumb_chip: Label
var _crumb_chip_panel: PanelContainer
var _crumb_league_btn: Button
var _crumb_club_btn: Button
var _back_btn: Button
var _fwd_btn: Button
var _fixture_block: PanelContainer
var _ident_block: PanelContainer
var _search: LineEdit
var _search_panel: PanelContainer
var _search_list: ItemList
var _toast_panel: PanelContainer
var _toast_label: Label
var _menu_btn: MenuButton
const ClubPicker := preload("res://shell/club_picker.gd")
const GameOverScreen := preload("res://shell/game_over.gd")
const Onboarding := preload("res://menu/onboarding.gd")

var _load_confirm: ConfirmationDialog
var _new_confirm: ConfirmationDialog   # unused since the club picker took over
var _club_picker: Control = null       # legacy club selector (picker_shots proof)
var _onboarding: Control = null        # new-career onboarding wizard (menu piece)
var _game_over: Control = null         # sacking / career-summary overlay
var _foot_label: Label = null          # sidebar footer (league name follows career)

# fonts (real typography via system fonts; no bundled assets)
var _font_bold: SystemFont
var _font_semibold: SystemFont
var _font_header: FontVariation

# state
var _advancing := false
var _history: Array = []                # [{screen, context}] navigation stack
var _history_pos := -1
var _nav_from_history := false
var _search_index: Array = []
var _search_results: Array = []
var _type_icon_cache: Dictionary = {}
var _toast_tween: Tween
var _shortcut_count := 1                # sidebar screen count (shortcut hints)


func _notification(what: int) -> void:
	## Language switched mid-career (Settings): static Control text retranslates
	## on its own, but code-composed chrome strings (footer, shortcut hints, top
	## bar, identity block) hold rendered text — refresh them live so the
	## "changes apply immediately" promise holds for the whole shell.
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_retranslate_chrome()


func _retranslate_chrome() -> void:
	if _foot_label == null or GameState.world.is_empty():
		return
	_foot_label.text = "TRAINER MANAGER · %s" % tr(GameState.world["meta"]["league_name"])
	var side_hint: Node = find_child("SidebarHint", true, false)
	if side_hint is Label:
		side_hint.text = tr("Space = Continue · %d–%d = screens · Ctrl+1–9 = sections") % [1, _shortcut_count]
	var top_hint: Node = find_child("ShortcutHint", true, false)
	if top_hint is Label:
		top_hint.text = tr("1–%d screens   ·   Ctrl+1–9 sections   ·   Space  Continue   ·   Alt+Left/Right  Back/Fwd   ·   Ctrl+F  Search") % _shortcut_count
	_refresh_identity()
	_refresh_topbar()
	_update_subnav()
	_rebuild_search_index()


func _ready() -> void:
	add_child(load("res://shared/audio/audio_manager.tscn").instantiate())  # audio piece
	theme = ThemeBuilder.build()
	_make_fonts()
	_build_chrome()
	_build_search_overlay()
	_build_dialogs()
	_build_toast()
	_discover_screens()
	_build_nav()
	GameState.date_changed.connect(func(_d): _refresh_topbar())
	GameState.table_updated.connect(_refresh_topbar)
	GameState.inbox_updated.connect(_refresh_badges)
	GameState.inventory_changed.connect(_refresh_topbar)
	GameState.career_started.connect(_on_career_started)
	# The sacking arc: the board fires the manager -> full-screen career
	# summary + job offers (or a loaded save that ended that way).
	GameState.game_over.connect(func(_info): _open_game_over())
	if GameState.is_game_over():
		_open_game_over.call_deferred()
	# Balance/wages can be mutated by any piece mid-day (transfer fees, board
	# settlements, shop purchases) — a light poll keeps the top bar honest.
	var money_sync := Timer.new()
	money_sync.wait_time = 1.0
	money_sync.autostart = true
	money_sync.timeout.connect(func():
		if not _advancing:
			_refresh_topbar())
	add_child(money_sync)
	_refresh_identity()
	_refresh_topbar()
	_refresh_badges()
	_rebuild_search_index()
	# keep sub-item highlight / breadcrumb tab honest even when the user clicks
	# the screen's own tab bar (the shell reads the live tab back, FM-style)
	var sync := Timer.new()
	sync.wait_time = 0.35
	sync.autostart = true
	sync.timeout.connect(_sync_tab_state)
	add_child(sync)
	if not screens.is_empty():
		navigate_to(screens.keys().front())


func _make_fonts() -> void:
	_font_bold = SystemFont.new()
	_font_bold.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
	_font_bold.font_weight = 700
	_font_semibold = SystemFont.new()
	_font_semibold.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Arial"])
	_font_semibold.font_weight = 600
	_font_header = FontVariation.new()
	_font_header.base_font = _font_bold
	_font_header.spacing_glyph = 2


# ------------------------------------------------------------------ navigation

func navigate_to(screen_name: String, context: Dictionary = {}) -> bool:
	if not screens.has(screen_name):
		push_error("Shell: unknown screen '%s'" % screen_name)
		return false
	var want_tab := str(context.get("tab", ""))
	# Pure tab switch on the screen we're already on: apply in place, no
	# reinstantiation (FM never rebuilds the page when you hop subsections).
	# History/Continue replays skip this so the screen re-reads fresh state.
	if screen_name == current_screen_name and want_tab != "" \
			and not _nav_from_history and str(context.get("kind", "tab")) == "tab":
		var live := _current_screen_instance()
		if live != null and _apply_tab(live, screen_name, want_tab):
			current_tab_id = want_tab
			if not _nav_from_history:
				_history_push(screen_name, context)
			_update_history_buttons()
			_refresh_breadcrumb()
			_update_subnav()
			return true
	for child in _content.get_children():
		child.queue_free()
	var packed: PackedScene = load(screens[screen_name]["path"])
	if packed == null:
		push_error("Shell: failed to load scene for screen '%s'" % screen_name)
		return false
	var inst := packed.instantiate()
	_content.add_child(inst)
	current_screen_name = screen_name
	AudioManager.on_screen_changed(screen_name)  # audio piece: music/ambience
	current_tab_id = ""
	for n in _nav_buttons:
		_nav_buttons[n].button_pressed = (n == screen_name)
	if inst is CanvasItem:
		inst.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(inst, "modulate:a", 1.0, 0.12)
	if inst.has_method("on_show"):
		inst.call("on_show")
	if want_tab != "" and _apply_tab(inst, screen_name, want_tab):
		current_tab_id = want_tab
	else:
		current_tab_id = _read_current_tab(inst, screen_name)
	_deliver_context(inst, context)
	if not _nav_from_history:
		_history_push(screen_name, context)
	_update_history_buttons()
	_refresh_breadcrumb()
	_update_subnav()
	return true


func _deliver_context(inst: Node, context: Dictionary) -> void:
	## Hand an entity context (club/pokemon/fixture) to the freshly shown
	## screen through the same best-effort hooks global search uses.
	if inst == null or context.is_empty():
		return
	for meth in ["reveal_search_target", "focus_search", "on_search"]:
		if inst.has_method(meth):
			inst.call(meth, context)
			return


# ---- sub-navigation: screen tabs as first-class shell destinations ----------

func _screen_tabs(screen_name: String) -> Array:
	return screens.get(screen_name, {}).get("tabs", [])


func _tab_index(screen_name: String, tab_id: String) -> int:
	var tabs := _screen_tabs(screen_name)
	for i in tabs.size():
		if str(tabs[i]["id"]) == tab_id:
			return i
	return -1


func _tab_title(screen_name: String, tab_id: String) -> String:
	var i := _tab_index(screen_name, tab_id)
	return str(_screen_tabs(screen_name)[i]["title"]) if i >= 0 else tab_id


func _apply_tab(inst: Node, screen_name: String, tab_id: String) -> bool:
	## Drive the screen to the requested subsection. Cascade documented in the
	## file header: public contract -> the screen's own selector -> TabContainer.
	var idx := _tab_index(screen_name, tab_id)
	if inst == null or idx < 0:
		return false
	for meth in ["select_tab", "set_tab", "show_tab"]:
		if inst.has_method(meth):
			inst.call(meth, tab_id)
			return true
	for meth in ["_select_tab", "_switch_tab", "_on_preset"]:
		if inst.has_method(meth):
			inst.call(meth, tab_id)
			return true
	if inst.has_method("_set_tab"):
		inst.call("_set_tab", idx)
		return true
	var tc := _find_tab_container(inst)
	if tc != null and idx < tc.get_tab_count():
		tc.current_tab = idx
		return true
	return false


func _read_current_tab(inst: Node, screen_name: String) -> String:
	## Best-effort read-back of the screen's live tab so shell chrome (sub-item
	## highlight, breadcrumb) reflects reality even after in-screen clicks.
	var tabs := _screen_tabs(screen_name)
	if inst == null or tabs.is_empty():
		return ""
	if inst.has_method("current_tab_id"):
		var pub = inst.call("current_tab_id")
		if pub is String and _tab_index(screen_name, pub) >= 0:
			return pub
	for prop in ["_current_tab", "_current", "_view"]:
		var v = inst.get(prop)
		if v is String and _tab_index(screen_name, str(v)) >= 0:
			return str(v)
	var vi = inst.get("_tab")
	if vi is int and vi >= 0 and vi < tabs.size():
		return str(tabs[vi]["id"])
	var tc := _find_tab_container(inst)
	if tc != null and tc.current_tab >= 0 and tc.current_tab < tabs.size():
		return str(tabs[tc.current_tab]["id"])
	return ""


func _find_tab_container(root: Node) -> TabContainer:
	if root is TabContainer:
		return root
	for child in root.get_children():
		var found := _find_tab_container(child)
		if found != null:
			return found
	return null


func _sync_tab_state() -> void:
	## Short poll: if the user switched tabs via the screen's own tab bar, pick
	## it up and refresh sub-item highlight + the breadcrumb's tab segment.
	if current_screen_name == "" or _screen_tabs(current_screen_name).is_empty():
		return
	var inst := _current_screen_instance()
	if inst == null:
		return
	var live := _read_current_tab(inst, current_screen_name)
	if live != "" and live != current_tab_id:
		current_tab_id = live
		_refresh_breadcrumb()
		_update_subnav()


# ---- back / forward history stack -------------------------------------------

func _history_push(screen_name: String, context: Dictionary) -> void:
	if _history_pos >= 0 and _history_pos < _history.size():
		var cur: Dictionary = _history[_history_pos]
		if cur["screen"] == screen_name and cur["context"] == context:
			return  # re-showing the same place (e.g. refresh after Continue)
	_history.resize(_history_pos + 1)     # drop any forward entries
	_history.append({"screen": screen_name, "context": context})
	if _history.size() > 60:
		_history.pop_front()
	_history_pos = _history.size() - 1


func go_back() -> void:
	if _history_pos <= 0:
		return
	_history_pos -= 1
	_history_jump()


func go_forward() -> void:
	if _history_pos >= _history.size() - 1:
		return
	_history_pos += 1
	_history_jump()


func _history_jump() -> void:
	var e: Dictionary = _history[_history_pos]
	_nav_from_history = true
	navigate_to(e["screen"], e["context"])
	_nav_from_history = false


func _reset_history() -> void:
	_history.clear()
	_history_pos = -1


func _history_label(e: Dictionary) -> String:
	var t: String = tr(str(screens.get(e["screen"], {}).get("title", e["screen"])))
	var ctx: Dictionary = e["context"]
	if ctx.has("label"):
		t += " · %s" % str(ctx["label"])
	return t


func _update_history_buttons() -> void:
	if _back_btn == null:
		return
	var can_back := _history_pos > 0
	var can_fwd := _history_pos < _history.size() - 1
	_back_btn.disabled = not can_back
	_fwd_btn.disabled = not can_fwd
	_back_btn.tooltip_text = (tr("Back to %s   (Alt+Left / mouse-4)") % _history_label(_history[_history_pos - 1])) \
		if can_back else tr("Back   (Alt+Left — nowhere to go)")
	_fwd_btn.tooltip_text = (tr("Forward to %s   (Alt+Right / mouse-5)") % _history_label(_history[_history_pos + 1])) \
		if can_fwd else tr("Forward   (Alt+Right — nowhere to go)")


func _current_screen_instance() -> Node:
	for child in _content.get_children():
		if not child.is_queued_for_deletion():
			return child
	return null


func _discover_screens() -> void:
	var dir := DirAccess.open("res://screens")
	if dir == null:
		push_warning("Shell: res://screens not found")
		return
	for folder in dir.get_directories():
		var scene_path := "res://screens/%s/screen.tscn" % folder
		var meta_path := "res://screens/%s/screen.json" % folder
		if not FileAccess.file_exists(meta_path) or not ResourceLoader.exists(scene_path):
			continue
		var meta: Variant = JSON.parse_string(FileAccess.open(meta_path, FileAccess.READ).get_as_text())
		if meta == null or typeof(meta) != TYPE_DICTIONARY:
			push_warning("Shell: bad screen.json in %s" % folder)
			continue
		screens[folder] = {
			"title": meta.get("title", folder.capitalize()),
			"order": int(meta.get("order", 999)),
			"icon_letter": meta.get("icon_letter", folder.substr(0, 1).to_upper()),
			"path": scene_path,
			"tabs": _discover_tabs(folder, meta),
		}
	var names := screens.keys()
	names.sort_custom(func(a, b): return screens[a]["order"] < screens[b]["order"])
	var ordered := {}
	for n in names:
		ordered[n] = screens[n]
	screens = ordered
	var summary := PackedStringArray()
	for n in screens:
		var tabs: Array = screens[n]["tabs"]
		summary.append("%s(%d tabs)" % [n, tabs.size()] if not tabs.is_empty() else n)
	print("Shell: discovered %d screens: %s" % [screens.size(), ", ".join(summary)])


func _discover_tabs(folder: String, meta: Dictionary) -> Array:
	## Normalised tab list [{id, title}] for a screen. Priority:
	## screen.json "tabs" > screen.gd consts (TABS / PRESETS) > SUBNAV_FALLBACK.
	var declared: Variant = meta.get("tabs")
	var normalized := _normalize_tabs(declared)
	if not normalized.is_empty():
		return normalized
	var script_path := "res://screens/%s/screen.gd" % folder
	if ResourceLoader.exists(script_path):
		var script: GDScript = load(script_path)
		if script != null:
			var consts: Dictionary = script.get_script_constant_map()
			normalized = _normalize_tabs(consts.get("TABS"))
			if not normalized.is_empty():
				return normalized
			var presets: Variant = consts.get("PRESETS")
			if presets is Dictionary and not presets.is_empty():
				var out: Array = []
				for key in presets.keys():
					out.append({"id": str(key), "title": str(key)})
				return out
	return SUBNAV_FALLBACK.get(folder, [])


func _normalize_tabs(raw: Variant) -> Array:
	## Accepts [{"id","title"}], [["id","Title"],..] or ["Title",..].
	if not (raw is Array):
		return []
	var out: Array = []
	for entry in raw:
		if entry is Dictionary and entry.has("id"):
			out.append({"id": str(entry["id"]), "title": str(entry.get("title", entry["id"]))})
		elif entry is Array and entry.size() >= 2:
			out.append({"id": str(entry[0]), "title": str(entry[1])})
		elif entry is String:
			out.append({"id": entry, "title": entry})
	return out


# ------------------------------------------------------------------ chrome build

func _build_chrome() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = ThemeBuilder.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	layout.add_child(_build_topbar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	layout.add_child(body)

	body.add_child(_build_sidebar())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	body.add_child(right)

	right.add_child(_build_breadcrumb())

	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_content.add_theme_constant_override(side, 14)
	right.add_child(_content)


func _build_topbar() -> Control:
	var top := PanelContainer.new()
	var sb := ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 0, 14, 7)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	top.add_theme_stylebox_override("panel", sb)
	top.custom_minimum_size.y = 58

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)

	# game menu (save / load / new career)
	_menu_btn = MenuButton.new()
	_menu_btn.text = " TM  "
	_menu_btn.icon = GlyphIcons.tex("menu", 12, ThemeBuilder.COL_ACCENT)
	_menu_btn.flat = false
	_menu_btn.focus_mode = Control.FOCUS_NONE
	_menu_btn.add_theme_font_override("font", _font_bold)
	_menu_btn.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	_menu_btn.add_theme_stylebox_override("normal",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_BORDER, 5, 8, 6))
	_menu_btn.add_theme_stylebox_override("hover",
		ThemeBuilder._flat(Color("2a3150"), ThemeBuilder.COL_ACCENT_DIM, 5, 8, 6))
	_menu_btn.add_theme_stylebox_override("pressed",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT_DIM, ThemeBuilder.COL_ACCENT, 5, 8, 6))
	var pm := _menu_btn.get_popup()
	pm.add_item("Save Game", 0)
	pm.set_item_accelerator(0, KEY_MASK_CTRL | KEY_S)
	pm.add_item("Load Game", 1)
	pm.add_separator()
	pm.add_item("New Career", 2)
	pm.id_pressed.connect(_on_menu_id)
	row.add_child(_menu_btn)

	# global search
	_search = LineEdit.new()
	_search.placeholder_text = "Search Pokémon or clubs…   (Ctrl+F)"
	_search.custom_minimum_size = Vector2(280, 34)
	_search.text_changed.connect(_on_search_text)
	_search.text_submitted.connect(func(_t): _activate_search_selection())
	_search.gui_input.connect(_on_search_gui_input)
	_search.focus_exited.connect(_on_search_focus_exited)
	row.add_child(_search)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# info blocks: next match | balance | date — all live hyperlinks
	var fx := _info_block("NEXT MATCH ›", _on_fixture_block_clicked)
	_fixture_block = fx[0]
	_fixture_value = fx[1]
	_fixture_caption = fx[2]
	row.add_child(fx[0])
	row.add_child(_vsep())

	var bal := _info_block("BALANCE ›", _on_balance_block_clicked)
	_balance_value = bal[1]
	_balance_caption = bal[2]
	bal[0].tooltip_text = "Open Board & Finances — balance, wages, board confidence"
	row.add_child(bal[0])
	row.add_child(_vsep())

	var dt := _info_block("DATE ›", _on_date_block_clicked)
	_date_value = dt[1]
	_date_caption = dt[2]
	dt[0].tooltip_text = "Open Competition — season calendar and fixtures"
	row.add_child(dt[0])

	# Continue button
	_continue_btn = Button.new()
	_continue_btn.custom_minimum_size = Vector2(252, 44)
	_continue_btn.focus_mode = Control.FOCUS_NONE
	_continue_btn.add_theme_stylebox_override("normal",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT_DIM, ThemeBuilder.COL_ACCENT, 5, 12, 4))
	_continue_btn.add_theme_stylebox_override("hover",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT, ThemeBuilder.COL_ACCENT, 5, 12, 4))
	_continue_btn.add_theme_stylebox_override("pressed",
		ThemeBuilder._flat(Color("9488ff"), Color("b0a8ff"), 5, 12, 4))
	_continue_btn.add_theme_stylebox_override("disabled",
		ThemeBuilder._flat(Color("3a3570"), ThemeBuilder.COL_ACCENT_DIM, 5, 12, 4))
	_continue_btn.pressed.connect(_on_continue)
	_continue_btn.set_meta("no_sfx", true)  # audio: whoosh in _on_continue instead of the generic click
	var cbox := VBoxContainer.new()
	cbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	cbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cbox.add_theme_constant_override("separation", 0)
	_continue_main = Label.new()
	_continue_main.text = "CONTINUE  ›"
	_continue_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_main.add_theme_font_override("font", _font_header)
	_continue_main.add_theme_font_size_override("font_size", 15)
	_continue_main.add_theme_color_override("font_color", Color.WHITE)
	cbox.add_child(_continue_main)
	_continue_sub = Label.new()
	_continue_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_sub.add_theme_font_size_override("font_size", 11)
	_continue_sub.add_theme_color_override("font_color", Color("d8d4ff"))
	cbox.add_child(_continue_sub)
	_continue_btn.add_child(cbox)
	row.add_child(_continue_btn)

	return top


func _info_block(caption: String, on_click: Callable) -> Array:
	## A top-bar stat block that behaves like an FM hyperlink: hand cursor,
	## hover highlight, click navigates to the referenced entity.
	var panel := _hyperlink_panel(on_click)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	var value := Label.new()
	value.add_theme_font_override("font", _font_semibold)
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(value)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	box.add_child(cap)
	return [panel, value, cap]


func _hyperlink_panel(on_click: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	var normal := ThemeBuilder._flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 5, 8, 3)
	var hover := ThemeBuilder._flat(Color("232a42"), ThemeBuilder.COL_ACCENT_DIM, 5, 8, 3)
	panel.add_theme_stylebox_override("panel", normal)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(func(): panel.add_theme_stylebox_override("panel", hover))
	panel.mouse_exited.connect(func(): panel.add_theme_stylebox_override("panel", normal))
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			panel.accept_event()
			on_click.call())
	return panel


func _on_fixture_block_clicked() -> void:
	var nf := GameState.next_player_fixture()
	if nf.is_empty():
		if screens.has("competition"):
			navigate_to("competition", {"kind": "tab", "tab": "fixtures", "label": "Fixtures & Results"})
		return
	var we_home: bool = GameState.is_player_club(nf["home"])
	var opp_id: String = str(nf["away"] if we_home else nf["home"])
	var opp := GameState.club(opp_id)
	var ctx := {"kind": "club", "id": opp_id, "label": str(opp.get("name", opp_id)),
		"color": DataStore.type_color(_club_primary_type(opp)), "fixture": nf,
		"tab": "fixtures", "sub": "Next opponent · %s" % _comp_name(nf)}
	if nf["date"] == GameState.current_date and screens.has("match"):
		ctx.erase("tab")
		navigate_to("match", ctx)
	elif screens.has("competition"):
		navigate_to("competition", ctx)


func _on_balance_block_clicked() -> void:
	# FM's money hyperlink goes to the finance section — ours lives on the
	# Inbox screen's Board & Finances tab. Deep-link straight to it.
	if screens.has("inbox") and _tab_index("inbox", "board") >= 0:
		navigate_to("inbox", {"kind": "tab", "tab": "board", "label": "Board & Finances"})
	elif screens.has("transfers"):
		navigate_to("transfers", {"kind": "finances", "id": str(GameState.player_club().get("id", "")),
			"label": "Finances", "tab": "centre"})


func _on_date_block_clicked() -> void:
	if screens.has("competition"):
		navigate_to("competition", {"kind": "calendar", "id": GameState.current_date,
			"label": I18n.pretty_date(GameState.current_date), "tab": "fixtures"})


func _vsep() -> Control:
	var v := ColorRect.new()
	v.color = ThemeBuilder.COL_BORDER
	v.custom_minimum_size = Vector2(1, 34)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return v


func _build_sidebar() -> Control:
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = SIDEBAR_W
	var sb := ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_BORDER, 0, 10, 12)
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	sidebar.add_theme_stylebox_override("panel", sb)

	_nav_box = VBoxContainer.new()
	_nav_box.add_theme_constant_override("separation", 2)
	sidebar.add_child(_nav_box)

	# club identity block — clickable, jumps to Squad (FM: club name = link)
	_ident_block = _hyperlink_panel(_on_crumb_club)
	var ident := HBoxContainer.new()
	ident.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ident.add_theme_constant_override("separation", 10)
	_crest_holder = Control.new()
	_crest_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crest_holder.custom_minimum_size = Vector2(46, 46)
	ident.add_child(_crest_holder)
	var idcol := VBoxContainer.new()
	idcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idcol.alignment = BoxContainer.ALIGNMENT_CENTER
	idcol.add_theme_constant_override("separation", 0)
	_club_name_label = Label.new()
	_club_name_label.add_theme_font_override("font", _font_bold)
	_club_name_label.add_theme_font_size_override("font_size", 15)
	_club_name_label.add_theme_color_override("font_color", Color.WHITE)
	_club_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	idcol.add_child(_club_name_label)
	var mgr_row := HBoxContainer.new()
	mgr_row.add_theme_constant_override("separation", 5)
	mgr_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mgr_face_holder = Control.new()
	_mgr_face_holder.custom_minimum_size = Vector2(16, 16)
	_mgr_face_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mgr_row.add_child(_mgr_face_holder)
	_club_sub_label = Label.new()
	_club_sub_label.add_theme_font_size_override("font_size", 11)
	_club_sub_label.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	mgr_row.add_child(_club_sub_label)
	idcol.add_child(mgr_row)
	_club_sub2_label = Label.new()
	_club_sub2_label.add_theme_font_size_override("font_size", 11)
	_club_sub2_label.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	idcol.add_child(_club_sub2_label)
	idcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ident.add_child(idcol)
	_ident_block.add_child(ident)
	_nav_box.add_child(_ident_block)

	_nav_box.add_child(_thin_sep())
	return sidebar


func _thin_sep() -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 8)
	wrap.add_theme_constant_override("margin_bottom", 6)
	var line := ColorRect.new()
	line.color = ThemeBuilder.COL_BORDER
	line.custom_minimum_size.y = 1
	wrap.add_child(line)
	return wrap


func _build_breadcrumb() -> Control:
	var bar := PanelContainer.new()
	var sb := ThemeBuilder._flat(Color("161a28"), ThemeBuilder.COL_BORDER, 0, 14, 6)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	bar.add_theme_stylebox_override("panel", sb)
	bar.custom_minimum_size.y = 40

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	# back / forward history arrows (FM-style)
	var arrows := HBoxContainer.new()
	arrows.add_theme_constant_override("separation", 2)
	_back_btn = _history_arrow("tri_left")
	_back_btn.pressed.connect(go_back)
	arrows.add_child(_back_btn)
	_fwd_btn = _history_arrow("tri_right")
	_fwd_btn.pressed.connect(go_forward)
	arrows.add_child(_fwd_btn)
	row.add_child(arrows)
	row.add_child(_vsep())

	_crumb_chip_panel = PanelContainer.new()
	_crumb_chip_panel.custom_minimum_size = Vector2(24, 24)
	_crumb_chip_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_crumb_chip_panel.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT_DIM, ThemeBuilder.COL_ACCENT, 6, 0, 0))
	_crumb_chip = Label.new()
	_crumb_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crumb_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crumb_chip.add_theme_font_override("font", _font_bold)
	_crumb_chip.add_theme_font_size_override("font_size", 12)
	_crumb_chip.add_theme_color_override("font_color", Color.WHITE)
	_crumb_chip_panel.add_child(_crumb_chip)
	row.add_child(_crumb_chip_panel)

	# clickable trail: League › Club › Screen
	_crumb_league_btn = _crumb_link()
	_crumb_league_btn.pressed.connect(_on_crumb_league)
	row.add_child(_crumb_league_btn)
	row.add_child(_crumb_sep())
	_crumb_club_btn = _crumb_link()
	_crumb_club_btn.pressed.connect(_on_crumb_club)
	row.add_child(_crumb_club_btn)
	row.add_child(_crumb_sep())

	_crumb_title = Label.new()
	_crumb_title.add_theme_font_override("font", _font_bold)
	_crumb_title.add_theme_font_size_override("font_size", 16)
	_crumb_title.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(_crumb_title)

	# final crumb segment: the live subsection (tab) within the screen
	_crumb_tab_sep = _crumb_sep()
	_crumb_tab_sep.visible = false
	row.add_child(_crumb_tab_sep)
	_crumb_tab_label = Label.new()
	_crumb_tab_label.visible = false
	_crumb_tab_label.add_theme_font_override("font", _font_semibold)
	_crumb_tab_label.add_theme_font_size_override("font_size", 14)
	_crumb_tab_label.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	row.add_child(_crumb_tab_label)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)

	var hint := Label.new()
	hint.text = tr("1–%d screens   ·   Space  Continue   ·   Alt+Left/Right  Back/Fwd   ·   Ctrl+F  Search   ·   Ctrl+S  Save") % 7
	hint.name = "ShortcutHint"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	row.add_child(hint)

	return bar


func _history_arrow(kind: String) -> Button:
	var btn := Button.new()
	btn.icon = GlyphIcons.tex(kind, 10, ThemeBuilder.COL_TEXT)
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(30, 26)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_stylebox_override("normal",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 5, 6, 3))
	btn.add_theme_stylebox_override("hover",
		ThemeBuilder._flat(Color("2a3150"), ThemeBuilder.COL_ACCENT_DIM, 5, 6, 3))
	btn.add_theme_stylebox_override("pressed",
		ThemeBuilder._flat(ThemeBuilder.COL_ACCENT_DIM, ThemeBuilder.COL_ACCENT, 5, 6, 3))
	btn.add_theme_stylebox_override("disabled",
		ThemeBuilder._flat(Color("171b29"), Color("222840"), 5, 6, 3))
	btn.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	btn.add_theme_color_override("font_disabled_color", Color("3d4358"))
	return btn


func _crumb_link() -> Button:
	## Breadcrumb segment rendered as a hyperlink: dim text, accent on hover,
	## hand cursor. Text + tooltip are refreshed in _refresh_breadcrumb().
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2
	empty.content_margin_right = 2
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, empty)
	btn.add_theme_font_override("font", _font_semibold)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", ThemeBuilder.COL_ACCENT)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_pressed_color", ThemeBuilder.COL_ACCENT)
	return btn


func _crumb_sep() -> Label:
	var sep := Label.new()
	sep.text = "›"
	sep.add_theme_font_size_override("font_size", 11)
	sep.add_theme_color_override("font_color", Color("4a5068"))
	return sep


func _on_crumb_league() -> void:
	if screens.has("competition"):
		navigate_to("competition", {"kind": "league", "id": "league",
			"label": str(GameState.world["meta"]["league_name"]), "tab": "table"})


func _on_crumb_club() -> void:
	if screens.has("squad"):
		var pc := GameState.player_club()
		navigate_to("squad", {"kind": "club", "id": str(pc.get("id", "")),
			"label": str(pc.get("name", ""))})


# ------------------------------------------------------------------ crest

func _club_primary_type(c: Dictionary) -> String:
	var counts := {}
	for inst in c.get("squad", []):
		var sp: Dictionary = DataStore.species(int(inst["species_id"]))
		if sp.is_empty():
			continue
		var types: Array = sp.get("types", [])
		if types.size() > 0:
			counts[types[0]] = counts.get(types[0], 0) + 2
		if types.size() > 1:
			counts[types[1]] = counts.get(types[1], 0) + 1
	var best := "Normal"
	var best_n := -1
	for t in counts:
		if counts[t] > best_n:
			best_n = counts[t]
			best = t
	return best


func _make_crest(c: Dictionary, px: int) -> Control:
	return Crest.icon(c, px)   # procedural gym-badge crest (crests piece)


# ------------------------------------------------------------------ nav

func _build_nav() -> void:
	_nav_order.clear()
	# the grouped list lives in a scroll container so pinned-open sub-sections
	# can never push the footer off-screen
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	_nav_box.add_child(scroll)

	var placed := {}
	var shortcut := 0
	for group in NAV_GROUPS:
		var members: Array = group["screens"].filter(func(n): return screens.has(n))
		if members.is_empty():
			continue
		list.add_child(_group_header(group["label"]))
		for n in members:
			shortcut += 1
			list.add_child(_nav_button(n, shortcut))
			_add_subnav(list, n)
			placed[n] = true
	# any screens not covered by the group map
	var leftovers := screens.keys().filter(func(n): return not placed.has(n))
	if not leftovers.is_empty():
		list.add_child(_group_header("MORE"))
		for n in leftovers:
			shortcut += 1
			list.add_child(_nav_button(n, shortcut))
			_add_subnav(list, n)

	_nav_box.add_child(_thin_sep())
	_shortcut_count = maxi(shortcut, 1)
	_foot_label = Label.new()
	_foot_label.text = "TRAINER MANAGER · %s" % tr(GameState.world["meta"]["league_name"])
	_foot_label.add_theme_font_size_override("font_size", 9)
	_foot_label.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_nav_box.add_child(_foot_label)

	var hint := Label.new()
	hint.name = "SidebarHint"
	hint.text = tr("Space = Continue · %d–%d = screens · Ctrl+1–9 = sections") % [1, maxi(shortcut, 1)]
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
	_nav_box.add_child(hint)

	var hint_node: Node = find_child("ShortcutHint", true, false)
	if hint_node is Label:
		hint_node.text = tr("1–%d screens   ·   Ctrl+1–9 sections   ·   Space  Continue   ·   Alt+Left/Right  Back/Fwd   ·   Ctrl+F  Search") % maxi(shortcut, 1)
	_update_subnav()


func _group_header(text: String) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 10)
	wrap.add_theme_constant_override("margin_bottom", 2)
	wrap.add_theme_constant_override("margin_left", 6)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_header)
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color("5c6480"))
	wrap.add_child(l)
	return wrap


func _nav_button(n: String, shortcut: int) -> Button:
	var meta: Dictionary = screens[n]
	var btn := Button.new()
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = 36
	btn.tooltip_text = tr("%s  (press %d)") % [tr(str(meta["title"])), shortcut]
	var normal := ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_PANEL, 5, 8, 4)
	var hover := ThemeBuilder._flat(Color("232a42"), Color("232a42"), 5, 8, 4)
	var active := ThemeBuilder._flat(Color("2c2f56"), Color("2c2f56"), 5, 8, 4)
	active.border_width_left = 3
	active.border_color = ThemeBuilder.COL_ACCENT
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", active)
	btn.add_theme_stylebox_override("hover_pressed", active)
	btn.pressed.connect(navigate_to.bind(n))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_child(row)
	btn.add_child(margin)

	# icon letter chip
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(22, 22)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_BORDER, 6, 0, 0))
	var chip_l := Label.new()
	chip_l.text = str(meta["icon_letter"])
	chip_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_l.add_theme_font_override("font", _font_bold)
	chip_l.add_theme_font_size_override("font_size", 11)
	chip_l.add_theme_color_override("font_color", ThemeBuilder.COL_ACCENT)
	chip.add_child(chip_l)
	row.add_child(chip)

	var title := Label.new()
	title.text = str(meta["title"])
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", _font_semibold)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT)
	row.add_child(title)

	# badge pill (unread count / TODAY)
	var badge := Label.new()
	badge.visible = false
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_override("font", _font_bold)
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", Color.WHITE)
	var pill := StyleBoxFlat.new()
	pill.bg_color = ThemeBuilder.COL_BAD
	pill.set_corner_radius_all(8)
	pill.content_margin_left = 7
	pill.content_margin_right = 7
	pill.content_margin_top = 1
	pill.content_margin_bottom = 1
	badge.add_theme_stylebox_override("normal", pill)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var num := Label.new()
	num.text = str(shortcut)
	num.add_theme_font_size_override("font_size", 10)
	num.add_theme_color_override("font_color", Color("4a5068"))
	row.add_child(num)

	# chevron: expand/collapse the FM-style sub-section list without navigating
	if not _screen_tabs(n).is_empty():
		var chev := Button.new()
		chev.icon = GlyphIcons.tex("caret_right", 8, Color("6a7186"))
		chev.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chev.flat = true
		chev.focus_mode = Control.FOCUS_NONE
		chev.custom_minimum_size = Vector2(18, 22)
		chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chev.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chev.tooltip_text = tr("Show %s sections") % tr(str(meta["title"]))
		chev.add_theme_font_size_override("font_size", 10)
		chev.add_theme_color_override("font_color", Color("6a7290"))
		chev.add_theme_color_override("font_hover_color", ThemeBuilder.COL_ACCENT)
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus"]:
			chev.add_theme_stylebox_override(st, empty)
		chev.pressed.connect(_toggle_pin.bind(n))
		row.add_child(chev)
		_nav_expanders[n] = chev

	_nav_buttons[n] = btn
	_nav_badges[n] = badge
	_nav_order.append(n)
	return btn


func _add_subnav(list: VBoxContainer, n: String) -> void:
	## Indented sub-items under a sidebar entry — one per declared/discovered
	## screen tab. Each is a real deep link: navigate_to(n, {"tab": id}).
	var tabs := _screen_tabs(n)
	if tabs.is_empty():
		return
	var box := VBoxContainer.new()
	box.visible = false
	box.add_theme_constant_override("separation", 1)
	var by_id := {}
	for t in tabs:
		var tab_id: String = str(t["id"])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 26
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "%s » %s" % [tr(str(screens[n]["title"])), tr(str(t["title"]))]
		b.pressed.connect(_on_subnav_pressed.bind(n, tab_id))
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 30)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_child(row)
		b.add_child(margin)
		var tick := Label.new()
		tick.name = "Tick"
		tick.text = "·"
		tick.add_theme_font_override("font", _font_bold)
		tick.add_theme_font_size_override("font_size", 12)
		tick.add_theme_color_override("font_color", Color("4a5068"))
		row.add_child(tick)
		var lbl := Label.new()
		lbl.name = "Title"
		lbl.text = str(t["title"])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.add_theme_font_override("font", _font_semibold)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", ThemeBuilder.COL_TEXT_DIM)
		row.add_child(lbl)
		box.add_child(b)
		by_id[tab_id] = b
	list.add_child(box)
	_nav_sub_boxes[n] = box
	_nav_sub_buttons[n] = by_id
	_style_subnav_button_states(n)


func _on_subnav_pressed(n: String, tab_id: String) -> void:
	navigate_to(n, {"kind": "tab", "tab": tab_id, "label": _tab_title(n, tab_id)})


func _toggle_pin(n: String) -> void:
	_nav_pinned[n] = not _nav_pinned.get(n, false)
	_update_subnav()


func _style_subnav_button_states(n: String) -> void:
	for tab_id in _nav_sub_buttons.get(n, {}):
		var b: Button = _nav_sub_buttons[n][tab_id]
		var active: bool = (n == current_screen_name and tab_id == current_tab_id)
		var normal := ThemeBuilder._flat(ThemeBuilder.COL_PANEL, ThemeBuilder.COL_PANEL, 4, 4, 2)
		var hover := ThemeBuilder._flat(Color("222840"), Color("222840"), 4, 4, 2)
		if active:
			normal = ThemeBuilder._flat(Color("262b4c"), Color("262b4c"), 4, 4, 2)
			normal.border_width_left = 2
			normal.border_color = ThemeBuilder.COL_ACCENT
			hover = normal
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		var tick: Label = b.find_child("Tick", true, false)
		var lbl: Label = b.find_child("Title", true, false)
		if tick != null:
			tick.text = "•" if active else "·"
			tick.add_theme_color_override("font_color",
				ThemeBuilder.COL_ACCENT if active else Color("4a5068"))
		if lbl != null:
			lbl.add_theme_color_override("font_color",
				Color.WHITE if active else ThemeBuilder.COL_TEXT_DIM)


func _update_subnav() -> void:
	## Accordion: the active screen's sub-items are expanded; others collapse
	## unless the user pinned them open with the chevron.
	for n in _nav_sub_boxes:
		var open: bool = (n == current_screen_name) or _nav_pinned.get(n, false)
		_nav_sub_boxes[n].visible = open
		if _nav_expanders.has(n):
			var chev: Button = _nav_expanders[n]
			chev.icon = GlyphIcons.tex("caret_down" if open else "caret_right", 8, Color("6a7186"))
			chev.tooltip_text = tr("Collapse %s sections" if _nav_pinned.get(n, false) \
				else ("Hide %s sections" if open else "Show %s sections")) % tr(str(screens[n]["title"]))
		_style_subnav_button_states(n)


# ------------------------------------------------------------------ refresh

func _on_career_started() -> void:
	if _foot_label != null:   # league can change with the chosen club
		_foot_label.text = "TRAINER MANAGER · %s" % tr(GameState.world["meta"]["league_name"])
	_refresh_identity()
	_refresh_topbar()
	_refresh_badges()
	_rebuild_search_index()


func _refresh_identity() -> void:
	var pc := GameState.player_club()
	for c in _crest_holder.get_children():
		c.queue_free()
	var crest := _make_crest(pc, 46)
	crest.set_anchors_preset(Control.PRESET_FULL_RECT)
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crest_holder.add_child(crest)
	_ident_block.tooltip_text = tr("Open Squad — %s") % pc.get("name", "")
	_club_name_label.text = str(pc.get("name", "—"))
	_club_sub_label.text = str(pc.get("manager", ""))
	# the manager's own procedural portrait (portraits piece)
	for c2 in _mgr_face_holder.get_children():
		c2.queue_free()
	var mf := Portrait.avatar(Portrait.manager_seed(), 16, {"collar": Portrait.club_collar(pc)})
	_mgr_face_holder.add_child(mf)
	_club_sub2_label.text = "%s · %s" % [_league_pos_text(), tr(GameState.world["meta"]["league_name"])]


func _refresh_topbar() -> void:
	var pc := GameState.player_club()
	# date block
	_date_value.text = I18n.pretty_date(GameState.current_date)
	_date_caption.text = tr("%s · Week %d") % [_weekday(GameState.current_date), _season_week()]
	# balance block: bank balance headline, board's budget split underneath
	var cur: String = GameState.world["meta"].get("currency", "P$")
	_balance_value.text = "%s%s" % [cur, _thousands(int(pc["finances"]["balance"]))]
	_balance_caption.text = tr("T. budget %s%s · wages %s%s/w") % [
		cur, _thousands(maxi(0, int(pc["finances"].get("transfer_budget", 0)))),
		cur, _thousands(int(pc["finances"]["wage_budget"]))]
	# next fixture block
	var nf := GameState.next_player_fixture()
	if nf.is_empty():
		_fixture_value.text = "No fixtures left"
		_fixture_caption.text = "SEASON COMPLETE"
		_fixture_block.tooltip_text = "Open Competition — final table"
	else:
		var we_home: bool = GameState.is_player_club(nf["home"])
		var opp := GameState.club(nf["away"] if we_home else nf["home"])
		var days := _days_until(nf["date"])
		_fixture_value.text = tr("vs %s (H)" if we_home else "vs %s (A)") % opp.get("name", "?")
		_fixture_caption.text = "%s · %s" % [_comp_name(nf), _days_phrase(days)]
		_fixture_block.tooltip_text = (tr("Go to matchday vs %s") % opp.get("name", "?")) if days <= 0 \
			else tr("Open fixture — %s, %s (%s)") % [opp.get("name", "?"), I18n.pretty_date(nf["date"]), _comp_name(nf)]
	# position line under club name ("—" until a league match is played)
	_club_sub2_label.text = "%s · %s" % [_league_pos_text(), tr(GameState.world["meta"]["league_name"])]
	_refresh_continue_label()
	_refresh_badges()


## Pre-season a table position is meaningless (alphabetical) — show "—".
func _league_pos_text() -> String:
	for r in GameState.league_table():
		if GameState.is_player_club(r["club_id"]):
			return "—" if int(r.get("played", 0)) == 0 else I18n.ordinal(GameState.player_table_position())
	return "—"


func _refresh_continue_label() -> void:
	if _advancing:
		return
	var nf := GameState.next_player_fixture()
	if nf.is_empty():
		_continue_main.text = "CONTINUE  ›"
		_continue_sub.text = tr("Advance %d days") % ADVANCE_CAP
		return
	var we_home: bool = GameState.is_player_club(nf["home"])
	var opp := GameState.club(nf["away"] if we_home else nf["home"])
	var days := _days_until(nf["date"])
	if days <= 0:
		_continue_main.text = "MATCHDAY  ›"
		_continue_sub.text = tr("vs %s · go to match") % opp.get("name", "?")
	elif days == 1:
		_continue_main.text = "CONTINUE  ›"
		_continue_sub.text = tr("Matchday vs %s") % opp.get("name", "?")
	else:
		_continue_main.text = "CONTINUE  ›"
		_continue_sub.text = tr("Advance %d days · vs %s") % [mini(days, ADVANCE_CAP), opp.get("short", "?")]


func _refresh_badges() -> void:
	if _nav_badges.has("inbox"):
		var unread := GameState.unread_inbox_count()
		var b: Label = _nav_badges["inbox"]
		b.visible = unread > 0
		b.text = str(unread)
	if _nav_badges.has("match"):
		var nf := GameState.next_player_fixture()
		var b2: Label = _nav_badges["match"]
		var today: bool = not nf.is_empty() and nf["date"] == GameState.current_date
		b2.visible = today
		if today:
			b2.text = "TODAY"


func _refresh_breadcrumb() -> void:
	if not screens.has(current_screen_name):
		return
	var meta: Dictionary = screens[current_screen_name]
	_crumb_chip.text = str(meta["icon_letter"])
	var league := str(GameState.world["meta"]["league_name"])
	var club := str(GameState.player_club().get("name", ""))
	_crumb_league_btn.text = league
	_crumb_league_btn.tooltip_text = tr("Open Competition — %s table & fixtures") % tr(league)
	_crumb_club_btn.text = club
	_crumb_club_btn.tooltip_text = tr("Open Squad — %s") % club
	_crumb_title.text = str(meta["title"])
	var has_tab := current_tab_id != "" and _tab_index(current_screen_name, current_tab_id) >= 0
	_crumb_tab_sep.visible = has_tab
	_crumb_tab_label.visible = has_tab
	if has_tab:
		_crumb_tab_label.text = _tab_title(current_screen_name, current_tab_id)


# ------------------------------------------------------------------ continue flow

func _on_continue() -> void:
	if _advancing:
		return
	AudioManager.play("continue")  # audio piece
	var nf := GameState.next_player_fixture()
	# A match is due today and being held for interactive play -> go there.
	if not nf.is_empty() and nf["date"] == GameState.current_date and not nf.get("played", false) \
			and not GameState.auto_sim_player_matches and screens.has("match"):
		navigate_to("match")
		return
	_advancing = true
	_continue_btn.disabled = true
	var spinner := ["·", "··", "···", "··"]
	var stop_reason := ""
	var played_fixture := {}
	for i in ADVANCE_CAP:
		var inbox_before: int = GameState.inbox.size()
		var day_events: Array = GameState.advance_day()
		for e in day_events:
			if e["t"] == "player_match_due":
				stop_reason = "match_due"
			elif e["t"] == "fixture_played":
				var f: Dictionary = e["fixture"]
				if GameState.is_player_club(f["home"]) or GameState.is_player_club(f["away"]):
					stop_reason = "played"
					played_fixture = f
		# stop on inbox items flagged urgent (or cup draws needing attention)
		var new_count: int = GameState.inbox.size() - inbox_before
		for j in new_count:
			var m: Dictionary = GameState.inbox[j]
			if m.get("urgent", false) or str(m.get("title", "")).begins_with("Cup draw") \
					or str(m.get("title", "")).begins_with(tr("Cup draw:")):
				if stop_reason == "":
					stop_reason = "urgent"
		_continue_main.text = tr("%s  ADVANCING") % spinner[i % spinner.size()]
		_continue_sub.text = I18n.pretty_date(GameState.current_date)
		await get_tree().create_timer(0.06).timeout
		if stop_reason != "":
			break
	GameState.save_game()
	_advancing = false
	_continue_btn.disabled = false
	_refresh_topbar()
	match stop_reason:
		"match_due":
			if screens.has("match"):
				navigate_to("match")
			_toast(tr("Matchday — your fixture is due today"))
		"played":
			_renavigate_current()
			var we_home: bool = GameState.is_player_club(played_fixture.get("home", ""))
			var us: int = int(played_fixture.get("score_home", 0)) if we_home else int(played_fixture.get("score_away", 0))
			var them: int = int(played_fixture.get("score_away", 0)) if we_home else int(played_fixture.get("score_home", 0))
			var opp := GameState.club(played_fixture.get("away", "") if we_home else played_fixture.get("home", ""))
			_toast(tr("Full time: won %d–%d vs %s — report in Inbox" if us > them
				else "Full time: lost %d–%d vs %s — report in Inbox") % [us, them, opp.get("name", "?")])
		"urgent":
			if screens.has("inbox"):
				navigate_to("inbox")
			_toast(tr("News needs your attention"))
		_:
			_renavigate_current()
			_toast(tr("Advanced to %s · game saved") % I18n.pretty_date(GameState.current_date))


func _renavigate_current() -> void:
	## Refresh the visible screen without polluting the history stack.
	if _history_pos >= 0 and _history_pos < _history.size():
		_history_jump()
	elif current_screen_name != "":
		navigate_to(current_screen_name)


# ------------------------------------------------------------------ save / load / new

func _on_menu_id(id: int) -> void:
	match id:
		0:
			if GameState.save_game():
				_toast(tr("Career saved · %s") % I18n.pretty_date(GameState.current_date))
			else:
				_toast(tr("Save failed"))
		1:
			if FileAccess.file_exists(GameState.SAVE_PATH):
				_load_confirm.popup_centered()
			else:
				_toast(tr("No save file found"))
		2:
			_open_onboarding()


func _build_dialogs() -> void:
	_load_confirm = ConfirmationDialog.new()
	_load_confirm.title = "Load Game"
	_load_confirm.dialog_text = "Reload the last saved career?\nUnsaved progress will be lost."
	_load_confirm.ok_button_text = "Load"
	_load_confirm.confirmed.connect(func():
		if GameState.load_game():
			_reset_history()
			if not screens.is_empty():
				navigate_to(screens.keys().front())
			_toast(tr("Career loaded · %s") % I18n.pretty_date(GameState.current_date))
		else:
			_toast(tr("Load failed")))
	add_child(_load_confirm)

	# "New Career" opens the FM-style club picker overlay instead of a plain
	# confirm — league tabs, one row per club (rep / balance / squad strength).
	_new_confirm = null


## In-game "New Career": the menu piece's FM-style onboarding wizard
## (manager identity -> club selection -> confirmation) over the shell.
## It starts + saves the career itself (MenuFlow.start_career), so the shell
## only refreshes its chrome afterwards.
func _open_onboarding() -> void:
	if _onboarding != null and is_instance_valid(_onboarding):
		return
	_onboarding = Onboarding.new()
	_onboarding.setup(_font_bold, _font_semibold, _font_header)
	_onboarding.career_created.connect(func():
		_onboarding = null
		_reset_history()
		if not screens.is_empty():
			navigate_to(screens.keys().front())
		_refresh_identity()
		_refresh_topbar()
		_toast(tr("New career started at %s · %s") %
			[GameState.player_club().get("name", ""), tr(GameState.league_name())]))
	_onboarding.cancelled.connect(func(): _onboarding = null)
	add_child(_onboarding)


## LEGACY club-only selector (kept for shell/picker_shots.tscn proof shots;
## live UI routes through _open_onboarding above).
func _open_club_picker() -> void:
	if _club_picker != null and is_instance_valid(_club_picker):
		return
	_club_picker = ClubPicker.new()
	_club_picker.setup(_font_bold, _font_semibold, _font_header)
	_club_picker.club_chosen.connect(func(club_id: String):
		if _club_picker != null and is_instance_valid(_club_picker):
			_club_picker.queue_free()
			_club_picker = null
		GameState.delete_save()
		GameState.new_career(20260801, club_id)
		GameState.save_game()
		_reset_history()
		if not screens.is_empty():
			navigate_to(screens.keys().front())
		_toast(tr("New career started at %s · %s") %
			[GameState.player_club().get("name", ""), tr(GameState.league_name())]))
	_club_picker.cancelled.connect(func(): _club_picker = null)
	add_child(_club_picker)


## The sacking moment (polish piece): modal career-summary overlay. The career
## continues at an offering club (GameState.accept_job_offer) or starts fresh
## through the normal club picker.
func _open_game_over() -> void:
	if _game_over != null and is_instance_valid(_game_over):
		return
	if not GameState.is_game_over():
		return
	# Kill the stadium/menu music before the SACKED overlay — upbeat chiptune
	# (or a roaring crowd, if the mail lands on the match screen) over a career
	# funeral is tonally wrong. Navigation after the overlay restores ambience.
	AudioManager.set_ambience("")
	AudioManager.play("error", -6.0, 0.8)
	_game_over = GameOverScreen.new()
	_game_over.setup(_font_bold, _font_semibold, _font_header)
	_game_over.offer_accepted.connect(func(club_id: String):
		var err: String = GameState.accept_job_offer(club_id)
		if err != "":
			return
		# the manager's own name follows them to the new club (menu piece —
		# board mails / press render the player club's "manager" field)
		var mn := str(GameState.world["meta"].get("manager_name", ""))
		if mn != "":
			GameState.player_club()["manager"] = mn
			GameState.save_game()
		if _game_over != null and is_instance_valid(_game_over):
			_game_over.queue_free()
			_game_over = null
		_reset_history()
		if screens.has("inbox"):
			navigate_to("inbox")
		elif not screens.is_empty():
			navigate_to(screens.keys().front())
		_toast(tr("You take over at %s · %s") %
			[GameState.player_club().get("name", ""), tr(GameState.league_name())]))
	_game_over.start_fresh.connect(func():
		if _game_over != null and is_instance_valid(_game_over):
			_game_over.queue_free()
			_game_over = null
		_open_onboarding())
	add_child(_game_over)


# ------------------------------------------------------------------ global search

func _build_search_overlay() -> void:
	_search_panel = PanelContainer.new()
	_search_panel.visible = false
	_search_panel.top_level = true
	_search_panel.z_index = 100
	_search_panel.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(ThemeBuilder.COL_PANEL_ALT, ThemeBuilder.COL_ACCENT_DIM, 6, 4, 4))
	_search_list = ItemList.new()
	_search_list.custom_minimum_size = Vector2(420, 100)
	_search_list.focus_mode = Control.FOCUS_NONE
	_search_list.allow_rmb_select = true
	# Left-click follows the result; right-click on a Pokémon result opens the
	# global action menu (offer / scout / shortlist / compare) in place.
	_search_list.item_clicked.connect(func(idx, _pos, btn):
		if btn == MOUSE_BUTTON_RIGHT:
			if idx >= 0 and idx < _search_results.size() \
					and str(_search_results[idx].get("kind", "")) == "pokemon" \
					and MonActions.can_act(str(_search_results[idx].get("id", ""))):
				MonActions.open_menu(self, str(_search_results[idx]["id"]))
			return
		_activate_search_index(idx))
	_search_panel.add_child(_search_list)
	add_child(_search_panel)


func _rebuild_search_index() -> void:
	_search_index.clear()
	# screens + their subsections are searchable destinations (FM lets you type
	# "fixtures" and land exactly there — so do we, via the same tab deep-link)
	for n in screens:
		var meta: Dictionary = screens[n]
		_search_index.append({
			"label": tr(str(meta["title"])),
			"sub": tr("Screen"),
			"screen": n,
			"color": ThemeBuilder.COL_ACCENT,
			"kind": "screen", "id": n,
		})
		for t in meta.get("tabs", []):
			_search_index.append({
				"label": tr(str(t["title"])),
				"sub": tr("Section · %s") % tr(str(meta["title"])),
				"screen": n,
				"color": ThemeBuilder.COL_ACCENT_DIM,
				"kind": "tab", "id": "%s/%s" % [n, t["id"]], "tab": str(t["id"]),
			})
	for c in GameState.world["clubs"]:
		var mine: bool = GameState.is_player_club(c["id"])
		_search_index.append({
			"label": str(c["name"]),
			"sub": tr("Club · %s · manager %s · rep %d") % [c["short"], c["manager"], int(c["reputation"])],
			"screen": "competition",
			"color": DataStore.type_color(_club_primary_type(c)),
			"kind": "club", "id": c["id"], "tab": "table",
		})
		for inst in c["squad"]:
			_search_index.append(_pokemon_entry(inst,
				"squad" if mine else "competition",
				(tr("%s · your squad") % c["short"]) if mine else str(c["name"]),
				"General" if mine else "table"))
	for inst in GameState.free_agents():
		_search_index.append(_pokemon_entry(inst, "transfers", tr("Free agent"), "search"))
	for inst in GameState.prospects():
		_search_index.append(_pokemon_entry(inst, "transfers", tr("Youth prospect"), "scouting"))


func _pokemon_entry(inst: Dictionary, screen: String, where: String, tab: String = "") -> Dictionary:
	var nick = inst.get("nickname")
	var display: String = str(nick) if nick != null and str(nick) != "" else str(inst["species"])
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var types: Array = sp.get("types", ["Normal"])
	var entry := {
		"label": display,
		"sub": tr("Lv %d %s · %s · %s") % [int(inst["level"]), inst["species"], I18n.types_join(types), where],
		"screen": screen,
		"color": DataStore.type_color(str(types[0])),
		"kind": "pokemon", "id": inst["uid"],
	}
	if tab != "" and _tab_index(screen, tab) >= 0:
		entry["tab"] = tab
	return entry


func _type_icon(col: Color) -> ImageTexture:
	var key := col.to_html()
	if _type_icon_cache.has(key):
		return _type_icon_cache[key]
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(col)
	var tex := ImageTexture.create_from_image(img)
	_type_icon_cache[key] = tex
	return tex


func _on_search_text(text: String) -> void:
	var q := text.strip_edges().to_lower()
	_search_results.clear()
	_search_list.clear()
	if q.length() < 2:
		_search_panel.visible = false
		return
	for entry in _search_index:
		if entry["label"].to_lower().contains(q) or entry["sub"].to_lower().contains(q):
			_search_results.append(entry)
			if _search_results.size() >= 9:
				break
	if _search_results.is_empty():
		_search_list.add_item(tr("No results for \"%s\"") % text, null, false)
	else:
		for entry in _search_results:
			var idx := _search_list.add_item("%s    —  %s" % [entry["label"], entry["sub"]], _type_icon(entry["color"]))
			var dest: String = tr(str(screens.get(entry["screen"], {}).get("title", entry["screen"])))
			if entry.has("tab"):
				dest += " › %s" % tr(_tab_title(entry["screen"], str(entry["tab"])))
			var tip: String = tr("Open %s") % dest
			if str(entry.get("kind", "")) == "pokemon":
				tip += "\n" + tr("Right-click: offer, scout, shortlist...")
			_search_list.set_item_tooltip(idx, tip)
	if not _search_results.is_empty():
		_search_list.select(0)
	var rows: int = maxi(_search_list.item_count, 1)
	_search_list.custom_minimum_size = Vector2(460, rows * 26 + 8)
	_search_panel.global_position = _search.get_global_rect().position + Vector2(0, _search.size.y + 4)
	_search_panel.reset_size()
	_search_panel.visible = true


func _on_search_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_close_search()
			accept_event()
		elif event.keycode == KEY_DOWN or event.keycode == KEY_UP:
			if _search_list.item_count > 0:
				var cur := 0
				var sel := _search_list.get_selected_items()
				if sel.size() > 0:
					cur = sel[0]
				var next: int = clampi(cur + (1 if event.keycode == KEY_DOWN else -1), 0, _search_list.item_count - 1)
				_search_list.select(next)
			accept_event()


func _on_search_focus_exited() -> void:
	await get_tree().process_frame
	if not _search_list.has_focus():
		_search_panel.visible = false


func _activate_search_selection() -> void:
	var sel := _search_list.get_selected_items()
	_activate_search_index(sel[0] if sel.size() > 0 else 0)


func _activate_search_index(idx: int) -> void:
	if idx < 0 or idx >= _search_results.size():
		_close_search()
		return
	var entry: Dictionary = _search_results[idx]
	_close_search()
	if not screens.has(entry["screen"]):
		_toast(tr("No screen available for %s yet") % entry["label"])
		return
	navigate_to(entry["screen"], entry)
	var dest: String = tr(str(screens[entry["screen"]]["title"]))
	if entry.has("tab"):
		dest += " › %s" % tr(_tab_title(entry["screen"], str(entry["tab"])))
	_toast("%s  »  %s" % [entry["label"], dest])


func _close_search() -> void:
	_search_panel.visible = false
	_search.clear()
	_search.release_focus()


# ------------------------------------------------------------------ toast

func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.visible = false
	_toast_panel.top_level = true
	_toast_panel.z_index = 200
	_toast_panel.add_theme_stylebox_override("panel",
		ThemeBuilder._flat(Color("242b48"), ThemeBuilder.COL_ACCENT, 6, 14, 8))
	_toast_label = Label.new()
	_toast_label.add_theme_font_override("font", _font_semibold)
	_toast_label.add_theme_font_size_override("font_size", 13)
	_toast_label.add_theme_color_override("font_color", Color.WHITE)
	_toast_panel.add_child(_toast_label)
	add_child(_toast_panel)


## Public toast — shared components (e.g. MonActions, the global Pokémon
## action layer) confirm their actions through the shell's toast.
func toast(msg: String) -> void:
	_toast(msg)


func _toast(msg: String) -> void:
	_toast_label.text = msg
	_toast_panel.visible = true
	_toast_panel.modulate.a = 0.0
	_toast_panel.reset_size()
	var vp := get_viewport_rect().size
	_toast_panel.global_position = Vector2(vp.x - _toast_panel.size.x - 24, vp.y - _toast_panel.size.y - 24)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func(): _toast_panel.visible = false)


# ------------------------------------------------------------------ shortcuts

func _unhandled_input(event: InputEvent) -> void:
	# mouse side buttons = browser/FM-style back & forward
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_XBUTTON1:
			go_back()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_XBUTTON2:
			go_forward()
			accept_event()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if event.is_command_or_control_pressed():
		if key == KEY_S:
			_on_menu_id(0)
			accept_event()
		elif key == KEY_F:
			_search.grab_focus()
			accept_event()
		elif key == KEY_BRACKETLEFT:
			go_back()
			accept_event()
		elif key == KEY_BRACKETRIGHT:
			go_forward()
			accept_event()
		elif key >= KEY_1 and key <= KEY_9:
			# Ctrl+number = jump to the Nth subsection of the current screen
			var tabs := _screen_tabs(current_screen_name)
			var ti: int = key - KEY_1
			if ti < tabs.size():
				navigate_to(current_screen_name, {"kind": "tab",
					"tab": str(tabs[ti]["id"]), "label": str(tabs[ti]["title"])})
				accept_event()
		return
	if event.alt_pressed:
		if key == KEY_LEFT:
			go_back()
			accept_event()
		elif key == KEY_RIGHT:
			go_forward()
			accept_event()
		return
	if key == KEY_SPACE:
		_on_continue()
		accept_event()
	elif key == KEY_SLASH:
		_search.grab_focus()
		accept_event()
	elif key >= KEY_1 and key <= KEY_9:
		var idx: int = key - KEY_1
		if idx < _nav_order.size():
			navigate_to(_nav_order[idx])
			accept_event()


# ------------------------------------------------------------------ helpers

func _days_until(date: String) -> int:
	return int((_unix(date) - _unix(GameState.current_date)) / 86400.0)


func _unix(date: String) -> int:
	var parts := date.split("-")
	return Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]),
		"day": int(parts[2]), "hour": 12, "minute": 0, "second": 0})


func _weekday(date: String) -> String:
	var d := Time.get_datetime_dict_from_unix_time(_unix(date))
	return tr(WEEKDAYS[int(d["weekday"]) % 7])


func _season_week() -> int:
	return maxi(1, _days_until_from(GameState.season_start, GameState.current_date) / 7 + 1)


func _days_until_from(a: String, b: String) -> int:
	return int((_unix(b) - _unix(a)) / 86400.0)


func _days_phrase(days: int) -> String:
	if days <= 0:
		return tr("TODAY")
	if days == 1:
		return tr("tomorrow")
	return tr("in %d days") % days


func _comp_name(f: Dictionary) -> String:
	if str(f.get("comp", "")) == "cup":   # name the competition, not just the round
		return "%s %s" % [tr(GameState.cup_name()), I18n.cup_round(int(f.get("round", 1)))]
	if str(f.get("comp", "")) == "playoff":   # Championship Series (season-end playoff)
		return tr("CS %s") % I18n.playoff_round(int(f.get("round", 1)))
	return tr(GameState.world["meta"]["league_name"])


func _thousands(n: int) -> String:
	return ("-" if n < 0 else "") + I18n.number(absi(n))


func _ordinal(n: int) -> String:
	if n <= 0:
		return "—"
	return I18n.ordinal(n)
