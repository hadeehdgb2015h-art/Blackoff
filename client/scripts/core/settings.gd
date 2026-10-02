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


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		sensitivity = clampf(float(cf.get_value("input", "sensitivity", sensitivity)), 0.2, 3.0)
		invert_y = bool(cf.get_value("input", "invert_y", invert_y))
		var q := str(cf.get_value("video", "quality", quality))
		quality = q if q in QUALITY else quality
		show_fps = bool(cf.get_value("video", "show_fps", show_fps))
		master_volume = clampf(float(cf.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	_apply_audio()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("input", "sensitivity", sensitivity)
	cf.set_value("input", "invert_y", invert_y)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("audio", "master_volume", master_volume)
	cf.save(PATH)
	_apply_audio()
	changed.emit()


## Per-tier rendering parameters, applied by the game scene.
func quality_params() -> Dictionary:
	match quality:
		"low":
			return {"scale": 0.6, "lights": false, "muzzle_light": false, "fog": false, "far": 55.0, "glow": false}
		"high":
			return {"scale": 1.0, "lights": true, "muzzle_light": true, "fog": true, "far": 90.0, "glow": true}
		_:
			return {"scale": 0.8, "lights": true, "muzzle_light": false, "fog": true, "far": 75.0, "glow": true}


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
