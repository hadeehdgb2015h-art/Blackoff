class_name NetWorld
extends SimWorld
## Online replica of a server zone. It keeps SimWorld's read API (players,
## zombies, director, zone_state, events, box_sys, interact_option) so the
## game scene, views and HUD work unchanged; the state comes from the server.
##   Local player: movement and shots are predicted from the inputs we send,
##     then reconciled with the server position at `ackSeq` (pending inputs are
##     replayed with the same movement rules, so corrections are rare and small).
##   Remote players and zombies: drawn INTERP_TICKS behind the newest snapshot,
##     interpolated between the two snapshots around the render time.
## Nothing here decides damage, ammo, currency, kills or waves.

const INTERP_TICKS := 2.0    ## 100 ms at 20 Hz
const SNAP_DIST := 2.0       ## prediction errors above this snap, below they blend
const BLEND := 0.35

var local_pid: int = -1
var zone_id: int = 0
var mode: int = 0              ## 0 zombies, 1 infection (from zoneJoined)
var soldiers_left: int = 0     ## infection: soldiers alive (snapshot)
var phase_left: float = 0.0    ## infection: seconds left in the lobby countdown, round or result pause
var round_result: int = -1     ## infection: 1 soldiers won, 0 infected won, -1 none yet
var roster := {}             ## entity id -> display name
var levels := {}             ## entity id -> level (roster, phase 26)
var ready_to_play := false

var _weapon_ids: Array = []
var _zombie_types: Array = []
var _box_ids: Array = []
var _entry_ids: Array = []
var _ev := {}                ## event kind number -> name
var _inbox: Array = []
var _snaps: Array = []       ## [{tick, ents: {id: Dictionary}}], oldest first
var _render_tick: float = -1.0
var _current: PlayerIntent
var _pending: Array = []     ## [{seq, intent, shots}] sent, not yet applied by the server
var _seq: int = 0
var _last_currency: int = -1
var corrections: int = 0       ## reconciliations that moved the player > 5 cm (stats)
var max_error: float = 0.0
var _dead := {}              ## killed zombie id -> time (older snapshots still list it)
var _revived := {}           ## downed player id -> true while a teammate revives them
var _self_revive: float = 0.0  ## server's revive progress for the local player (0..1)
var _self_bleed: float = 0.0   ## server's bleed-out seconds for the local player
var _scores: Array = []      ## final table from the server's scoreboard message
var _powerup_types: Array = []
var _drop_until := {}        ## powerup id -> sim time it vanishes (from the drop event)


func _init(shared_defs: Dictionary, map_id: String) -> void:
	super(shared_defs, map_id, 1)
	zone_state = ZoneState.INTERMISSION
	director.phase = WaveDirector.Phase.INTERMISSION
	_weapon_ids = defs.weapons.keys()
	_weapon_ids.sort()
	_zombie_types = defs.zombies.keys()
	_zombie_types.sort()
	for it in map.interactables:
		if it.kind == "box":
			_box_ids.append(it.id)
	for e in map.zombie_entries:
		_entry_ids.append(e.id)
	_powerup_types = powerups.types
	var kinds: Dictionary = defs.protocol.enums.eventKind
	for k in kinds:
		_ev[int(kinds[k])] = k
	Net.message.connect(_on_message)
	for m in Net.take_buffer():
		_on_message(m[0], m[1])


func close() -> void:
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)


func _on_message(msg_name: String, msg: Dictionary) -> void:
	_inbox.append([msg_name, msg])


