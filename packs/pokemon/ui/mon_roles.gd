class_name MonRoles
extends Object
## Battle ROLES (transfers piece, shared everywhere): an FM-style position
## label derived from a species' base stats + learnset, so managers can shop
## for "a wall" or "a sweeper" instead of reading six stat columns blind.
##
##   wall     — soaks hits, thin offence            (Muro)
##   sweeper  — fast and hard-hitting               (Vanguardia)
##   tank     — hits hard AND takes hits            (Ariete)
##   striker  — massive offence, glass body         (Cañón de cristal)
##   support  — status-move toolkit                 (Táctico)
##   allround — a bit of everything                 (Todoterreno)

const ROLES := ["wall", "sweeper", "tank", "striker", "support", "allround"]
const NAMES := {"wall": "Wall", "sweeper": "Sweeper", "tank": "Bulky Attacker",
	"striker": "Glass Cannon", "support": "Support", "allround": "All-Rounder"}
const COLORS := {"wall": Color("6890f0"), "sweeper": Color("f8d030"),
	"tank": Color("c03028"), "striker": Color("f08030"),
	"support": Color("78c850"), "allround": Color("a8a090")}

static var _cache: Dictionary = {}


static func role_of(species_id: int) -> String:
	if _cache.has(species_id):
		return _cache[species_id]
	var sp: Dictionary = DataStore.species(species_id)
	var role := "allround"
	if not sp.is_empty():
		var b: Dictionary = sp.get("base", {})
		var off := maxf(float(b.get("atk", 50)), float(b.get("spa", 50)))
		var bulk := (float(b.get("hp", 50)) + float(b.get("def", 50)) + float(b.get("spd", 50))) / 3.0
		var spe := float(b.get("spe", 50))
		var status := 0
		var learnset: Array = sp.get("learnset", [])
		for mv in learnset:
			if str(DataStore.move(str(mv)).get("category", "")) == "status":
				status += 1
		var status_ratio := float(status) / maxf(float(learnset.size()), 1.0)
		if bulk >= 82.0 and off < 75.0:
			role = "wall"
		elif spe >= 85.0 and off >= 82.0:
			role = "sweeper"
		elif off >= 82.0 and bulk >= 75.0:
			role = "tank"
		elif off >= 92.0:
			role = "striker"
		elif status_ratio >= 0.5:
			role = "support"
	_cache[species_id] = role
	return role


static func role_name(role: String) -> String:
	return I18n.t(str(NAMES.get(role, "All-Rounder")))


static func name_of(species_id: int) -> String:
	return role_name(role_of(species_id))


static func role_color(role: String) -> Color:
	return COLORS.get(role, Color("a8a090"))


## Small role chip (mobile squad/club rows) matching the type-chip styling.
static func chip(species_id: int, font_size: int = 9) -> Control:
	var role := role_of(species_id)
	var col := role_color(role)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ThemeBuilder._flat(col.darkened(0.55), col, 4, 6, 2))
	var l := Label.new()
	l.text = role_name(role).to_upper()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color("f0f2fa"))
	p.add_child(l)
	return p
