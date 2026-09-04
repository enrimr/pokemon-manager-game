extends Node
## GameAnalytics bridge — web builds only.
##
## Loads the official GameAnalytics JavaScript SDK at runtime through
## JavaScriptBridge (no custom HTML shell needed, so every re-export keeps
## working) and forwards gameplay design events. Sessions, DAU/retention and
## the anonymous player id are handled by the SDK itself.
##
## Everything is a silent no-op on desktop/headless builds or while the keys
## below are unset, so QA scripts and native builds are unaffected.
##
## Keys live at gameanalytics.com -> your game -> Settings -> Game keys.

const GAME_KEY := "657bca11d21b4027af7328b095dab991"
const SECRET_KEY := "f02121db3e66e395be51378e799dccae926a3914"
const SDK_URL := "https://download.gameanalytics.com/js/GameAnalytics-4.4.5.min.js"

const MAX_PENDING := 128   # events buffered while the SDK script downloads

var _sdk_ready := false
var _pending: Array[String] = []
var _on_sdk_ready_cb: JavaScriptObject   # kept referenced or the callback dies


func _ready() -> void:
	if not enabled():
		return
	GameState.season_rolled.connect(func(n: int): event("season:rolled", n))
	GameState.game_over.connect(func(_info: Dictionary): event("career:game_over"))
	_inject_sdk()


func enabled() -> bool:
	return OS.has_feature("web") and GAME_KEY != "" and SECRET_KEY != ""


## Design event. `id` uses GameAnalytics' "part1:part2:..." hierarchy (max 5
## parts); `value` is an optional number attached to the event.
func event(id: String, value = null) -> void:
	if not enabled():
		return
	var args := JSON.stringify(_sanitize_id(id))
	if value != null:
		args += ", %s" % JSON.stringify(float(value))
	_run("gameanalytics.GameAnalytics.addDesignEvent(%s);" % args)


func screen(name: String) -> void:
	event("screen:%s" % name)


## One event per player match with mode ("live" battles vs "sim" delegation),
## verdict and competition baked into the id; value = battles we won.
func match_played(mode: String, comp: String, us: int, them: int) -> void:
	var verdict := "win" if us > them else ("loss" if us < them else "draw")
	event("match:%s:%s:%s" % [mode, verdict, comp], us)


# ------------------------------------------------------------------ plumbing

func _inject_sdk() -> void:
	_on_sdk_ready_cb = JavaScriptBridge.create_callback(_on_sdk_ready)
	var window := JavaScriptBridge.get_interface("window")
	window.__tm_ga_ready = _on_sdk_ready_cb
	JavaScriptBridge.eval("""
		(function () {
			if (window.__tm_ga_loading) return;
			window.__tm_ga_loading = true;
			var s = document.createElement('script');
			s.src = %s;
			s.onload = function () {
				var GA = gameanalytics.GameAnalytics;
				GA.configureBuild(%s);
				GA.initialize(%s, %s);
				window.__tm_ga_ready();
			};
			document.head.appendChild(s);
		})();
	""" % [JSON.stringify(SDK_URL), JSON.stringify(_build_version()),
		JSON.stringify(GAME_KEY), JSON.stringify(SECRET_KEY)], true)


func _on_sdk_ready(_args: Array) -> void:
	_sdk_ready = true
	for js in _pending:
		JavaScriptBridge.eval(js, true)
	_pending.clear()


func _run(js: String) -> void:
	if _sdk_ready:
		JavaScriptBridge.eval(js, true)
	elif _pending.size() < MAX_PENDING:
		_pending.append(js)


func _build_version() -> String:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else "dev"


## GameAnalytics only accepts [A-Za-z0-9 -_.():!?;*+] in ids, 1-64 chars per
## part, max 5 parts.
func _sanitize_id(id: String) -> String:
	var re := RegEx.create_from_string("[^A-Za-z0-9\\s\\-_.():!?;*+]")
	var parts := id.split(":", false)
	var out: Array[String] = []
	for p in parts.slice(0, 5):
		var clean := re.sub(p, "_", true).substr(0, 64)
		out.append(clean if clean != "" else "_")
	return ":".join(out)