## The game calls this once per local tick with the player's controls.
func set_input(pid: int, intent: PlayerIntent) -> void:
	if pid != local_pid:
		return
	# Quantize exactly like the wire format so prediction matches the server.
	var q := PlayerIntent.new()
	_seq = (_seq % 65535) + 1
	q.seq = _seq
	q.move = Vector2(roundi(clampf(intent.move.x, -1, 1) * 127.0) / 127.0, roundi(clampf(intent.move.y, -1, 1) * 127.0) / 127.0)
	var turns := intent.yaw / TAU - floorf(intent.yaw / TAU)
	q.yaw = float(roundi(turns * 65536.0) & 0xffff) / 65536.0 * TAU
	q.pitch = float(clampi(roundi(intent.pitch / (PI / 2.0) * 32767.0), -32767, 32767)) / 32767.0 * (PI / 2.0)
	q.buttons = intent.buttons & 63
	_current = q
	Net.send("input", {"seq": q.seq, "moveX": roundi(q.move.x * 127.0), "moveY": roundi(q.move.y * 127.0),
		"yaw": q.yaw, "pitch": q.pitch, "buttons": q.buttons})


func step() -> void:
	events.clear()
	tick += 1
	time += dt
	var inbox := _inbox
	_inbox = []
	for m in inbox:
		_handle(m[0], m[1])
	if not ready_to_play:
		return
	_predict_local()
	_render_remote()


# ------------------------------------------------------------------ prediction

func _predict_local() -> void:
	var p: SimPlayer = players.get(local_pid)
	if p == null or _current == null:
		return
	p.prev_pos = p.pos
	p.yaw = SimMath.wrap_angle(_current.yaw)
	p.pitch = clampf(_current.pitch, -1.4, 1.4)
	var shots := 0
	# The server freezes a reviver in place and keeps their gun down; predict the same.
	var reviving := _current.buttons & PlayerIntent.REVIVE != 0 and player_sys.revive_candidate(p) != null
	if p.is_alive() and not reviving:
		p.pos = _move(p.pos, _current)
		p.moving = _current.move.limit_length(1.0).length_squared() > 0.01
		shots = _predict_fire(p, _current)
	elif reviving:
		p.moving = false
	_pending.append({"seq": _current.seq, "intent": _current, "shots": shots})
	if _pending.size() > 120:
		_pending.pop_front()


func _move(pos: Vector2, inp: PlayerIntent) -> Vector2:
	var mv := inp.move.limit_length(1.0)
	if mv.length_squared() <= 0.01:
		return pos
	var yaw := SimMath.wrap_angle(inp.yaw)
	var dir := SimMath.right(yaw) * mv.x + SimMath.forward(yaw) * mv.y
	var p: SimPlayer = players.get(local_pid)
	var speed := float(constants.player.moveSpeed) * (float(constants.infection.zombieSpeedMul) if p and p.team == 1 else 1.0)
	return map.move_circle(pos, dir * speed * dt, float(constants.player.radius))


## Cosmetic shots (muzzle, tracer, sound) right away; the server decides hits.
func _predict_fire(p: SimPlayer, inp: PlayerIntent) -> int:
	var wp := p.weapon()
	var pressed := inp.has(PlayerIntent.FIRE_PRESSED)
	if wp == null or not (inp.has(PlayerIntent.FIRE_HELD) or pressed) or p.is_reloading() or time < p.switch_end:
		return 0
	if wp.mag <= 0 or (not wp.is_auto() and not pressed):
		return 0
	var t := maxf(p.next_fire_time, time - dt)
	var shots := 0
	while t <= time and wp.mag > 0 and shots < 3:
		wp.mag -= 1
		shots += 1
		_cosmetic_shot(p, wp, inp)
		t += wp.interval()
		if not wp.is_auto():
			break
	if shots > 0:
		p.next_fire_time = t
	return shots


func _cosmetic_shot(p: SimPlayer, wp: WeaponState, inp: PlayerIntent) -> void:
	var origin := Vector3(p.pos.x, float(constants.player.eyeHeight), p.pos.y)
	var dir := SimMath.dir3(inp.yaw, clampf(inp.pitch, -1.5, 1.5))
	var rng_max := float(wp.def.range)
	var best := map.raycast(origin, dir, rng_max)
	var hit := "wall" if best < rng_max else "none"
	for z in zombies.values():
		var h := HitTest.ray_character(origin, dir, z.pos, z.radius(), float(z.def.headCenterHeight), float(z.def.headRadius))
		if not h.is_empty() and h.t < best:
			best = h.t
			hit = "zombie"
	for o in players.values():
		if o.id == p.id or o.team != 1 or not o.is_alive():
			continue
		var h := HitTest.ray_character(origin, dir, o.pos, float(constants.player.radius), float(constants.player.headCenterHeight), float(constants.player.headRadius))
		if not h.is_empty() and h.t < best:
			best = h.t
			hit = "zombie"
	var end := origin + dir * best
	emit({"type": "shot", "pid": p.id, "weapon": wp.id, "from": origin, "to": end, "ends": [end], "hit": hit, "predicted": true})


