extends Node
## Surfacing verification: staged nature/ability reveal in Search detail,
## nature/ability filters, and the written report card.
##   Godot --path . res://screens/transfers/surf_shots.tscn

const Market := preload("res://screens/transfers/market.gd")
const OUT := "artifacts/surfacing"
const SETTLE := 12

var _shell: Control


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("res://").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)
	(load("res://tools/save_guard.gd") as GDScript).preserve_player_save()
	GameState.delete_save()
	if FileAccess.file_exists("user://transfers.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://transfers.json"))
	GameState.new_career()
	Market._inst = null
	var m: RefCounted = Market.instance()

	var targets: Array = m.all_targets().filter(func(t):
		return t["pool"] == "club" and not m.is_ext_uid(String(t["inst"]["uid"])))
	targets.sort_custom(func(a, b): return m.value_of(a["inst"]) > m.value_of(b["inst"]))
	var star: Dictionary = targets[0]
	var star_uid := String(star["inst"]["uid"])
	var part: Dictionary = targets[4]
	var part_uid := String(part["inst"]["uid"])
	# staged knowledge: one Detailed (ability confirmed), one Part scouted
	m.knowledge[star_uid] = 80.0
	m._generate_report(star_uid, String(m.player_scouts()[0]["name"]), false)
	m.knowledge[part_uid] = 55.0
	m._generate_report(part_uid, String(m.player_scouts()[0]["name"]), false)

	_shell = (load("res://shell/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_shell)
	await _settle()
	_shell.navigate_to("transfers")
	await _settle()
	var screen: Control = _shell._content.get_children().back()

	# Search: Detailed target selected — nature + confirmed ability in detail
	screen._selected_uid = star_uid
	screen._tabs.current_tab = 1
	screen._refresh_all()
	await _settle()
	await _shot(out_dir, "transfers_search_detailed")

	# Part-scouted target — nature revealed, ability still unconfirmed
	screen._selected_uid = part_uid
	screen._refresh_detail()
	await _settle()
	await _shot(out_dir, "transfers_search_part")

	# Full report on a nature-modified target — exact stats, nature-tinted
	# (+stat green / −stat red), engine-identical to the squad profile
	var full: Dictionary = targets.filter(func(t):
		var nn: Dictionary = DataStore.nature(String(t["inst"].get("nature", "Hardy")))
		return not nn.is_empty() and nn.get("plus") != null).front()
	var full_uid := String(full["inst"]["uid"])
	m.knowledge[full_uid] = 100.0
	screen._selected_uid = full_uid
	screen._refresh_all()
	await _settle()
	await _shot(out_dir, "transfers_search_full")
	var sq_helpers = load("res://screens/squad/ui_helpers.gd")
	print("parity %s (%s): transfers=%s squad=%s" % [String(full["inst"]["species"]),
		String(full["inst"].get("nature")), str(m.battle_stats(full["inst"])),
		str(sq_helpers.effective_stats(full["inst"]))])

	# filters: ability filter on = only ability-confirmed matches survive
	screen._ability_filter = String(star["inst"].get("ability", ""))
	screen._refresh_search()
	await _settle()
	await _shot(out_dir, "transfers_filter_ability")
	screen._ability_filter = ""
	screen._nature_filter = String(star["inst"].get("nature", "Hardy"))
	screen._refresh_search()
	await _settle()
	await _shot(out_dir, "transfers_filter_nature")
	screen._nature_filter = ""

	# the written report card with the staged nature/ability block
	screen._tabs.current_tab = 2
	screen._refresh_all()
	screen._show_report(star_uid)
	await _settle()
	await _shot(out_dir, "transfers_report_card")

	# the inbox scout-desk dossier obeys the SAME staged ladder — and filing
	# it granted real Part-scouted market knowledge on the prospect
	_shell.navigate_to("inbox")
	await _settle()
	var ib: Control = _shell._content.get_children().back()
	var scout_msg := {}
	for msg in GameState.inbox:
		if str(msg.get("uid", "")).begins_with("scout:"):
			scout_msg = msg
			break
	if scout_msg.is_empty():
		printerr("SURF SHOT ERROR: no scout dossier in inbox")
		get_tree().quit(1)
		return
	ib._selected = scout_msg
	ib._rebuild_all()
	await _settle()
	await _shot(out_dir, "inbox_scout_dossier")
	print("dossier prospect knowledge: %.0f%% (filed report granted Part scouted)" %
		m.knowledge_of(str(scout_msg.get("prospect_uid", ""))))

	GameState.delete_save()
	print("SURF SHOTS OK")
	get_tree().quit(0)


func _shot(out_dir: String, name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.save_png(out_dir.path_join(name + ".png")) != OK:
		printerr("SURF SHOT ERROR: %s" % name)
		get_tree().quit(1)
		return
	print("shot: %s" % name)


func _settle() -> void:
	for i in SETTLE:
		await get_tree().process_frame
