extends Node
## Autoload: player settings persisted to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"
const QUALITY := ["auto", "low", "medium", "high"]
const SETTINGS_VERSION := 3

var sensitivity: float = 1.0      ## multiplier on touch/mouse look speed
var invert_y: bool = false
var quality: String = "auto"        ## auto = the game picks a tier from the measured frame rate
var auto_tier: String = "low"       ## current tier under auto (not saved; set by the game)
var fps_cap: int = 0                 ## 0 = auto (60, then 30 for the session when the device cannot hold ~45), 30, 60 or MAX_FPS
var auto_fps: int = 60               ## the cap in force under auto (not saved): 60 until the device proves it cannot hold it
const MAX_FPS := 120                 ## "Max": every display refresh (90 or 120 Hz screens)
var auto_scale: float = 1.0          ## 3D resolution factor the governor lowers on devices that cannot hold 30 (not saved)
var show_fps: bool = true
var master_volume: float = 0.8
var music_volume: float = 0.5
var sfx_volume: float = 1.0
var hud_opacity: float = 1.0
var layout: Dictionary = {}       ## touch control layout (TouchLayout), {} = defaults
var voice_speaker: bool = true    ## hear other players (the mic is off at every start)
var third_person: bool = true     ## over-the-shoulder camera (phase 22); false = first person
var language: String = ""         ## interface language: en, ar, ru; "" = the player's own (phase 24, see I18n)


func _ready() -> void:
	# Phase 32: every device starts at 60 (phones were held at 30 and felt choked
	# on strong devices); auto drops to a steady 30 only if 60 cannot be held.
	var cf := ConfigFile.new()
	var loaded := cf.load(PATH) == OK
	if loaded and int(cf.get_value("meta", "version", 1)) < SETTINGS_VERSION:
		# phase 15: older builds saved 60 FPS and a fixed quality by default:
		# phones must start on automatic (a steady 30, low) like new players
		cf.set_value("video", "fps_cap", 0)
		cf.set_value("video", "quality", "auto")
		# phase 32: the old advice was 30 on phones: everyone back on automatic once
	if loaded:
		sensitivity = clampf(float(cf.get_value("input", "sensitivity", sensitivity)), 0.2, 3.0)
		invert_y = bool(cf.get_value("input", "invert_y", invert_y))
		var q := str(cf.get_value("video", "quality", quality))
		quality = q if q in QUALITY else quality
		show_fps = bool(cf.get_value("video", "show_fps", show_fps))
		var fc := int(cf.get_value("video", "fps_cap", fps_cap))
		fps_cap = fc if fc in [0, 30, 60, MAX_FPS] else 0
		master_volume = clampf(float(cf.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
		music_volume = clampf(float(cf.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(cf.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
		hud_opacity = clampf(float(cf.get_value("hud", "opacity", hud_opacity)), 0.3, 1.0)
		var l: Variant = cf.get_value("hud", "layout", {})
		layout = l if l is Dictionary else {}
		voice_speaker = bool(cf.get_value("voice", "speaker", voice_speaker))
		third_person = bool(cf.get_value("video", "third_person", third_person))
		language = str(cf.get_value("ui", "language", language))
	_apply_audio()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("input", "sensitivity", sensitivity)
	cf.set_value("input", "invert_y", invert_y)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("video", "fps_cap", fps_cap)
	cf.set_value("meta", "version", SETTINGS_VERSION)
	cf.set_value("audio", "master_volume", master_volume)
	cf.set_value("audio", "music_volume", music_volume)
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("hud", "opacity", hud_opacity)
	cf.set_value("hud", "layout", layout)
	cf.set_value("voice", "speaker", voice_speaker)
	cf.set_value("video", "third_person", third_person)
	cf.set_value("ui", "language", language)
	cf.save(PATH)
	_apply_audio()
	changed.emit()


## The tier in force: the chosen one, or under auto the measured one.
func effective_quality() -> String:
	return auto_tier if quality == "auto" else quality


## Per-tier rendering parameters, applied by the game scene.
## Phones never get MSAA: the owner's phone drew black lines across the screen
## and stalled on "high" (4x MSAA under the web renderer, phase 18), and the
## extra light count there is capped at 10 (each lit pixel pays per light).
func quality_params() -> Dictionary:
	var phone := DisplayServer.is_touchscreen_available()
	match effective_quality():
		"low":
			return {"msaa": 0, "scale": 0.6, "lights": false, "lights_n": 4, "muzzle_light": false, "fog": false, "far": 480.0, "glow": false}
		"high":
			# at most 8 extra lights: the per-object limit of the web renderer (the map's walls are one mesh, phase 32)
			return {"msaa": 0 if phone else 4, "scale": 1.0, "lights": true, "lights_n": 8, "muzzle_light": true, "fog": true, "far": 700.0, "glow": true}
		_:
			return {"msaa": 0 if phone else 2, "scale": 0.85, "lights": true, "lights_n": 8, "muzzle_light": false, "fog": true, "far": 650.0, "glow": true}


## The frame cap in force: the chosen one, or under auto the measured one.
func effective_fps_cap() -> int:
	return auto_fps if fps_cap == 0 else fps_cap


## The frame cap: on the web the page paces frames evenly (BlackoffPace in
## shell.html) and the engine's own cap stays off; elsewhere Engine.max_fps.
func apply_fps_cap() -> void:
	var cap := effective_fps_cap()
	if OS.has_feature("web") and Platform.set_frame_cap(0 if cap >= MAX_FPS else cap):
		Engine.max_fps = 0
	else:
		Engine.max_fps = 0 if cap >= MAX_FPS else cap


func _apply_audio() -> void:
	apply_fps_cap()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
