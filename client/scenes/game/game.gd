extends Node3D
## Solo practice game scene: wires the local SimWorld to the views, HUD,
## controls and audio. Online play (phase 2+) replaces SimWorld with a
## network world exposing the same read API (players, zombies, events,
## director, zone_state), so the views stay unchanged.

const MAP_SCENES := {"facility_01": "res://scenes/maps/facility_01.tscn"}
const MAX_CATCHUP_TICKS := 5

var world: SimWorld
var pid: int = -1
var bot: BotBrain

var _map_root: Node3D
var _atmosphere: Atmosphere
var _rig: FpRig
var _effects: Effects
var _sfx: Sfx
var _hud: Hud
var _controls: TouchControls
var _zviews := {}  ## zid -> ZombieView
var _pviews := {}  ## other players' entity id -> RemotePlayerView
var _izviews := {}  ## infection: infected players' entity id -> ZombieView (with a name tag)
var _perf_t: float = 0.0
var _perf_frames: int = 0
var _perf_good: int = 0
var _perf_dropped: bool = false
var _light_t: float = 0.0
var _light_scan: int = 0
var _map_lights: Array[Light3D] = []
var _prof: bool = false            ## ?perf=1 / BLACKOFF_PERF=1: print where frame time goes
var _prof_acc := {}                ## section -> usec this window
var _prof_frames: int = 0
var _prof_wall: int = 0            ## usec at window start
var _prof_t0: int = 0
var _online: bool = false
var _net_log_t: float = 10.0
var _showcase_soldiers: Array = []
var _showcase_t: float = 0.0
var _defs: Dictionary
var _boxes := {}   ## box id -> BoxView
var _puviews := {} ## power-up id -> PowerupView
var _step_t: float = 0.0
var _heart_t: float = 0.0
var _room_t: float = 0.0
var _machines := {} ## perk id -> PerkMachineView
var _acc: float = 0.0
var _paused: bool = false
var _last_wave: int = 0  ## the wave the game ended on (the challenge message)
var _pause_menu: Control
var _groan_t: float = 2.0
var _game_over_shown: bool = false
var _debug_js: bool = false
var _debug_t: float = 0.0


func _ready() -> void:
	var defs := SharedData.data
	var map_id: String = defs.constants.maps.default
	var t0 := Time.get_ticks_msec()
	# props placed and meshes merged once per session (MapCache), then copied
	_map_root = MapCache.instance(MAP_SCENES[map_id])
	add_child(_map_root)
	var t1 := Time.get_ticks_msec()
	_atmosphere = Atmosphere.build(_map_root)
	print("[load] map %d ms (%d merged meshes, %d lights), atmosphere %d ms" % [t1 - t0,
		_map_root.find_children("Batched_*", "MeshInstance3D", false, false).size(),
		_map_root.find_children("*", "Light3D", true, false).size(), Time.get_ticks_msec() - t1])

	_rig = FpRig.new()
	add_child(_rig)
	_effects = Effects.new()
	add_child(_effects)
	_sfx = Sfx.new()
	add_child(_sfx)
	_sfx.occlusion_check = _occluded
	Audio.play_music("ambient")
	_atmosphere.thunder.connect(func(delay: float):
		get_tree().create_timer(delay).timeout.connect(func(): _sfx.play("thunder", -9.0, 0.1)))

	var vignette_layer := CanvasLayer.new()
	vignette_layer.layer = 0
	add_child(vignette_layer)
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vmat := ShaderMaterial.new()
	vmat.shader = load("res://shaders/vignette.gdshader")
	vignette.material = vmat
	vignette_layer.add_child(vignette)
	var ui := CanvasLayer.new()
	add_child(ui)
	_hud = Hud.new()
	ui.add_child(_hud)
	_hud.retry_pressed.connect(_retry)
	_hud.menu_pressed.connect(_to_menu)
	_hud.streak.connect(func(n: int):
		_sfx.play("powerup", -9.0 if n < 5 else -6.0, 0.0)
		Platform.haptic("medium" if n < 5 else "heavy"))
	_hud.challenge_pressed.connect(func():
		var me: SimPlayer = world.players.get(pid) if world else null
		_hud.show_toast(Social.challenge(_last_wave, me.kills if me else 0)))
	_controls = TouchControls.new()
	ui.add_child(_controls)
	_controls.pause_requested.connect(_toggle_pause)
	_controls.voice_toggled.connect(_on_voice_toggled)
	Net.voice_changed.connect(_sync_voice_buttons)
	if Platform.query_param("nohud") == "1":  # clean captures (menu backdrop)
		_hud.visible = false
		_controls.visible = false
		_rig.set_viewmodel_visible(false)

	_defs = defs
	Settings.changed.connect(_apply_quality)
	_debug_js = Platform.is_web and Platform.query_param("debug") == "1"
	_prof = Platform.query_param("perf") == "1"
	if _debug_js or Platform.query_param("audiocheck") == "1":
		# how this platform plays sound (web without threads = sample playback; a
		# stream that is not registered as a sample stays silent there)
		var music: AudioStream = load("res://assets/sfx/music_ambient.wav")
		var shot: AudioStream = load("res://assets/sfx/pistol_shot.wav")
		print("[audio] music sample=%s shot sample=%s; music class %s; buses %d; master %.1f dB" % [
			AudioServer.is_stream_registered_as_sample(music), AudioServer.is_stream_registered_as_sample(shot),
			music.get_class(), AudioServer.bus_count, AudioServer.get_bus_volume_db(0)])
	_online = Net.online_requested or Platform.query_param("server") != ""
	if Platform.query_param("mode") == "infection" and not Net.online_requested:
		Net.mode = 1  # headless/online tests launch the game scene directly
	if _online:
		# Online: the server owns the zone; we wait for our slot (zoneJoined + first snapshot).
		world = NetWorld.new(defs, map_id)
		_spawn_box_views(defs)
		_spawn_machine_views(defs)
		_apply_quality()
		_hud.show_status("Connecting...")
		Net.failed.connect(_on_net_failed)
		if Net.status != "in_zone":
			if Net.status in ["ready", "connecting", "handshake"]:
				Net.quick_play()  # joins as soon as the login (started by the menu) completes
			else:
				Net.connect_to_server(true)
		return
	world = SimWorld.new(defs, map_id, randi())
	_spawn_box_views(defs)
	_spawn_machine_views(defs)
	pid = world.add_player("You")
	_on_player_ready()
	_apply_quality()
	var p: SimPlayer = world.players[pid]
	var forced := Platform.query_param("weapon")  # art review: ?weapon=rifle
	if forced != "" and defs.weapons.has(forced):
		world.player_sys.give_weapon(p, forced)
		_rig.set_weapon(forced)
	var at := Platform.query_param("at")  # art review: ?at=x,z,yaw_deg[,pitch_deg]
	if at != "":
		var v := at.split(",")
		if v.size() >= 3:
			p.pos = Vector2(float(v[0]), float(v[1]))
			p.prev_pos = p.pos
			_controls.set_look(deg_to_rad(float(v[2])), deg_to_rad(float(v[3])) if v.size() > 3 else 0.0)
			world.director.phase = WaveDirector.Phase.STOPPED
	var showcase := Platform.query_param("showcase")
	if showcase == "1" or showcase == "boss":
		_start_showcase()
	elif showcase == "box":
		_start_box_showcase()
	elif showcase == "soldier":
		_start_soldier_showcase()


