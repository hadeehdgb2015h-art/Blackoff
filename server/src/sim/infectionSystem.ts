/**
 * Infection mode (phase 13): real players only, no AI zombies. The zone waits
 * in the LOBBY for `minPlayers`, counts down, then each round starts with a few
 * infected players (one per `playersPerFirstInfected`) against soldiers with
 * the start weapons. A soldier killed by an infected player turns infected on
 * the spot; an infected player killed by a soldier comes back after a short
 * delay at a zombie entry. Infected win when no soldier is left, soldiers win
 * when the round clock runs out. Rounds repeat while enough players stay.
 * Zone states are reused: LOBBY = waiting, WAVE = a round is on, INTERMISSION
 * = the result pause. (No client mirror: infection is online only.)
 */
import { PlayerState, Team, WeaponState, type PlayerIntent, type SimPlayer } from "./entities.js";
import { Btn } from "./entities.js";
import { dist, wrapAngle, yawTo, type V3 } from "./math.js";
import { ZoneState, type SimWorld } from "./simWorld.js";

const DEG = Math.PI / 180;

export class InfectionSystem {
  round = 0;
  /** sim time the lobby countdown, the round or the result pause ends (0 = no countdown) */
  phaseEnd = 0;
  /** the last round's winner, for the HUD (true = soldiers) */
  soldiersWon = false;

  constructor(private readonly w: SimWorld) {}

  private get c() { return this.w.constants.infection; }

  /** Seconds left in the current phase (lobby countdown, round, result pause). */
  secondsLeft(): number {
    return this.phaseEnd > 0 ? Math.max(0, this.phaseEnd - this.w.time) : 0;
  }

  soldiersAlive(): number {
    let n = 0;
    for (const p of this.w.players.values()) if (p.team === Team.SOLDIER && p.isAlive()) n += 1;
    return n;
  }

  infectedCount(): number {
    let n = 0;
    for (const p of this.w.players.values()) if (p.team === Team.ZOMBIE) n += 1;
    return n;
  }

  /** A player entered the zone: a soldier while waiting, infected during a round. */
  onJoin(p: SimPlayer): void {
    if (this.w.zoneState === ZoneState.WAVE) this.makeZombie(p, true);
    else this.makeSoldier(p);
  }

  update(): void {
    const w = this.w;
    const n = w.players.size;
    switch (w.zoneState) {
      case ZoneState.LOBBY:
        if (n < this.c.minPlayers) {
          this.phaseEnd = 0;
        } else if (this.phaseEnd === 0) {
          this.phaseEnd = w.time + (n >= this.c.maxPlayers ? this.c.lobbyFullSec : this.c.lobbySec);
        } else if (n >= this.c.maxPlayers) {
          this.phaseEnd = Math.min(this.phaseEnd, w.time + this.c.lobbyFullSec);
        }
        if (this.phaseEnd > 0 && w.time >= this.phaseEnd) this.startRound();
        return;
      case ZoneState.WAVE:
        for (const p of w.players.values()) {
          if (p.team === Team.ZOMBIE && p.state === PlayerState.DEAD && w.time >= p.respawnAt) this.respawnZombie(p);
        }
        if (this.soldiersAlive() === 0) this.endRound(false);
        else if (w.time >= this.phaseEnd) this.endRound(true);
        else if (this.infectedCount() === 0 && n >= this.c.minPlayers) this.pickFirstInfected(); // the only infected left
        return;
      case ZoneState.INTERMISSION:
        if (w.time < this.phaseEnd) return;
        if (n >= this.c.minPlayers) this.startRound();
        else {
          w.zoneState = ZoneState.LOBBY;
          this.phaseEnd = 0;
          for (const p of w.players.values()) this.makeSoldier(p);
        }
        return;
      default:
        return;
    }
  }

  private startRound(): void {
    const w = this.w;
    this.round += 1;
    let i = 0;
    for (const p of w.players.values()) {
      this.makeSoldier(p);
      const spawn = w.map.playerSpawns[i % w.map.playerSpawns.length]!;
      i += 1;
      p.pos = { ...spawn.pos };
      p.prevPos = { ...p.pos };
      p.yaw = spawn.yaw;
    }
    w.zoneState = ZoneState.WAVE;
    this.phaseEnd = w.time + this.c.roundSec;
    const k = this.pickFirstInfected();
    w.emit({ type: "round_start", round: this.round, seconds: this.c.roundSec, infected: k });
  }

  /** Turns ceil(n / playersPerFirstInfected) random soldiers infected. */
  private pickFirstInfected(): number {
    const w = this.w;
    const soldiers = w.rng.shuffle([...w.players.values()].filter((p) => p.team === Team.SOLDIER));
    const k = Math.min(soldiers.length, Math.max(1, Math.ceil(w.players.size / this.c.playersPerFirstInfected)));
    for (let i = 0; i < k; i++) this.makeZombie(soldiers[i]!, true);
    return k;
  }

