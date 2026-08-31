extends RefCounted
## Squad piece: coach-report ability / potential model (FM's CA/PA star layer).
##
## CURRENT ABILITY — how strong the battler is right now: effective battle
## stats (level + species base + IVs, the exact engine math) scaled by the
## quality of the best damaging move actually known (power x accuracy x STAB —
## a wall of great stats with weak moves does not win battles in this engine).
##
## POTENTIAL ABILITY — the realistic ceiling in THIS game's development model:
## IVs are trainable toward 15 at a rate driven by age and growth curve
## (mirroring the training model's age/growth multipliers), and the move
## ceiling comes from the species' full learnset. Old or slow-growth battlers
## realise little of their remaining IV headroom; young fast growers most of it.
##
## Stars are RELATIVE TO THE LEAGUE: every battler in all 16 club squads is
## scored and the star bands are percentiles of that live population, so
## "4 stars" always means "top ~15% of the Indigo League right now".
##
## Like FM, what you see is a COACH REPORT, not the truth: the displayed
## rating is the true rating perturbed by your best staff's judging_ability /
## judging_potential (1-20), and potential is shown as a range whose width
## shrinks as your judge of potential improves. Deterministic per career+uid:
## reports do not jitter day to day.

const UI := preload("res://screens/squad/ui_helpers.gd")

const STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]

# percentile -> star bands (half-star resolution, FM-style scarcity at the top)
const STAR_BANDS := [
	[0.96, 5.0], [0.90, 4.5], [0.80, 4.0], [0.68, 3.5], [0.54, 3.0],
	[0.40, 2.5], [0.26, 2.0], [0.14, 1.5], [0.05, 1.0], [-1.0, 0.5],
]

const GROWTH_REALISE := {"fast": 1.0, "medium_fast": 0.92, "medium_slow": 0.82, "slow": 0.72}

const COL_STARS_NOW := Color("edc254")     # gold — current ability
const COL_STARS_POT := Color("9fb4e8")     # steel blue — potential
const COL_STARS_RANGE := Color("8d7a45")   # uncertain band in range icons
const COL_STARS_EMPTY := Color("3a4059")

static var _icon_cache: Dictionary = {}
static var _league_key := ""
static var _league_raw: Array = []          # sorted raw ability of every league battler
static var _report_cache: Dictionary = {}   # uid -> report (invalidated with league key)


# ================================================================ core scores

## Best damaging move among `moves` for this species: power x accuracy x STAB.
static func best_move(sp: Dictionary, moves: Array) -> Dictionary:
	var best := 0.0
	var best_name := "-"
	for mn in moves:
		var mv: Dictionary = DataStore.move(mn)
		if mv.is_empty() or str(mv["category"]) == "status":
			continue
		var pw := float(mv["power"])
		if pw <= 0.0:
			pw = 45.0  # fixed-damage moves: modest constant threat
		var acc := float(mv["accuracy"])
		if acc <= 0.0:
			acc = 100.0  # accuracy 0 = never misses
		var stab := 1.5 if (sp["types"] as Array).has(mv["type"]) else 1.0
		var s := pw * (acc / 100.0) * stab
		if s > best:
			best = s
			best_name = mn
	# 180 = a 120-power STAB move that always hits.
	return {"score": clampf(best / 180.0, 0.0, 1.0), "name": best_name}


## Raw ability from a stat block + move quality. Stats carry most of the
## weight; the move factor spans 0.8..1.2.
static func raw_score(stats: Dictionary, move_score: float) -> float:
	var tot := 0.0
	for k in STAT_KEYS:
		tot += float(stats[k])
	return tot * (0.8 + 0.4 * move_score)


static func raw_now(inst: Dictionary) -> float:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var mv := best_move(sp, inst.get("moves", []))
	return raw_score(UI.effective_stats(inst), float(mv["score"]))