## Server position for the last applied input, then our unapplied inputs again.
func _reconcile(server_pos: Vector2, ack: int) -> void:
	var p: SimPlayer = players.get(local_pid)
	if p == null:
		return
	while not _pending.is_empty() and _seq_le(int(_pending[0].seq), ack):
		_pending.pop_front()
	var pos := server_pos
	if p.is_alive():
		for e in _pending:
			pos = _move(pos, e.intent)
	var err := pos - p.pos
	if err.length() > 0.05:
		corrections += 1
		max_error = maxf(max_error, err.length())
	if err.length() > SNAP_DIST or not p.is_alive():
		p.pos = pos
		p.prev_pos = pos
	elif err.length_squared() > 1e-6:
		p.pos += err * BLEND


static func _seq_le(a: int, b: int) -> bool:
	return ((b - a + 65536) % 65536) < 32768


# ------------------------------------------------------------------ remote entities

func _render_remote() -> void:
	if _snaps.is_empty():
		return
	var newest: float = _snaps[-1].tick
	var target := newest - INTERP_TICKS
	if _render_tick < 0.0 or absf(_render_tick + 1.0 - target) > 4.0:
		_render_tick = target
	else:
		_render_tick += 1.0 + clampf((target - _render_tick - 1.0) * 0.1, -0.2, 0.2)
	while _snaps.size() > 2 and _snaps[1].tick <= _render_tick:
		_snaps.pop_front()
	var a: Dictionary = _snaps[0]
	var b: Dictionary = _snaps[1] if _snaps.size() > 1 else a
	var span := maxf(1.0, float(b.tick - a.tick))
	var k := clampf((_render_tick - a.tick) / span, 0.0, 1.0)
	var seen := {}
	for id in _dead.keys():
		if time - float(_dead[id]) > 3.0:
			_dead.erase(id)
	for id in b.ents:
		if _dead.has(id):
			continue
		var eb: Dictionary = b.ents[id]
		var ea: Dictionary = a.ents.get(id, eb)
		var pos: Vector2 = ea.pos.lerp(eb.pos, k)
		var yaw := lerp_angle(float(ea.yaw), float(eb.yaw), k)
		seen[id] = true
		if eb.kind == 1:
			_place_zombie(id, eb, pos, yaw)
		elif eb.kind == 2:
			_place_powerup(id, eb)
		elif id != local_pid:
			_place_player(id, eb, pos, yaw)
	for id in zombies.keys():
		if not seen.has(id):
			zombies.erase(id)
	for id in powerups.drops.keys():
		if not seen.has(id):
			powerups.drops.erase(id)
	for id in players.keys():
		if id != local_pid and not seen.has(id):
			players.erase(id)


func _place_zombie(id: int, e: Dictionary, pos: Vector2, yaw: float) -> void:
	var z: SimZombie = zombies.get(id)
	if z == null:
		var type: String = _zombie_types[clampi(int(e.sub), 0, _zombie_types.size() - 1)]
		z = SimZombie.new()
		z.id = id
		z.type = type
		z.def = defs.zombies[type]
		z.pos = pos
		zombies[id] = z
	z.prev_pos = z.pos
	z.pos = pos
	z.yaw = yaw
	z.moving = int(e.flags) & 1 != 0
	z.state = SimZombie.State.WINDUP if int(e.flags) & 2 != 0 else SimZombie.State.CHASE
	z.max_hp = 100.0
	z.hp = float(e.hp)


