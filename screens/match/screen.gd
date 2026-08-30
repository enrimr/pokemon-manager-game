extends Control
## Match screen — the player match-day flow. Phases:
##   IDLE (no match due)  ->  PRE (scout + lineup)  ->  LIVE (best-of-3
##   replayed turn-by-turn with touchline control)  ->  POST (report).
## Match state lives in MatchRunner (static) so the shell can freely
## re-instance this screen without losing a match in progress.

const MatchRunner := preload("res://screens/match/match_runner.gd")
const IdleView := preload("res://screens/match/idle_view.gd")
const PrematchView := preload("res://screens/match/prematch_view.gd")
const LiveView := preload("res://screens/match/live_view.gd")
const PostmatchView := preload("res://screens/match/postmatch_view.gd")


func _ready() -> void:
	_maybe_setup_demo()
	_render()


func _render() -> void:
	for c in get_children():
		c.queue_free()

	var runner = MatchRunner.active
	if runner != null and runner.fixture.get("played", false) and not runner.recorded \
			and not runner.exhibition:
		# Fixture got resolved elsewhere (stale runner) — drop it.
		MatchRunner.clear()
		runner = null
	if runner == null:
		var f: Dictionary = MatchRunner.pending_fixture()
		if not f.is_empty():
			runner = MatchRunner.begin(f)
	if runner == null:
		add_child(IdleView.new())
		return

	match runner.phase:
		MatchRunner.Phase.PRE:
			var pre: Control = PrematchView.new()
			pre.setup(runner)
			pre.start_live.connect(func(manual: bool):
				runner.set_policy("full_control", manual)
				runner.confirm_lineup()
				_render())
			pre.instant_result.connect(func():
				runner.instant_result()
				_render())
			add_child(pre)
		MatchRunner.Phase.LIVE:
			var live: Control = LiveView.new()
			live.setup(runner)
			live.request_post.connect(_render)
			add_child(live)
		MatchRunner.Phase.POST:
			var post: Control = PostmatchView.new()
			post.setup(runner)
			post.done.connect(_finish)
			add_child(post)


func _finish() -> void:
	MatchRunner.clear()
	var shell := _find_shell()
	if shell != null and shell.screens.has("inbox"):
		shell.navigate_to("inbox")
	else:
		_render()


func _find_shell() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("navigate_to") and "screens" in n:
			return n
		n = n.get_parent()
	return null


# ------------------------------------------------------------------ demo hook
# For screenshot/QA runs only: `--match-demo=pre|live|post` fabricates an
# exhibition match against the next fixture opponent. Never writes results.

func _maybe_setup_demo() -> void:
	var kind := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--match-demo="):
			kind = a.substr(13)
	if kind == "" or MatchRunner.active != null:
		return
	var f: Dictionary = GameState.next_player_fixture()
	if f.is_empty():
		return
	var runner = MatchRunner.begin(f)
	runner.exhibition = true
	match kind:
		"live":
			# Watch mode: coach drives, stage plays out on its own.
			runner.set_policy("full_control", false)
			runner.confirm_lineup()
			var seen := 0
			while seen < 200:
				var e: Dictionary = runner.consume_next()
				if e.is_empty():
					break
				seen += 1
				# stop on a turn boundary so both actives are standing for capture
				if seen >= 110 and str(e.get("t", "")) == "turn_start":
					break
			runner.set_meta("demo_pause", true)  # pose the stage for capture
		"input":
			# Manual combat (the default flow): halt at the action bar.
			runner.set_policy("full_control", false)
			runner.confirm_lineup()
			runner.set_policy("aggression", "attacking")
			runner.set_policy("switching", "eager")
			for i in 30:
				if runner.consume_next().is_empty():
					break
			runner.set_policy("aggression", "balanced")
			runner.set_policy("full_control", true)
			for i in 200:
				if runner.consume_next().is_empty():
					break
		"post":
			runner.instant_result()
		_:
			pass  # "pre" — stay in PRE phase
