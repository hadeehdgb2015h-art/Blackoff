/**
 * A zone: one SimWorld plus its members. Each tick it applies the merged inputs,
 * steps the world, turns sim events into protocol messages and, at the snapshot
 * rate, sends every member a snapshot (entities within `net.interestRadius`,
 * players always) and its own selfState. Messages are encoded once per broadcast.
 */
import type { Codec, Msg } from "../net/codec.js";
import type { SharedData } from "../shared/loadShared.js";
import { BTN_MASK, Btn, PlayerState, ZombieState, emptyIntent, type PlayerIntent, type SimEvent, type SimPlayer } from "../sim/entities.js";
import { SimWorld, ZoneState } from "../sim/simWorld.js";
import { Phase } from "../sim/waveDirector.js";
import type { MatchResult } from "../db/profileStore.js";

/** What a zone needs from a connection (implemented by Session). */
export interface ZoneClient {
  readonly displayName: string;
  sendBytes(bytes: Uint8Array): void;
  onZoneClosed(zone: Zone): void;
}

export interface Member {
  entityId: number;
  name: string;
  accountId: string;
  client: ZoneClient | null;
  disconnectedAt: number;
  latest: PlayerIntent;
  queue: PlayerIntent[];
  latched: number;
  joinedAt: number;
  lastSeq: number;
  appliedSeq: number;
  known: Set<number>;
}

/** Inputs buffered per player; one is applied per tick so client prediction
 *  (which also moves one step per input) replays exactly. Excess drops the oldest. */
const MAX_QUEUE = 4;
/** Buttons that are momentary: kept until the next tick applies them once. */
const LATCH = Btn.FIRE_PRESSED | Btn.RELOAD | Btn.INTERACT | Btn.SWITCH | Btn.REVIVE;
const EV: Record<string, number> = {};

export class Zone {
  readonly world: SimWorld;
  readonly members = new Map<number, Member>();
  readonly createdAt: number;
  readonly startedAtDate = new Date();
  emptySince: number | null;
  gameOverAt: number | null = null;
  /** Most members held at once (for the match record). */
  peakPlayers = 0;
  /** Called once per member when it leaves the zone or the zone closes. */
  onResult: ((r: MatchResult) => void) | null = null;
  private readonly weaponIdx = new Map<string, number>();
  private readonly zombieIdx = new Map<string, number>();
  private readonly boxIdx = new Map<string, number>();
  private readonly entryIdx = new Map<string, number>();
  private readonly snapEvery: number;

  constructor(readonly id: number, private readonly shared: SharedData, private readonly codec: Codec, readonly mapId: string, seed: number, now: number) {
    this.world = new SimWorld(shared, mapId, seed);
    this.createdAt = now;
    this.emptySince = now;
    Object.keys(shared.weapons).sort().forEach((k, i) => this.weaponIdx.set(k, i));
    Object.keys(shared.zombies).sort().forEach((k, i) => this.zombieIdx.set(k, i));
    this.world.map.interactables.filter((it) => it.kind === "box").forEach((it, i) => this.boxIdx.set(it.id, i));
    this.world.map.zombieEntries.forEach((e, i) => this.entryIdx.set(e.id, i));
    if (Object.keys(EV).length === 0) Object.assign(EV, shared.protocol.enums.eventKind);
    this.snapEvery = shared.constants.sim.tickRate / shared.constants.sim.snapshotRate;
  }

  get state(): ZoneState { return this.world.zoneState; }

  /** Members holding a slot (connected or within the reconnect grace). */
  get size(): number { return this.members.size; }

  join(client: ZoneClient, accountId: string, now = performance.now()): Member {
    const entityId = this.world.addPlayer(client.displayName);
    const m: Member = {
      entityId, name: client.displayName, accountId, client, disconnectedAt: 0,
      latest: { ...emptyIntent(), yaw: this.world.players.get(entityId)!.yaw }, queue: [], latched: 0, joinedAt: now, lastSeq: 0, appliedSeq: 0, known: new Set(),
    };
    this.members.set(entityId, m);
    this.peakPlayers = Math.max(this.peakPlayers, this.members.size);
    this.emptySince = null;
    this.welcomeMember(m);
    return m;
  }

