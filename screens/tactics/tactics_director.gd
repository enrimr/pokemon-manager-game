extends Node
## TacticsDirector — the piece of the tactics module that makes the plan
## COMMAND matches instead of describing them. Installed at boot (see
## screen.gd's _static_init; the shell loads that script during nav discovery)
## and again defensively whenever the Tactics screen opens.
##
## Consumption paths it wires up, without touching any other piece's files:
##
## 1. LIVE / MATCH-SCREEN FLOW — when the player's fixture comes due, this
##    node creates the MatchRunner FIRST (public static API of the match
##    piece) and stamps it: starting_six = the plan's lineup in battle order,
##    policy = the plan's instructions mapped onto the runner's touchline
##    vocabulary. The match screen then builds its pre-match UI from that
##    runner, so the XI the manager picked on this screen is the XI on the
##    team sheet — for the live match AND the runner's "instant result".
##
## 2. INSTANT SIM FALLBACK — if a player fixture is resolved by
##    GameState._play_fixture (Season.pick_team, level-order team), this node
##    re-resolves it during the fixture_played emission with the plan's
##    lineup and TacticsBrain driving every turn (same fixture seed, still
##    deterministic), overwriting the score in place before the league table
##    or the inbox report read it.
##
## 3. PLAN REFRESH — the Tactics screen calls stamp_pending_runner(force)
##    after every save so a pending, not-yet-confirmed lineup follows edits.

const Logic := preload("res://screens/tactics/tactics_logic.gd")
const Brain := preload("res://screens/tactics/tactics_brain.gd")

const MATCH_RUNNER_PATH := "res://screens/match/match_runner.gd"
const NODE_NAME := "TacticsDirector"


# ------------------------------------------------------------------ install

static func install() -> void:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var root: Node = (ml as SceneTree).root
	if root == null or root.has_node(NODE_NAME) or root.get_node_or_null("GameState") == null:
		return
	var d: Node = (load("res://screens/tactics/tactics_director.gd") as GDScript).new()
	d.name = NODE_NAME
	root.add_child(d)


static func installed() -> bool:
	var ml := Engine.get_main_loop()
	return ml is SceneTree and (ml as SceneTree).root != null \
		and (ml as SceneTree).root.has_node(NODE_NAME)


func _ready() -> void:
	GameState.player_match_due.connect(_on_player_match_due)
	GameState.date_changed.connect(_on_date_changed)
	GameState.fixture_played.connect(_on_fixture_played)
	GameState.career_started.connect(_on_career_started)
	_publish_from_disk_if_needed()
	# Safety net: a runner created by a path we don't hear about (e.g. the
	# match screen itself) still gets the plan while it sits in pre-match.
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(func(): stamp_pending_runner(false, false))
	add_child(t)


func _on_career_started() -> void:
	_publish_from_disk_if_needed()


## Careers saved before the tactics link existed (or fresh boots) still get
## their plan: republish user://tactics.json into world.meta without saving.
func _publish_from_disk_if_needed() -> void:
	if not active_plan().is_empty():
		return
	if not FileAccess.file_exists(Logic.TACTICS_PATH):
		return
	if GameState.player_club().get("squad", []).is_empty():
		return
	Logic.apply_to_gamestate(Logic.load_state(), false)


# ------------------------------------------------------------------ plan access

static func active_plan() -> Dictionary:
	var meta: Dictionary = GameState.world.get("meta", {})
	var tac: Variant = meta.get("tactics")
	return tac if tac is Dictionary and not (tac as Dictionary).get("lineup", []).is_empty() else {}


static func _runner_script() -> GDScript:
	if not ResourceLoader.exists(MATCH_RUNNER_PATH):
		return null
	return load(MATCH_RUNNER_PATH)


# ------------------------------------------------------------------ live flow

func _on_player_match_due(_fixture: Dictionary) -> void:
	# Runs synchronously during advance_day — before the match screen's
	# deferred navigation instantiates its pre-match view — so the runner is
	# born already carrying the plan.
	stamp_pending_runner(true, false)


func _on_date_changed(_date: String) -> void:
	stamp_pending_runner(true, false)


## Ensure the pending player fixture's MatchRunner exists and carries the
## published plan. `create`: begin the runner ourselves if the fixture is due.
## `force`: re-stamp even if already stamped (tactics screen after a save).
static func stamp_pending_runner(create: bool, force: bool) -> void:
	var tac := active_plan()
	if tac.is_empty():
		return
	var mr := _runner_script()
	if mr == null:
		return
	var runner: Variant = mr.active
	if runner == null and create:
		var f: Dictionary = mr.pending_fixture()
		if f.is_empty():
			return
		runner = mr.begin(f)
	if runner == null:
		return
	if bool(runner.exhibition) or int(runner.phase) != 0:   # 0 == Phase.PRE
		return
	if runner.has_meta("tactics_plan") and not force:
		return
	runner.set_meta("tactics_plan", str(tac.get("name", "")))
	var six: Array = Logic.lineup_instances(tac, runner.player_club())
	if not six.is_empty():
		runner.starting_six = six
	var pol: Dictionary = Logic.instructions_to_policy(tac.get("instructions", {}))
	runner.policy["aggression"] = pol["aggression"]
	runner.policy["switching"] = pol["switching"]


# ------------------------------------------------------------------ instant sim

func _on_fixture_played(f: Dictionary) -> void:
	if not (GameState.is_player_club(str(f.get("home", ""))) or GameState.is_player_club(str(f.get("away", "")))):
		return
	var tac := active_plan()
	if tac.is_empty():
		return
	# Results decided on the match screen already used the stamped lineup
	# (exhibition runners never write results, so they don't count).
	var mr := _runner_script()
	if mr != null and mr.active != null and not bool(mr.active.exhibition) \
			and str(mr.active.fixture.get("id", "")) == str(f.get("id", "!")):
		return
	resolve_with_plan(f, tac)


## Re-resolve an auto-simmed player fixture with the plan's lineup, battle
## order and instructions (TacticsBrain drives our side every turn). Same
## deterministic seed formula as GameState._play_fixture; scores are
## overwritten in place mid-emission, so the league table, inbox report and
## every listener read the plan-driven result.
static func resolve_with_plan(f: Dictionary, tac: Dictionary) -> Dictionary:
	var home: Dictionary = GameState.club(str(f.get("home", "")))
	var away: Dictionary = GameState.club(str(f.get("away", "")))
	if home.is_empty() or away.is_empty():
		return {}
	var our_side := 0 if GameState.is_player_club(str(f["home"])) else 1
	var seed_v: int = GameState.career_seed + absi(str(f["id"]).hash()) % 1000000
	var res: Dictionary = Brain.run_fixture(home, away, our_side, tac, seed_v)
	if res.is_empty():
		return {}
	f["score_home"] = res["score_home"]
	f["score_away"] = res["score_away"]
	GameState._table_dirty = true
	return res
