extends Node
## Autoload: GameState
## The single source of truth for a running career: world data, calendar,
## fixtures, league table, inbox. Screens read from here and connect to
## the signals below. Piece-builders: use the public API, never mutate
## `fixtures`/`world` structurally without going through it.

signal career_started
signal date_changed(new_date: String)
signal fixture_played(fixture: Dictionary)
signal table_updated
signal inbox_updated
signal player_match_due(fixture: Dictionary)

const SAVE_PATH := "user://save.json"

var world: Dictionary = {}          # deep-copied from world.json, mutated over time
var current_date: String = ""
var season_start: String = ""
var fixtures: Array = []            # league + generated cup fixtures
var cup_round: int = 0              # highest cup round generated so far
var inbox: Array = []               # [{date, title, body, read}]
var career_seed: int = 0
var auto_sim_player_matches := true # match piece can set false and intercept

var _clubs_by_id: Dictionary = {}
var _table_cache: Array = []
var _table_dirty := true


func _ready() -> void:
	# Boot into a playable state: load save if present, else new career.
	# (Deferred so DataStore's _ready has definitely run first.)
	if not load_game():
		new_career()


# ------------------------------------------------------------------ lifecycle

func new_career(seed_value: int = 20260801) -> void:
	career_seed = seed_value
	var f := FileAccess.open("res://shared/data/world.json", FileAccess.READ)
	world = JSON.parse_string(f.get_as_text())
	_index_clubs()
	season_start = world["meta"]["season_start"]
	current_date = season_start
	fixtures = Season.make_league_fixtures(club_ids(), season_start)
	cup_round = 1
	fixtures += Season.make_cup_round(club_ids(), 1, Season.cup_round_date(season_start, 1), career_seed)
	inbox = []
	add_inbox_message(current_date, "Welcome to %s" % player_club()["name"],
		"The board expects a solid mid-table finish in the %s. Your first fixture is on %s." %
		[world["meta"]["league_name"], Season.pretty_date(next_player_fixture().get("date", season_start))])
	_table_dirty = true
	career_started.emit()
	date_changed.emit(current_date)
	table_updated.emit()


