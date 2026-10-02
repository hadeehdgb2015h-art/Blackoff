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
var _pause_menu: Control
var _groan_t: float = 2.0
var _game_over_shown: bool = false
var _debug_js: bool = false
var _debug_t: float = 0.0


func _ready() -> void:
	var defs := SharedData.data
	var map_id: String = defs.constants.maps.default
	_map_root = (load(MAP_SCENES[map_id]) as PackedScene).instantiate()
	add_child(_map_root)
	MapDecor.decorate(_map_root)
	var batches := MapBatcher.batch(_map_root)
	print("[game] map batched into %d meshes" % batches)
	_atmosphere = Atmosphere.build(_map_root)

	_rig = FpRig.new()
	add_child(_rig)
	_effects = Effects.new()
	add_child(_effects)
	_sfx = Sfx.new()
	add_child(_sfx)
	_sfx.occlusion_check = _occluded
	Audio.play_music("ambient")
	_atmosphere.thunder.connect(func(delay: float):
		get_tree().create_timer(delay).timeout.connect(func(): _sfx.play("thunder", -3.0, 0.15)))

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
	_controls = TouchControls.new()
	ui.add_child(_controls)
	_controls.pause_requested.connect(_toggle_pause)
	if Platform.query_param("nohud") == "1":  # clean captures (menu backdrop)
		_hud.visible = false
		_controls.visible = false
		_rig.set_viewmodel_visible(false)

	_defs = defs
	Settings.changed.connect(_apply_quality)
	_debug_js = Platform.is_web and Platform.query_param("debug") == "1"
	_online = Net.online_requested or Platform.query_param("server") != ""
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
	if showcase == "1":
		_start_showcase()
	elif showcase == "box":
		_start_box_showcase()
	elif showcase == "soldier":
		_start_soldier_showcase()


## The local player exists (offline: at once; online: after the first snapshot).
func _on_player_ready() -> void:
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
			print("[game] online: joined zone %d as entity %d" % [nw.zone_id, pid])
		return
	if _paused and _online:
		# The zone keeps running on the server: keep stepping with idle input.
		_acc += delta
		while _acc >= world.dt:
			world.set_input(pid, PlayerIntent.new())
			world.step()
			_sync_views()
			_acc -= world.dt
	if not _paused:
		_acc += delta
		var ticks := 0
		while _acc >= world.dt and ticks < MAX_CATCHUP_TICKS:
			var intent := bot.think(world) if bot else _controls.sample()
			world.set_input(pid, intent)
			world.step()
			_sync_views()
			for e in world.events:
				_on_event(e)
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
	_rig.set_view(Vector3(eye.x, float(world.constants.player.eyeHeight), eye.y), _controls.yaw, _controls.pitch, p.moving, delta)
	for v in _zviews.values():
		v.update_view(alpha, delta)
	for v in _pviews.values():
		v.update_view(alpha, delta)
	_sync_powerup_views()
	for v in _puviews.values():
		v.update_view(world.time, delta)
	_body_sounds(p, delta)
	var opt := world.interact_option(pid)
	var revive: bool = not opt.is_empty() and opt.action == "revive"
	_controls.revive_available = revive
	_controls.interact_label = "" if opt.is_empty() or revive else str(opt.label)
	_controls.interact_ok = not opt.is_empty() and opt.affordable and not opt.full
	_hud.update_state(p, world, opt, delta)
	_hud.set_markers(_downed_markers(p))
	_ambient_groans(delta)
	if not _showcase_soldiers.is_empty():
		_update_soldier_showcase(delta)
	if _online:
		_net_log_t -= delta
		if _net_log_t <= 0.0:
			_net_log_t = 10.0
			var nw := world as NetWorld
			print("[net] rtt=%d ms players=%d zombies=%d corrections=%d max_error=%.2f m" % [Net.rtt_ms, world.players.size(), world.zombies.size(), nw.corrections, nw.max_error])
	if _debug_js:
		_publish_debug(p, delta)


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
		"tick": world.tick, "online": _online, "players": world.players.size(), "rtt": Net.rtt_ms}
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
		if not world.players.has(id):
			_pviews[id].queue_free()
			_pviews.erase(id)
	for p in world.players.values():
		if p.id == pid:
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
				_sfx.play_at(wvis.get("sound", "pistol_shot"), from, -6.0)
				var pv: RemotePlayerView = _pviews.get(e.pid)
				if pv:
					pv.on_fire()
			else:
				_rig.on_fire()
				_sfx.play(wvis.get("sound", "pistol_shot"), -2.0)
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
		"zombie_killed":
			var v: ZombieView = _zviews.get(e.zid)
			if v:
				v.on_death(e.pos, e.yaw)
				_zviews.erase(e.zid)
			_sfx.play_at("zombie_death", Vector3(e.pos.x, 1.4, e.pos.y), -2.0)
			if local and e.head:
				_sfx.play("headshot", -8.0, 0.02)
		"zombie_attack":
			var v: ZombieView = _zviews.get(e.zid)
			if v:
				v.on_attack(float(v.def.attackWindupSec))
				_sfx.play_at("zombie_attack", v.global_position + Vector3(0, 1.5, 0), 0.0)
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
			_step_t = 0.42
			_sfx.play("step%d" % (1 + randi() % 4), -16.0, 0.12)
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
	_groan_t = randf_range(1.2, 3.5)
	var views := _zviews.values()
	var v: ZombieView = views[randi() % views.size()]
	_sfx.play_at("zombie_groan%d" % (1 + randi() % 2), v.global_position + Vector3(0, 1.5, 0), -4.0, 0.15)


## ?showcase=1: art review mode. Waves off, player invulnerable, one of each
## zombie type spawned a few metres in front of the camera.
func _start_showcase() -> void:
	world.director.phase = WaveDirector.Phase.STOPPED
	var spots := [Vector2(-1.1, 11.6), Vector2(1.2, 12.0)]
	var types := ["walker", "runner"]
	for i in 2:
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
	elif _pause_menu:
		_pause_menu.queue_free()
		_pause_menu = null


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
	for n in get_tree().get_nodes_in_group("map_light_extra"):
		(n as Light3D).visible = q.lights
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


func _exit_tree() -> void:
	if world is NetWorld:
		(world as NetWorld).close()
	if Net.failed.is_connected(_on_net_failed):
		Net.failed.disconnect(_on_net_failed)


func _to_menu() -> void:
	if _online:
		Net.leave()
		Net.online_requested = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
