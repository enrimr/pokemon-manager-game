class_name AudioManager
extends Node
## Trainer Manager audio engine (audio piece).
##
## Instanced once by the shell (res://shared/audio/audio_manager.tscn). All
## public access is static and null-safe — safe to call from any screen even
## if the shell (and therefore the manager) isn't running (headless tools).
##
##     AudioManager.play("confirm")          # one-shot SFX by short name
##     AudioManager.set_ambience("match")    # ""/"menu"/"match"
##     AudioManager.on_screen_changed(name)  # shell nav hook (music+ambience)
##     AudioManager.on_battle_event(ev)      # match piece: engine event -> SFX
##     AudioManager.crowd("roar")            # roar/gasp/cheer/chant
##
## Buses: Master / Music / SFX / Ambience (created at runtime if missing).
## Volume OWNERSHIP CONTRACT (agreed with the platform piece):
## - STORAGE: the Settings autoload (screens/settings/settings_service.gd,
##   keys audio_master/audio_music/audio_sfx/audio_ambience, linear 0..1,
##   user://settings.json) is the persisted source of truth when present;
##   set_volume() writes THROUGH Settings.set_setting(). Standalone boots
##   fall back to user://audio_settings.json (+ "audio_enabled" switch).
## - APPLICATION: while AudioManager.instance is alive IT applies the bus
##   volumes (Settings._apply_audio defers to it); it listens to
##   Settings.setting_changed so the Settings screen's Audio tab sliders work.
## Music auto-ducks -7 dB under big SFX and recovers to the set value.
## All WAVs are original procedural material from tools/gen_audio.py.

static var instance: AudioManager = null

const DIR := "res://assets/audio/"
const SETTINGS_PATH := "user://audio_settings.json"
const SETTINGS_KEYS := {
	"audio_master": "Master", "audio_music": "Music",
	"audio_sfx": "SFX", "audio_ambience": "Ambience",
}

## short name -> [file, base gain db]
const SOUNDS := {
	"click": ["ui_click", -6.0], "hover": ["ui_hover", -14.0],
	"confirm": ["ui_confirm", -6.0], "error": ["ui_error", -7.0],
	"mail": ["ui_mail", -5.0], "continue": ["ui_continue", -5.0],
	"back": ["ui_back", -8.0],
	"hit_phys": ["hit_phys", -3.0], "hit_zap": ["hit_zap", -4.0],
	"hit_splash": ["hit_splash", -4.0], "hit_flame": ["hit_flame", -4.0],
	"hit_whoosh": ["hit_whoosh", -4.0], "hit_burst": ["hit_burst", -4.0],
	"hit_super": ["hit_super", -1.0], "hit_weak": ["hit_weak", -6.0],
	"miss": ["miss", -8.0], "faint": ["faint", -3.0],
	"switch": ["switch", -6.0], "item": ["item", -5.0],
	"status": ["status", -6.0], "stat_up": ["stat_up", -7.0],
	"stat_down": ["stat_down", -7.0], "heal": ["heal", -6.0],
	"weather": ["weather", -6.0],
	"crowd_roar": ["crowd_roar", -5.0], "crowd_gasp": ["crowd_gasp", -6.0],
	"crowd_cheer": ["crowd_cheer", -4.0], "crowd_chant": ["crowd_chant", -12.0],
}
const MENU_TRACKS := ["music_menu_a", "music_menu_b"]
const DUCKERS := ["hit_super", "faint", "crowd_roar", "crowd_cheer"]

var _streams: Dictionary = {}       # file -> AudioStream
var _sfx_pool: Array = []           # AudioStreamPlayer x10
var _pool_i := 0
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _chant: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _volumes := {"Master": 0.9, "Music": 0.55, "SFX": 0.8, "Ambience": 0.7}
var _enabled := true
var _ambience_kind := ""
var _menu_track_i := 0
var _boot_ms := 0
var _last_mail_ms := -10000
var _last_hover_ms := -10000
var _last_battle_ms := -10000
var _last_crowd_ms := -10000
var _duck_tween: Tween
var _chant_timer: Timer
var debug := false                  # AUDIO_DEBUG=1 prints every play
var plays: Dictionary = {}          # sound name -> times played (proof/QA)
# headless (dummy audio device): run all logic/routing/counters but skip actual
# playback — Dummy-driver playbacks are never reaped and flag resource leaks.
var silent := false


