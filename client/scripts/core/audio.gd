extends Node
## Autoload: audio buses (Music, SFX, UI under Master), room reverb on the
## SFX bus, looping music with crossfades, and UI clicks. Volumes come from
## Settings. Streams are real CC0 recordings cut by tools/sfx/build_sfx.py;
## the music is three real dark tracks looped where their end matches their
## start (menu, between waves, during a wave).
##
## Web (phase 14): the engine plays sounds as browser samples there, and buses
## added at runtime end up wired in a loop in its audio graph, which Web Audio
## answers with total silence. So on the web everything stays on Master and the
## music / effects volumes are applied per player instead (`flat` mode).

const MUSIC := {"menu": "res://assets/sfx/music_menu.wav", "ambient": "res://assets/sfx/music_ambient.wav",
	"tension": "res://assets/sfx/music_tension.wav"}
const FADE_SEC := 1.6

var _players: Array[AudioStreamPlayer] = []  ## two music players for crossfades
var _fade: Array[float] = [0.0, 0.0]        ## each player's fade level 0..1
var _active: int = 0
var _fade_t: float = 0.0
var _current: String = ""
var _ui: AudioStreamPlayer
var _ui_stream: AudioStream
var _reverb: AudioEffectReverb
var _reverb_wet_target: float = 0.08
var _reverb_room_target: float = 0.3


## True on the web: no sub-buses, volumes applied per player.
var flat: bool = false


func _ready() -> void:
	flat = OS.has_feature("web")
	if not flat:
		for bus in ["Music", "SFX", "UI"]:
			if AudioServer.get_bus_index(bus) < 0:
				AudioServer.add_bus()
				var i := AudioServer.bus_count - 1
				AudioServer.set_bus_name(i, bus)
				AudioServer.set_bus_send(i, "Master")
		var sfx := AudioServer.get_bus_index("SFX")
		if AudioServer.get_bus_effect_count(sfx) == 0:
			_reverb = AudioEffectReverb.new()
			_reverb.wet = 0.08
			_reverb.dry = 1.0
			_reverb.room_size = 0.3
			_reverb.damping = 0.6
			_reverb.predelay_msec = 20.0
			AudioServer.add_bus_effect(sfx, _reverb)
		else:
			_reverb = AudioServer.get_bus_effect(sfx, 0) as AudioEffectReverb
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus_for("Music")
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_ui = AudioStreamPlayer.new()
	_ui.bus = bus_for("UI")
	add_child(_ui)
	if ResourceLoader.exists("res://assets/sfx/ui_click.wav"):
		_ui_stream = load("res://assets/sfx/ui_click.wav")
	apply_volumes()
	Settings.changed.connect(apply_volumes)


## The bus a player should use: the named one, or Master in flat mode.
func bus_for(name: String) -> String:
	return name if not flat and AudioServer.get_bus_index(name) >= 0 else "Master"


## Volume offset (dB) a sound-effect player adds in flat mode (0 with real buses).
func sfx_offset_db() -> float:
	return linear_to_db(maxf(Settings.sfx_volume, 0.0001)) if flat else 0.0


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Settings.master_volume, 0.0001)))
	if flat:
		return
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(Settings.music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Settings.sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), linear_to_db(maxf(Settings.sfx_volume, 0.0001)))


## Crossfades to a music loop ("menu", "ambient", "tension"); "" fades out.
func play_music(name: String) -> void:
	if name == _current:
		return
	_current = name
	var next := 1 - _active
	var p := _players[next]
	if name != "" and MUSIC.has(name) and ResourceLoader.exists(MUSIC[name]):
		p.stream = load(MUSIC[name])
		p.volume_db = -80.0
		p.play()
	else:
		p.stream = null
	_active = next
	_fade_t = 0.0


func ui_click() -> void:
	if _ui_stream:
		_ui.stream = _ui_stream
		_ui.volume_db = -8.0 + sfx_offset_db()
		_ui.play()


## Reverb for the local player's surroundings (indoors: longer, wetter).
func set_room(indoor: bool) -> void:
	_reverb_wet_target = 0.22 if indoor else 0.06
	_reverb_room_target = 0.55 if indoor else 0.2


func _process(delta: float) -> void:
	_fade_t = minf(FADE_SEC, _fade_t + delta)
	var k := _fade_t / FADE_SEC
	for i in 2:
		var p := _players[i]
		var target := 0.0 if (i == _active and p.stream != null) else -80.0
		var lin: float = _fade[i]
		var want := 1.0 if target == 0.0 else 0.0
		var v := lerpf(lin, want, minf(1.0, k if k < 1.0 else 1.0) * delta * 3.0 + (1.0 if k >= 1.0 else 0.0) * 0.0)
		v = move_toward(lin, want, delta / FADE_SEC)
		_fade[i] = v
		var music_k := maxf(Settings.music_volume, 0.0001) if flat else 1.0
		p.volume_db = linear_to_db(v * music_k) if v > 0.001 else -80.0
		if v <= 0.001 and i != _active and p.playing:
			p.stop()
	if _reverb:
		_reverb.wet = move_toward(_reverb.wet, _reverb_wet_target, delta * 0.4)
		_reverb.room_size = move_toward(_reverb.room_size, _reverb_room_target, delta * 0.6)
