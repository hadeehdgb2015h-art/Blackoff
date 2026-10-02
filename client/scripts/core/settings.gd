extends Node
## Autoload: player settings persisted to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"
const QUALITY := ["low", "medium", "high"]

var sensitivity: float = 1.0      ## multiplier on touch/mouse look speed
var invert_y: bool = false
var quality: String = "medium"
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
	cf.set_value("audio", "master_volume", master_volume)
	cf.set_value("audio", "music_volume", music_volume)
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("hud", "opacity", hud_opacity)
	cf.set_value("hud", "layout", layout)
	cf.set_value("voice", "speaker", voice_speaker)
	cf.save(PATH)
	_apply_audio()
	changed.emit()


## Per-tier rendering parameters, applied by the game scene.
func quality_params() -> Dictionary:
	match quality:
		"low":
			return {"msaa": 0, "scale": 0.65, "lights": false, "muzzle_light": false, "fog": false, "far": 520.0, "glow": false}
		"high":
			return {"msaa": 4, "scale": 1.0, "lights": true, "muzzle_light": true, "fog": true, "far": 700.0, "glow": true}
		_:
			return {"msaa": 2, "scale": 0.85, "lights": true, "muzzle_light": false, "fog": true, "far": 650.0, "glow": true}


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