func _ready() -> void:
	instance = self
	debug = OS.get_environment("AUDIO_DEBUG") == "1"
	silent = DisplayServer.get_name() == "headless"
	_boot_ms = Time.get_ticks_msec()
	_make_buses()
	_load_settings()
	_load_streams()
	_make_players()
	_apply_volumes()
	# auto-wire every BaseButton in the game for click/hover feedback
	get_tree().node_added.connect(_on_node_added)
	_wire_existing(get_tree().root)
	# mail arrival ding (inbox_updated only fires on add)
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("inbox_updated"):
		gs.connect("inbox_updated", _on_mail)
	set_ambience_i("menu")


func _exit_tree() -> void:
	if instance == self:
		instance = null
	# release every stream reference so nothing is "still in use at exit"
	for p in [_music, _ambience, _chant, _crowd] + _sfx_pool:
		if p != null:
			p.stop()
			p.stream = null
	_streams.clear()


func _make_buses() -> void:
	for b in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(b) == -1:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func _load_streams() -> void:
	var seen := {}
	for entry in SOUNDS.values():
		seen[entry[0]] = true
	for f in MENU_TRACKS + ["music_matchday", "ambience_stadium"]:
		seen[f] = true
	for f in seen:
		var path: String = DIR + f + ".wav"
		if ResourceLoader.exists(path):
			_streams[f] = load(path)
		else:
			push_warning("AudioManager: missing sound %s" % path)
	# loops: ambience + chant + matchday music loop forward
	for f in ["ambience_stadium", "crowd_chant", "music_matchday"]:
		var s: AudioStreamWAV = _streams.get(f)
		if s != null:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = s.data.size() / 2 / (2 if s.stereo else 1)


func _make_players() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	add_child(_ambience)
	_chant = AudioStreamPlayer.new()
	_chant.bus = "Ambience"
	add_child(_chant)
	_crowd = AudioStreamPlayer.new()
	_crowd.bus = "Ambience"
	add_child(_crowd)
	_chant_timer = Timer.new()
	_chant_timer.one_shot = true
	_chant_timer.timeout.connect(_chant_burst)
	add_child(_chant_timer)


# ---------------------------------------------------------------- settings


func _settings_autoload() -> Node:
	# platform piece's Settings service — the volume source of truth when present
	return get_node_or_null("/root/Settings")


func _key_for(bus: String) -> String:
	for key in SETTINGS_KEYS:
		if SETTINGS_KEYS[key] == bus:
			return key
	return ""


func _load_settings() -> void:
	var sv := _settings_autoload()
	if sv != null:
		for key in SETTINGS_KEYS:
			_volumes[SETTINGS_KEYS[key]] = clampf(float(sv.call("get_setting", key, 0.8)), 0.0, 1.0)
		if sv.has_signal("setting_changed"):
			sv.connect("setting_changed", _on_setting_changed)
		return
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for key in SETTINGS_KEYS:
				if d.has(key):
					_volumes[SETTINGS_KEYS[key]] = clampf(float(d[key]), 0.0, 1.0)
			if d.has("audio_enabled"):
				_enabled = bool(d["audio_enabled"])


func _on_setting_changed(key: String, value: Variant) -> void:
	if SETTINGS_KEYS.has(key):
		_volumes[SETTINGS_KEYS[key]] = clampf(float(value), 0.0, 1.0)
		if key == "audio_music" and _duck_tween != null and _duck_tween.is_valid():
			_duck_tween.kill()  # slider moved mid-duck: the new value wins
		_apply_volumes()


func _save_settings() -> void:
	if _settings_autoload() != null:
		return  # Settings service persists user://settings.json itself
	var d := {"audio_enabled": _enabled}
	for key in SETTINGS_KEYS:
		d[key] = _volumes[SETTINGS_KEYS[key]]
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


func _apply_volumes() -> void:
	# AudioManager applies bus volumes while alive (Settings defers to us)
	for bus in _volumes:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(_volumes[bus], 0.0001)))
			AudioServer.set_bus_mute(i, not _enabled or _volumes[bus] <= 0.001)


# ---------------------------------------------------------------- static API


static func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if instance != null:
		instance.play_i(name, vol_db, pitch)


static func set_ambience(kind: String) -> void:
	if instance != null:
		instance.set_ambience_i(kind)


static func on_screen_changed(screen_name: String) -> void:
	if instance != null:
		instance.set_ambience_i("match" if screen_name == "match" else "menu")


static func on_battle_event(ev: Dictionary) -> void:
	if instance != null:
		instance.battle_event_i(ev)


static func crowd(kind: String) -> void:
	if instance != null:
		instance.crowd_i(kind)


