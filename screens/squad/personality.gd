extends RefCounted
## Squad piece: the qualitative personality / happiness layer (FM24's
## personality traits + squad-status expectations + explained happiness).
##
## PERSONALITY — every squad Pokemon has four hidden character attributes
## (Ambition, Professionalism, Temperament, Loyalty; 1-20, deterministic per
## career+uid so they never jitter) condensed into an FM-style archetype word
## ("Model Professional", "Fiery", ...). They are NOT cosmetic: SquadService
## scales praise/criticism reactions, contract demands, promise-breaking
## fallout and match-result morale swings by them.
##
## SQUAD STATUS — an expectation tier (Star Battler / Important / Youth
## Prospect / Squad Battler / Backup) derived from ability rank inside the
## player squad plus age. Each tier carries a playing-time expectation that
## the happiness model checks against real appearance data.
##
## HAPPINESS — a factor ledger, not a number pulled from thin air: playing
## time vs status, form, wage fairness, contract runway, transfer listing,
## collapsed talks, promises (kept / open / broken), team results and league
## position, physical state, recent manager talks. Every factor comes with a
## short label, a detail sentence, a signed weight and (where sensible) an
## action the manager can take to resolve it. The stored day-to-day morale
## value drifts toward this underlying happiness in SquadService's daily tick,
## so "Poor" morale always has visible reasons behind it.

const UI := preload("res://screens/squad/ui_helpers.gd")
const SeasonStats := preload("res://screens/squad/season_stats.gd")
const Selection := preload("res://screens/squad/selection.gd")
const Ability := preload("res://screens/squad/ability.gd")

const ATTR_NAMES := {"ambition": "Ambition", "professionalism": "Professionalism",
	"temperament": "Temperament", "loyalty": "Loyalty"}
const ATTR_ORDER := ["ambition", "professionalism", "temperament", "loyalty"]

const COL_DELIGHTED := Color("57c979")
const COL_CONTENT := Color("a8c96a")
const COL_SETTLED := Color("d6dae6")
const COL_UNSETTLED := Color("e0b050")
const COL_UNHAPPY := Color("e06060")


# ================================================================ personality

## Deterministic hidden attribute 1..20 (stable for the whole career).
static func _roll(uid: String, salt: String) -> int:
	var h := absi(("pers|%s|%s|%d" % [uid, salt, GameState.career_seed]).hash())
	return 1 + h % 20


## {ambition, professionalism, temperament, loyalty} — 1..20.
## High temperament = calm; low = volatile (FM convention).
static func attrs(uid: String) -> Dictionary:
	return {
		"ambition": _roll(uid, "amb"),
		"professionalism": _roll(uid, "pro"),
		"temperament": _roll(uid, "tem"),
		"loyalty": _roll(uid, "loy"),
	}


static func attr_word(v: int) -> String:
	if v >= 17: return "Very high"
	if v >= 13: return "High"
	if v >= 9: return "Fair"
	if v >= 5: return "Low"
	return "Very low"


static func attr_color(v: int) -> Color:
	if v >= 13: return UI.COL_GOOD
	if v >= 9: return UI.COL_TEXT
	return UI.COL_WARN