func _place_player(id: int, e: Dictionary, pos: Vector2, yaw: float) -> void:
	var p: SimPlayer = players.get(id)
	if p == null:
		p = _new_player(id)
		p.pos = pos
	p.prev_pos = p.pos
	p.pos = pos
	p.yaw = yaw
	p.moving = int(e.flags) & 1 != 0
	p.state = _state_from_flags(int(e.flags))
	if int(e.flags) & 16 != 0:
		_revived[id] = true
	else:
		_revived.erase(id)
	p.hp = float(e.hp)
	p.reload_end = time + 1.0 if int(e.flags) & 8 != 0 else 0.0
	p.team = 1 if int(e.flags) & 64 != 0 else 0
	if p.team == 1:
		p.max_hp = float(constants.infection.zombieHealth) if mode == 1 else p.max_hp
		p.weapons = []
		p.slot = 0
		return
	var wid: String = _weapon_ids[clampi(int(e.sub), 0, _weapon_ids.size() - 1)]
	if p.weapons.is_empty() or p.weapons[0].id != wid:
		p.weapons = [WeaponState.create(wid, defs.weapons[wid])]
		p.slot = 0


func _place_powerup(id: int, e: Dictionary) -> void:
	if powerups.drops.has(id):
		return
	var d := PowerupSystem.Powerup.new()
	d.id = id
	d.type = _powerup_types[clampi(int(e.sub), 0, _powerup_types.size() - 1)]
	d.pos = e.pos
	d.until = float(_drop_until.get(id, time + float(constants.powerups.lifetimeSec)))
	powerups.drops[id] = d


static func _state_from_flags(flags: int) -> SimPlayer.State:
	if flags & 32 != 0:
		return SimPlayer.State.DEAD
	return SimPlayer.State.DOWNED if flags & 4 != 0 else SimPlayer.State.ALIVE


# ------------------------------------------------------------------ HUD read API (server values)

func revive_progress(p: SimPlayer) -> float:
	return _self_revive if p.id == local_pid else 0.0


func is_being_revived(p: SimPlayer) -> bool:
	if p.id == local_pid:
		return p.state == SimPlayer.State.DOWNED and _self_revive > 0.0
	return _revived.has(p.id)


func bleedout_left(p: SimPlayer) -> float:
	if p.id == local_pid:
		return _self_bleed
	return super(p)


func scores() -> Array:
	return _scores if not _scores.is_empty() else super()


func _new_player(id: int) -> SimPlayer:
	var p := SimPlayer.new()
	p.id = id
	p.name = str(roster.get(id, tr("Player")))
	p.max_hp = float(constants.player.maxHealth)
	p.hp = p.max_hp
	players[id] = p
	return p


# ------------------------------------------------------------------ messages

func _handle(msg_name: String, m: Dictionary) -> void:
	match msg_name:
		"zoneJoined":
			zone_id = int(m.zoneId)
			local_pid = int(m.entityId)
			mode = int(m.get("mode", 0))
			var p: SimPlayer = players.get(local_pid)
			if p == null:
				p = _new_player(local_pid)
			ready_to_play = false  # wait for the first snapshot to place us
			_pending.clear()
		"roster":
			roster.clear()
			levels.clear()
			for r in m.players:
				roster[int(r.id)] = str(r.name)
				levels[int(r.id)] = int(r.get("level", 1))
				if players.has(int(r.id)):
					players[int(r.id)].name = str(r.name)
			print("[net] roster: %d players" % roster.size())
		"snapshot":
			_on_snapshot(m)
		"scoreboard":
			_scores = []
			for r in m.players:
				_scores.append({"id": int(r.id), "name": str(r.name), "kills": int(r.kills), "headshots": int(r.headshots),
					"downs": int(r.downs), "revives": int(r.revives)})
		"selfState":
			_on_self(m)
		"event":
			_on_event(m)
		"shot":
			var pid := int(m.playerId)
			if pid == local_pid:
				return  # our own shots were already shown when fired
			var shooter: SimPlayer = players.get(pid)
			var from := Vector3(m.toX, m.toY, m.toZ)
			if shooter:
				from = Vector3(shooter.pos.x, float(constants.player.eyeHeight), shooter.pos.y)
			var to := Vector3(m.toX, m.toY, m.toZ)
			emit({"type": "shot", "pid": pid, "weapon": _weapon_ids[clampi(int(m.weapon), 0, _weapon_ids.size() - 1)],
				"from": from, "to": to, "ends": [to], "hit": ["none", "wall", "zombie"][clampi(int(m.hit), 0, 2)]})


