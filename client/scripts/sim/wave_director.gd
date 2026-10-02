class_name WaveDirector
extends RefCounted
## Infinite waves driven by shared/waves.json. The formulas here are the
## contract the server mirrors; tests pin them.

enum Phase { INTERMISSION, WAVE, STOPPED }

var cfg: Dictionary
var zombie_defs: Dictionary
var phase: Phase = Phase.INTERMISSION
var wave: int = 0
var phase_end: float = 0.0
var to_spawn: int = 0
var spawned: int = 0
var killed: int = 0
var next_spawn_time: float = 0.0


func _init(waves_cfg: Dictionary, zombies: Dictionary) -> void:
	cfg = waves_cfg
	zombie_defs = zombies


func start(now: float) -> void:
	phase = Phase.INTERMISSION
	wave = 0
	phase_end = now + float(cfg.firstWaveDelaySec)


func remaining() -> int:
	return to_spawn - killed


static func count_for(c: Dictionary, wave_n: int, players: int) -> int:
	var cc: Dictionary = c.count
	var raw := pow(float(cc.base) + float(cc.perWave) * (wave_n - 1), float(cc.exponent))
	var scaled := raw * (1.0 + float(cc.perExtraPlayer) * maxi(0, players - 1))
	return mini(int(cc.max), maxi(1, roundi(scaled)))


static func spawn_interval_for(c: Dictionary, wave_n: int) -> float:
	var s: Dictionary = c.spawnIntervalSec
	return maxf(float(s.min), float(s.start) + float(s.perWave) * (wave_n - 1))


static func health_for(def: Dictionary, wave_n: int) -> float:
	return float(def.baseHealth) + float(def.healthPerWave) * (wave_n - 1)


static func speed_for(def: Dictionary, wave_n: int) -> float:
	return minf(float(def.maxMoveSpeed), float(def.moveSpeed) + float(def.moveSpeedPerWave) * (wave_n - 1))


static func mix_for(c: Dictionary, wave_n: int) -> Dictionary:
	var best: Dictionary = c.mix[0].weights
	for entry in c.mix:
		if int(entry.fromWave) <= wave_n:
			best = entry.weights
	return best


static func pick_type(c: Dictionary, wave_n: int, rng: RandomNumberGenerator) -> String:
	var weights := mix_for(c, wave_n)
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	var last := ""
	for k in weights:
		last = k
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return last