  /** Reattaches a reconnecting client to its slot (resume token). */
  attach(entityId: number, client: ZoneClient): Member | null {
    const m = this.members.get(entityId);
    if (!m) return null;
    m.client?.onZoneClosed(this); // a newer connection replaces an older one
    m.client = client;
    m.disconnectedAt = 0;
    m.known.clear(); // next snapshot is full
    this.welcomeMember(m);
    return m;
  }

  /** Connection lost: the player stays (idle) for the reconnect grace period. */
  detach(entityId: number, now: number): void {
    const m = this.members.get(entityId);
    if (!m) return;
    m.client = null;
    m.disconnectedAt = now;
    m.latest = { ...m.latest, move: { x: 0, y: 0 }, buttons: 0 };
    m.queue = [];
    m.latched = 0;
  }

  remove(entityId: number, now: number): void {
    const m = this.members.get(entityId);
    if (!m) return;
    this.finish(m, now);
    this.members.delete(entityId);
    this.world.removePlayer(entityId);
    if (this.members.size === 0) this.emptySince = now;
    this.broadcastRoster();
  }

  pushInput(entityId: number, intent: PlayerIntent): void {
    const m = this.members.get(entityId);
    if (!m) return;
    // seq is a wrapping u16: ignore inputs older than the last one applied
    const ahead = (intent.seq - m.lastSeq + 65536) % 65536;
    if (m.lastSeq !== 0 && (ahead === 0 || ahead > 32768)) return;
    m.lastSeq = intent.seq;
    m.queue.push(intent);
    if (m.queue.length > MAX_QUEUE) {
      const dropped = m.queue.shift()!;
      m.latched |= dropped.buttons & LATCH; // never lose a tap
    }
  }

  tick(now: number): void {
    const w = this.world;
    for (const m of this.members.values()) {
      const next = m.queue.shift();
      if (next) {
        m.latest = next;
        m.appliedSeq = next.seq;
        m.latched |= next.buttons & LATCH;
      }
      // With no new input the last one repeats (keeps walking), minus one-shot presses.
      const buttons = ((m.latest.buttons & ~LATCH) | m.latched) & BTN_MASK;
      w.setInput(m.entityId, { ...m.latest, buttons });
      m.latched = 0;
    }
    w.step();
    for (const e of w.events) this.forwardEvent(e);
    if (w.zoneState === ZoneState.GAME_OVER && this.gameOverAt === null) this.gameOverAt = now;
    if (Math.floor(w.tick / this.snapEvery) !== Math.floor((w.tick - 1) / this.snapEvery)) this.sendSnapshots();
  }

  /** Disconnected members past the grace period lose their slot. */
  expireDisconnected(now: number, graceMs: number): void {
    for (const m of [...this.members.values()]) {
      if (!m.client && now - m.disconnectedAt >= graceMs) this.remove(m.entityId, now);
    }
  }

  close(now = performance.now()): void {
    for (const m of this.members.values()) {
      this.finish(m, now);
      m.client?.onZoneClosed(this);
    }
    this.members.clear();
  }

  private finish(m: Member, now: number): void {
    const p = this.world.players.get(m.entityId);
    this.onResult?.({
      accountId: m.accountId, name: m.name, kills: p?.kills ?? 0, headshots: p?.headshots ?? 0,
      // a dropped player's time ends when the connection did, not after the grace period
      wave: this.world.director.wave, seconds: Math.max(0, (m.client ? now : m.disconnectedAt) - m.joinedAt) / 1000,
    });
  }

  // ------------------------------------------------------------------ output

  private welcomeMember(m: Member): void {
    this.sendTo(m, "zoneJoined", { zoneId: this.id, mapId: this.mapId, entityId: m.entityId });
    this.broadcastRoster();
  }