## FM-style archetype from the hidden attributes. {name, desc}.
static func archetype(a: Dictionary) -> Dictionary:
	var amb := int(a["ambition"])
	var pro := int(a["professionalism"])
	var tem := int(a["temperament"])
	var loy := int(a["loyalty"])
	if pro >= 16 and tem >= 11:
		return {"name": "Model Professional", "desc":
			"Trains impeccably and keeps perspective — form dips and hard words rarely become crises."}
	if amb >= 16 and pro >= 11:
		return {"name": "Driven", "desc":
			"Hungry for battles and status. Delivers when trusted, agitates quickly when overlooked."}
	if tem <= 5:
		return {"name": "Fiery", "desc":
			"Explosive character: criticism, benching and broken promises all land twice as hard."}
	if loy >= 16:
		return {"name": "Loyal", "desc":
			"Attached to the club — flexible in contract talks, but deeply wounded by a transfer listing."}
	if amb >= 15:
		return {"name": "Ambitious", "desc":
			"Expects the club, the team sheet and the wage slip to keep pace with their ability."}
	if pro <= 5:
		return {"name": "Casual", "desc":
			"Needs firm management: standards drift without scrutiny and criticism is shrugged off."}
	if tem <= 8:
		return {"name": "Temperamental", "desc":
			"Morale swings hard with results and manager talks — handle with care."}
	if amb <= 5 and tem >= 12:
		return {"name": "Easy-Going", "desc":
			"Content in almost any role. Rarely agitates — and rarely pushes for more."}
	if pro >= 13:
		return {"name": "Professional", "desc":
			"Reliable attitude on the training ground; takes fair criticism on the chin."}
	return {"name": "Balanced", "desc":
		"No strong edges to the character — reacts to events much as you would expect."}


## One-line coach's read of all four attributes ("Ambition: High · ...").
static func attrs_line(a: Dictionary) -> String:
	var parts: Array = []
	for k in ATTR_ORDER:
		parts.append("%s: %s" % [I18n.t(ATTR_NAMES[k]), I18n.t(attr_word(int(a[k])))])
	return " · ".join(PackedStringArray(parts))


# ================================================================ context

## Shared per-refresh context so the model is computed once per squad pass:
## ability + salary ranks inside the player squad, matchdays played, recent
## results, league position vs the club's reputation rank, live selection.
static func context(_svc: Node) -> Dictionary:
	SeasonStats.player_stats()
	var club: Dictionary = GameState.player_club()
	var squad: Array = club.get("squad", [])
	var scored: Array = []
	for inst in squad:
		scored.append([str(inst["uid"]), Ability.raw_now(inst)])
	scored.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
	var abil_rank := {}
	for i in scored.size():
		abil_rank[scored[i][0]] = i + 1
	var by_pay: Array = squad.duplicate()
	by_pay.sort_custom(func(x, y): return int(x["contract"]["salary"]) > int(y["contract"]["salary"]))
	var pay_rank := {}
	for i in by_pay.size():
		pay_rank[str(by_pay[i]["uid"])] = i + 1

	var played: Array = []
	for f in GameState.player_fixtures():
		if f.get("played", false):
			played.append(f)
	played.sort_custom(func(x, y): return str(x["date"]) > str(y["date"]))
	var last3: Array = []
	for f in played.slice(0, 3):
		var home := GameState.is_player_club(str(f["home"]))
		var us := int(f["score_home"]) if home else int(f["score_away"])
		var them := int(f["score_away"]) if home else int(f["score_home"])
		last3.append(us > them)

	var pos := GameState.player_table_position()
	var reps: Array = []
	for c in GameState.world["clubs"]:
		reps.append([str(c["id"]), int(c.get("reputation", 10))])
	reps.sort_custom(func(x, y): return int(x[1]) > int(y[1]))
	var rep_rank := 8
	for i in reps.size():
		if GameState.is_player_club(str(reps[i][0])):
			rep_rank = i + 1
	return {
		"n": squad.size(), "abil_rank": abil_rank, "pay_rank": pay_rank,
		"team_played": played.size(), "last3": last3,
		"pos": pos, "rep_rank": rep_rank,
		"sel": Selection.selection(),
	}


# ================================================================ squad status

