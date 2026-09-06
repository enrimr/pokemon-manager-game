extends Node
## Guards the pack-lexicon mechanism (theming, docs/THEMING.md §3.4): a pack
## overrides sport vocabulary by SHADOWING i18n keys per locale. Godot 4.6
## resolves the FIRST translation added for a locale — Packs.install_lexicon
## relies on that to outrank the base catalog. This check injects a fake
## overlay and asserts it wins in en (no base catalog) AND es (real catalog).
## Run: godot --headless --path . res://tools/lexicon_check.tscn

var _fails := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		printerr("  LEXICON FAIL: %s" % what)
		_fails += 1


func _ready() -> void:
	print("=== pack lexicon check ===")
	# a base es row that really exists in the compiled catalog
	TranslationServer.set_locale("es")
	var base_es := tr("Continue")
	_check(base_es != "Continue", "base es catalog live ('Continue' -> '%s')" % base_es)

	Packs.install_lexicon({
		"en": {"Continue": "PROCEED-EN", "__lex_probe": "PROBE-EN"},
		"es": {"Continue": "PROCEED-ES"},
	})
	_check(tr("Continue") == "PROCEED-ES", "es overlay OUTRANKS the base catalog")
	TranslationServer.set_locale("en")
	_check(tr("Continue") == "PROCEED-EN", "en overlay applies")
	_check(tr("__lex_probe") == "PROBE-EN", "en overlay adds brand-new keys")
	_check(tr("Match report: %d-%d vs %s") == "Match report: %d-%d vs %s",
		"unrelated keys pass through untouched")
	TranslationServer.set_locale("es")
	_check(tr("Squad") != "PROCEED-ES", "unrelated es keys unaffected")

	if _fails == 0:
		print("LEXICON CHECK OK")
	else:
		printerr("LEXICON CHECK FAILED")
	get_tree().quit(0 if _fails == 0 else 1)