## Fraction of remaining IV headroom this battler will realistically train up,
## from age (mirrors the training model's age curve) and growth speed.
static func realise_fraction(age_months: int, growth: String) -> float:
	var f := 0.12
	if age_months <= 30:
		f = 1.0
	elif age_months <= 48:
		f = 0.85
	elif age_months <= 66:
		f = 0.55
	elif age_months <= 84:
		f = 0.30
	return clampf(f * float(GROWTH_REALISE.get(growth, 0.9)), 0.0, 1.0)


## Projected peak: IVs trained toward 15 by the realisable fraction, best move
## taken from the full learnset. Returns {raw, ivs, move_name, move_score}.
static func peak_projection(inst: Dictionary) -> Dictionary:
	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var frac := realise_fraction(int(inst.get("age_months", 48)), str(sp.get("growth", "medium_fast")))
	var ivs: Dictionary = inst.get("ivs", {})
	var proj_ivs := {}
	var lvl := int(inst.get("level", 20))
	var stats := {}
	for k in STAT_KEYS:
		var iv := int(ivs.get(k, 8))
		var piv := clampi(iv + int(round(float(15 - iv) * frac)), iv, 15)
		proj_ivs[k] = piv
		stats[k] = DataStore.calc_stat(int(sp["base"][k]), piv, lvl, k == "hp")
	var pool: Array = (sp.get("learnset", []) as Array).duplicate()
	for m in inst.get("moves", []):
		if not pool.has(m):
			pool.append(m)
	var mv := best_move(sp, pool)
	return {"raw": raw_score(stats, float(mv["score"])), "ivs": proj_ivs,
		"move_name": mv["name"], "move_score": mv["score"], "frac": frac}


# ================================================================ league scale

## Rebuild the league-wide raw-ability distribution when the world changes.
static func _league() -> Array:
	var n := 0
	for c in GameState.world["clubs"]:
		n += (c["squad"] as Array).size()
	var key := "%s:%d" % [GameState.current_date, n]
	if key == _league_key and not _league_raw.is_empty():
		return _league_raw
	_league_key = key
	_report_cache.clear()
	_league_raw.clear()
	for c in GameState.world["clubs"]:
		for inst in c["squad"]:
			_league_raw.append(raw_now(inst))
	_league_raw.sort()
	return _league_raw


static func league_size() -> int:
	return _league().size()


## Percentile (0..1) of a raw score within the live league population.
static func percentile(raw: float) -> float:
	var arr := _league()
	if arr.is_empty():
		return 0.5
	var lo := 0
	var hi := arr.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(arr[mid]) < raw:
			lo = mid + 1
		else:
			hi = mid
	return float(lo) / float(arr.size())


static func stars_from_pct(p: float) -> float:
	for band in STAR_BANDS:
		if p >= float(band[0]):
			return float(band[1])
	return 0.5


# ================================================================ coach report

## Best judges on the player club's staff. {"ja", "ja_name", "jp", "jp_name"}.
static func judges() -> Dictionary:
	var out := {"ja": 8, "ja_name": "no qualified coach", "jp": 8, "jp_name": "no qualified scout"}
	for s in GameState.player_club().get("staff", []):
		var r: Dictionary = s.get("ratings", {})
		if int(r.get("judging_ability", 0)) > int(out["ja"]):
			out["ja"] = int(r["judging_ability"])
			out["ja_name"] = str(s["name"])
		if int(r.get("judging_potential", 0)) > int(out["jp"]):
			out["jp"] = int(r["judging_potential"])
			out["jp_name"] = str(s["name"])
	return out


## Deterministic per-career, per-battler noise in [-1, 1] — reports are stable.
static func _noise(uid: String, salt: String) -> float:
	var h := absi(("%s|%s|%d" % [uid, salt, GameState.career_seed]).hash())
	return float(h % 2001) / 1000.0 - 1.0


static func _snap(stars: float) -> float:
	return clampf(snappedf(stars, 0.5), 0.5, 5.0)