  private endRound(soldiersWin: boolean): void {
    const w = this.w;
    this.soldiersWon = soldiersWin;
    w.zoneState = ZoneState.INTERMISSION;
    this.phaseEnd = w.time + this.c.resultSec;
    for (const p of w.players.values()) {
      if (p.state === PlayerState.DEAD) p.state = PlayerState.ALIVE; // nobody waits through the pause
      p.input = { ...p.input, buttons: 0 };
    }
    w.emit({ type: "round_end", round: this.round, soldiersWin });
  }

  makeSoldier(p: SimPlayer): void {
    p.team = Team.SOLDIER;
    p.state = PlayerState.ALIVE;
    this.w.playerSys.clearPerks(p);
    p.maxHp = this.c.soldierHealth;
    p.hp = p.maxHp;
    p.weapons = this.c.soldierWeapons.filter((id) => this.w.defs.weapons[id]).map((id) => new WeaponState(id, this.w.defs.weapons[id]!));
    p.slot = 0;
    p.currency = 0;
    p.reloadEnd = 0;
    p.switchEnd = 0;
    p.nextFireTime = 0;
    p.respawnAt = 0;
  }

  /** Infected: no weapons, more health, faster, a claw attack on FIRE. */
  makeZombie(p: SimPlayer, atEntry: boolean): void {
    p.team = Team.ZOMBIE;
    p.state = PlayerState.ALIVE;
    this.w.playerSys.clearPerks(p);
    p.maxHp = this.c.zombieHealth;
    p.hp = p.maxHp;
    p.weapons = [];
    p.slot = 0;
    p.currency = 0;
    p.reloadEnd = 0;
    p.switchEnd = 0;
    p.nextFireTime = 0;
    p.respawnAt = 0;
    if (atEntry) this.placeAtEntry(p);
  }

  /** A zombie entry away from the soldiers (the farthest of a few random picks). */
  private placeAtEntry(p: SimPlayer): void {
    const w = this.w;
    const entries = w.rng.shuffle([...w.map.zombieEntries]).slice(0, 4);
    let best = entries[0] ?? null;
    let bestD = -1;
    for (const e of entries) {
      let d = Infinity;
      for (const o of w.players.values()) if (o !== p && o.team === Team.SOLDIER && o.isAlive()) d = Math.min(d, dist(e.pos, o.pos));
      if (d > bestD) { bestD = d; best = e; }
    }
    if (!best) return;
    p.pos = { x: best.pos.x, y: best.pos.y };
    p.prevPos = { ...p.pos };
    p.yaw = yawTo(best.pos, best.inside);
  }

  /** A soldier's health reached zero at the hands of `by`: they turn infected where they stand. */
  infect(p: SimPlayer, by: SimPlayer | null): void {
    const w = this.w;
    if (by) by.kills += 1;
    p.downs += 1;
    this.makeZombie(p, false);
    w.emit({ type: "infected", pid: p.id, by: by?.id ?? 0 });
  }

  /** An infected player's health reached zero: down for zombieRespawnSec, then back at an entry. */
  killZombie(z: SimPlayer, by: SimPlayer | null, head: boolean): void {
    const w = this.w;
    if (by) {
      by.kills += 1;
      if (head) by.headshots += 1;
    }
    z.state = PlayerState.DEAD;
    z.respawnAt = w.time + this.c.zombieRespawnSec;
    z.deaths += 1;
    w.emit({ type: "player_killed", pid: z.id, by: by?.id ?? 0, head });
  }

  private respawnZombie(p: SimPlayer): void {
    this.makeZombie(p, true);
    this.w.emit({ type: "player_respawned", pid: p.id });
  }

  /** A hit on an infected player by a soldier's weapon. */
  hitZombie(z: SimPlayer, dmg: number, head: boolean, by: SimPlayer, point: V3): void {
    const w = this.w;
    w.emit({ type: "player_hit", pid: by.id, target: z.id, damage: dmg, head, point });
    w.damagePlayer(z, dmg, by.id);
  }

  /** The infected player's claw: FIRE hits the nearest soldier inside the cone. */
  melee(p: SimPlayer, inp: PlayerIntent, pressed: boolean): void {
    const w = this.w;
    const held = (inp.buttons & Btn.FIRE_HELD) !== 0 || pressed;
    if (!held || w.time < p.nextFireTime) return;
    p.nextFireTime = w.time + this.c.zombieAttackCooldownSec;
    const reach = this.c.zombieAttackRange + w.constants.player.radius;
    const half = (this.c.zombieAttackConeDeg / 2) * DEG;
    let target: SimPlayer | null = null;
    let bestD = reach;
    for (const o of w.players.values()) {
      if (o === p || o.team !== Team.SOLDIER || !o.isAlive()) continue;
      const d = dist(p.pos, o.pos);
      if (d > bestD) continue;
      if (Math.abs(wrapAngle(yawTo(p.pos, o.pos) - p.yaw)) > half) continue;
      if (!w.map.segmentClear(p.pos, o.pos, 0.05)) continue;
      target = o;
      bestD = d;
    }
    w.emit({ type: "zombie_attack", zid: p.id, pid: target?.id ?? 0, player: true });
    if (target) w.damagePlayer(target, this.c.zombieAttackDamage, p.id);
  }
}