static func set_volume(bus: String, v: float) -> void:  # "Master"/"Music"/"SFX"/"Ambience"
	if instance == null or not instance._volumes.has(bus):
		return
	instance._volumes[bus] = clampf(v, 0.0, 1.0)
	instance._apply_volumes()
	var sv := instance._settings_autoload()
	if sv != null:
		# write-through: Settings persists user://settings.json + signals
		sv.call("set_setting", instance._key_for(bus), instance._volumes[bus])
	else:
		instance._save_settings()


static func volume(bus: String) -> float:
	return instance._volumes.get(bus, 1.0) if instance != null else 1.0


static func set_enabled(on: bool) -> void:
	if instance == null:
		return
	instance._enabled = on
	instance._apply_volumes()
	var mi := AudioServer.get_bus_index("Master")
	if mi >= 0:
		AudioServer.set_bus_mute(mi, not on)
	instance._save_settings()


static func enabled() -> bool:
	return instance != null and instance._enabled


# ---------------------------------------------------------------- playback


func play_i(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not _enabled or not SOUNDS.has(name):
		return
	var entry: Array = SOUNDS[name]
	var stream: AudioStream = _streams.get(entry[0])
	if stream == null:
		return
	var p: AudioStreamPlayer = _sfx_pool[_pool_i]
	_pool_i = (_pool_i + 1) % _sfx_pool.size()
	p.stream = stream
	p.volume_db = entry[1] + vol_db
	p.pitch_scale = pitch
	if not silent:
		p.play()
	plays[name] = int(plays.get(name, 0)) + 1
	if name in DUCKERS:
		_duck()
	if debug:
		print("[audio] play %s" % name)


func _duck() -> void:
	var i := AudioServer.get_bus_index("Music")
	if i < 0:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	var base := linear_to_db(maxf(_volumes["Music"], 0.0001))
	AudioServer.set_bus_volume_db(i, base - 7.0)
	_duck_tween = create_tween()
	_duck_tween.tween_interval(0.5)
	_duck_tween.tween_method(
		func(v: float): AudioServer.set_bus_volume_db(i, v), base - 7.0, base, 0.7)


# ---------------------------------------------------------------- music + ambience


func set_ambience_i(kind: String) -> void:
	if kind == _ambience_kind:
		return
	_ambience_kind = kind
	if debug:
		print("[audio] ambience -> %s" % (kind if kind != "" else "off"))
	match kind:
		"match":
			_fade(_ambience, _streams.get("ambience_stadium"), -8.0, 1.2)
			_fade(_music, _streams.get("music_matchday"), -10.0, 1.5)
			_chant_timer.start(randf_range(12.0, 22.0))
		"menu":
			_fade(_ambience, null, -60.0, 0.8)
			_chant_timer.stop()
			_chant.stop()
			if not _music.playing or _music.stream != _streams.get(MENU_TRACKS[_menu_track_i]):
				_fade(_music, _streams.get(MENU_TRACKS[_menu_track_i]), -6.0, 1.0)
		_:
			_fade(_ambience, null, -60.0, 0.8)
			_fade(_music, null, -60.0, 0.8)
			_chant_timer.stop()
			_chant.stop()


func _fade(p: AudioStreamPlayer, stream: AudioStream, target_db: float, dur: float) -> void:
	if stream == null and not p.playing:
		return
	var tw := create_tween()
	if p.playing and p.stream != stream:
		tw.tween_property(p, "volume_db", -50.0, dur * 0.5)
		tw.tween_callback(func():
			p.stop()
			if stream != null:
				p.stream = stream
				p.volume_db = -50.0
				if not silent:
					p.play())
		if stream != null:
			tw.tween_property(p, "volume_db", target_db, dur * 0.5)
	elif stream != null:
		if not p.playing:
			p.stream = stream
			p.volume_db = -50.0
			if not silent:
				p.play()
		tw.tween_property(p, "volume_db", target_db, dur)


func _on_music_finished() -> void:
	# menu tracks don't loop — rotate to the next one for variety
	if _ambience_kind == "menu":
		_menu_track_i = (_menu_track_i + 1) % MENU_TRACKS.size()
		var s: AudioStream = _streams.get(MENU_TRACKS[_menu_track_i])
		if s != null:
			_music.stream = s
			_music.volume_db = -6.0
			if not silent:
				_music.play()


func _chant_burst() -> void:
	# occasional short crowd chant during matchday ambience
	if _ambience_kind == "match" and _enabled:
		var s: AudioStream = _streams.get("crowd_chant")
		if s != null:
			_chant.stream = s
			_chant.volume_db = SOUNDS["crowd_chant"][1]
			if not silent:
				_chant.play()
				get_tree().create_timer(s.get_length() * 2.0).timeout.connect(_chant.stop)
		_chant_timer.start(randf_range(35.0, 60.0))


func crowd_i(kind: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_crowd_ms < 3500 or not _enabled:
		return
	_last_crowd_ms = now
	var name := "crowd_" + kind
	if not SOUNDS.has(name):
		return
	_crowd.stream = _streams.get(SOUNDS[name][0])
	_crowd.volume_db = SOUNDS[name][1]
	_crowd.pitch_scale = randf_range(0.96, 1.04)
	if not silent:
		_crowd.play()
	plays[name] = int(plays.get(name, 0)) + 1
	if name in DUCKERS:
		_duck()
	if debug:
		print("[audio] crowd %s" % kind)


# ---------------------------------------------------------------- UI auto-wire


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		_wire_button(n)


func _wire_existing(root: Node) -> void:
	if root is BaseButton:
		_wire_button(root)
	for c in root.get_children():
		_wire_existing(c)


func _wire_button(b: BaseButton) -> void:
	if b.has_meta("no_sfx") or b.has_meta("_sfx_wired"):
		return
	b.set_meta("_sfx_wired", true)
	b.pressed.connect(func():
		if not b.has_meta("no_sfx"):
			play_i("click"))
	b.mouse_entered.connect(func():
		var now := Time.get_ticks_msec()
		if not b.disabled and not b.has_meta("no_sfx") and now - _last_hover_ms > 90:
			_last_hover_ms = now
			play_i("hover"))


func _on_mail() -> void:
	var now := Time.get_ticks_msec()
	if now - _boot_ms > 3000 and now - _last_mail_ms > 2000:
		_last_mail_ms = now
		play_i("mail")


# ---------------------------------------------------------------- battle events

const SPEC_FAMILY := {
	"electric": "hit_zap", "psychic": "hit_zap", "dragon": "hit_zap",
	"water": "hit_splash", "ice": "hit_splash",
	"fire": "hit_flame",
	"grass": "hit_whoosh", "bug": "hit_whoosh", "poison": "hit_whoosh",
	"flying": "hit_whoosh", "ghost": "hit_whoosh", "dark": "hit_whoosh",
	"fairy": "hit_whoosh",
	"rock": "hit_burst", "ground": "hit_burst", "steel": "hit_burst",
	"normal": "hit_burst", "fighting": "hit_burst",
}


func battle_event_i(ev: Dictionary) -> void:
	if not _enabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_battle_ms < 70:  # fast-forward replay: don't machine-gun SFX
		return
	var t := str(ev.get("t", ""))
	var hum := randf_range(0.94, 1.06)  # humanize repeated hits
	match t:
		"damage":
			if int(ev.get("amount", 0)) <= 0:
				return
			_last_battle_ms = now
			var eff := float(ev.get("effectiveness", 1.0))
			var frac := float(ev.get("amount", 0)) / maxf(float(ev.get("max_hp", 1)), 1.0)
			if eff >= 2.0 or bool(ev.get("crit", false)):
				play_i("hit_super", 0.0, hum)
				if frac > 0.35:
					# the crowd senses a momentum swing
					crowd_i("roar")
			elif eff > 0.0 and eff <= 0.5:
				play_i("hit_weak", 0.0, hum)
			else:
				var ds := get_node_or_null("/root/DataStore")
				var mv: Dictionary = ds.move(str(ev.get("move", ""))) if ds != null else {}
				if str(mv.get("category", "phys")) == "spec":
					play_i(SPEC_FAMILY.get(str(mv.get("type", "")), "hit_burst"), 0.0, hum)
				else:
					play_i("hit_phys", 0.0, hum)
		"miss":
			_last_battle_ms = now
			play_i("miss", 0.0, hum)
		"faint":
			_last_battle_ms = now
			play_i("faint")
			_last_crowd_ms = -100000  # a faint always gets a reaction
			crowd_i("gasp" if int(ev.get("side", 1)) == 0 else "roar")
		"switch":
			if not bool(ev.get("first", false)):
				_last_battle_ms = now
				play_i("switch", 0.0, hum)
		"item_used", "held_item":
			_last_battle_ms = now
			play_i("item", 0.0, hum)
		"status_applied", "status_tick", "confused_hit":
			_last_battle_ms = now
			play_i("status", 0.0, hum)
		"stat_change":
			_last_battle_ms = now
			play_i("stat_up" if int(ev.get("delta", 1)) > 0 else "stat_down", 0.0, hum)
		"heal":
			_last_battle_ms = now
			play_i("heal", 0.0, hum)
		"weather_start":
			_last_battle_ms = now
			play_i("weather")
		"battle_end":
			_last_crowd_ms = -100000
			crowd_i("cheer")
	if debug and _last_battle_ms == now:
		print("[audio] battle_event %s" % t)
