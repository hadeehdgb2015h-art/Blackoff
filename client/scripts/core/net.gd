extends Node
## Autoload: the connection to the game server (WebSocket + NetCodec).
## Flow: connect_to_server() → hello → welcome → quick_play() → zoneJoined.
## Every decoded server message is emitted as `message(name, msg)`.
## A dropped connection retries with the resume token for the reconnect grace
## period, so a short network blip returns the player to the same slot.

signal message(name: String, msg: Dictionary)
signal status_changed(status: String)   ## offline, connecting, ready, in_zone, failed
signal failed(reason: String)

const RETRY_SEC := 2.0

var status: String = "offline"
var online_requested: bool = false  ## set by the menu; the game scene plays online
var url: String = ""
var player_id: int = 0
var display_name: String = ""
var tick_rate: int = 20
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
		send("quickPlay", {})


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
			var resumed := _resume_token != "" and _resume_token == str(msg.resumeToken)
			_resume_token = str(msg.resumeToken)
			_retry_until = 0.0
			_set_status("ready")
			if _want_zone and not resumed:
				send("quickPlay", {})
		"zoneJoined":
			_set_status("in_zone")
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
