/**
 * One zone's authoritative simulation at a fixed tick (mirror of sim_world.gd).
 * Only PlayerIntents go in; state and the per-tick `events` list come out.
 * Server additions: removePlayer() (disconnects).
 */
import type { SharedData } from "../shared/loadShared.js";
import type { Constants } from "../shared/schemas.js";
import { MapData } from "./mapData.js";
import { NavGrid } from "./navGrid.js";
import { Rng } from "./rng.js";
import { WaveDirector, Phase } from "./waveDirector.js";
import { PlayerState, SimPlayer, WeaponState, type PlayerIntent, type SimEvent, type SimZombie } from "./entities.js";
import { PlayerSystem, type InteractOption } from "./playerSystem.js";
import { ZombieSystem } from "./zombieSystem.js";
import { BoxSystem } from "./boxSystem.js";

export enum ZoneState { LOBBY = 0, INTERMISSION = 1, WAVE = 2, GAME_OVER = 3 }

export class SimWorld {
  readonly constants: Constants;
  readonly map: MapData;
  readonly nav: NavGrid;
  readonly rng: Rng;
  readonly dt: number;
  tick = 0;
  time = 0;
  zoneState = ZoneState.LOBBY;
  players = new Map<number, SimPlayer>();
  zombies = new Map<number, SimZombie>();
  readonly director: WaveDirector;
  events: SimEvent[] = [];
  readonly playerSys: PlayerSystem;
  readonly zombieSys: ZombieSystem;
  readonly boxSys: BoxSystem;
  private nextId = 1;

  constructor(readonly defs: SharedData, mapId: string, seed: number) {
    this.constants = defs.constants;
    this.dt = 1 / this.constants.sim.tickRate;
    this.rng = new Rng(seed);
    const mapDef = defs.maps[mapId];
    if (!mapDef) throw new Error(`unknown map ${mapId}`);
    this.map = new MapData(mapDef, this.constants.player.stepHeight);
    this.nav = new NavGrid(this.map, this.constants.maps.navCellSize, this.constants.maps.navAgentRadius);
    this.director = new WaveDirector(defs.waves);
    this.playerSys = new PlayerSystem(this);
    this.zombieSys = new ZombieSystem(this);
    this.boxSys = new BoxSystem(this);
  }

  addPlayer(displayName: string): number {
    const p = new SimPlayer(this.allocId(), displayName);
    const spawn = this.map.playerSpawns[this.players.size % this.map.playerSpawns.length]!;
    p.pos = { ...spawn.pos };
    p.prevPos = { ...p.pos };
    p.yaw = spawn.yaw;
    p.maxHp = this.constants.player.maxHealth;
    p.hp = p.maxHp;
    p.currency = this.constants.player.startCurrency;
    const startId = this.constants.player.startWeapon;
    p.weapons.push(new WeaponState(startId, this.defs.weapons[startId]!));
    this.players.set(p.id, p);
    if (this.zoneState === ZoneState.LOBBY) {
      this.zoneState = ZoneState.INTERMISSION;
      this.director.start(this.time);
    }
    this.emit({ type: "player_joined", pid: p.id });
    return p.id;
  }

  removePlayer(pid: number): void {
    if (!this.players.delete(pid)) return;
    this.emit({ type: "player_left", pid });
  }

  setInput(pid: number, intent: PlayerIntent): void {
    const p = this.players.get(pid);
    if (p) p.input = intent;
  }

  step(): void {
    this.events = [];
    this.tick += 1;
    this.time += this.dt;
    if (this.zoneState === ZoneState.GAME_OVER) return;
    for (const p of this.players.values()) this.playerSys.update(p);
    this.boxSys.update();
    this.updateDirector();
    this.zombieSys.updateAll();
    this.zombieSys.separateFromPlayers();
    this.checkGameOver();
  }

  alivePlayers(): SimPlayer[] {
    return [...this.players.values()].filter((p) => p.isAlive());
  }

  emit(e: SimEvent): void {
    e.tick = this.tick;
    this.events.push(e);
  }

  addCurrency(p: SimPlayer, amount: number, reason: string): void {
    if (amount === 0) return;
    p.currency += amount;
    this.emit({ type: "currency", pid: p.id, amount, reason });
  }

