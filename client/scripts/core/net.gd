extends Node
## Autoload: the connection to the game server (WebSocket + NetCodec).
## Flow: connect_to_server() → hello → welcome → quick_play() → zoneJoined.
## Every decoded server message is emitted as `message(name, msg)`.
## A dropped connection retries with the resume token for the reconnect grace
## period, so a short network blip returns the player to the same slot.

signal message(name: String, msg: Dictionary)
signal status_changed(status: String)   ## offline, connecting, ready, in_zone, failed
signal failed(reason: String)
signal leaderboard_received(board: Dictionary)
signal voice_changed   ## mic or speaker state changed (buttons redraw)

const RETRY_SEC := 2.0

var status: String = "offline"
var online_requested: bool = false  ## set by the menu; the game scene plays online
var mode: int = 0                   ## game mode for quick play: 0 zombies (co-op), 1 infection (players vs players)
var url: String = ""
var player_id: int = 0
var display_name: String = ""
var profile: Dictionary = {}  ## lifetime stats from the server: games, kills, bestWave, tonMicro, weekKills, weekRank
var ton_per_kill: int = 0     ## TON points (millionths) the server pays per kill; 0 = off
var leaderboard: Dictionary = {}  ## last weekly leaderboard received
var tick_rate: int = 20
var invite_code: String = ""      ## this player's invite code (from welcome)
var bot_username: String = ""     ## the bot's @username, for t.me links ("" = invites off)
var dev: bool = false             ## this account has the owner's dev powers (welcome.dev)
var friend_code: String = ""      ## a friend's invite code to join on the next quick play (from the launch link)
var joined_friend: int = 0        ## last zoneJoined: 0 alone, 1 in a friend's game, 2 the invite could not be honoured
var joined_friend_name: String = ""
var voice_available: bool = false  ## server relays voice and this page can capture/play audio
var voice_mic: bool = false        ## microphone on (always off at start)
var voice_speaker: bool = true     ## hear other players
var voice_mic_state: String = "off"  ## off, starting, on, denied, unsupported (from the page)
var voice_talking: bool = false    ## the local mic passes the voice gate right now
var _voice_seq: int = 0
var _voice_poll_t: float = 0.0
var rtt_ms: float = 0.0
var last_error: String = ""

var _ws: WebSocketPeer
var _codec: NetCodec
var _resume_token: String = ""
var _want_zone: bool = false
var _retry_t: float = -1.0
var _retry_until: float = 0.0
var _ping_t: float = 0.0
var _clock: float = 0.0
var _buffer: Array = []  ## messages that arrived while nobody listened (scene change)


func _ready() -> void:
	_codec = NetCodec.new(SharedData.protocol)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Server URL: ?server= (or BLACKOFF_SERVER off-web), else data/net.json.
func configured_url() -> String:
	var q := Platform.query_param("server")
	if q != "":
		return q
	var site := Platform.web_config("server")
	if site != "":
		return site
	var f := FileAccess.get_file_as_string("res://data/net.json")
	var d: Variant = JSON.parse_string(f) if f != "" else null
	return str(d.get("server", "")) if d is Dictionary else ""


func is_online_available() -> bool:
	return configured_url() != ""


func connect_to_server(join_zone: bool = true) -> void:
	url = configured_url()
	_want_zone = join_zone
	_retry_until = 0.0
	_open()


func quick_play() -> void:
	_want_zone = true
	if status == "ready":
		send("quickPlay", {"mode": mode, "friend": friend_code})


## The link that brings a friend into this player's game ("" when the server
## has no bot username): t.me/<bot>?startapp=sq<code>.
func invite_link() -> String:
	if invite_code == "" or bot_username == "":
		return ""
	return "https://t.me/%s?startapp=sq%s" % [bot_username, invite_code]