## The local player exists (offline: at once; online: after the first snapshot).
func _on_player_ready() -> void:
	_prewarm_gpu()
	var p: SimPlayer = world.players[pid]
	_controls.set_look(p.yaw, p.pitch)
	_rig.set_weapon(p.weapon().id if p.weapon() else str(_defs.constants.player.startWeapon))
	if Platform.query_param("bot") == "1":
		bot = BotBrain.new(pid, randi())
	_hud.show_status("")


func _process(delta: float) -> void:
	if _online and pid < 0:
		world.step()  # drain the network inbox until our slot is ready
		var nw := world as NetWorld
		if nw.ready_to_play and nw.local_pid >= 0:
			pid = nw.local_pid
			_on_player_ready()
			print("[game] online: joined zone %d as entity %d (%s)" % [nw.zone_id, pid, "infection" if nw.mode == 1 else "zombies"])
			_sync_voice_buttons()
			if Net.joined_friend == 1:
				print("[game] invite: joined %s's game" % Net.joined_friend_name)
				_hud.show_toast("You joined %s's squad" % Net.joined_friend_name, 4.0)
			elif Net.joined_friend == 2:
				_hud.show_toast("Your friend's game was full or over: here is a new one", 4.0)
			Net.joined_friend = 0
			if Platform.query_param("voice") == "1":  # browser tests: talk right away
				Net.set_voice_mic(true)
		return
	if _paused and _online:
		# The zone keeps running on the server: keep stepping with idle input.
		_acc += delta
		while _acc >= world.dt:
			world.set_input(pid, PlayerIntent.new())
			world.step()
			_sync_views()
			_acc -= world.dt
	_prof_t0 = Time.get_ticks_usec()
	if not _paused:
		_acc += delta
		var ticks := 0
		while _acc >= world.dt and ticks < MAX_CATCHUP_TICKS:
			var intent := bot.think(world) if bot else _controls.sample()
			world.set_input(pid, intent)
			world.step()
			_pm("step")
			_sync_views()
			_pm("sync_views")
			for e in world.events:
				_on_event(e)
			_pm("events")
			_acc -= world.dt
			ticks += 1
		if ticks == MAX_CATCHUP_TICKS:
			_acc = 0.0  # drop backlog after a stall instead of fast-forwarding
	var alpha := clampf(_acc / world.dt, 0.0, 1.0)
	var p: SimPlayer = world.players[pid]
	if bot:
		_controls.set_look(p.yaw, p.pitch)
	var eye := p.prev_pos.lerp(p.pos, alpha)
	_controls.aim_friction = _aim_friction(Vector3(eye.x, float(world.constants.player.eyeHeight), eye.y))
	_pm("aim_friction")
	_rig.set_view(Vector3(eye.x, float(world.constants.player.eyeHeight), eye.y), _controls.yaw, _controls.pitch, p.moving, delta)
	_pm("rig")
	var low := Settings.effective_quality() == "low"
	for v in _zviews.values():
		v.update_view(alpha, delta, low and _far_from(eye, v))
	for v in _izviews.values():
		v.update_view(alpha, delta, low and _far_from(eye, v))
	_pm("zombie_views")
	for v in _pviews.values():
		v.update_view(alpha, delta)
	if _online:
		_rig.set_claws(p.team == 1)
		_controls.melee_mode = p.team == 1
	_sync_powerup_views()
	for v in _puviews.values():
		v.update_view(world.time, delta)
	_pm("other_views")
	_body_sounds(p, delta)
	_pm("sounds")
	var opt := world.interact_option(pid)
	var revive: bool = not opt.is_empty() and opt.action == "revive"
	_controls.revive_available = revive
	_controls.interact_label = "" if opt.is_empty() or revive else str(opt.label)
	_controls.interact_ok = not opt.is_empty() and opt.affordable and not opt.full
	_pm("interact")
	_hud.update_state(p, world, opt, delta)
	_pm("hud")
	_hud.set_markers(_downed_markers(p))
	_pm("markers")
	_cull_lights(p, delta)
	_govern_quality(delta)
	_prof_frame()
	_ambient_groans(delta)
	if not _showcase_soldiers.is_empty():
		_update_soldier_showcase(delta)
	if _online:
		_net_log_t -= delta
		if _net_log_t <= 0.0:
			_net_log_t = 10.0
			var nw := world as NetWorld
			print("[net] rtt=%d ms players=%d zombies=%d corrections=%d max_error=%.2f m" % [Net.rtt_ms, world.players.size(), world.zombies.size(), nw.corrections, nw.max_error])
			if nw.mode == 1:
				var others := PackedStringArray()
				for o in world.players.values():
					if o.id != pid:
						others.append("%d:%s@%.1fm" % [o.id, "inf" if o.team == 1 else "sol", p.pos.distance_to(o.pos)])
				print("[game] infection: me %s hp=%d at (%.1f, %.1f) others %s" % ["inf" if p.team == 1 else "sol", p.hp, p.pos.x, p.pos.y, " ".join(others)])
	if _debug_js:
		_publish_debug(p, delta)


