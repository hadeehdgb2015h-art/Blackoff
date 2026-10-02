extends Node
## Autoload: player settings persisted to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"
const QUALITY := ["auto", "low", "medium", "high"]

var sensitivity: float = 1.0      ## multiplier on touch/mouse look speed
var invert_y: bool = false
var quality: String = "auto"        ## auto = the game picks a tier from the measured frame rate
var auto_tier: String = "low"       ## current tier under auto (not saved; set by the game)
var fps_cap: int = 60                ## 30 runs cooler on phones
var show_fps: bool = true
var master_volume: float = 0.8
var music_volume: float = 0.5
var sfx_volume: float = 1.0
var hud_opacity: float = 1.0
var layout: Dictionary = {}       ## touch control layout (TouchLayout), {} = defaults
var voice_speaker: bool = true    ## hear other players (the mic is off at every start)


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		sensitivity = clampf(float(cf.get_value("input", "sensitivity", sensitivity)), 0.2, 3.0)
		invert_y = bool(cf.get_value("input", "invert_y", invert_y))
		var q := str(cf.get_value("video", "quality", quality))
		quality = q if q in QUALITY else quality
		show_fps = bool(cf.get_value("video", "show_fps", show_fps))
		fps_cap = 30 if int(cf.get_value("video", "fps_cap", fps_cap)) == 30 else 60
		master_volume = clampf(float(cf.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
		music_volume = clampf(float(cf.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(cf.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
		hud_opacity = clampf(float(cf.get_value("hud", "opacity", hud_opacity)), 0.3, 1.0)
		var l: Variant = cf.get_value("hud", "layout", {})
		layout = l if l is Dictionary else {}
		voice_speaker = bool(cf.get_value("voice", "speaker", voice_speaker))
	_apply_audio()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("input", "sensitivity", sensitivity)
	cf.set_value("input", "invert_y", invert_y)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("video", "fps_cap", fps_cap)
	cf.set_value("audio", "master_volume", master_volume)
	cf.set_value("audio", "music_volume", music_volume)
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("hud", "opacity", hud_opacity)
	cf.set_value("hud", "layout", layout)
	cf.set_value("voice", "speaker", voice_speaker)
	cf.save(PATH)
	_apply_audio()
	changed.emit()


## The tier in force: the chosen one, or under auto the measured one.
func effective_quality() -> String:
	return auto_tier if quality == "auto" else quality


## Per-tier rendering parameters, applied by the game scene.
func quality_params() -> Dictionary:
	match effective_quality():
		"low":
			return {"msaa": 0, "scale": 0.6, "lights": false, "muzzle_light": false, "fog": false, "far": 480.0, "glow": false}
		"high":
			return {"msaa": 4, "scale": 1.0, "lights": true, "muzzle_light": true, "fog": true, "far": 700.0, "glow": true}
		_:
			return {"msaa": 2, "scale": 0.85, "lights": true, "muzzle_light": false, "fog": true, "far": 650.0, "glow": true}


func _apply_audio() -> void:
	Engine.max_fps = fps_cap
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
