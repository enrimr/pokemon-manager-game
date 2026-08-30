extends Node
## Headless verification for shell sub-navigation deep links (shell-owned).
## Boots the real shell, then for every screen×tab pair discovered from
## screen.json / script consts / SUBNAV_FALLBACK it calls
## navigate_to(screen, {"tab": id}) and asserts the screen's LIVE tab state
## (read back from the instance) matches. Also asserts a same-screen tab hop
## is applied in place (no reinstantiation). Prints "TAB CHECK OK" on success.
##
## Run:  Godot --headless --path . res://shell/tab_check.tscn

var _fails := 0


func _ready() -> void:
	var shell: Control = load("res://shell/main.tscn").instantiate()
	add_child(shell)
	await _frames(6)

	# 1. every discovered tab must be deep-linkable and verifiably applied
	var total := 0
	for screen_name in shell.screens:
		for t in shell.screens[screen_name].get("tabs", []):
			total += 1
			var tab_id: String = str(t["id"])
			shell.navigate_to(screen_name, {"kind": "tab", "tab": tab_id, "label": str(t["title"])})
			await _frames(3)
			var inst: Node = shell._current_screen_instance()
			var live: String = shell._read_current_tab(inst, screen_name)
			if live == tab_id and shell.current_tab_id == tab_id:
				print("  ok: %s -> %s (live tab confirmed)" % [screen_name, tab_id])
			else:
				_fails += 1
				printerr("  FAIL: %s -> %s (live='%s', shell='%s')" % [screen_name, tab_id, live, shell.current_tab_id])

	# 2. same-screen tab hop happens in place (FM never rebuilds the page)
	shell.navigate_to("competition", {"kind": "tab", "tab": "table", "label": "League Table"})
	await _frames(3)
	var before: Node = shell._current_screen_instance()
	shell.navigate_to("competition", {"kind": "tab", "tab": "fixtures", "label": "Fixtures & Results"})
	await _frames(3)
	var after: Node = shell._current_screen_instance()
	if before == after and shell._read_current_tab(after, "competition") == "fixtures":
		print("  ok: in-place tab switch (no reinstantiation)")
	else:
		_fails += 1
		printerr("  FAIL: in-place tab switch reinstantiated the screen")

	# 3. history carries tab context: back must restore the previous tab
	shell.go_back()
	await _frames(3)
	if shell.current_screen_name == "competition" and shell.current_tab_id == "table":
		print("  ok: back restores previous tab (competition/table)")
	else:
		_fails += 1
		printerr("  FAIL: back gave %s/%s" % [shell.current_screen_name, shell.current_tab_id])

	if _fails == 0:
		print("TAB CHECK OK (%d deep links verified)" % total)
	else:
		printerr("TAB CHECK FAILED: %d failures" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
