extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	await get_tree().process_frame
	preload("res://tools/save_guard.gd").backup()
	var fails := 0
	# 1) a wild basic (Mareep 179) is accepted
	GameState.new_career()
	var pro = ProtegeService.instance
	var err := str(pro.select_starter(179, "Lanita"))
	if err != "" or not pro.has_protege() or int(pro.academy_entry().get("species_id", 0)) != 179:
		printerr("FAIL basic: '%s'" % err); fails += 1
	else:
		print("  ok: wild basic accepted (Mareep in academy, rival mirrors: %s)" % str(pro.rival().get("manager", "?")))
	# 2) a legendary (Articuno 144) is accepted
	GameState.new_career(777)
	pro = ProtegeService.instance
	err = str(pro.select_starter(144))
	if err != "" or int(pro.academy_entry().get("species_id", 0)) != 144:
		printerr("FAIL legend: '%s'" % err); fails += 1
	else:
		print("  ok: legendary accepted (Articuno, Lv%d juvenile)" % int(pro.academy_entry().get("level", 0)))
	# 3) an evolved species (Charmeleon 5) is still rejected
	GameState.new_career(778)
	pro = ProtegeService.instance
	err = str(pro.select_starter(5))
	if err == "":
		printerr("FAIL evolved accepted"); fails += 1
	else:
		print("  ok: evolved species still rejected ('%s')" % err)
	preload("res://tools/save_guard.gd").restore()
	print("WILD CHECK %s" % ("OK" if fails == 0 else "FAILED"))
	get_tree().quit(0 if fails == 0 else 1)
