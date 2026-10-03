class_name Sfx
extends Node
## Sound playback. Streams live in res://assets/sfx/ (real CC0 recordings cut by
## tools/sfx/build_sfx.py).
##
## Phase 17 (crackle fix): in the browser a voice that is reused is stopped
## dead, mid-waveform, which clicks. A shared pool of 8 players cycled every
## few shots, so footsteps, hit ticks and shots kept cutting each other off: a
## constant crackle in a fight. Now each 2D sound has its own player with a
## small voice limit (a new shot only replaces an older shot, whose attack masks
## the cut, and the sound files fade to silence before they end), and 3D sounds
## take a free player before stealing the one that started first.

const NAMES := ["pistol_shot", "rifle_shot", "dry_fire", "reload", "switch",
	"zombie_groan1", "zombie_groan2", "zombie_groan3", "zombie_groan4",
	"zombie_attack", "zombie_hit", "zombie_death", "player_hurt", "buy", "deny", "wave_start", "wave_end", "shotgun_shot", "smg_shot", "box_open", "box_roll", "box_offer", "thunder", "lmg_shot", "sniper_shot", "arc_shot", "gale_shot", "powerup",
	"step1", "step2", "step3", "step4", "hit_tick", "headshot", "heartbeat"]
## Voices per 2D sound (default 2). Fast guns need a few to overlap their tails.
const VOICES := {"smg_shot": 3, "lmg_shot": 3, "rifle_shot": 3, "pistol_shot": 3, "zombie_hit": 3, "hit_tick": 2,
	"step1": 1, "step2": 1, "step3": 1, "step4": 1, "heartbeat": 1, "reload": 1, "thunder": 1, "wave_start": 1, "wave_end": 1}
const POOL_3D := 12

var _streams := {}
var _p2d := {}                                ## name -> AudioStreamPlayer
var _p3d: Array[AudioStreamPlayer3D] = []
var _started: Array[int] = []                 ## msec each 3D player last started
var occlusion_check: Callable  ## set by the game: Callable(pos: Vector3) -> bool (true = behind a wall)


func _ready() -> void:
	for n in NAMES:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	# Web: a sound is turned into a browser sample (decoded) the first time it
	# plays, which froze the first shot. Do it for all of them while loading.
	if OS.has_feature("web"):
		var t0 := Time.get_ticks_msec()
		for s in _streams.values():
			if not AudioServer.is_stream_registered_as_sample(s):
				AudioServer.register_stream_as_sample(s)
		print("[load] %d sounds registered in %d ms" % [_streams.size(), Time.get_ticks_msec() - t0])
	for n in _streams:
		var p := AudioStreamPlayer.new()
		p.bus = Audio.bus_for("SFX")
		p.stream = _streams[n]
		p.max_polyphony = int(VOICES.get(n, 2))
		add_child(p)
		_p2d[n] = p
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = Audio.bus_for("SFX")
		p.unit_size = 4.0
		p.max_distance = 45.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_db = -18.0
		add_child(p)
		_p3d.append(p)
		_started.append(0)


func play(name: String, volume_db := 0.0, pitch_var := 0.05, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _p2d.get(name)
	if p == null:
		return
	p.volume_db = volume_db + Audio.sfx_offset_db()
	p.pitch_scale = pitch + randf_range(-pitch_var, pitch_var)
	p.play()


func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.08) -> void:
	if not _streams.has(name):
		return
	# a player that is free, else the one that started longest ago
	var pick := 0
	for i in POOL_3D:
		if not _p3d[i].playing:
			pick = i
			break
		if _started[i] < _started[pick]:
			pick = i
	var p := _p3d[pick]
	_started[pick] = Time.get_ticks_msec()
	p.stream = _streams[name]
	p.global_position = pos
	# Behind a wall: muffled and quieter (cheap occlusion from the sim map).
	var occluded := occlusion_check.is_valid() and bool(occlusion_check.call(pos))
	p.attenuation_filter_cutoff_hz = 900.0 if occluded else 20500.0
	p.volume_db = volume_db - (7.0 if occluded else 0.0) + Audio.sfx_offset_db()
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