func save_game() -> bool:
	var data := {
		"version": 1,
		"career_seed": career_seed,
		"current_date": current_date,
		"season_start": season_start,
		"cup_round": cup_round,
		"world": world,
		"fixtures": fixtures,
		"inbox": inbox,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot write save file")
		return false
	f.store_string(JSON.stringify(data))
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null or typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != 1:
		push_warning("GameState: ignoring incompatible save file")
		return false
	career_seed = int(data["career_seed"])
	current_date = data["current_date"]
	season_start = data["season_start"]
	cup_round = int(data["cup_round"])
	world = data["world"]
	fixtures = data["fixtures"]
	inbox = data["inbox"]
	_index_clubs()
	_table_dirty = true
	career_started.emit()
	date_changed.emit(current_date)
	table_updated.emit()
	return true


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ------------------------------------------------------------------ queries

func club_ids() -> Array:
	return world["clubs"].map(func(c): return c["id"])


func club(id: String) -> Dictionary:
	return _clubs_by_id.get(id, {})


func player_club() -> Dictionary:
	return club(world["meta"]["player_club_id"])


func is_player_club(id: String) -> bool:
	return id == world["meta"]["player_club_id"]


func league_table() -> Array:
	if _table_dirty:
		_table_cache = Season.compute_table(club_ids(), fixtures)
		_table_dirty = false
	return _table_cache


func player_table_position() -> int:
	var t := league_table()
	for i in t.size():
		if is_player_club(t[i]["club_id"]):
			return i + 1
	return 0


func fixtures_on(date: String) -> Array:
	return fixtures.filter(func(f): return f["date"] == date)


func next_player_fixture() -> Dictionary:
	var pid: String = world["meta"]["player_club_id"]
	for f in fixtures:
		if not f["played"] and (f["home"] == pid or f["away"] == pid):
			return f
	return {}


func player_fixtures() -> Array:
	var pid: String = world["meta"]["player_club_id"]
	return fixtures.filter(func(f): return f["home"] == pid or f["away"] == pid)


func free_agents() -> Array:
	return world["free_agents"]


func prospects() -> Array:
	return world["prospects"]


func unread_inbox_count() -> int:
	return inbox.filter(func(m): return not m.get("read", false)).size()


# ------------------------------------------------------------------ time

## Advance the calendar one day; sim any fixtures due. Returns events of the day.
func advance_day() -> Array:
	current_date = Season.date_add(current_date, 1)
	var day_events: Array = []
	for f in fixtures_on(current_date):
		if f["played"]:
			continue
		var involves_player: bool = is_player_club(f["home"]) or is_player_club(f["away"])
		if involves_player and not auto_sim_player_matches:
			player_match_due.emit(f)
			day_events.append({"t": "player_match_due", "fixture": f})
			continue
		_play_fixture(f)
		day_events.append({"t": "fixture_played", "fixture": f})
	_maybe_generate_next_cup_round()
	date_changed.emit(current_date)
	return day_events


## Continue button behaviour: advance until something notable happens
## (player fixture played/due or new inbox item), capped at `max_days`.
func advance_to_next_event(max_days: int = 14) -> void:
	var pid: String = world["meta"]["player_club_id"]
	var stop := false
	for i in max_days:
		var day_events := advance_day()
		for e in day_events:
			if e["t"] == "player_match_due":
				stop = true
			elif e["t"] == "fixture_played":
				var f: Dictionary = e["fixture"]
				if f["home"] == pid or f["away"] == pid:
					stop = true
		if stop:
			break
	save_game()


func _play_fixture(f: Dictionary) -> void:
	var seed_v: int = career_seed + absi(str(f["id"]).hash()) % 1000000
	var result := Season.simulate_fixture(club(f["home"]), club(f["away"]), seed_v)
	f["played"] = true
	f["score_home"] = result["score_home"]
	f["score_away"] = result["score_away"]
	_table_dirty = true
	fixture_played.emit(f)
	table_updated.emit()
	if is_player_club(f["home"]) or is_player_club(f["away"]):
		var we_home := is_player_club(f["home"])
		var us: int = f["score_home"] if we_home else f["score_away"]
		var them: int = f["score_away"] if we_home else f["score_home"]
		var opp: String = club(f["away"] if we_home else f["home"])["name"]
		var verdict := "won" if us > them else "lost"
		add_inbox_message(current_date, "Match report: %d-%d vs %s" % [us, them, opp],
			"We %s the %s tie against %s, %d-%d in battles." % [verdict, f["comp"], opp, us, them])


func _maybe_generate_next_cup_round() -> void:
	var current := fixtures.filter(func(f): return f["comp"] == "cup" and int(f["round"]) == cup_round)
	if current.is_empty() or current.any(func(f): return not f["played"]):
		return
	if current.size() <= 1:
		return  # final played, cup over
	var winners: Array = current.map(func(f):
		return f["home"] if f["score_home"] > f["score_away"] else f["away"])
	cup_round += 1
	fixtures += Season.make_cup_round(winners, cup_round,
		Season.cup_round_date(season_start, cup_round), career_seed + cup_round)
	add_inbox_message(current_date, "Cup draw: %s" % Season.cup_round_name(cup_round),
		"The %s draw has been made." % Season.cup_round_name(cup_round))


# ------------------------------------------------------------------ inbox

func add_inbox_message(date: String, title: String, body: String) -> void:
	inbox.push_front({"date": date, "title": title, "body": body, "read": false})
	inbox_updated.emit()


func _index_clubs() -> void:
	_clubs_by_id.clear()
	for c in world["clubs"]:
		_clubs_by_id[c["id"]] = c