## Reads a friend's invite from the launch link (t.me/<bot>?startapp=sq<code>).
func take_launch_invite() -> bool:
	var p := Platform.start_param()
	if p.begins_with("sq") and p.length() == 12:
		friend_code = p.substr(2)
		return true
	return false


func leave() -> void:
	_want_zone = false
	if status == "in_zone":
		send("leave", {})
		_set_status("ready")


func disconnect_from_server() -> void:
	_want_zone = false
	_retry_until = 0.0
	_resume_token = ""
	if _ws:
		_ws.close(1000, "bye")
	_ws = null
	_set_status("offline")


func send(msg_name: String, msg: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send(_codec.encode("C2S", msg_name, msg))


## Identity: Telegram initData inside Telegram; outside it a dev name, which
## only servers started with ALLOW_DEV_AUTH=1 accept.
func _init_data() -> String:
	var tg := Platform.get_init_data()
	if tg != "":
		return tg
	var dev := Platform.query_param("name")
	return "dev:" + (dev if dev != "" else "Player%d" % (randi() % 10000))


func _open() -> void:
	if url == "":
		_fail("no server configured")
		return
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail("cannot connect (%d)" % err)
		return
	_set_status("connecting")


func _process(delta: float) -> void:
	_clock += delta
	if _ws == null:
		if _retry_t >= 0.0:
			_retry_t -= delta
			if _retry_t < 0.0:
				_open()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if status == "connecting":
				send("hello", {"protocolVersion": int(SharedData.protocol.protocolVersion), "initData": _init_data(), "resumeToken": _resume_token})
				_set_status("handshake")
			while _ws.get_available_packet_count() > 0:
				_on_packet(_ws.get_packet())
			_ping_t -= delta
			if _ping_t <= 0.0 and status in ["ready", "in_zone"]:
				_ping_t = 2.0
				send("ping", {"clientTime": int(_clock * 1000.0) & 0xffffffff})
			if voice_mic and status == "in_zone":
				_pump_voice(delta)
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			_ws = null
			_on_closed(code)


func _on_packet(data: PackedByteArray) -> void:
	var d := _codec.decode("S2C", data)
	if d.has("error"):
		push_warning("Net: bad frame from server: " + str(d.error))
		return
	var msg_name: String = d.name
	var msg: Dictionary = d.msg
	match msg_name:
		"welcome":
			player_id = int(msg.playerId)
			display_name = str(msg.displayName)
			tick_rate = int(msg.tickRate)
			profile = _profile_of(msg)
			ton_per_kill = int(msg.get("tonPerKill", 0))
			invite_code = str(msg.get("inviteCode", ""))
			bot_username = str(msg.get("botUsername", ""))
			dev = bool(msg.get("dev", false))
			_setup_voice(bool(msg.get("voice", false)))
			print("[net] logged in as %s (games %d, best wave %d, TON %.3f)" % [display_name, profile.games, profile.bestWave, profile.tonMicro / 1000000.0])
			var resumed := _resume_token != "" and _resume_token == str(msg.resumeToken)
			_resume_token = str(msg.resumeToken)
			_retry_until = 0.0
			_set_status("ready")
			if _want_zone and not resumed:
				send("quickPlay", {"mode": mode, "friend": friend_code})
		"zoneJoined":
			joined_friend = int(msg.get("friend", 0))
			joined_friend_name = str(msg.get("friendName", ""))
			if joined_friend != 0:
				friend_code = ""  # an invite is used once
			_set_status("in_zone")
		"profile":
			profile = _profile_of(msg)
			ton_per_kill = int(msg.get("tonPerKill", ton_per_kill))
		"leaderboard":
			leaderboard = msg
			leaderboard_received.emit(msg)
		"voice":
			if voice_speaker and voice_available:
				Platform.voice_play(int(msg.entityId), int(msg.seq), msg.data)
			return  # audio frames never reach the scenes
		"pong":
			rtt_ms = lerpf(rtt_ms if rtt_ms > 0.0 else 100.0, float((int(_clock * 1000.0) - int(msg.clientTime)) & 0xffffffff), 0.3)
		"error":
			last_error = str(msg.message)
			push_warning("Net: server error %d: %s" % [msg.code, msg.message])
	if message.get_connections().is_empty():
		if _buffer.size() < 400:
			_buffer.append([msg_name, msg])
	else:
		message.emit(msg_name, msg)


# ---- voice chat (phase 12): frames come from and go to web/voice.js via Platform

func _setup_voice(server_on: bool) -> void:
	voice_available = server_on and Platform.voice_supported()
	if voice_available:
		Platform.voice_configure(SharedData.constants.get("voice", {}))
		voice_speaker = Settings.voice_speaker
		Platform.voice_set_speaker(voice_speaker)
		if not voice_speaker:
			send("voiceListen", {"on": false})
	voice_changed.emit()


func set_voice_mic(on: bool) -> void:
	if not voice_available:
		return
	voice_mic = on
	Platform.voice_set_mic(on)
	if not on:
		voice_mic_state = "off"
		voice_talking = false
	voice_changed.emit()


func set_voice_speaker(on: bool) -> void:
	if not voice_available:
		return
	voice_speaker = on
	Settings.voice_speaker = on
	Settings.save()
	Platform.voice_set_speaker(on)
	if status in ["ready", "in_zone"]:
		send("voiceListen", {"on": on})
	voice_changed.emit()


## Sends every encoded microphone frame the page has ready; polls the mic state.
func _pump_voice(delta: float) -> void:
	for i in 32:  # the page encodes 25 frames/s; a slow frame rate must not back up the queue
		var frame := Platform.voice_take()
		if frame.is_empty():
			break
		send("voice", {"seq": _voice_seq, "data": frame})
		_voice_seq = (_voice_seq + 1) & 0xffff
	_voice_poll_t -= delta
	if _voice_poll_t <= 0.0:
		_voice_poll_t = 0.25
		var st := Platform.voice_status()
		var mic := str(st.get("mic", "off"))
		var talking := bool(st.get("talking", false))
		if mic != voice_mic_state or talking != voice_talking:
			voice_mic_state = mic
			voice_talking = talking
			if mic in ["denied", "unsupported"]:
				voice_mic = false
			voice_changed.emit()


## Entity ids of players heard just now (for the team panel).
func voice_speaking() -> Array:
	return Platform.voice_speaking() if voice_available and voice_speaker else []


static func _profile_of(msg: Dictionary) -> Dictionary:
	return {"games": int(msg.games), "kills": int(msg.kills), "bestWave": int(msg.bestWave),
		"tonMicro": int(msg.get("tonMicro", 0)), "weekKills": int(msg.get("weekKills", 0)), "weekRank": int(msg.get("weekRank", 0))}


## Asks for this week's top hunters (answered with `leaderboard_received`).
func request_leaderboard() -> void:
	if status in ["ready", "in_zone"]:
		send("leaderboard", {})


## Messages received while no scene was listening (e.g. during the scene change).
func take_buffer() -> Array:
	var b := _buffer
	_buffer = []
	return b


func _on_closed(code: int) -> void:
	# 4001 = refused (bad version / identity / abuse), 4000 = replaced, 1000 = normal.
	if code in [4000, 4001, 1000] or status == "offline":
		_fail(last_error if last_error != "" else "connection closed (%d)" % code)
		return
	if _retry_until == 0.0:
		_retry_until = _clock + float(SharedData.constants.net.reconnectGraceSec)
	if _clock < _retry_until:
		_set_status("connecting")
		_retry_t = RETRY_SEC
	else:
		_fail("connection lost")


func _fail(reason: String) -> void:
	last_error = reason
	_ws = null
	_retry_t = -1.0
	_set_status("failed")
	failed.emit(reason)


func _set_status(s: String) -> void:
	if s == status:
		return
	status = s
	print("[net] ", s)
	status_changed.emit(s)