  private broadcastRoster(): void {
    const players = [...this.members.values()].map((m) => ({ id: m.entityId, name: m.name }));
    this.broadcast("roster", { players });
  }

  private sendTo(m: Member, name: string, msg: Msg): void {
    m.client?.sendBytes(this.codec.encode("S2C", name, msg));
  }

  private broadcast(name: string, msg: Msg): void {
    const bytes = this.codec.encode("S2C", name, msg);
    for (const m of this.members.values()) m.client?.sendBytes(bytes);
  }

  private event(kind: string, a = 0, b = 0, value = 0, flags = 0): void {
    this.broadcast("event", { kind: EV[kind]!, a: u16(a), b: u16(b), value: i16(value), flags: flags & 0xff });
  }

  private forwardEvent(e: SimEvent): void {
    const n = (k: string) => Number(e[k] ?? 0);
    const wIdx = (k: string) => this.weaponIdx.get(String(e[k])) ?? 0;
    switch (e.type) {
      case "shot": {
        const to = e.to as { x: number; y: number; z: number };
        const hit = e.hit === "zombie" ? 2 : e.hit === "wall" ? 1 : 0;
        this.broadcast("shot", { playerId: n("pid"), weapon: wIdx("weapon"), toX: to.x, toY: to.y, toZ: to.z, hit });
        return;
      }
      case "zombie_hit": return this.event("hit", n("zid"), n("pid"), Math.round(n("damage")), e.head ? 1 : 0);
      case "zombie_killed": return this.event("kill", n("zid"), n("pid"), this.zombieIdx.get(String(e.ztype)) ?? 0, e.head ? 1 : 0);
      case "zombie_spawned": return this.event("zombieSpawned", n("zid"), this.zombieIdx.get(String(e.ztype)) ?? 0, this.entryIdx.get(String(e.entry)) ?? 0);
      case "zombie_attack": return this.event("zombieAttack", n("zid"), n("pid"));
      case "player_damaged": return this.event("playerDamaged", n("pid"), n("source"), Math.round(n("amount")));
      case "player_downed": return this.event("playerDowned", n("pid"));
      case "player_died": return this.event("playerDied", n("pid"));
      case "player_joined": return this.event("playerJoined", n("pid"));
      case "player_left": return this.event("playerLeft", n("pid"));
      case "wave_started": return this.event("waveStart", n("wave"), 0, n("count"));
      case "wave_cleared": return this.event("waveEnd", n("wave"));
      case "game_over":
        this.event("gameOver", n("wave"));
        return this.broadcast("scoreboard", this.scoreboard());
      case "player_revived": return this.event("playerRevived", n("pid"), n("by"));
      case "player_respawned": return this.event("playerRespawned", n("pid"));
      case "reload_started": return this.event("reloadStarted", n("pid"), 0, Math.round(n("duration") * 100));
      case "reload_done": return this.event("reloadDone", n("pid"));
      case "weapon_switched": return this.event("weaponSwitched", n("pid"), wIdx("weapon"));
      case "dry_fire": return this.event("dryFire", n("pid"));
      case "purchase": return this.event("purchase", n("pid"), wIdx("item"), n("cost"), e.action === "ammo" ? 1 : 0);
      case "purchase_denied": return this.event("purchaseDenied", n("pid"), 0, 0, e.reason === "full" ? 1 : 0);
      case "box_opened":
        return this.event("boxOpened", n("pid"), this.boxIdx.get(String(e.box)) ?? 0, Math.round((n("until") - this.world.time) * 10));
      case "box_offer": return this.event("boxOffer", n("pid"), this.boxIdx.get(String(e.box)) ?? 0, wIdx("weapon"));
      case "box_taken": return this.event("boxTaken", n("pid"), this.boxIdx.get(String(e.box)) ?? 0, wIdx("weapon"));
      case "box_expired": return this.event("boxExpired", 0, this.boxIdx.get(String(e.box)) ?? 0);
      default: return; // currency changes travel in selfState
    }
  }