## Low tier: zombies beyond this are moved but not animated each frame.
func _far_from(eye: Vector2, v: ZombieView) -> bool:
	return eye.distance_squared_to(v.cur_pos) > 30.0 * 30.0


## Touch aim assist (presentation only, the server still checks every shot):
## the look slows down while the crosshair crosses a visible zombie.
func _aim_friction(eye: Vector3) -> float:
	if not Platform.is_touch:
		return 1.0
	var dir := SimMath.dir3(_controls.yaw, _controls.pitch)
	for z in world.zombies.values():
		var to: Vector2 = z.pos - Vector2(eye.x, eye.z)
		if to.length_squared() > 900.0:
			continue
		var h := HitTest.ray_character(eye, dir, z.pos, z.radius() * 1.8, float(z.def.headCenterHeight), float(z.def.headRadius) * 1.8)
		if not h.is_empty() and world.map.raycast(eye, dir, h.t) >= h.t:
			return 0.55
	return 1.0


## ?debug=1 exposes a small state snapshot to the page for automated browser tests.
func _publish_debug(p: SimPlayer, delta: float) -> void:
	_debug_t -= delta
	if _debug_t > 0.0:
		return
	_debug_t = 0.2
	var d := {"x": p.pos.x, "z": p.pos.y, "yaw": p.yaw, "pitch": p.pitch, "shots": p.shots_fired,
		"mag": p.weapon().mag, "hp": p.hp, "wave": world.director.wave, "zombies": world.zombies.size(),
		"tick": world.tick, "online": _online, "players": world.players.size(), "rtt": Net.rtt_ms,
		"fps": Engine.get_frames_per_second(), "tier": Settings.effective_quality(),
		"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"canvas": [get_viewport().size.x, get_viewport().size.y]}
	JavaScriptBridge.eval("window.__blackoff = %s;" % JSON.stringify(d), true)


func _spawn_machine_views(defs: Dictionary) -> void:
	for it in world.map.interactables:
		if it.kind != "perk" or not defs.get("perks", {}).has(it.item):
			continue
		var v := PerkMachineView.new()
		add_child(v)
		v.setup(it.item, defs.perks[it.item], it.pos, float(it.get("yaw", 0.0)))
		_machines[it.item] = v


func _sync_powerup_views() -> void:
	for id in _puviews.keys():
		if not world.powerups.drops.has(id):
			_puviews[id].queue_free()
			_puviews.erase(id)
	for d in world.powerups.drops.values():
		var v: PowerupView = _puviews.get(d.id)
		if v == null:
			v = PowerupView.new()
			add_child(v)
			var def: Dictionary = world.constants.powerups.types.get(d.type, {})
			v.setup(d.id, d.type, str(def.get("displayName", d.type)), d.pos, d.until)
			_puviews[d.id] = v
		v.until = d.until


func _spawn_box_views(defs: Dictionary) -> void:
	var pool := []
	for id in defs.weapons:
		if float(defs.weapons[id].get("boxWeight", 0)) > 0.0:
			pool.append(id)
	for b in world.box_sys.boxes.values():
		var v := BoxView.new()
		add_child(v)
		# Face the interaction point (the box sits just behind it).
		var block_center: Vector2 = b.pos + Vector2(0, 1.2)
		v.setup(b.id, block_center, SimMath.yaw_to(b.pos, block_center) + PI, pool)
		_boxes[b.id] = v


func _sync_views() -> void:
	for id in _pviews.keys():
		if not world.players.has(id) or world.players[id].team == 1:
			_pviews[id].queue_free()
			_pviews.erase(id)
	for id in _izviews.keys():
		var o: SimPlayer = world.players.get(id)
		if o == null or o.team != 1 or o.state == SimPlayer.State.DEAD:
			_izviews[id].queue_free()
			_izviews.erase(id)
	for p in world.players.values():
		if p.id == pid:
			continue
		if p.team == 1:
			# an infected player looks like a zombie (walker model) with a name tag
			if p.state == SimPlayer.State.DEAD:
				continue
			var iv: ZombieView = _izviews.get(p.id)
			if iv == null:
				iv = ZombieView.new()
				add_child(iv)
				iv.setup(p.id, "walker", _defs.zombies.walker, p.pos, p.yaw)
				var tag := Label3D.new()
				tag.position = Vector3(0, 2.15, 0)
				tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				tag.font_size = 44
				tag.pixel_size = 0.004
				tag.outline_size = 10
				tag.modulate = Color(0.55, 0.95, 0.6)
				tag.no_depth_test = true
				tag.text = p.name
				iv.add_child(tag)
				_izviews[p.id] = iv
			iv.set_sim_state(p.pos, p.yaw, p.moving)
			continue
		var pv: RemotePlayerView = _pviews.get(p.id)
		if pv == null:
			pv = RemotePlayerView.new()
			add_child(pv)
			pv.setup(p)
			_pviews[p.id] = pv
		pv.set_state(p)
	for id in _zviews.keys():
		if not world.zombies.has(id):  # online: left the interest radius
			_zviews[id].queue_free()
			_zviews.erase(id)
	for z in world.zombies.values():
		var v: ZombieView = _zviews.get(z.id)
		if v == null:
			v = ZombieView.new()
			add_child(v)
			v.setup(z.id, z.type, z.def, z.pos, z.yaw)
			_zviews[z.id] = v
		else:
			v.set_sim_state(z.pos, z.yaw, z.moving)


func _on_event(e: Dictionary) -> void:
	var local: bool = e.get("pid", -1) == pid
	match e.type:
		"shot":
			var wvis := Visuals.weapon(e.weapon)
			var from: Vector3 = _rig.muzzle_position() if local else e.from + Vector3(0, -0.2, 0)
			if not local:
				_sfx.play_at(wvis.get("sound", "pistol_shot"), from, -8.0)
				var pv: RemotePlayerView = _pviews.get(e.pid)
				if pv:
					pv.on_fire()
			else:
				_rig.on_fire(clampf(float(wvis.get("recoilKick", 0.04)) * 2.5, 0.05, 0.35))
				_sfx.play(wvis.get("sound", "pistol_shot"), -4.0)
				_controls.add_recoil(float(wvis.get("recoilPitch", 0.02)) * randf_range(0.6, 1.0), randf_range(-0.006, 0.006))
			var fx := str(wvis.get("fx", "tracer"))
			if fx == "blast":
				_effects.blast(from, e.to - e.from, from.distance_to(e.to))
			elif fx == "bolt":
				_effects.bolt(from, e.to, Color(str(wvis.get("tracer", "#88e0ff"))))
				_effects.impact(e.to, false)
			else:
				_effects.tracer(from, e.to)
			if e.hit == "wall":
				_effects.impact(e.to, false)
		"zombie_hit":
			_effects.impact(e.point, true)
			var v: ZombieView = _zviews.get(e.zid)
			if v:
				v.on_hit()
			if local:
				_sfx.play("zombie_hit", -6.0)
				_sfx.play("hit_tick", -12.0, 0.02)
		"zombie_spawned":
			var bv := Visuals.zombie(str(e.get("ztype", "")))
			if bv.has("bossName"):
				_hud.boss_arrived(str(bv.bossName))
				_sfx.play("zombie_groan4", 2.0, 0.0, 0.6)  # a slowed, deep roar
				_sfx.play("thunder", -4.0, 0.0)
				_rig.on_damage(30.0)  # the ground shakes
				Platform.haptic("heavy")
				print("[game] boss %s spawned (wave %d)" % [bv.bossName, world.director.wave])
		"zombie_killed":
			var v: ZombieView = _zviews.get(e.zid)
			if v and v.vis.has("bossName"):
				_hud.boss_fell(str(v.vis.bossName))
				_sfx.play("wave_end", -2.0, 0.0, 0.8)
				for i in 3:
					_effects.gore(Vector3(e.pos.x + randf_range(-0.6, 0.6), 1.6, e.pos.y + randf_range(-0.6, 0.6)))
				print("[game] boss killed")
			if v:
				v.on_death(e.pos, e.yaw)
				_zviews.erase(e.zid)
			_sfx.play_at("zombie_death", Vector3(e.pos.x, 1.4, e.pos.y), -2.0)
			_effects.gore(Vector3(e.pos.x, 1.0, e.pos.y))
			if local:
				_rig.punch(3.0 if e.head else 1.6)
				Platform.haptic("light")
			if local and e.head:
				_sfx.play("headshot", -8.0, 0.02)
		"zombie_attack":
			if e.get("player", false):
				# an infected player's claw
				if e.zid == pid:
					_rig.on_claw()
					_sfx.play("zombie_attack", -4.0)
					Platform.haptic("medium")
				else:
					var iv: ZombieView = _izviews.get(e.zid)
					if iv:
						iv.on_attack(0.25)
						_sfx.play_at("zombie_attack", iv.global_position + Vector3(0, 1.5, 0), 0.0)
				return
			var v: ZombieView = _zviews.get(e.zid)
			if v:
				v.on_attack(float(v.def.attackWindupSec))
				_sfx.play_at("zombie_attack", v.global_position + Vector3(0, 1.5, 0), 0.0)
		"player_hit":
			_effects.impact(e.point, true)
			var iv: ZombieView = _izviews.get(e.target)
			if iv:
				iv.on_hit()
			if local:
				_sfx.play("zombie_hit", -6.0)
				_sfx.play("hit_tick", -12.0, 0.02)
		"player_killed":
			var iv: ZombieView = _izviews.get(e.pid)
			var victim: SimPlayer = world.players.get(e.pid)
			if iv and victim:
				iv.on_death(victim.pos, victim.yaw)
				_izviews.erase(e.pid)
			if victim:
				_sfx.play_at("zombie_death", Vector3(victim.pos.x, 1.4, victim.pos.y), -2.0)
			if local:
				_controls.release_all()
			elif e.by == pid and e.head:
				_sfx.play("headshot", -8.0, 0.02)
			print("[game] player %d killed by %d" % [e.pid, e.by])
		"infected":
			var victim: SimPlayer = world.players.get(e.pid)
			if victim:
				_sfx.play_at("zombie_attack", Vector3(victim.pos.x, 1.5, victim.pos.y), 0.0)
			if local:
				_sfx.play("player_hurt", -3.0)
				_rig.set_claws(true)
				_controls.release_all()
				Platform.haptic("heavy")
			print("[game] player %d infected by %d" % [e.pid, e.by])
		"round_start":
			_sfx.play("wave_start", -6.0, 0.0)
			Audio.play_music("tension")
			_controls.enabled = true
			_controls.release_all()
			print("[game] round %d started (%d infected, %d s)" % [e.round, e.infected, e.seconds])
		"round_end":
			_sfx.play("wave_end", -6.0, 0.0)
			Audio.play_music("ambient")
			print("[game] round %d over: %s win" % [e.round, "soldiers" if e.soldiersWin else "infected"])
		"player_damaged":
			if local:
				_rig.on_damage(float(e.amount))
				_sfx.play("player_hurt", -3.0)
				Platform.haptic("heavy")
		"player_downed":
			if local:
				_rig.set_downed(true)
			print("[game] player %d down" % e.pid)
		"player_revived", "player_respawned":
			if local:
				_rig.set_downed(false)
				_controls.release_all()
			if e.type == "player_revived":
				print("[game] player %d revived by %d" % [e.pid, e.by])
				if local or e.by == pid:
					_sfx.play("buy", -4.0)
			else:
				print("[game] player %d respawned" % e.pid)
		"reload_started":
			if local:
				_rig.on_reload(float(e.duration))
				_sfx.play("reload", -4.0)
		"weapon_switched":
			if local:
				_rig.on_switch(e.weapon)
				_sfx.play("switch", -6.0)
		"purchase":
			if local:
				_sfx.play("buy", -4.0)
				if e.action != "perk":
					_rig.on_switch(world.players[pid].weapon().id)
		"powerup_taken":
			_sfx.play("powerup", -2.0)
			print("[game] power-up %s taken by %d" % [e.ptype, e.pid])
		"powerup_dropped":
			_sfx.play_at("box_offer", Vector3(e.get("pos", Vector2.ZERO).x, 1.0, e.get("pos", Vector2.ZERO).y) if e.has("pos") else _rig.camera.global_position, -8.0)
		"purchase_denied":
			if local:
				_sfx.play("deny", -6.0)
		"dry_fire":
			if local:
				_sfx.play("dry_fire", -4.0)
		"wave_started":
			_sfx.play("wave_start", -6.0, 0.0)
			Audio.play_music("tension")
			print("[game] wave %d started (%d zombies)" % [e.wave, e.count])
		"wave_cleared":
			_sfx.play("wave_end", -6.0, 0.0)
			Audio.play_music("ambient")
			print("[game] wave %d cleared, kills=%d" % [e.wave, world.players[pid].kills])
		"box_opened":
			_boxes[e.box].on_open(float(world.constants.supplyBox.rollSec))
			_sfx.play_at("box_open", _boxes[e.box].global_position + Vector3(0, 0.8, 0), 0.0, 0.0)
			_sfx.play_at("box_roll", _boxes[e.box].global_position + Vector3(0, 0.8, 0), -4.0, 0.0)
		"box_offer":
			_boxes[e.box].on_offer(e.weapon)
			_sfx.play_at("box_offer", _boxes[e.box].global_position + Vector3(0, 0.8, 0), 0.0, 0.0)
		"box_taken":
			_boxes[e.box].on_close()
			if local:
				_sfx.play("buy", -4.0)
				_rig.on_switch(e.weapon)
		"box_expired":
			_boxes[e.box].on_close()
		"game_over":
			print("[game] game over at wave %d" % e.wave)
			Audio.play_music("")
			_controls.enabled = false
			_controls.release_all()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_last_wave = int(e.wave)
			_hud.show_game_over(int(e.wave), world.players[pid], world.scores())
	_hud.on_event(e, pid)


## True when a wall sits between the player's eye and `pos` (muffled sound).
func _occluded(pos: Vector3) -> bool:
	if world == null or not world.players.has(pid):
		return false
	var p: SimPlayer = world.players[pid]
	var eye := Vector3(p.pos.x, float(world.constants.player.eyeHeight), p.pos.y)
	var to := pos - eye
	var d := to.length()
	return d > 1.0 and world.map.raycast(eye, to / d, d) < d - 0.2


## Footsteps, low-health heartbeat and room reverb for the local player.
func _body_sounds(p: SimPlayer, delta: float) -> void:
	if p.is_alive() and p.moving:
		_step_t -= delta * world.player_sys.perk_mul(p, "moveSpeedMul")
		if _step_t <= 0.0:
			_step_t = 0.5
			# quiet and soft: heard under the action, not over it (phase 17)
			_sfx.play("step%d" % (1 + randi() % 4), -24.0, 0.06)
	else:
		_step_t = minf(_step_t, 0.1)
	if p.is_alive() and p.hp < p.max_hp * 0.3:
		_heart_t -= delta
		if _heart_t <= 0.0:
			_heart_t = 0.95
			_sfx.play("heartbeat", -6.0, 0.03)
	_room_t -= delta
	if _room_t <= 0.0:
		_room_t = 0.5
		Audio.set_room(_indoors(p.pos))


## Indoors when a ceiling-height wall is close in most directions (the yard is open).
func _indoors(pos: Vector2) -> bool:
	var eye := Vector3(pos.x, 1.6, pos.y)
	var hits := 0
	for i in 8:
		var a := i * TAU / 8.0
		if world.map.raycast(eye, Vector3(sin(a), 0.0, -cos(a)), 12.0) < 12.0:
			hits += 1
	return hits >= 5


## Screen positions of downed teammates for the HUD (edge-pinned when off screen).
func _downed_markers(me: SimPlayer) -> Array:
	var out := []
	var cam := _rig.camera
	var rect := get_viewport().get_visible_rect()
	var inner := rect.grow(-48.0)
	for o in world.players.values():
		if o == me or o.state != SimPlayer.State.DOWNED:
			continue
		var at := Vector3(o.pos.x, 0.9, o.pos.y)
		var sp := cam.unproject_position(at)
		var behind := cam.is_position_behind(at)
		if behind:
			sp = rect.size - sp  # mirror so the arrow points the right way
		var on_screen := not behind and inner.has_point(sp)
		if not on_screen:
			var c := rect.size / 2.0
			var d := sp - c
			if d.length() < 1.0:
				d = Vector2(0, 1)
			var k := minf(absf((inner.size.x / 2.0) / maxf(0.001, absf(d.x))), absf((inner.size.y / 2.0) / maxf(0.001, absf(d.y))))
			sp = c + d * minf(k, 1.0)
		out.append({"pos": sp, "on_screen": on_screen, "dist": me.pos.distance_to(o.pos), "revived": world.is_being_revived(o)})
	return out


func _ambient_groans(delta: float) -> void:
	_groan_t -= delta
	if _groan_t > 0.0 or _zviews.is_empty():
		return
	_groan_t = randf_range(2.5, 6.0)
	var views := _zviews.values()
	var v: ZombieView = views[randi() % views.size()]
	_sfx.play_at("zombie_groan%d" % (1 + randi() % 4), v.global_position + Vector3(0, 1.5, 0), -6.0, 0.1)


## ?showcase=1: art review mode. Waves off, player invulnerable, one of each
## zombie type spawned a few metres in front of the camera.
func _start_showcase() -> void:
	world.director.phase = WaveDirector.Phase.STOPPED
	var spots := [Vector2(-1.1, 11.6), Vector2(1.2, 12.0), Vector2(2.6, 11.4)]
	var types := ["walker", "runner", "boss"]
	if Platform.query_param("showcase") != "boss":
		types.resize(2)  # ?showcase=boss adds the Warden behind them
	for i in types.size():
		if world.zombie_sys.spawn(types[i], 1):
			var z: SimZombie = world.zombies.values()[world.zombies.size() - 1]
			z.pos = spots[i]
			z.prev_pos = z.pos
			z.speed *= 0.35
			z.def = z.def.duplicate()
			z.def.attackDamage = 0.0


## ?showcase=soldier: art review of the remote-player model, one standing
## (holding the current weapon) and one running a circle in front of the camera.
func _start_soldier_showcase() -> void:
	world.director.phase = WaveDirector.Phase.STOPPED
	var me: SimPlayer = world.players[pid]
	var guns := ["rifle", "rifle", "smg", "pistol"]
	for i in 4:
		var fake := SimPlayer.new()
		fake.id = 900 + i
		fake.name = ["Ally", "Runner", "Viper", "Ghost"][i]
		fake.pos = me.pos + [Vector2(-1.4, -3.2), Vector2(0, 0), Vector2(0.2, -3.6), Vector2(1.6, -3.0)][i]
		fake.yaw = me.yaw + PI + [0.6, 0.0, 0.0, -0.6][i]
		fake.weapons = [WeaponState.create(guns[i], _defs.weapons[guns[i]])]
		var v := RemotePlayerView.new()
		add_child(v)
		v.setup(fake)
		_showcase_soldiers.append([v, fake])


func _update_soldier_showcase(delta: float) -> void:
	_showcase_t += delta
	for i in _showcase_soldiers.size():
		var v: RemotePlayerView = _showcase_soldiers[i][0]
		var p: SimPlayer = _showcase_soldiers[i][1]
		if i == 1:
			var c: Vector2 = world.players[pid].pos + Vector2(1.2, -4.5)
			p.pos = c + Vector2(cos(_showcase_t * 1.6), sin(_showcase_t * 1.6)) * 1.8
			p.yaw = SimMath.yaw_to(c, p.pos) - PI / 2
			p.moving = true
		v.set_state(p)
		v.update_view(1.0, delta)


## ?showcase=box: stand at the supply cache with credits; it opens after 1 s.
func _start_box_showcase() -> void:
	world.director.phase = WaveDirector.Phase.STOPPED
	var p: SimPlayer = world.players[pid]
	var b = world.box_sys.boxes.values()[0]
	p.pos = b.pos + Vector2(0.4, -1.2)
	p.prev_pos = p.pos
	p.currency = 5000
	var yaw := SimMath.yaw_to(p.pos, b.pos + Vector2(0, 1.2))
	_controls.set_look(yaw, -0.25)
	get_tree().create_timer(1.0).timeout.connect(func(): _controls.queue_press(PlayerIntent.INTERACT))


func _toggle_pause() -> void:
	if world.zone_state == SimWorld.ZoneState.GAME_OVER:
		return
	_paused = not _paused
	_controls.enabled = not _paused
	_controls.release_all()
	if _paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pause_menu = PauseMenu.new()
		_hud.add_child(_pause_menu)
		_pause_menu.resume.connect(_toggle_pause)
		_pause_menu.quit.connect(_to_menu)
		_pause_menu.invite.connect(func(): _hud.show_toast(Social.invite()))
	elif _pause_menu:
		_pause_menu.queue_free()
		_pause_menu = null


## Only the nearest few lights are on: every lit pixel pays per light in the
## shader (up to 8 per object), and the scene holds over forty. Low keeps the
## 4 nearest within reach, medium 8, high 16 (10 on phones). Lights that views create later
## (power-ups, machines) are picked up on the next pass.
func _cull_lights(p: SimPlayer, delta: float) -> void:
	_light_t -= delta
	if _light_t > 0.0:
		return
	_light_t = 0.5
	_light_scan -= 1
	if _map_lights.is_empty() or _light_scan <= 0:
		_light_scan = 10  # rescan every 5 s for lights created since
		_map_lights.clear()
		for n in get_tree().root.find_children("*", "OmniLight3D", true, false):
			if n is Light3D and not n.is_in_group("rig_light"):
				_map_lights.append(n)
	var qp := Settings.quality_params()
	var keep: int = qp.lights_n
	var extra_on: bool = qp.lights
	var ranked: Array = []
	for l in _map_lights:
		if not is_instance_valid(l):
			continue
		var allowed := extra_on or not l.is_in_group("map_light_extra")
		var reach: float = float(l.get("omni_range")) if l is OmniLight3D else 10.0
		var d := Vector2(l.global_position.x, l.global_position.z).distance_to(p.pos) - reach
		if allowed and d < 18.0:
			ranked.append([d, l])
		else:
			l.visible = false
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	for i in ranked.size():
		(ranked[i][1] as Light3D).visible = i < keep


## WebGL compiles a material's shader the first time it is drawn: on a phone
## that is a freeze of up to a second the first time a gun fires, a zombie is
## hit or a teammate appears. Draw each of them once, in front of the camera,
## behind a short cover, as the match starts.
func _prewarm_gpu() -> void:
	if Platform.query_param("nohud") == "1":
		return
	var cover := ColorRect.new()
	cover.color = Color(0.02, 0.02, 0.03, 1.0)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.title("PREPARING", 26, UiTheme.GOLD)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cover.add_child(l)
	_hud.add_child(cover)
	var t0 := Time.get_ticks_msec()
	var p: SimPlayer = world.players[pid]
	var yaw := p.yaw
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var eye := Vector3(p.pos.x, float(world.constants.player.eyeHeight), p.pos.y)
	var at := eye + fwd * 2.5
	var temp: Array[Node] = []
	var i := 0
	for type in _defs.zombies:
		var v := ZombieView.new()
		add_child(v)
		v.setup(-100 - i, type, _defs.zombies[type], Vector2(at.x, at.z) + Vector2(fwd.z, -fwd.x) * (i - 0.5), yaw + PI)
		v.on_hit()   # the hit flash overlay is a material of its own
		temp.append(v)
		i += 1
	var dummy := SimPlayer.new()
	dummy.id = -99
	dummy.name = " "
	dummy.pos = Vector2(at.x, at.z) + Vector2(fwd.x, fwd.z) * 1.5
	dummy.weapons = [WeaponState.create(str(_defs.constants.player.startWeapon), _defs.weapons[str(_defs.constants.player.startWeapon)])]
	var rv := RemotePlayerView.new()
	add_child(rv)
	rv.setup(dummy)
	temp.append(rv)
	_rig.on_fire()
	_effects.tracer(eye + fwd * 0.5, at)
	_effects.impact(at, true)
	_effects.impact(at + Vector3(0, 0.3, 0), false)
	_effects.blast(eye, fwd, 4.0)
	_effects.bolt(eye + fwd * 0.5, at, Color("#88e0ff"))
	_effects.gore(at)
	for f in 3:
		await get_tree().process_frame
	_effects.clear_gore()
	for n in temp:
		n.queue_free()
	cover.queue_free()
	print("[load] prewarmed shaders in %d ms" % (Time.get_ticks_msec() - t0))


## Profiling (?perf=1): accumulates the section that ended now.
func _pm(section: String) -> void:
	if not _prof:
		return
	var now := Time.get_ticks_usec()
	_prof_acc[section] = int(_prof_acc.get(section, 0)) + (now - _prof_t0)
	_prof_t0 = now


func _prof_frame() -> void:
	if not _prof:
		return
	_prof_frames += 1
	var now := Time.get_ticks_usec()
	if _prof_wall == 0:
		_prof_wall = now
	if now - _prof_wall < 10_000_000:
		return
	var n := maxf(1.0, float(_prof_frames))
	var parts := PackedStringArray()
	var total := 0
	for k in _prof_acc:
		total += int(_prof_acc[k])
		parts.append("%s %.2f" % [k, int(_prof_acc[k]) / n / 1000.0])
	print("[perf] %d frames in 10 s (%.1f fps): script ms/frame %.2f = %s | zombies %d views %d draw %d prims %d process %.2f ms" % [
		_prof_frames, n / 10.0, total / n / 1000.0, ", ".join(parts), world.zombies.size(), _zviews.size(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	_prof_acc.clear()
	_prof_frames = 0
	_prof_wall = now
	_prof_breakdown()


## What the camera can see, by kind: the draw-call budget on a phone.
func _prof_breakdown() -> void:
	var cam := _rig.camera
	var counts := {}
	var surfs := {}
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var aabb := vi.get_aabb()
		var center := vi.global_transform * aabb.get_center()
		var inside := cam.is_position_in_frustum(center)
		if not inside and aabb.size.length() > 6.0:
			inside = true  # big meshes count even when their centre is behind the camera
		if not inside:
			continue
		var key := vi.get_class()
		if vi is MeshInstance3D:
			var nm := str(vi.name)
			key = "Mesh:" + nm.split("_")[0] if "_" in nm else "Mesh:" + nm.left(10)
			var p := vi.get_parent()
			if p and p.get_script():
				key = "Mesh<" + str(p.get_script().get_global_name())
			var m: Mesh = (vi as MeshInstance3D).mesh
			surfs[key] = int(surfs.get(key, 0)) + (m.get_surface_count() if m else 0)
		counts[key] = int(counts.get(key, 0)) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var parts := PackedStringArray()
	for k in keys.slice(0, 16):
		parts.append("%s %d%s" % [k, counts[k], ("/%ds" % surfs[k]) if surfs.has(k) else ""])
	print("[perf] in view: " + ", ".join(parts))


## Auto quality: phones start low and climb while the frame rate holds; any
## tier that cannot hold ~42 FPS drops. Measured over 4-second windows.
func _govern_quality(delta: float) -> void:
	if Settings.quality != "auto":
		return
	_perf_t += delta
	_perf_frames += 1
	if _perf_t < 4.0:
		return
	var fps := _perf_frames / _perf_t
	_perf_t = 0.0
	_perf_frames = 0
	var cap := Settings.effective_fps_cap()
	# Frame cap first: a screen that cannot hold ~50 of 60 runs at a steady 30
	# for the rest of the session (steady beats stuttering, and it runs cooler).
	if Settings.fps_cap == 0 and cap == 60 and fps < 50.0:
		Settings.auto_fps = 30
		Engine.max_fps = 30
		print("[perf] frame cap -> 30 (%.0f fps)" % fps)
		return
	var tiers := ["low", "medium", "high"]
	var i := tiers.find(Settings.auto_tier)
	var top := 0 if Platform.is_touch else 2   # phones stay low on their own; the player can pick more in settings
	var want := i
	if fps < cap * 0.7 and i > 0:
		want = i - 1
		_perf_good = 0
		_perf_dropped = true   # once dropped, never climb back this session (no flip-flop)
	elif fps > cap * 0.93 and i < top and not _perf_dropped:
		_perf_good += 1
		if _perf_good >= 3:   # 12 steady seconds before stepping up
			want = i + 1
			_perf_good = 0
	else:
		_perf_good = 0
	if want != i:
		Settings.auto_tier = tiers[want]
		print("[perf] auto quality -> %s (%.0f fps)" % [Settings.auto_tier, fps])
		_apply_quality()


func _apply_quality() -> void:
	var q := Settings.quality_params()
	get_viewport().scaling_3d_scale = q.scale
	get_viewport().msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}[int(q.msaa)]
	_rig.camera.far = q.far
	_rig.muzzle_light_enabled = q.muzzle_light
	var we := _map_root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we:
		we.environment.fog_enabled = q.fog
		we.environment.ambient_light_energy = 0.85 if q.lights else 1.05
	_light_t = 0.0  # the light culling pass re-evaluates every light for this tier
	if we:
		we.environment.glow_enabled = q.glow
	_atmosphere.set_quality(Settings.quality)


func _retry() -> void:
	if _online:
		Net.leave()
		Net.quick_play()
	get_tree().reload_current_scene()


func _on_net_failed(reason: String) -> void:
	_hud.show_status("Connection failed: %s" % reason)


# ---- voice chat buttons (online only; frames flow through Net and web/voice.js)

func _on_voice_toggled(which: String) -> void:
	if which == "mic":
		Net.set_voice_mic(not Net.voice_mic)
		if Net.voice_mic:
			_hud.show_toast("Microphone on")
	else:
		Net.set_voice_speaker(not Net.voice_speaker)
		_hud.show_toast("Voice chat on" if Net.voice_speaker else "Voice chat muted")


func _sync_voice_buttons() -> void:
	_controls.voice_buttons = _online and Net.voice_available
	_controls.mic_on = Net.voice_mic
	_controls.speaker_on = Net.voice_speaker
	_controls.mic_talking = Net.voice_talking
	var blocked := Net.voice_mic_state in ["denied", "unsupported"]
	if blocked and not _controls.mic_blocked:
		_hud.show_toast("Microphone not allowed here" if Net.voice_mic_state == "denied" else "Microphone not available in this app")
	_controls.mic_blocked = blocked
	_controls.queue_redraw()


func _exit_tree() -> void:
	if world is NetWorld:
		(world as NetWorld).close()
	if Net.failed.is_connected(_on_net_failed):
		Net.failed.disconnect(_on_net_failed)
	if Net.voice_changed.is_connected(_sync_voice_buttons):
		Net.voice_changed.disconnect(_sync_voice_buttons)
	if Net.voice_mic:
		Net.set_voice_mic(false)  # never keep the microphone open outside a match


func _to_menu() -> void:
	if _online:
		Net.leave()
		Net.online_requested = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