## Expectation tier. {key, label, color, expect, share_need, rank, n}.
static func squad_status(inst: Dictionary, ctx: Dictionary) -> Dictionary:
	var uid := str(inst["uid"])
	var r := int((ctx["abil_rank"] as Dictionary).get(uid, 99))
	var n := maxi(int(ctx["n"]), 1)
	var age := int(inst.get("age_months", 48))
	if r <= 2 and n >= 6:
		return {"key": "star", "label": "Star Battler", "color": Color("edc254"),
			"expect": "Expects to start every match and lead the side.",
			"share_need": 0.65, "rank": r, "n": n}
	if r <= int(ceil(n / 3.0)):
		return {"key": "important", "label": "Important Battler", "color": UI.COL_GOOD,
			"expect": "Expects to start most matches.",
			"share_need": 0.5, "rank": r, "n": n}
	if age < 30:
		return {"key": "prospect", "label": "Youth Prospect", "color": UI.COL_ACCENT.lightened(0.25),
			"expect": "Expects battles to develop, plus focused training.",
			"share_need": 0.2, "rank": r, "n": n}
	if r <= int(ceil(n * 2.0 / 3.0)):
		return {"key": "rotation", "label": "Squad Battler", "color": UI.COL_TEXT,
			"expect": "Expects a fair share of matchdays.",
			"share_need": 0.3, "rank": r, "n": n}
	return {"key": "backup", "label": "Backup", "color": UI.COL_TEXT_DIM,
		"expect": "Accepts a bench role; content with occasional battles.",
		"share_need": 0.08, "rank": r, "n": n}


# ================================================================ happiness

static func happiness_word(score: int) -> String:
	if score >= 78: return "Delighted"
	if score >= 64: return "Content"
	if score >= 50: return "Settled"
	if score >= 38: return "Unsettled"
	if score >= 26: return "Unhappy"
	return "Very Unhappy"


static func happiness_color(score: int) -> Color:
	if score >= 78: return COL_DELIGHTED
	if score >= 64: return COL_CONTENT
	if score >= 50: return COL_SETTLED
	if score >= 38: return COL_UNSETTLED
	return COL_UNHAPPY


static func _f(short: String, detail: String, w: float, act: String = "") -> Dictionary:
	return {"short": short, "detail": detail, "w": w, "act": act}


