extends Node
## MatchDirector — installed at boot (windowed runs only) by BattleEngine's
## static init, using GameState's documented hooks:
##   auto_sim_player_matches = false  +  player_match_due
## Ensures the game stops on the player's match day and pulls the shell to
## the Match screen, even if the player has never opened it.

const MatchRunner := preload("res://screens/match/match_runner.gd")

var _queued := false


func _ready() -> void:
	GameState.auto_sim_player_matches = false
	GameState.player_match_due.connect(_on_match_due)
	GameState.date_changed.connect(_on_date_changed)
	GameState.career_started.connect(func(): MatchRunner.clear())


func _on_match_due(_fixture: Dictionary) -> void:
	_queue_nav()


func _on_date_changed(_date: String) -> void:
	# A pending (skipped) match also drags the manager back to the dugout.
	if MatchRunner.pending_fixture().is_empty():
		return
	_queue_nav()


func _queue_nav() -> void:
	if _queued:
		return
	_queued = true
	_navigate.call_deferred()


func _navigate() -> void:
	_queued = false
	if MatchRunner.pending_fixture().is_empty():
		return
	var shell := _find_shell()
	if shell != null and shell.screens.has("match"):
		shell.navigate_to("match")


func _find_shell() -> Node:
	for c in get_tree().root.get_children():
		if c.has_method("navigate_to") and "screens" in c:
			return c
	return null
