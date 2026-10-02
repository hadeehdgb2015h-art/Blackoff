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
var _rig: FpRig
var _effects: Effects
var _sfx: Sfx
var _hud: Hud
var _controls: TouchControls
var _zviews := {}  ## zid -> ZombieView
var _boxes := {}   ## box id -> BoxView
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

	_rig = FpRig.new()
	add_child(_rig)
	_effects = Effects.new()
	add_child(_effects)
	_sfx = Sfx.new()
	add_child(_sfx)

	var ui := CanvasLayer.new()
	add_child(ui)
	_hud = Hud.new()
	ui.add_child(_hud)
	_hud.retry_pressed.connect(func(): get_tree().reload_current_scene())
	_hud.menu_pressed.connect(_to_menu)
	_controls = TouchControls.new()
	ui.add_child(_controls)
	_controls.pause_requested.connect(_toggle_pause)

	world = SimWorld.new(defs, map_id, randi())
	_spawn_box_views(defs)
	pid = world.add_player("You")
	var p: SimPlayer = world.players[pid]
	_controls.set_look(p.yaw, p.pitch)
	_rig.set_weapon(p.weapon().id)
	if Platform.query_param("bot") == "1":
		bot = BotBrain.new(pid, randi())
	Settings.changed.connect(_apply_quality)
	_apply_quality()
	_debug_js = Platform.is_web and Platform.query_param("debug") == "1"
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


func _process(delta: float) -> void:
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
	_rig.set_view(Vector3(eye.x, float(world.constants.player.eyeHeight), eye.y), _controls.yaw, _controls.pitch, p.moving, delta)
	for v in _zviews.values():
		v.update_view(alpha, delta)
	var opt := world.interact_option(pid)
	_controls.interact_label = "" if opt.is_empty() else str(opt.label)
	_controls.interact_ok = not opt.is_empty() and opt.affordable and not opt.full
	_hud.update_state(p, world, opt, delta)
	_ambient_groans(delta)
	if _debug_js:
		_publish_debug(p, delta)


## ?debug=1 exposes a small state snapshot to the page for automated browser tests.
func _publish_debug(p: SimPlayer, delta: float) -> void:
	_debug_t -= delta
	if _debug_t > 0.0:
		return
	_debug_t = 0.2
	var d := {"x": p.pos.x, "z": p.pos.y, "yaw": p.yaw, "pitch": p.pitch, "shots": p.shots_fired,
		"mag": p.weapon().mag, "hp": p.hp, "wave": world.director.wave, "zombies": world.zombies.size(),
		"tick": world.tick}
	JavaScriptBridge.eval("window.__blackoff = %s;" % JSON.stringify(d), true)


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
			if local:
				_rig.on_fire()
				var vis := Visuals.weapon(e.weapon)
				_sfx.play(vis.get("sound", "pistol_shot"), -2.0)
				_controls.add_recoil(float(vis.get("recoilPitch", 0.02)) * randf_range(0.6, 1.0), randf_range(-0.006, 0.006))
				_effects.tracer(_rig.muzzle_position(), e.to)
			if e.hit == "wall":
				_effects.impact(e.to, false)
		"zombie_hit":
			_effects.impact(e.point, true)
			var v: ZombieView = _zviews.get(e.zid)
			if v:
				v.on_hit()
			if local:
				_sfx.play("zombie_hit", -6.0)
		"zombie_killed":
			var v: ZombieView = _zviews.get(e.zid)
			if v:
				v.on_death(e.pos, e.yaw)
				_zviews.erase(e.zid)
			_sfx.play_at("zombie_death", Vector3(e.pos.x, 1.4, e.pos.y), -2.0)
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
				_rig.on_switch(world.players[pid].weapon().id)
		"purchase_denied":
			if local:
				_sfx.play("deny", -6.0)
		"dry_fire":
			if local:
				_sfx.play("dry_fire", -4.0)
		"wave_started":
			_sfx.play("wave_start", -6.0, 0.0)
			print("[game] wave %d started (%d zombies)" % [e.wave, e.count])
		"wave_cleared":
			_sfx.play("wave_end", -6.0, 0.0)
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
			_controls.enabled = false
			_controls.release_all()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_hud.show_game_over(int(e.wave), world.players[pid])
	_hud.on_event(e, pid)


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


func _to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