## Full coach report for a squad instance. Cached per league state.
static func report(inst: Dictionary) -> Dictionary:
	var uid := str(inst.get("uid", ""))
	_league()  # refresh cache key first
	if _report_cache.has(uid):
		return _report_cache[uid]

	var sp: Dictionary = DataStore.species(int(inst["species_id"]))
	var mv_now := best_move(sp, inst.get("moves", []))
	var rn := raw_score(UI.effective_stats(inst), float(mv_now["score"]))
	var peak := peak_projection(inst)
	var rp := maxf(float(peak["raw"]), rn)

	var pct_now := percentile(rn)
	var pct_pot := percentile(rp)
	var true_now := stars_from_pct(pct_now)
	var true_pot := maxf(stars_from_pct(pct_pot), true_now)

	var j := judges()
	var ja := int(j["ja"])
	var jp := int(j["jp"])
	# Perceived current: error grows as judging_ability falls (max +-0.75 star).
	var now := _snap(true_now + _noise(uid, "ca") * float(20 - ja) / 20.0 * 0.75)
	# Perceived potential: centre wobbles with judging_potential, and the
	# quoted range widens as the judge gets worse.
	var pot_c := _snap(maxf(true_pot + _noise(uid, "pa") * float(20 - jp) / 20.0 * 1.0, now))
	# An elite judge quotes an exact potential; weaker ones a widening range.
	var half_w := 0.0
	if jp < 18:
		half_w = 0.5
	if jp < 14:
		half_w = 1.0
	if jp < 10:
		half_w = 1.5
	var pot_lo := _snap(maxf(pot_c - half_w, now))
	var pot_hi := _snap(maxf(pot_c + half_w, pot_lo))
	var confidence := "High" if jp >= 16 else ("Fair" if jp >= 11 else "Low")

	# IV summary numbers for the report body.
	var ivs: Dictionary = inst.get("ivs", {})
	var iv_sum := 0
	var proj_sum := 0
	for k in STAT_KEYS:
		iv_sum += int(ivs.get(k, 8))
		proj_sum += int((peak["ivs"] as Dictionary)[k])

	var out := {
		"now": now, "pot": pot_c, "pot_lo": pot_lo, "pot_hi": pot_hi,
		"true_now": true_now, "true_pot": true_pot,
		"pct_now": pct_now, "pct_pot": pct_pot,
		"league_n": league_size(),
		"ja": ja, "ja_name": j["ja_name"], "jp": jp, "jp_name": j["jp_name"],
		"confidence": confidence,
		"iv_pct": int(round(float(iv_sum) / 90.0 * 100.0)),
		"iv_pct_peak": int(round(float(proj_sum) / 90.0 * 100.0)),
		"realise": float(peak["frac"]),
		"move_now": mv_now["name"], "move_ceiling": peak["move_name"],
	}
	var verdict := _verdict(out, inst)
	out["verdict"] = verdict["word"]
	out["verdict_color"] = verdict["color"]
	out["reason"] = verdict["reason"]
	_report_cache[uid] = out
	return out


static func ability_word(stars: float) -> String:
	if stars >= 5.0: return I18n.t("Elite for this league")
	if stars >= 4.5: return I18n.t("Leading battler")
	if stars >= 4.0: return I18n.t("Excellent")
	if stars >= 3.5: return I18n.t("Good league level")
	if stars >= 3.0: return I18n.t("Decent")
	if stars >= 2.5: return I18n.t("Fair")
	if stars >= 2.0: return I18n.t("Weak")
	if stars >= 1.5: return I18n.t("Poor")
	return I18n.t("Far below league level")


