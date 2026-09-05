extends Node
## Headless layout check for the pre-match view (user bug 2026-09-05: Spanish
## strings forced the right column past the viewport). Mounts PrematchView at
## the shell's real content width in BOTH locales and fails if any visible
## control's rect crosses the right edge.
## Run: godot --headless --path . res://tools/prematch_overflow_check.tscn

const MatchRunner := preload("res://screens/match/match_runner.gd")
const PrematchView := preload("res://screens/match/prematch_view.gd")
const SaveGuard := preload("res://tools/save_guard.gd")

const CONTENT_SIZE := Vector2(1240, 780)   # 1600x900 canvas minus shell chrome

var _fail := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveGuard.backup()
	GameState.new_career(112233)
	var f: Dictionary = GameState.next_player_fixture()
	if f.is_empty():
		printerr("OVERFLOW CHECK FAIL: no player fixture")
		_finish(1)
		return
	for locale in ["es", "en"]:
		TranslationServer.set_locale(locale)
		var host := Control.new()
		host.custom_minimum_size = CONTENT_SIZE
		host.size = CONTENT_SIZE
		get_tree().root.add_child(host)
		MatchRunner.clear()
		var runner = MatchRunner.begin(f)
		var pre: Control = PrematchView.new()
		pre.setup(runner)
		host.add_child(pre)
		for i in 8:
			await get_tree().process_frame
		var worst := _max_right(pre)
		if worst > CONTENT_SIZE.x + 0.5:
			printerr("OVERFLOW CHECK FAIL [%s]: content reaches x=%.0f (limit %.0f)" % [locale, worst, CONTENT_SIZE.x])
			_fail = true
		else:
			print("  ok [%s]: widest control ends at x=%.0f (limit %.0f)" % [locale, worst, CONTENT_SIZE.x])
		host.queue_free()
		await get_tree().process_frame
	MatchRunner.clear()
	_finish(1 if _fail else 0)


func _max_right(n: Node) -> float:
	var worst := 0.0
	if n is Control and n.visible:
		worst = n.get_global_rect().end.x
	for c in n.get_children():
		worst = maxf(worst, _max_right(c))
	return worst


func _finish(code: int) -> void:
	SaveGuard.restore()
	if code == 0:
		print("PREMATCH OVERFLOW CHECK OK")
	get_tree().quit(code)