func _on_snapshot(m: Dictionary) -> void:
	var ents := {}
	for e in m.entities:
		ents[int(e.id)] = {"kind": int(e.kind), "sub": int(e.sub), "pos": Vector2(e.x, e.y), "yaw": float(e.yaw),
			"hp": int(e.hp), "flags": int(e.flags)}
	_snaps.append({"tick": int(m.tick), "ents": ents})
	if _snaps.size() > 30:
		_snaps.pop_front()
	zone_state = int(m.zoneState) as ZoneState
	director.wave = int(m.wave)
	if mode == 1:
		soldiers_left = int(m.remaining)
		phase_left = float(m.timer) / 10.0
		director.phase = WaveDirector.Phase.STOPPED
	elif zone_state == ZoneState.WAVE:
		director.phase = WaveDirector.Phase.WAVE
		director.to_spawn = int(m.remaining)
		director.killed = 0
	elif zone_state == ZoneState.INTERMISSION:
		director.phase = WaveDirector.Phase.INTERMISSION
		director.phase_end = time + float(m.timer) / 10.0
	for t in ["instaKill", "doublePoints", "fireSale"]:
		if int(m.get(t, 0)) > 0:
			powerups.active[t] = time + float(m[t])
		else:
			powerups.active.erase(t)
	if zone_state != ZoneState.WAVE and zone_state != ZoneState.INTERMISSION:
		director.phase = WaveDirector.Phase.STOPPED
	var me: Dictionary = ents.get(local_pid, {})
	if me.is_empty():
		return
	var p: SimPlayer = players.get(local_pid)
	if p == null:
		p = _new_player(local_pid)
	p.state = _state_from_flags(int(me.flags))
	if not ready_to_play:
		ready_to_play = true
		p.pos = me.pos
		p.prev_pos = me.pos
		p.yaw = me.yaw
		return
	_reconcile(me.pos, int(m.ackSeq))


func _on_self(m: Dictionary) -> void:
	var p: SimPlayer = players.get(local_pid)
	if p == null:
		return
	p.hp = float(m.hp)
	p.state = int(m.state) as SimPlayer.State
	var was_team := p.team
	p.team = 1 if int(m.flags) & 4 != 0 else 0
	if p.team != was_team:
		p.next_fire_time = 0.0
	_self_revive = float(m.revive) / 255.0
	_self_bleed = float(m.bleedout)
	var bits := int(m.get("perks", 0))
	var owned: Array[String] = []
	for i in perk_ids.size():
		if bits & (1 << i) != 0:
			owned.append(perk_ids[i])
	p.perks = owned
	if mode == 1:
		p.max_hp = float(constants.infection.zombieHealth if p.team == 1 else constants.infection.soldierHealth)
	else:
		p.max_hp = float(constants.player.maxHealth) * player_sys.perk_mul(p, "maxHealthMul")
	var cur := int(m.currency)
	if _last_currency >= 0 and cur != _last_currency:
		emit({"type": "currency", "pid": local_pid, "amount": cur - _last_currency, "reason": "server"})
	_last_currency = cur
	p.currency = cur
	# Weapons: server mag minus the shots we predicted after the acked input.
	var unacked := 0
	for e in _pending:
		unacked += int(e.shots)
	var list: Array[WeaponState] = []
	for i in m.weapons.size():
		var ws: Dictionary = m.weapons[i]
		var wid: String = _weapon_ids[clampi(int(ws.weapon), 0, _weapon_ids.size() - 1)]
		var w := WeaponState.create(wid, defs.weapons[wid])
		w.mag = int(ws.mag) - (unacked if i == int(m.slot) else 0)
		w.mag = maxi(0, w.mag)
		w.reserve = int(ws.reserve)
		list.append(w)
	var slot_changed := p.weapons.size() != list.size() or p.slot != int(m.slot)
	p.weapons = list
	p.slot = clampi(int(m.slot), 0, maxi(0, list.size() - 1))
	p.reload_end = time + 999.0 if int(m.flags) & 1 != 0 else 0.0
	if int(m.flags) & 2 != 0 and slot_changed:
		p.switch_end = time + float(constants.player.weaponSwitchSec)
	elif int(m.flags) & 2 == 0:
		p.switch_end = 0.0


