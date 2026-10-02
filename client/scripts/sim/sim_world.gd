class_name SimWorld
extends RefCounted
## One zone's authoritative simulation at a fixed tick (constants.sim.tickRate).
## Runs locally for offline play; the server runs the same rules in TypeScript.
## Views read `players`, `zombies`, `director` and the per-tick `events` list
## and never write to the sim. Only PlayerIntent goes in.

enum ZoneState { LOBBY, INTERMISSION, WAVE, GAME_OVER }

var defs: Dictionary
var constants: Dictionary
var map: MapData
var nav: NavGrid
var rng := RandomNumberGenerator.new()
var dt: float
var tick: int = 0
var time: float = 0.0
var zone_state: ZoneState = ZoneState.LOBBY
var players := {}  ## id -> SimPlayer
var zombies := {}  ## id -> SimZombie
var director: WaveDirector
var events: Array[Dictionary] = []

var _next_id: int = 1
var player_sys: PlayerSystem
var zombie_sys: ZombieSystem
var box_sys: BoxSystem


## defs = SharedLoader.load_all() result; map_id selects defs.maps entry.
func _init(shared_defs: Dictionary, map_id: String, seed: int) -> void:
	defs = shared_defs
	constants = defs.constants
	dt = 1.0 / float(constants.sim.tickRate)
	rng.seed = seed
	map = MapData.from_dict(defs.maps[map_id], float(constants.player.stepHeight))
	nav = NavGrid.new(map, float(constants.maps.navCellSize), float(constants.maps.navAgentRadius))
	director = WaveDirector.new(defs.waves, defs.zombies)
	player_sys = PlayerSystem.new(self)
	zombie_sys = ZombieSystem.new(self)
	box_sys = BoxSystem.new(self)


func add_player(display_name: String) -> int:
	var p := SimPlayer.new()
	p.id = _alloc_id()
	p.name = display_name
	var spawn: Dictionary = map.player_spawns[players.size() % map.player_spawns.size()]
	p.pos = spawn.pos
	p.prev_pos = p.pos
	p.yaw = spawn.yaw
	p.max_hp = float(constants.player.maxHealth)
	p.hp = p.max_hp
	p.currency = int(constants.player.startCurrency)
	var start_id: String = constants.player.startWeapon
	p.weapons.append(WeaponState.create(start_id, defs.weapons[start_id]))
	players[p.id] = p
	if zone_state == ZoneState.LOBBY:
		zone_state = ZoneState.INTERMISSION
		director.start(time)
	emit({"type": "player_joined", "pid": p.id})
	return p.id


func set_input(pid: int, intent: PlayerIntent) -> void:
	if players.has(pid):
		players[pid].input = intent


func step() -> void:
	events.clear()
	tick += 1
	time += dt
	if zone_state == ZoneState.GAME_OVER:
		return
	for p in players.values():
		player_sys.update(p)
	box_sys.update()
	_update_director()
	zombie_sys.update_all()
	zombie_sys.separate_from_players()
	_check_game_over()


func alive_players() -> Array:
	var out := []
	for p in players.values():
		if p.is_alive():
			out.append(p)
	return out


func emit(e: Dictionary) -> void:
	e["tick"] = tick
	events.append(e)


func add_currency(p: SimPlayer, amount: int, reason: String) -> void:
	if amount == 0:
		return
	p.currency += amount
	emit({"type": "currency", "pid": p.id, "amount": amount, "reason": reason})


func damage_player(p: SimPlayer, amount: float, source_id: int) -> void:
	if not p.is_alive():
		return
	p.hp -= amount
	p.last_damage_time = time
	emit({"type": "player_damaged", "pid": p.id, "amount": amount, "source": source_id})
	if p.hp <= 0.0:
		p.hp = 0.0
		p.state = SimPlayer.State.DOWNED
		p.downed_time = time
		p.reload_end = 0.0
		p.revive_target = 0
		p.revive_ticks = 0
		p.downs += 1
		emit({"type": "player_downed", "pid": p.id})


## The player currently reviving `p`, or null.
func reviver_of(p: SimPlayer) -> SimPlayer:
	for o in players.values():
		if o.revive_target == p.id and o.is_alive():
			return o
	return null


