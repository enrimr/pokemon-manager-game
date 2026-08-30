extends Node
## Builder verification: boots the real shell, plays the market for a while,
## then screenshots every transfers tab (windowed run required).
##   Godot --path . res://screens/transfers/verify_shots.tscn
## Tabs: 0 Recruitment hub · 1 Search · 2 Scouting · 3 Transfer Centre

const Market := preload("res://screens/transfers/market.gd")
const OUT := "artifacts/transfers/w3_fix"
const SETTLE := 12

var _shell: Control


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("res://").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Fresh career + fresh market state (player's real save parked in a
	# one-time backup slot first — see tools/save_guard.gd).
	(load("res://tools/save_guard.gd") as GDScript).preserve_player_save()
	GameState.delete_save()
	if FileAccess.file_exists("user://transfers.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://transfers.json"))
	GameState.new_career()
	Market._inst = null
	var m: RefCounted = Market.instance()

	_shell = (load("res://shell/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_shell)
	await _settle()
	_shell.navigate_to("transfers")
	await _settle()
	await _shot(out_dir, "01_recruitment_fresh")

	# --- play the market: build the full recruitment pipeline ---
	var scouts: Array = m.player_scouts()
	var targets: Array = m.all_targets().filter(func(t):
		return t["pool"] == "club" and not m.is_ext_uid(String(t["inst"]["uid"])))
	targets.sort_custom(func(a, b): return m.value_of(a["inst"]) > m.value_of(b["inst"]))
	var ext_targets: Array = m.all_targets().filter(func(t):
		return t["pool"] == "club" and m.is_ext_uid(String(t["inst"]["uid"])))
	ext_targets.sort_custom(func(a, b): return m.value_of(a["inst"]) > m.value_of(b["inst"]))
	var star: Dictionary = targets[0]
	var mid: Dictionary = targets[8]
	var ext_star: Dictionary = ext_targets[0]
	m.assign_scout_to_target(scouts[0]["name"], star["inst"]["uid"])
	if scouts.size() > 1:
		m.assign_scout_to_focus(scouts[1]["name"], "Coastal Circuit")
	# hire a dedicated scout from the monthly market and ship them overseas —
	# travel days + staged knowledge on the Scouting tab
	var pool_h: Array = m.scout_market()
	pool_h.sort_custom(func(a, b): return int(a["wage"]) < int(b["wage"]))
	if not pool_h.is_empty():
		m.hire_scout(String(pool_h[0]["name"]))
		m.assign_scout_to_target(String(pool_h[0]["name"]), String(ext_star["inst"]["uid"]))
	m.toggle_shortlist(String(ext_star["inst"]["uid"]))
	# shortlist a spread of targets — the board the pipeline reports on
	m.toggle_shortlist(star["inst"]["uid"])
	m.toggle_shortlist(targets[3]["inst"]["uid"])
	m.toggle_shortlist(targets[12]["inst"]["uid"])
	var fa0: Dictionary = GameState.free_agents()[4]
	m.toggle_shortlist(fa0["uid"])
	# delegate the chores to the DoF
	m.set_dof("handle_bids", true)
	m.set_dof("auto_scout", true)
	# structured lowball: upfront + installments + sell-on, to draw a structured counter
	var ask8: int = m.ask_price(mid["inst"], mid["club_id"])
	m.make_offer(mid["inst"]["uid"], {"upfront": int(ask8 * 0.55), "inst_amount": int(ask8 * 0.25),
		"inst_years": 2, "sell_on": 10})
	var fa: Dictionary = GameState.free_agents()[2]
	m.sign_free_agent(fa["uid"], {"wage": int(float(fa["contract"]["salary"]) * 1.5),
		"years": 3, "bonus": 2000, "status": "First team"})
	# a loan bid for a fringe battler with an option to buy
	for t in targets:
		var c: Dictionary = m.club_of(t["club_id"])
		if c["squad"].size() > 9 and m.importance_of(t["inst"], c) < 1.15 and m.offer_for_target(t["inst"]["uid"]).is_empty():
			m.make_loan_offer(t["inst"]["uid"], 100, m.ask_price(t["inst"], t["club_id"]))
			break
	for i in 9:
		GameState.auto_sim_player_matches = true
		GameState.advance_day()
	# a second lowball to leave a live "countered" negotiation on screen
	var mid2: Dictionary = targets[5]
	if m.offer_for_target(mid2["inst"]["uid"]).is_empty():
		var ask5: int = m.ask_price(mid2["inst"], mid2["club_id"])
		m.make_offer(mid2["inst"]["uid"], {"upfront": int(ask5 * 0.65), "inst_amount": int(ask5 * 0.15),
			"inst_years": 2, "sell_on": 10})
	for i in 5:
		GameState.auto_sim_player_matches = true
		GameState.advance_day()
	GameState.save_game()
	m.save_state()

	# re-open the screen with the lived-in state
	_shell.navigate_to("transfers")
	await _settle()
	var screen: Control = _shell._content.get_children().back()

	# the recruitment hub, mid-window: shortlist alive, rumours grinding
	screen._tabs.current_tab = 0
	screen._refresh_all()
	await _settle()
	await _shot(out_dir, "02_recruitment_hub")

	# search tab with a scouted target selected
	screen._selected_uid = star["inst"]["uid"]
	screen._tabs.current_tab = 1
	screen._refresh_all()
	await _settle()
	await _shot(out_dir, "03_search_lived_in")

	# search filtered to the overseas leagues, an island target selected
	screen._selected_uid = String(ext_star["inst"]["uid"])
	screen._pool_filter = 6
	screen._refresh_search()
	screen._refresh_detail()
	await _settle()
	await _shot(out_dir, "03b_search_overseas")
	screen._pool_filter = 0
	screen._refresh_search()

	screen._tabs.current_tab = 2
	await _settle()
	await _shot(out_dir, "04_scouting")

	screen._tabs.current_tab = 3
	await _settle()
	await _shot(out_dir, "05_transfer_centre")

	# the structured offer sheet itself (installments / sell-on / loan toggle)
	screen._open_offer_sheet(star["inst"]["uid"])
	await _settle()
	await _shot(out_dir, "06_offer_sheet")
	for c in screen.get_children():
		if c is ConfirmationDialog:
			c.hide()

	# --- deadline run-in: jump to 3 days before the summer deadline ---
	var close: String = String(m.current_window()["close"])
	var to_go: int = Season.days_between(GameState.current_date, close) - 3
	for i in maxi(0, to_go):
		GameState.auto_sim_player_matches = true
		GameState.advance_day()
	# a live negotiation with a rival circling, for the Transfer Centre shot
	var late_t: Dictionary = {}
	for t2 in m.all_targets():
		if t2["pool"] == "club" and m.offer_for_target(t2["inst"]["uid"]).is_empty():
			late_t = t2
			break
	if not late_t.is_empty():
		var ask_l: int = m.ask_price(late_t["inst"], late_t["club_id"])
		m.make_offer(late_t["inst"]["uid"], {"upfront": mini(int(ask_l * 0.85),
			int(GameState.player_club()["finances"]["balance"])), "inst_amount": 0, "inst_years": 2, "sell_on": 0})
		var o_l: Dictionary = m.offer_for_target(late_t["inst"]["uid"])
		if not o_l.is_empty() and o_l.get("rival", {}).is_empty():
			var rich: Dictionary = {}
			for c2 in GameState.world["clubs"]:
				if not GameState.is_player_club(c2["id"]) and String(c2["id"]) != String(late_t["club_id"]):
					if rich.is_empty() or int(c2["finances"]["balance"]) > int(rich["finances"]["balance"]):
						rich = c2
			o_l["rival"] = {"club_id": rich["id"], "club": rich["short"],
				"value": int(float(ask_l) * 1.05), "decides_on": close}
			m.save_state()
	screen = _shell._content.get_children().back()
	screen._refresh_all()
	screen._tabs.current_tab = 3
	await _settle()
	await _shot(out_dir, "07_deadline_runin")

	# --- window shut: locked market, rumours still grinding on the hub ---
	for i in 6:
		GameState.auto_sim_player_matches = true
		GameState.advance_day()
	screen._refresh_all()
	screen._tabs.current_tab = 3
	await _settle()
	await _shot(out_dir, "08_window_closed")
	screen._tabs.current_tab = 0
	await _settle()
	await _shot(out_dir, "09_hub_window_closed")

	# leave a CONSISTENT lived-in save (game + market together) for the
	# shell screenshot harness
	GameState.save_game()
	m.save_state()
	print("VERIFY SHOTS OK")
	get_tree().quit(0)


func _shot(out_dir: String, name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.save_png(out_dir.path_join(name + ".png")) != OK:
		printerr("VERIFY SHOT ERROR: %s" % name)
		get_tree().quit(1)
		return
	print("shot: %s" % name)


func _settle() -> void:
	for i in SETTLE:
		await get_tree().process_frame