  /** Final stats of everyone still in the zone (sent at game over). */
  scoreboard(): Msg {
    const players = [...this.world.players.values()].map((p) => ({
      id: p.id, name: p.name, kills: u16(p.kills), headshots: u16(p.headshots), downs: Math.min(255, p.downs), revives: Math.min(255, p.revives),
    }));
    return { wave: u16(this.world.director.wave), players: players.slice(0, 255) };
  }

  /** 0-255 progress of the revive this player is doing, or (when downed) receiving. */
  private reviveProgress(p: SimPlayer): number {
    const w = this.world;
    const doer = p.isAlive() ? (p.reviveTarget ? p : null) : w.reviverOf(p);
    if (!doer) return 0;
    return Math.max(0, Math.min(255, Math.round((doer.reviveTicks / w.playerSys.reviveTicksNeeded()) * 255)));
  }

  private sendSnapshots(): void {
    const w = this.world;
    const r2 = this.shared.constants.net.interestRadius ** 2;
    const players = [...w.players.values()].map((p) => ({
      id: p.id, kind: 0, sub: this.weaponIdx.get(p.weapon()?.id ?? "") ?? 0, x: p.pos.x, y: p.pos.y, floor: 0, yaw: p.yaw,
      hp: pct(p.hp, p.maxHp),
      flags: (p.moving ? 1 : 0) | (p.state === PlayerState.DOWNED ? 4 : 0) | (p.isReloading() ? 8 : 0)
        | (p.state === PlayerState.DOWNED && w.reviverOf(p) ? 16 : 0) | (p.state === PlayerState.DEAD ? 32 : 0),
    }));
    for (const m of this.members.values()) {
      if (!m.client) continue;
      const self = w.players.get(m.entityId);
      if (!self) continue;
      const entities: Msg[] = [...players];
      for (const z of w.zombies.values()) {
        if ((z.pos.x - self.pos.x) ** 2 + (z.pos.y - self.pos.y) ** 2 > r2) continue;
        entities.push({
          id: z.id, kind: 1, sub: this.zombieIdx.get(z.type) ?? 0, x: z.pos.x, y: z.pos.y, floor: 0, yaw: z.yaw,
          hp: pct(z.hp, z.maxHp), flags: (z.moving ? 1 : 0) | (z.state === ZombieState.WINDUP ? 2 : 0),
        });
      }
      const ids = new Set(entities.map((e) => e.id as number));
      const removed = [...m.known].filter((id) => !ids.has(id)).slice(0, 255);
      m.known = ids;
      const d = w.director;
      this.sendTo(m, "snapshot", {
        tick: w.tick >>> 0, ackSeq: m.appliedSeq, zoneState: w.zoneState, wave: u16(d.wave),
        remaining: u16(d.phase === Phase.WAVE ? d.remaining() : 0),
        timer: u16(d.phase === Phase.INTERMISSION ? Math.max(0, d.phaseEnd - w.time) * 10 : 0),
        entities: entities.slice(0, 255), removed,
      });
      this.sendTo(m, "selfState", {
        hp: Math.max(0, Math.min(255, Math.round(self.hp))), state: self.state, currency: Math.max(0, Math.min(0xffffffff, self.currency)),
        slot: self.slot,
        weapons: self.weapons.map((wp) => ({ weapon: this.weaponIdx.get(wp.id) ?? 0, mag: Math.min(255, wp.mag), reserve: u16(wp.reserve) })),
        flags: (self.isReloading() ? 1 : 0) | (w.time < self.switchEnd ? 2 : 0),
        revive: this.reviveProgress(self),
        bleedout: self.state === PlayerState.DOWNED ? Math.min(255, Math.ceil(w.bleedoutLeft(self))) : 0,
      });
    }
  }
}

const u16 = (v: number): number => Math.max(0, Math.min(0xffff, Math.round(v)));
const i16 = (v: number): number => Math.max(-0x8000, Math.min(0x7fff, Math.round(v)));
const pct = (hp: number, max: number): number => Math.max(0, Math.min(100, Math.round((hp / Math.max(1e-9, max)) * 100)));