## Keep / develop / sell call from perceived ratings, age and headroom.
static func _verdict(r: Dictionary, inst: Dictionary) -> Dictionary:
	var now := float(r["now"])
	var pot := (float(r["pot_lo"]) + float(r["pot_hi"])) / 2.0
	var age := int(inst.get("age_months", 48))
	var top_pct := int(round((1.0 - float(r["pct_now"])) * 100.0))
	if now >= 4.25:
		return {"word": "Key battler", "color": UI.COL_GOOD, "reason":
			I18n.t("Top %d%% of the league's %d battlers right now — build the side around them.") % [maxi(top_pct, 1), int(r["league_n"])]}
	if pot - now >= 1.0 and age < 48:
		return {"word": "Develop", "color": UI.COL_ACCENT.lightened(0.25), "reason":
			I18n.t("Clear headroom (%s -> %s potential): young enough to realise ~%d%% of the remaining IV ceiling. Give battles and focused training.") %
			[stars_text(now), stars_range_text(float(r["pot_lo"]), float(r["pot_hi"])), int(round(float(r["realise"]) * 100.0))]}
	if now >= 3.5:
		return {"word": "First team", "color": Color("a8c96a"), "reason":
			I18n.t("Comfortably first-team level (top %d%% of the league). A regular starter.") % maxi(top_pct, 1)}
	if age >= 84 and now < 3.5:
		return {"word": "Aging", "color": UI.COL_WARN, "reason":
			I18n.t("Veteran at %s with almost no development left — plan a succession and consider cashing in.") % UI.age_str(age)}
	if now >= 2.5:
		return {"word": "Squad depth", "color": UI.COL_TEXT, "reason":
			"Useful rotation piece, but not first-team quality and limited headroom."}
	return {"word": "Surplus", "color": UI.COL_BAD, "reason":
		I18n.t("Below league level (bottom %d%%) with little realistic improvement — a candidate to sell or release.") % maxi(100 - top_pct, 1)}


# ================================================================ formatting

static func stars_text(stars: float) -> String:
	var whole := int(stars)
	var half := stars - float(whole) >= 0.25
	if whole == 0 and half:
		return "1/2"
	return str(whole) + (" 1/2" if half else "")


static func stars_range_text(lo: float, hi: float) -> String:
	if is_equal_approx(lo, hi):
		return stars_text(lo)
	return "%s - %s" % [stars_text(lo), stars_text(hi)]


# ================================================================ star icons

## 5-star row texture. `lo`..`hi` renders an uncertainty band: solid fill to
## lo, dimmed fill to hi, empty beyond. Pass lo == hi for a plain rating.
static func stars_icon(lo: float, hi: float = -1.0, fill: Color = COL_STARS_NOW,
		cell: int = 13) -> ImageTexture:
	if hi < 0.0:
		hi = lo
	hi = maxf(hi, lo)
	var key := "st:%.1f:%.1f:%s:%d" % [lo, hi, fill.to_html(), cell]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var gap := 2
	var w := cell * 5 + gap * 4
	var img := Image.create(w, cell, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var band := Color(COL_STARS_RANGE.r, COL_STARS_RANGE.g, COL_STARS_RANGE.b).lerp(fill, 0.35)
	band.a = 0.85
	for i in 5:
		var x0 := i * (cell + gap)
		var poly := _star_poly(Vector2(x0 + cell / 2.0, cell / 2.0), cell / 2.0)
		for px in cell:
			for py in cell:
				var cov := 0.0
				var frac_sum := 0.0
				for off: Vector2 in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]:
					var pt: Vector2 = Vector2(x0 + px, py) + off
					if Geometry2D.is_point_in_polygon(pt, poly):
						cov += 0.25
						frac_sum += float(i) + clampf((pt.x - x0) / float(cell), 0.0, 1.0)
				if cov <= 0.0:
					continue
				var f := frac_sum / (cov * 4.0)
				var c := COL_STARS_EMPTY
				if f <= lo + 0.02:
					c = fill
				elif f <= hi + 0.02:
					c = band
				img.set_pixel(x0 + px, py, Color(c.r, c.g, c.b, c.a * cov))
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[key] = tex
	return tex


static func _star_poly(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + float(i) * PI / 5.0
		var rad := r if i % 2 == 0 else r * 0.45
		pts.append(center + Vector2(cos(ang), sin(ang)) * rad)
	return pts
