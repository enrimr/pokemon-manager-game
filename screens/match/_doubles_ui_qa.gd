extends Node
## WINDOWED QA for the manual-doubles PRESENTATION layer (the round-1 critic's
## blocker: the action bar laid out off-screen in doubles). Boots the REAL
## shell, reaches game 2 of a cup tie (2v2 doubles) in manual mode, then:
##   - asserts the action bar is visible and FULLY INSIDE the viewport,
##   - drives both slots through the real buttons / target-picker popups,
##   - captures screenshots to artifacts/battle-depth/.
## Run: godot --path . res://screens/match/_doubles_ui_qa.tscn   (not headless)
## Prints "DOUBLES UI QA OK" and exits 0 on success.

const MatchRunner := preload("res://screens/match/match_runner.gd")
const Commentary := preload("res://screens/match/commentary.gd")
const SaveGuard := preload("res://tools/save_guard.gd")

var _fail := false
var _shell: Control


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		printerr("  QA FAIL: %s" % what)
		_fail = true


func _settle(frames := 12) -> void:
	for i in frames:
		await get_tree().process_frame


func _run() -> void:
	print("=== doubles UI QA: manual 2v2 in the real shell ===")
	SaveGuard.backup()
	GameState.new_career(20260830)
	var f: Dictionary = GameState.next_player_fixture()
	_check(not f.is_empty(), "player has an upcoming fixture")
	var r = MatchRunner.begin(f)
	r.exhibition = true
	r.fixture = r.fixture.duplicate(true)
	r.fixture["comp"] = "cup"
	r.fixture["round"] = 2
	r.set_policy("full_control", false)
	r.confirm_lineup()
	r.skip_battle()
	if not r.series_decided():
		r.next_battle()
	_check(r.doubles_now(), "game 2 is 2v2 doubles")
	r.set_policy("full_control", true)
	for i in 400:
		if r.consume_next().is_empty():
			break
	_check(r.awaiting_input(), "manual doubles halts for input")

	_shell = load("res://shell/main.tscn").instantiate()
	get_tree().root.add_child(_shell)
	await _settle()
	_check(_shell.navigate_to("match"), "shell navigates to the match screen")
	await _settle(20)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var picked_via_menu := false
	for step in 2:
		var bar: Control = _find_bar(_shell)
		_check(bar != null and bar.visible, "slot %d: action bar is visible" % (step + 1))
		if bar == null:
			break
		var rect: Rect2 = bar.get_global_rect()
		_check(rect.position.y >= 0.0 and rect.end.y <= vp.y + 0.5
			and rect.position.x >= 0.0 and rect.end.x <= vp.x + 0.5,
			"slot %d: bar FULLY on the %dx%d canvas (rect %s)" % [step + 1, vp.x, vp.y, rect])
		var moves: Control = bar.get_meta("moves_row")
		_check(moves.get_child_count() > 0, "slot %d: move buttons offered" % (step + 1))
		await _shot("doubles_ui_slot%d" % (step + 1))
		# drive the real controls: prefer the two-step target picker
		var mb := _first_menu_button(moves)
		if mb != null:
			mb.show_popup()
			await _settle(4)
			var pop := mb.get_popup()
			_check(pop.item_count >= 2, "slot %d: target picker lists both foes" % (step + 1))
			var prect := Rect2(pop.position, Vector2(pop.size))
			_check(prect.end.y <= vp.y + 40.0, "slot %d: target popup on-screen" % (step + 1))
			pop.hide()
			pop.id_pressed.emit(pop.get_item_id(0))
			picked_via_menu = true
		elif moves.get_child(0) is Button:
			(moves.get_child(0) as Button).pressed.emit()
		await _settle(6)
	_check(picked_via_menu, "at least one order went through the target picker")
	_check(r.live_state == MatchRunner.LiveState.REPLAYING, "both slots ordered -> turn executes")
	await _settle(100)   # let the live view replay the turn itself
	await _shot("doubles_ui_resolved")

	# Weather + ability presentation-path checks (commentary + stage + scoreboard).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wl: Array = Commentary.lines_for({"t": "weather_start", "kind": "rain",
		"source": "move", "pokemon": "Gyarados"}, {}, rng)
	_check(not wl.is_empty() and bool(wl[0]["key"]), "weather_start produces a KEY ticker line")
	_check(not Commentary.lines_for({"t": "weather_chip", "kind": "sand", "amount": 9,
		"max_hp": 144, "pokemon": "Tauros"}, {}, rng).is_empty(), "weather_chip produces a ticker line")
	var al: Array = Commentary.lines_for({"t": "ability_triggered", "effect": "sturdy",
		"pokemon": "Onix", "ability_name": "Sturdy"}, {}, rng)
	_check(not al.is_empty() and str(al[0]["text"]).contains("Sturdy"),
		"ability_triggered names the ability in commentary")
	_check(Commentary.is_key_event({"t": "weather_start", "kind": "sun"}),
		"weather_start counts as a key moment")
	r.vm["weather"] = "rain"
	r.vm["weather_turns"] = 4
	await _settle(30)    # next turn_start would clear it; grab the render now
	await _shot("doubles_ui_weather")

	MatchRunner.clear()
	GameState.delete_save()
	SaveGuard.restore()
	if _fail:
		printerr("DOUBLES UI QA FAILED")
		get_tree().quit(1)
	else:
		print("DOUBLES UI QA OK")
		get_tree().quit(0)


## The live view's action bar is the PanelContainer carrying the moves_row meta.
func _find_bar(n: Node) -> Control:
	if n is Control and n.has_meta("moves_row"):
		return n
	for c in n.get_children():
		var hit := _find_bar(c)
		if hit != null:
			return hit
	return null


func _first_menu_button(row: Control) -> MenuButton:
	for c in row.get_children():
		if c is MenuButton:
			return c
	return null


func _shot(tag: String) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("artifacts/battle-depth")
	DirAccess.make_dir_recursive_absolute(dir)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		_check(false, "viewport image for %s" % tag)
		return
	var path := dir.path_join("%s.png" % tag)
	_check(img.save_png(path) == OK, "screenshot saved: %s" % path)
