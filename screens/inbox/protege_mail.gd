extends RefCounted
## Renderer for the Manager's Protégé mail arc (starter-companion piece).
## Messages carry protege_kind (selection / debut / first_ko / evolution /
## final_form / rival_evolution / transfer / mind / staff notes) plus a
## JSON-safe snapshot taken on send day (species, nickname, level, in_academy).
## Loaded lazily and defensively by report_gen.render() — the inbox keeps
## working unchanged if this file is absent.

const C_WHITE := "e8ebf5"
const C_DIM := "8b91a8"
const C_ACC := "9a8cff"
const C_GOLD := "e8c15a"

const KIND_TAGS := {
	"selection": "THE CEREMONY",
	"debut": "MILESTONE — FIRST-TEAM DEBUT",
	"first_ko": "MILESTONE — FIRST KO",
	"evolution": "MILESTONE — EVOLUTION",
	"final_form": "FRONT PAGE — FINAL FORM",
	"rival_evolution": "RIVAL WATCH",
	"transfer": "THE PROTÉGÉ FOLLOWS",
	"mind": "PROTÉGÉ RIVALRY",
}


func render(msg: Dictionary) -> Dictionary:
	var kind := str(msg.get("protege_kind", "note"))
	var tag := I18n.t(str(KIND_TAGS.get(kind, "MANAGER'S PROTÉGÉ")))
	var species := str(msg.get("species", ""))
	var nick := str(msg.get("nickname", ""))
	var who := ("%s (%s)" % [nick, species]) if nick != "" and nick != species else species
	var col := C_GOLD if kind in ["final_form", "selection"] else C_ACC

	var bb := "[color=#%s][b]%s[/b][/color]" % [col, tag]
	if who != "":
		bb += "  [color=#%s]·  %s" % [C_DIM, who]
		if int(msg.get("level", 0)) > 0:
			bb += "  ·  Lv %d" % int(msg.get("level", 0))
		bb += "[/color]"
	bb += "\n\n[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))]
	var sender := str(msg.get("sender", ""))
	if sender != "":
		bb += "\n\n[color=#%s]— %s[/color]" % [C_DIM, sender]

	var actions: Array = []
	if bool(msg.get("in_academy", false)):
		actions.append({"label": I18n.t("Go to Academy"), "screen": "academy"})
	else:
		actions.append({"label": I18n.t("View Squad"), "screen": "squad"})
	if kind == "mind":
		actions.append({"label": I18n.t("Go to Fixture"), "screen": "competition"})
		actions.append({"label": I18n.t("Tactics"), "screen": "tactics"})
	return {"bbcode": bb, "actions": actions, "banner": {}}
