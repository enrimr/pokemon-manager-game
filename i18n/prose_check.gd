extends Node
## Spanish-prose leak check (spanish piece). Boots a FRESH career with the
## locale forced to es, advances deep into the season, runs the inbox
## generators exactly like the Inbox screen does, renders every message body
## through the real renderers, and fails on any raw English token that the
## blind critic flagged (types, natures, months, cup rounds, W/L letters,
## ISO dates, EN number formats). Run:
##   godot --headless --path . res://i18n/prose_check.tscn
## Restores the player's save before quitting. Prints PROSE CHECK OK.

const SaveGuard := preload("res://tools/save_guard.gd")

const FORBIDDEN := [
	"BASIC FACILITIES", "Basic Facilities", "Adequate Facilities",
	"First Round", "Second Round", "Quarter-Final", "Semi-Final",
	" in the league", "yet to play",
	"tipo Psychic", "tipo Flying", "tipo Water", "tipo Grass",
	"PSYCHIC", "FLYING", "GRASS", "POISON", "ELECTRIC", "FIGHTING",
	"Attack +", "Defense +", "Sp. Atk +", "Sp. Def +", "Speed +", "HP +",
	"Timid", "Adamant", "Jolly", "Naive", "Rash", "Brave", "Mild",
	"Sleep Powder", "Mega Drain", "Fire Spin", "Solar Beam", "Body Slam",
	"Leftovers", "(OVER BUDGET)", " won,", "RACHA W", " W  W ", "KO'd",
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		push_error("prose_check: GameState autoload missing")
		get_tree().quit(1)
		return
	SaveGuard.backup()
	TranslationServer.set_locale("es")
	gs.new_career(20260801)
	for i in 46:
		gs.advance_day()

	# wire the generators exactly like screens/inbox/screen.gd does
	var news: RefCounted = (load("res://screens/inbox/news_gen.gd") as GDScript).new()
	var economy: RefCounted = (load("res://screens/inbox/economy.gd") as GDScript).new(news)
	var board: RefCounted = (load("res://screens/inbox/board_room.gd") as GDScript).new(news)
	board.economy = economy
	var people: RefCounted = (load("res://screens/inbox/people_gen.gd") as GDScript).new(news)
	var reports: RefCounted = (load("res://screens/inbox/report_gen.gd") as GDScript).new(news)
	reports.board = board
	reports.economy = economy
	reports.people = people
	reports.evolutions = (load("res://screens/inbox/evolution_gen.gd") as GDScript).new()
	news.enrich_existing()
	news.generate()
	people.generate()
	economy.tick()
	board.tick()

	var bad := 0
	var seen_kinds := {}
	for m in gs.inbox:
		var rendered: Dictionary = reports.render(m)
		var blob: String = str(m.get("title", "")) + "\n" + str(rendered.get("bbcode", ""))
		for a in rendered.get("actions", []):
			blob += "\n" + str(a.get("label", ""))
		var tag := str(m.get("academy_kind", m.get("cat", "?")))
		if OS.get_environment("PROSE_DUMP") == "1" and not seen_kinds.has(tag):
			print("\n===== SAMPLE [%s] =====\n%s\n" % [tag, blob.left(1400)])
		seen_kinds[tag] = true
		bad += _scan(blob, "inbox[%s] %s" % [tag, str(m.get("title", ""))])
	print("prose_check: rendered %d inbox messages (%s)" % [gs.inbox.size(),
		", ".join(seen_kinds.keys())])

	# operating ledger (the Board & Finances rows the critic quoted)
	var rows: Array = board.ledger_rows(200)
	for r in rows:
		bad += _scan(str(r["text"]), "ledger %s" % str(r["date"]))
	print("prose_check: scanned %d ledger rows" % rows.size())

	# ordinals + numbers must be es-formatted
	var ord := I18n.ordinal(9)
	if ord != "9.º":
		push_error("prose_check: es ordinal wrong: " + ord)
		bad += 1
	if I18n.number(1356000) != "1.356.000":
		push_error("prose_check: es number grouping wrong: " + I18n.number(1356000))
		bad += 1
	if I18n.decimal(1.5, 1) != "1,5":
		push_error("prose_check: es decimal wrong: " + I18n.decimal(1.5, 1))
		bad += 1

	if OS.get_environment("PROSE_KEEP_SAVE") == "1":
		# screenshot prep: leave the deep-season es career in the save slot
		# (caller deletes user://save.json afterwards to keep user data clean)
		gs.save_game()
	else:
		SaveGuard.restore()
	if bad > 0:
		print("PROSE CHECK FAILED: %d leaks" % bad)
		get_tree().quit(1)
		return
	print("PROSE CHECK OK")
	get_tree().quit(0)


func _scan(blob: String, label: String) -> int:
	var hits := 0
	for tok in FORBIDDEN:
		if blob.contains(str(tok)):
			print("  LEAK [%s] contains %s" % [label, str(tok)])
			print("    > " + blob.substr(maxi(0, blob.find(str(tok)) - 60), 160).replace("\n", " "))
			hits += 1
	var iso := RegEx.create_from_string("\\d{4}-\\d{2}-\\d{2}")
	var mm := iso.search(blob)
	if mm != null:
		print("  LEAK [%s] ISO date %s" % [label, mm.get_string()])
		print("    > " + blob.substr(maxi(0, blob.find(mm.get_string()) - 60), 160).replace("\n", " "))
		hits += 1
	var months := RegEx.create_from_string("\\b(January|February|March|April|June|July|August|September|October|November|December)\\b")
	var mo := months.search(blob)
	if mo != null:
		print("  LEAK [%s] English month %s" % [label, mo.get_string()])
		print("    > " + blob.substr(maxi(0, blob.find(mo.get_string()) - 60), 160).replace("\n", " "))
		hits += 1
	return hits