func _on_event(m: Dictionary) -> void:
	var kind: String = _ev.get(int(m.kind), "")
	var a := int(m.a)
	var b := int(m.b)
	var v := int(m.value)
	var f := int(m.flags)
	var weapon := func(i: int) -> String: return _weapon_ids[clampi(i, 0, _weapon_ids.size() - 1)]
	var box := func(i: int) -> String: return _box_ids[clampi(i, 0, maxi(0, _box_ids.size() - 1))] if not _box_ids.is_empty() else ""
	match kind:
		"hit":
			var z: SimZombie = zombies.get(a)
			var point := Vector3(z.pos.x, 1.3, z.pos.y) if z else Vector3.ZERO
			if f & 2 != 0:  # infection: the target is an infected player
				var t: SimPlayer = players.get(a)
				if t:
					point = Vector3(t.pos.x, 1.3, t.pos.y)
				emit({"type": "player_hit", "pid": b, "target": a, "damage": float(v), "head": f & 1 != 0, "point": point})
				return
			emit({"type": "zombie_hit", "zid": a, "pid": b, "damage": float(v), "head": f & 1 != 0, "point": point})
		"kill":
			var z: SimZombie = zombies.get(a)
			var pos := z.pos if z else Vector2.ZERO
			var yaw := z.yaw if z else 0.0
			zombies.erase(a)
			_dead[a] = time
			var killer: SimPlayer = players.get(b)
			if killer:
				killer.kills += 1
				if f & 1 != 0:
					killer.headshots += 1
			emit({"type": "zombie_killed", "zid": a, "pid": b, "head": f & 1 != 0, "ztype": _zombie_types[clampi(v, 0, _zombie_types.size() - 1)], "pos": pos, "yaw": yaw})
		"zombieSpawned": emit({"type": "zombie_spawned", "zid": a, "ztype": _zombie_types[clampi(b, 0, _zombie_types.size() - 1)], "entry": _entry_ids[clampi(v, 0, _entry_ids.size() - 1)]})
		"zombieAttack": emit({"type": "zombie_attack", "zid": a, "pid": b, "player": f & 1 != 0})
		"playerKilled":
			var victim: SimPlayer = players.get(a)
			if victim:
				victim.state = SimPlayer.State.DEAD
			var killer: SimPlayer = players.get(b)
			if killer:
				killer.kills += 1
				if f & 1 != 0:
					killer.headshots += 1
			emit({"type": "player_killed", "pid": a, "by": b, "head": f & 1 != 0})
		"infected":
			var victim: SimPlayer = players.get(a)
			if victim:
				victim.team = 1
				victim.weapons = []
				victim.downs += 1
			var by: SimPlayer = players.get(b)
			if by:
				by.kills += 1
			emit({"type": "infected", "pid": a, "by": b})
		"roundStart":
			round_result = -1
			emit({"type": "round_start", "round": a, "infected": b, "seconds": v})
		"roundEnd":
			round_result = 1 if f & 1 != 0 else 0
			emit({"type": "round_end", "round": a, "soldiersWin": f & 1 != 0})
		"playerDamaged": emit({"type": "player_damaged", "pid": a, "amount": float(v), "source": b})
		"playerDowned":
			var p: SimPlayer = players.get(a)
			if p:
				p.state = SimPlayer.State.DOWNED
				p.downed_time = time
				p.downs += 1
			emit({"type": "player_downed", "pid": a})
		"playerDied":
			var p: SimPlayer = players.get(a)
			if p:
				p.state = SimPlayer.State.DEAD
			emit({"type": "player_died", "pid": a})
		"playerRevived":
			var p: SimPlayer = players.get(a)
			if p:
				p.state = SimPlayer.State.ALIVE
			var by: SimPlayer = players.get(b)
			if by:
				by.revives += 1
			emit({"type": "player_revived", "pid": a, "by": b})
		"playerRespawned":
			var p: SimPlayer = players.get(a)
			if p:
				p.state = SimPlayer.State.ALIVE
			emit({"type": "player_respawned", "pid": a})
		"playerJoined": emit({"type": "player_joined", "pid": a})
		"playerLeft": emit({"type": "player_left", "pid": a})
		"waveStart": emit({"type": "wave_started", "wave": a, "count": v})
		"waveEnd": emit({"type": "wave_cleared", "wave": a})
		"gameOver":
			zone_state = ZoneState.GAME_OVER
			emit({"type": "game_over", "wave": a})
		"reloadStarted": emit({"type": "reload_started", "pid": a, "duration": v / 100.0})
		"reloadDone": emit({"type": "reload_done", "pid": a})
		"weaponSwitched": emit({"type": "weapon_switched", "pid": a, "weapon": weapon.call(b)})
		"dryFire": emit({"type": "dry_fire", "pid": a})
		"purchase":
			if f == 3:
				var perk: String = perk_ids[clampi(b, 0, maxi(0, perk_ids.size() - 1))] if not perk_ids.is_empty() else ""
				var buyer: SimPlayer = players.get(a)
				if buyer and perk != "" and not buyer.perks.has(perk):
					buyer.perks.append(perk)
				emit({"type": "purchase", "pid": a, "action": "perk", "item": perk, "cost": v})
			else:
				emit({"type": "purchase", "pid": a, "action": "ammo" if f == 1 else "weapon", "item": weapon.call(b), "cost": v})
		"powerupDropped":
			_drop_until[a] = time + v / 10.0
			var d: PowerupSystem.Powerup = powerups.drops.get(a)
			if d:
				d.until = _drop_until[a]
			emit({"type": "powerup_dropped", "id": a, "ptype": _powerup_types[clampi(b, 0, _powerup_types.size() - 1)], "until": _drop_until[a]})
		"powerupTaken":
			emit({"type": "powerup_taken", "pid": a, "ptype": _powerup_types[clampi(b, 0, _powerup_types.size() - 1)]})
		"powerupExpired":
			powerups.drops.erase(a)
			_drop_until.erase(a)
			emit({"type": "powerup_expired", "id": a})
		"purchaseDenied": emit({"type": "purchase_denied", "pid": a, "reason": "full" if f == 1 else "funds"})
		"boxOpened":
			var bx = box_sys.boxes.get(box.call(b))
			if bx:
				bx.state = BoxSystem.State.ROLLING
				bx.owner_pid = a
			emit({"type": "box_opened", "box": box.call(b), "pid": a, "until": time + v / 10.0})
		"boxOffer":
			var bx = box_sys.boxes.get(box.call(b))
			if bx:
				bx.state = BoxSystem.State.OFFER
				bx.owner_pid = a
				bx.result = weapon.call(v)
			emit({"type": "box_offer", "box": box.call(b), "pid": a, "weapon": weapon.call(v)})
		"boxTaken", "boxExpired":
			var bx = box_sys.boxes.get(box.call(b))
			if bx:
				bx.state = BoxSystem.State.IDLE
				bx.owner_pid = -1
				bx.result = ""
			if kind == "boxTaken":
				emit({"type": "box_taken", "box": box.call(b), "pid": a, "weapon": weapon.call(v)})
			else:
				emit({"type": "box_expired", "box": box.call(b)})