## 0..1 progress of the revive `p` is doing, or (when downed) receiving.
func revive_progress(p: SimPlayer) -> float:
	var doer: SimPlayer = p if p.is_alive() and p.revive_target != 0 else (reviver_of(p) if p.state == SimPlayer.State.DOWNED else null)
	if doer == null:
		return 0.0
	return clampf(float(doer.revive_ticks) / float(player_sys.revive_ticks_needed()), 0.0, 1.0)


func is_being_revived(p: SimPlayer) -> bool:
	return p.state == SimPlayer.State.DOWNED and reviver_of(p) != null


## Final stats per player (the game-over table).
func scores() -> Array:
	var out := []
	for p in players.values():
		out.append({"id": p.id, "name": p.name, "kills": p.kills, "headshots": p.headshots, "downs": p.downs, "revives": p.revives})
	return out


## Seconds a downed player has left before bleeding out.
func bleedout_left(p: SimPlayer) -> float:
	return maxf(0.0, float(constants.player.downedBleedoutSec) - (time - p.downed_time))


## Describes what the player could interact with right now (for HUD prompts).
func interact_option(pid: int) -> Dictionary:
	return player_sys.interact_option(players[pid]) if players.has(pid) else {}


func _update_director() -> void:
	var d := director
	match d.phase:
		WaveDirector.Phase.INTERMISSION:
			zone_state = ZoneState.INTERMISSION
			if time >= d.phase_end:
				d.wave += 1
				d.phase = WaveDirector.Phase.WAVE
				d.to_spawn = WaveDirector.count_for(defs.waves, d.wave, players.size())
				d.spawned = 0
				d.killed = 0
				d.next_spawn_time = time
				zone_state = ZoneState.WAVE
				emit({"type": "wave_started", "wave": d.wave, "count": d.to_spawn})
				_respawn_dead()
		WaveDirector.Phase.WAVE:
			zone_state = ZoneState.WAVE
			var cap := int(constants.zone.maxAliveZombies)
			if d.spawned < d.to_spawn and time >= d.next_spawn_time and zombies.size() < cap:
				if zombie_sys.spawn(WaveDirector.pick_type(defs.waves, d.wave, rng), d.wave):
					d.spawned += 1
					d.next_spawn_time = time + WaveDirector.spawn_interval_for(defs.waves, d.wave)
			if d.spawned >= d.to_spawn and zombies.is_empty():
				d.phase = WaveDirector.Phase.INTERMISSION
				d.phase_end = time + float(defs.waves.intermissionSec)
				zone_state = ZoneState.INTERMISSION
				for p in players.values():
					if p.is_alive():
						p.hp = p.max_hp
				emit({"type": "wave_cleared", "wave": d.wave})


## Players who bled out come back at the start of the next wave.
func _respawn_dead() -> void:
	var i := 0
	for p in players.values():
		if p.state == SimPlayer.State.DEAD:
			var spawn: Dictionary = map.player_spawns[i % map.player_spawns.size()]
			i += 1
			p.state = SimPlayer.State.ALIVE
			p.hp = p.max_hp
			p.pos = spawn.pos
			p.prev_pos = p.pos
			p.yaw = spawn.yaw
			p.reload_end = 0.0
			emit({"type": "player_respawned", "pid": p.id})


func _check_game_over() -> void:
	if players.is_empty():
		return
	for p in players.values():
		if p.state == SimPlayer.State.DOWNED and reviver_of(p) != null:
			p.downed_time += dt  # the bleed-out clock pauses while someone revives
		elif p.state == SimPlayer.State.DOWNED and time - p.downed_time >= float(constants.player.downedBleedoutSec):
			p.state = SimPlayer.State.DEAD
			emit({"type": "player_died", "pid": p.id})
	if alive_players().is_empty():
		zone_state = ZoneState.GAME_OVER
		director.phase = WaveDirector.Phase.STOPPED
		emit({"type": "game_over", "wave": director.wave})


func _alloc_id() -> int:
	var id := _next_id
	_next_id = (_next_id % 65535) + 1
	while players.has(_next_id) or zombies.has(_next_id):
		_next_id = (_next_id % 65535) + 1
	return id


func alloc_id() -> int:
	return _alloc_id()
