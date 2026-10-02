class_name Sfx
extends Node
## Sound playback with small player pools. Streams live in res://assets/sfx/
## (generated placeholders, see tools/gen_sfx.py; replace files to upgrade).

const NAMES := ["pistol_shot", "rifle_shot", "dry_fire", "reload", "switch", "zombie_groan1", "zombie_groan2",
	"zombie_attack", "zombie_hit", "zombie_death", "player_hurt", "buy", "deny", "wave_start", "wave_end"]
const POOL_2D := 8
const POOL_3D := 8

var _streams := {}
var _p2d: Array[AudioStreamPlayer] = []
var _p3d: Array[AudioStreamPlayer3D] = []
var _i2d: int = 0
var _i3d: int = 0


func _ready() -> void:
	for n in NAMES:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_p2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 40.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_p3d.append(p)


func play(name: String, volume_db := 0.0, pitch_var := 0.05) -> void:
	if not _streams.has(name):
		return
	var p := _p2d[_i2d]
	_i2d = (_i2d + 1) % POOL_2D
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.08) -> void:
	if not _streams.has(name):
		return
	var p := _p3d[_i3d]
	_i3d = (_i3d + 1) % POOL_3D
	p.stream = _streams[name]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
