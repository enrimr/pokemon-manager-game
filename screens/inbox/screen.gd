extends Control
## Inbox screen STUB — owned by the "inbox" piece.


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "Inbox"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Stub — the inbox piece will build threaded news, media and board messages."
	hint.add_theme_color_override("font_color", Color("8b91a8"))
	box.add_child(hint)
	box.add_child(HSeparator.new())

	var info := Label.new()
	info.text = "%d messages (%d unread)" % [GameState.inbox.size(), GameState.unread_inbox_count()]
	box.add_child(info)

	for m in GameState.inbox.slice(0, 10):
		var l := Label.new()
		l.text = "  [%s] %s — %s" % [Season.pretty_date(m["date"]), m["title"], m["body"]]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