## Full happiness breakdown for a player-squad instance.
## Returns {score, word, color, factors, concerns, top_concern, status, arch, attrs}.
## `svc` is SquadService (promises / talks / interaction memory live there);
## `ctx` comes from context() and should be shared across a squad pass.
static func happiness(inst: Dictionary, svc: Node, ctx: Dictionary) -> Dictionary:
	var uid := str(inst["uid"])
	var a := attrs(uid)
	var st := squad_status(inst, ctx)
	var name := UI.display_name(inst)
	var f: Array = []

	# --- playing time vs squad-status expectation
	var team_played := int(ctx["team_played"])
	var apps := SeasonStats.stat_of(uid, "battles")
	var picked: bool = ((ctx["sel"] as Dictionary)["slot"] as Dictionary).has(uid)
	var need := float(st["share_need"])
	if team_played >= 4:
		var share := float(apps) / float(team_played)
		if share >= need:
			f.append(_f("Happy with playing time",
				I18n.t("%d battles across %d matchdays meets a %s's expectations.") % [apps, team_played, I18n.t(st["label"])],
				8.0 + (2.0 if st["key"] == "star" else 0.0)))
		else:
			var amb_scale := 1.0 + (float(a["ambition"]) - 10.0) * 0.04
			var tier_scale: float = {"star": 1.0, "important": 0.9, "prospect": 0.8,
				"rotation": 0.6, "backup": 0.35}.get(str(st["key"]), 0.6)
			var w := -16.0 * (need - share) / maxf(need, 0.01) * amb_scale * tier_scale
			w = clampf(w, -16.0, -2.0)
			var short := "Wants more battles"
			if st["key"] == "star":
				short = "Unhappy at being overlooked"
			if picked:
				w *= 0.4
				f.append(_f("Wants the starts to keep coming",
					I18n.t("Only %d battles in %d matchdays — below what a %s expects — but being named in the current starting six is easing it.") %
					[apps, team_played, I18n.t(st["label"])], w, "promise_battles"))
			else:
				f.append(_f(short,
					I18n.t("%d battles in %d matchdays is below what a %s expects (%s). Not in the current picked six.") %
					[apps, team_played, I18n.t(st["label"]), I18n.t(st["expect"]).to_lower()], w, "promise_battles"))
	elif picked:
		f.append(_f("Named in the starting six",
			I18n.t("The season is young and they are in the picked six — no complaints."), 4.0))

	# --- form
	if apps >= 3:
		var rat := SeasonStats.avg_rating(uid)
		if rat >= 7.3:
			f.append(_f("In excellent form",
				I18n.t("Averaging %.2f over %d battles — confidence is soaring.") % [rat, apps], 6.0))
		elif rat < 6.2:
			f.append(_f("Struggling for form",
				I18n.t("Averaging just %.2f over %d battles — confidence is low.") % [rat, apps], -4.0))

	# --- wage fairness (ability rank vs salary rank inside the squad)
	var abil_r := int((ctx["abil_rank"] as Dictionary).get(uid, 99))
	var pay_r := int((ctx["pay_rank"] as Dictionary).get(uid, 99))
	if abil_r <= 4 and pay_r - abil_r >= 4 and int(ctx["n"]) >= 8:
		var w2 := -6.0 - maxf(float(a["ambition"]) - 12.0, 0.0) * 0.5
		f.append(_f("Feels underpaid",
			I18n.t("Rated the squad's %s-strongest battler but only its %s-highest earner — wants the deal to reflect their standing.") %
			[_ord(abil_r), _ord(pay_r)], w2, "contract"))

	# --- contract runway
	var days_left := UI.days_between(GameState.current_date, str(inst["contract"]["expiry"]))
	if st["key"] in ["star", "important", "prospect"]:
		if days_left < 120:
			f.append(_f("Contract running down",
				I18n.t("Deal expires in %d days and nothing new is agreed — a %s wants their future settled.") %
				[maxi(days_left, 0), I18n.t(st["label"])], -7.0, "contract"))
		elif days_left < 240 and st["key"] != "prospect":
			f.append(_f("Would welcome a new deal",
				I18n.t("%d days left on the current contract; open to talks.") % days_left, -3.0, "contract"))

	# --- transfer listing
	if bool(inst.get("transfer_listed", false)):
		var w3 := -10.0 - maxf(float(a["loyalty"]) - 8.0, 0.0) * 0.5
		f.append(_f("Transfer-listed — feels unwanted",
			I18n.t("On the list at %s. Loyalty makes it sting%s.") % [UI.money(int(inst.get("asking_price", 0))),
			I18n.t(" badly") if int(a["loyalty"]) >= 13 else ""], clampf(w3, -16.0, -8.0), "unlist"))

	# --- collapsed talks
	if svc.talks_locked(uid):
		f.append(_f("Bruised by collapsed talks",
			I18n.t("Contract negotiations broke down; will not return to the table before %s.") %
			I18n.pretty_date(svc.talks_locked_until(uid)), -8.0))

	# --- promises (squad-screen promises + coach-brokered inbox pledges)
	var open_p: Dictionary = svc.open_promise(uid)
	if not open_p.is_empty():
		f.append(_f("Trusting the manager's promise",
			I18n.t("%s Deadline %s.") % [str(open_p["text"]), I18n.pretty_date(str(open_p["deadline"]))], 3.0))
	var kept: Dictionary = svc.recent_promise(uid, "kept", 30)
	if not kept.is_empty():
		f.append(_f("Manager kept their word",
			I18n.t("Promise honoured on %s: %s") % [I18n.pretty_date(str(kept["resolved_on"])), str(kept["text"])], 5.0))
	var broken: Dictionary = svc.recent_promise(uid, "broken", 45)
	if not broken.is_empty():
		var w4 := -10.0 - maxf(8.0 - float(a["temperament"]), 0.0) * 0.5
		f.append(_f("Trust broken by the manager",
			I18n.t("Promise broken on %s: %s The distrust lingers.") %
			[I18n.pretty_date(str(broken["resolved_on"])), str(broken["text"])], clampf(w4, -15.0, -8.0)))
	for pl in svc.inbox_pledges(uid):
		if str(pl.get("status", "")) == "open":
			f.append(_f("Awaiting a promised run of battles",
				I18n.t("The coach brokered a pledge of %d battles by %s (see Inbox).") %
				[int(pl.get("target", 4)), I18n.pretty_date(str(pl.get("deadline", GameState.current_date)))], 2.0))

	# --- team position vs club reputation
	if team_played >= 4:
		var pos := int(ctx["pos"])
		var rep_rank := int(ctx["rep_rank"])
		if pos <= 3:
			f.append(_f("Enjoying a strong season",
				I18n.t("The club sits %s in the league — the mood around the pens is good.") % _ord(pos), 4.0))
		elif pos - rep_rank >= 4 and int(a["ambition"]) >= 13:
			f.append(_f("Frustrated by the league position",
				I18n.t("%s in the table against a squad reputation of %s — an ambitious character notices.") %
				[_ord(pos), _ord(rep_rank)], -5.0))

	# --- recent results (last three matchdays)
	var last3: Array = ctx["last3"]
	if last3.size() >= 3:
		var tem_edge := 1.0 if int(a["temperament"]) <= 8 else 0.0
		if last3.all(func(w): return bool(w)):
			f.append(_f("Riding the winning run", I18n.t("Three straight wins — spirits are high."), 4.0 + tem_edge))
		elif last3.all(func(w): return not bool(w)):
			f.append(_f("Weighed down by defeats", I18n.t("Three straight losses — the mood has darkened."), -4.0 - tem_edge))

	# --- physical state
	if int(inst.get("condition", 100)) < 45:
		f.append(_f("Run into the ground",
			I18n.t("Condition is down to %d%% — needs rest before resentment builds.") % int(inst["condition"]), -4.0))

	# --- settled veteran
	if int(inst.get("age_months", 48)) >= 84 and int(a["loyalty"]) >= 13:
		f.append(_f("Settled senior figure",
			I18n.t("A loyal veteran, comfortable in their role at the club."), 3.0))

	# --- recent manager talk
	var li: Dictionary = svc.last_interaction(uid)
	if not li.is_empty() and UI.days_between(str(li["date"]), GameState.current_date) <= 8:
		if int(li["delta"]) > 0:
			f.append(_f("Buoyed by the manager's praise",
				I18n.t("Praised on %s (morale %+d).") % [I18n.pretty_date(str(li["date"])), int(li["delta"])], 3.0))
		else:
			f.append(_f("Smarting from criticism",
				I18n.t("Criticised on %s (morale %+d).") % [I18n.pretty_date(str(li["date"])), int(li["delta"])], -3.0))

	# --- score + concerns
	var score := 58.0
	for fac in f:
		score += float(fac["w"])
	var s := clampi(int(round(score)), 2, 98)
	var concerns := f.filter(func(x): return float(x["w"]) < 0.0)
	concerns.sort_custom(func(x, y): return float(x["w"]) < float(y["w"]))
	return {
		"score": s, "word": happiness_word(s), "color": happiness_color(s),
		"factors": f, "concerns": concerns,
		"top_concern": (str(concerns[0]["short"]) if not concerns.is_empty() else ""),
		"status": st, "arch": archetype(a), "attrs": a,
	}


## Multi-line tooltip: every factor as a signed line, FM-style.
static func factors_tip(h: Dictionary) -> String:
	var lines: Array = [I18n.t("%s (%d/100) — %s, %s.") % [I18n.t(h["word"]), int(h["score"]),
		I18n.t((h["arch"] as Dictionary)["name"]), I18n.t((h["status"] as Dictionary)["label"])]]
	var fs: Array = (h["factors"] as Array).duplicate()
	fs.sort_custom(func(x, y): return float(x["w"]) > float(y["w"]))
	for fac in fs:
		lines.append("%s %s — %s" % ["+" if float(fac["w"]) >= 0.0 else "-",
			I18n.t(str(fac["short"])), I18n.t(str(fac["detail"]))])
	if fs.is_empty():
		lines.append(I18n.t("Nothing on their mind — no active happiness factors."))
	return "\n".join(PackedStringArray(lines))


static func _ord(n: int) -> String:
	return I18n.ordinal(n)