  damagePlayer(p: SimPlayer, amount: number, sourceId: number): void {
    if (!p.isAlive()) return;
    p.hp -= amount;
    p.lastDamageTime = this.time;
    this.emit({ type: "player_damaged", pid: p.id, amount, source: sourceId });
    if (p.hp <= 0) {
      p.hp = 0;
      p.state = PlayerState.DOWNED;
      p.downedTime = this.time;
      p.reloadEnd = 0;
      p.reviveTarget = 0;
      p.reviveTicks = 0;
      p.downs += 1;
      this.emit({ type: "player_downed", pid: p.id });
    }
  }

  /** The player currently reviving `p`, or null. */
  reviverOf(p: SimPlayer): SimPlayer | null {
    for (const o of this.players.values()) if (o.reviveTarget === p.id && o.isAlive()) return o;
    return null;
  }

  /** Seconds a downed player has left before bleeding out. */
  bleedoutLeft(p: SimPlayer): number {
    return Math.max(0, this.constants.player.downedBleedoutSec - (this.time - p.downedTime));
  }

  interactOption(pid: number): InteractOption | null {
    const p = this.players.get(pid);
    return p ? this.playerSys.interactOption(p) : null;
  }

  private updateDirector(): void {
    const d = this.director;
    if (d.phase === Phase.INTERMISSION) {
      this.zoneState = ZoneState.INTERMISSION;
      if (this.time >= d.phaseEnd) {
        d.wave += 1;
        d.phase = Phase.WAVE;
        d.toSpawn = WaveDirector.countFor(this.defs.waves, d.wave, this.players.size);
        d.spawned = 0;
        d.killed = 0;
        d.nextSpawnTime = this.time;
        this.zoneState = ZoneState.WAVE;
        this.emit({ type: "wave_started", wave: d.wave, count: d.toSpawn });
        this.respawnDead();
      }
    } else if (d.phase === Phase.WAVE) {
      this.zoneState = ZoneState.WAVE;
      const cap = this.constants.zone.maxAliveZombies;
      if (d.spawned < d.toSpawn && this.time >= d.nextSpawnTime && this.zombies.size < cap) {
        if (this.zombieSys.spawn(WaveDirector.pickType(this.defs.waves, d.wave, this.rng), d.wave)) {
          d.spawned += 1;
          d.nextSpawnTime = this.time + WaveDirector.spawnIntervalFor(this.defs.waves, d.wave);
        }
      }
      if (d.spawned >= d.toSpawn && this.zombies.size === 0) {
        d.phase = Phase.INTERMISSION;
        d.phaseEnd = this.time + this.defs.waves.intermissionSec;
        this.zoneState = ZoneState.INTERMISSION;
        for (const p of this.players.values()) if (p.isAlive()) p.hp = p.maxHp;
        this.emit({ type: "wave_cleared", wave: d.wave });
      }
    }
  }

  /** Players who bled out come back at the start of the next wave. */
  private respawnDead(): void {
    let i = 0;
    for (const p of this.players.values()) {
      if (p.state !== PlayerState.DEAD) continue;
      const spawn = this.map.playerSpawns[i % this.map.playerSpawns.length]!;
      i += 1;
      p.state = PlayerState.ALIVE;
      p.hp = p.maxHp;
      p.pos = { ...spawn.pos };
      p.prevPos = { ...p.pos };
      p.yaw = spawn.yaw;
      p.reloadEnd = 0;
      this.emit({ type: "player_respawned", pid: p.id });
    }
  }

  private checkGameOver(): void {
    if (this.players.size === 0) return;
    for (const p of this.players.values()) {
      if (p.state === PlayerState.DOWNED && this.reviverOf(p)) {
        p.downedTime += this.dt; // the bleed-out clock pauses while someone revives
      } else if (p.state === PlayerState.DOWNED && this.time - p.downedTime >= this.constants.player.downedBleedoutSec) {
        p.state = PlayerState.DEAD;
        this.emit({ type: "player_died", pid: p.id });
      }
    }
    if (this.alivePlayers().length === 0) {
      this.zoneState = ZoneState.GAME_OVER;
      this.director.phase = Phase.STOPPED;
      this.emit({ type: "game_over", wave: this.director.wave });
    }
  }

  /** Entity ids share one u16 space (1..65535), never reused while alive. */
  allocId(): number {
    const id = this.nextId;
    this.nextId = (this.nextId % 65535) + 1;
    while (this.players.has(this.nextId) || this.zombies.has(this.nextId)) this.nextId = (this.nextId % 65535) + 1;
    return id;
  }
}
