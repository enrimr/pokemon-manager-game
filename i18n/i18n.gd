class_name I18n
## Localization helpers (spanish piece). All static and locale-driven, safe
## from any context (RefCounted generators, static funcs, tool scripts).
##
## Pattern used across the game (see artifacts/spanish/README.md):
## - Static Control text translates automatically via the catalog
##   (i18n/translations.csv, keys = English source strings).
## - Composed strings use tr("template %s") % args at the call site.
## - Sim-layer display helpers (Season.pretty_date/comp_label/round names)
##   stay English internally — UI code routes them through these wrappers so
##   headless checks keep asserting stable English strings.

static func t(s: String) -> String:
	return TranslationServer.translate(s)


## Boot-order shim: GameState (autoload #2) boots careers — and writes inbox
## mail — BEFORE the Settings autoload applies the saved locale. Calling this
## first makes boot-time text (welcome mail, incompatible-save note, seeded
## rumours) come out in the player's language instead of English.
static func apply_saved_locale() -> void:
	if DisplayServer.get_name() == "headless":
		return  # headless checks assert English strings (see settings_service)
	if not FileAccess.file_exists("user://settings.json"):
		return
	var f := FileAccess.open("user://settings.json", FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary and data.has("locale") and String(data["locale"]) != "":
		TranslationServer.set_locale(String(data["locale"]))


# --------------------------------------------------------------- entity names
# Canonical entity names (moves, items, abilities, types) live in English in
# the data layer and sim events; every UI surface must route them through
# these helpers so the es catalog applies on match/stats/search screens too.

## Localized move display name ("Body Slam" -> "Golpe Cuerpo").
static func move_name(n: String) -> String:
	return t(n)


## Localized item display name from an item id ("quick_claw" -> "Garra Rápida").
static func item_name(id: String) -> String:
	return t(DataStore.item_name(id))


## Localized item effect description from an item id.
static func item_desc(id: String) -> String:
	return t(str(DataStore.item(id).get("desc", "")))


## Localized ability display name from an ability id ("intimidate" -> "Intimidación").
static func ability_name(id: String) -> String:
	return t(DataStore.ability_name(id))


## Localized type name. Accepts any case and slash-compounds:
## "psychic" -> "Psíquico", "water/psychic" -> "Agua/Psíquico".
static func type_name(raw: String) -> String:
	var parts := raw.split("/")
	var out: Array = []
	for p in parts:
		var s := String(p).strip_edges()
		if s == "":
			continue
		out.append(t(s.capitalize()))
	return "/".join(out)


## Localized " / "-joined type list for table columns ("Water / Psychic").
static func types_join(types: Array, sep: String = "/") -> String:
	var out: Array = []
	for ty in types:
		out.append(t(String(ty).capitalize()))
	return sep.join(out)


## English-plural-suffix-free plural chooser: both keys are full templates
## containing one %d, so every language keeps correct morphology.
static func np(count: int, singular_key: String, plural_key: String) -> String:
	return (t(singular_key) % count) if count == 1 else (t(plural_key) % count)


## Locale-aware thousands grouping: 1356000 -> "1,356,000" (en) / "1.356.000" (es).
static func number(v: int) -> String:
	var sep := "." if TranslationServer.get_locale().begins_with("es") else ","
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = sep + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


## Locale-aware decimal: 1.5 -> "1.5" (en) / "1,5" (es).
static func decimal(x: float, decimals: int = 1) -> String:
	var s := ("%.*f" % [decimals, x])
	if TranslationServer.get_locale().begins_with("es"):
		s = s.replace(".", ",")
	return s


## Localized calendar date, e.g. "12 Aug 2026" -> "12 ago 2026".
static func pretty_date(date_str: String) -> String:
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var parts := date_str.split("-")
	if parts.size() != 3:
		return date_str
	return "%d %s %s" % [int(parts[2]), t(months[int(parts[1]) - 1]), parts[0]]


## Compact localized day+month, e.g. "2026-08-01" -> "1 Aug" / "1 ago".
static func short_date(date_str: String) -> String:
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var parts := date_str.split("-")
	if parts.size() != 3:
		return date_str
	return "%d %s" % [int(parts[2]), t(months[int(parts[1]) - 1])]


static func cup_round(round_no: int) -> String:
	return t(Season.cup_round_name(round_no))


static func playoff_round(round_no: int) -> String:
	return t(Season.playoff_round_name(round_no))


## Round name for MID-SENTENCE prose. Spanish round names carry mixed
## gender/number ("los cuartos de final" vs "la semifinal"), so composing
## "en la %s" in a template breaks for Cuartos. This returns the es name
## with its own article, lowercase, ready to sit after "en"/"para"/"de";
## English keeps the plain proper name (templates already carry "the").
static func round_prose(name_en: String) -> String:
	if not TranslationServer.get_locale().begins_with("es"):
		return t(name_en)
	match name_en:
		"First Round": return "la primera ronda"
		"Second Round": return "la segunda ronda"
		"Quarter-Final": return "los cuartos de final"
		"Semi-Final": return "la semifinal"
		"Final": return "la final"
	return t(name_en)


static func cup_round_prose(round_no: int) -> String:
	return round_prose(Season.cup_round_name(round_no))


static func playoff_round_prose(round_no: int) -> String:
	return round_prose(Season.playoff_round_name(round_no))


## Mid-sentence competition prose for any fixture: "the league" /
## "los cuartos de final" (cup) / "la final" (playoff). Playoff fixtures used
## to fall into the CUP naming and mislabel rounds (user report: the
## Championship Series Final rendered as "Copa Añil · Cuartos de final").
static func comp_prose(f: Dictionary) -> String:
	match str(f.get("comp", "")):
		"cup":
			return cup_round_prose(int(f.get("round", 1)))
		"playoff":
			return playoff_round_prose(int(f.get("round", 1)))
	return t("league")


## Localized Season.comp_label (league / cup / playoff fixture label).
static func comp_label(f: Dictionary) -> String:
	match str(f.get("comp", "")):
		"cup":
			return "%s · %s" % [t(GameState.cup_name()), cup_round(int(f.get("round", 1)))]
		"playoff":
			return "%s · %s" % [t(Season.PLAYOFF_NAME), playoff_round(int(f.get("round", 1)))]
	return "%s · %s" % [t(GameState.league_name(str(f.get("league", "")))),
		t("Matchday %d") % int(f.get("round", 1))]


## Localized ordinal: 3 -> "3rd" (en) / "3.º" (es).
static func ordinal(n: int) -> String:
	if n <= 0:
		return "—"
	if TranslationServer.get_locale().begins_with("es"):
		return "%d.º" % n
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


## Localized month-name-free short date "Sat 12 Aug".
static func weekday(date_str: String) -> String:
	var days := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	var parts := date_str.split("-")
	if parts.size() != 3:
		return date_str
	var unix := Time.get_unix_time_from_datetime_dict({"year": int(parts[0]),
		"month": int(parts[1]), "day": int(parts[2]), "hour": 12, "minute": 0, "second": 0})
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return t(days[int(d["weekday"]) % 7])
