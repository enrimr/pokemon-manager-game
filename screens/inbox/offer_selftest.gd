extends Node
## Inbox piece self-test: proves inbox transfer-offer decisions are wired to
## the LIVE transfers market — accepting moves the squad member and the fee,
## countering opens negotiation, rejecting closes the offer, and urgency
## flags follow the real offer state.
## Run: godot --headless --path . res://screens/inbox/offer_selftest.tscn
## (Run against a scratch save — this mutates game state on purpose.)

const NewsGen := preload("res://screens/inbox/news_gen.gd")

var _fails := 0


func _ready() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails += 1
		printerr("  FAIL: %s" % label)


func _msg_for(offer_id: int) -> Dictionary:
	for m in GameState.inbox:
		if int(m.get("offer_id", -1)) == offer_id:
			return m
	return {}


func _run() -> void:
	var news: RefCounted = NewsGen.new()
	news.enrich_existing()
	news.generate()
	var mkt: RefCounted = news.market()
	_check(mkt != null, "transfers market singleton reachable")
	if mkt == null:
		get_tree().quit(1)
		return

	var pc: Dictionary = GameState.player_club()

	# ---- 1. inbox generation produced a REAL market offer with linked mail
	var live: Dictionary = {}
	for o in mkt.offers_in:
		if news.offer_actionable(o):
			live = o
			break
	_check(not live.is_empty(), "a live offers_in entry exists after generate()")
	if live.is_empty():
		get_tree().quit(1)
		return
	var oid := int(live["id"])
	var msg := _msg_for(oid)
	_check(not msg.is_empty(), "inbox message linked to offer %d exists" % oid)
	_check(bool(msg.get("urgent", false)), "linked message is flagged urgent (decision required)")
	msg["read"] = true
	news.sync_market_offers()
	_check(bool(msg.get("urgent", false)), "urgency survives reading (decision still pending)")

	# ---- 2. COUNTER: demand more through the market API the inbox button uses
	var ask: int = news.offer_bid(live) + 50000
	var err := str(mkt.counter_offer_in(oid, ask))
	_check(err == "", "counter_offer_in accepted (err='%s')" % err)
	_check(str(live["stage"]) == "counter_pending", "offer stage -> counter_pending")
	news.sync_market_offers()
	_check(not bool(msg.get("urgent", false)), "urgency clears while ball is in their court")

	# ---- 3. REJECT: close it out
	mkt.reject_offer_in(oid)
	_check(str(live["stage"]) == "rejected", "offer stage -> rejected")
	news.sync_market_offers()
	_check(not bool(msg.get("urgent", false)), "rejected offer no longer urgent")

	# ---- 4. ACCEPT: fresh offer, confirm money + squad member actually move
	var squad: Array = pc["squad"].duplicate()
	squad.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	var target: Dictionary = squad[0]
	var buyer_id := ""
	for c in GameState.world["clubs"]:
		if not GameState.is_player_club(c["id"]) and int(c["finances"]["balance"]) > 100000:
			buyer_id = c["id"]
			break
	var fee := 77000
	var oid2: int = news._register_market_offer(target, buyer_id, fee,
		GameState.current_date, Season.date_add(GameState.current_date, 5))
	_check(oid2 >= 0, "second offer registered in market ledger")
	news.sync_market_offers()
	var msg2 := _msg_for(oid2)
	_check(not msg2.is_empty() and bool(msg2.get("urgent", false)), "second offer mail created + urgent")
	var bal_before := int(pc["finances"]["balance"])
	var size_before: int = pc["squad"].size()
	var buyer: Dictionary = GameState.club(buyer_id)
	var buyer_size: int = buyer["squad"].size()
	err = str(mkt.accept_offer_in(oid2))
	_check(err == "", "accept_offer_in succeeded (err='%s')" % err)
	_check(int(pc["finances"]["balance"]) == bal_before + fee, "fee credited to our balance (+%d)" % fee)
	_check(pc["squad"].size() == size_before - 1, "squad member left our squad")
	_check(buyer["squad"].size() == buyer_size + 1, "squad member joined the buyer")
	_check(not pc["squad"].any(func(i): return i["uid"] == target["uid"]), "sold uid gone from our squad")
	var sale_mail := false
	for m in GameState.inbox:
		if str(m.get("title", "")).begins_with("Sale completed:"):
			sale_mail = true
	_check(sale_mail, "'Sale completed' confirmation mail arrived")
	news.enrich_existing()
	news.sync_market_offers()
	_check(not bool(msg2.get("urgent", false)), "accepted offer's mail no longer urgent")

	if _fails == 0:
		print("INBOX OFFER SELFTEST OK")
		get_tree().quit(0)
	else:
		printerr("INBOX OFFER SELFTEST FAILED (%d)" % _fails)
		get_tree().quit(1)
