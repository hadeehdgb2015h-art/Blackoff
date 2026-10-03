/**
 * Owns every zone in this process: quick-play matchmaking, the shared fixed-rate
 * tick scheduler (drift-corrected), and zone lifecycle (empty zones expire after
 * `zone.emptyZoneTtlSec`, finished games close after GAME_OVER_LINGER_MS).
 */
import type { Codec } from "../net/codec.js";
import type { SharedData } from "../shared/loadShared.js";
import { GameMode, ZoneState } from "../sim/simWorld.js";
import { log } from "../log.js";
import type { MatchSummary } from "../db/profileStore.js";
import { Zone, type FriendJoin, type Member, type ZoneClient, type ZoneResult } from "./zone.js";

export const GAME_OVER_LINGER_MS = 10_000;

export interface ZoneStats {
  zones: number;
  players: number;
  zombies: number;
  tickMsAvg: number;
  tickMsMax: number;
}

/** Receives finished player results and match records (the SessionHub). */
export interface ZoneSink {
  onResult(r: ZoneResult): void;
  onMatch(s: MatchSummary): void;
}

export class ZoneManager {
  sink: ZoneSink | null = null;
  readonly zones = new Map<number, Zone>();
  private nextZoneId = 1;
  private timer: NodeJS.Timeout | null = null;
  private startedAt = 0;
  private ticks = 0;
  private tickMsSum = 0;
  private tickMsMax = 0;
  private statWindow = 0;
  private readonly tickMs: number;

  constructor(private readonly shared: SharedData, private readonly codec: Codec, private readonly now: () => number = () => performance.now()) {
    this.tickMs = 1000 / shared.constants.sim.tickRate;
  }

  /** Players a zone of this mode holds. */
  maxPlayers(mode: GameMode): number {
    return mode === GameMode.INFECTION ? this.shared.constants.infection.maxPlayers : this.shared.constants.zone.maxPlayers;
  }

  /** Puts the client into a friend's zone (an invite link): any wave, the
   *  friend's mode, while it has room and is not over. Null when it cannot. */
  joinFriend(client: ZoneClient, accountId: string, zone: Zone, friendName: string): { zone: Zone; member: Member } | null {
    if (!this.zones.has(zone.id) || zone.state === ZoneState.GAME_OVER || zone.size >= this.maxPlayers(zone.mode)) return null;
    return { zone, member: zone.join(client, accountId, this.now(), { status: 1, name: friendName }) };
  }

  /** Puts the client into the fullest joinable zone of that mode, or a new one. */
  quickPlay(client: ZoneClient, accountId: string, mode: GameMode = GameMode.CLASSIC, friend?: FriendJoin): { zone: Zone; member: Member } {
    const zc = this.shared.constants.zone;
    const max = this.maxPlayers(mode);
    let best: Zone | null = null;
    for (const z of this.zones.values()) {
      if (z.mode !== mode || z.state === ZoneState.GAME_OVER || z.size >= max) continue;
      if (mode === GameMode.CLASSIC && zc.quickPlayJoinableUntilWave > 0 && z.world.director.wave > zc.quickPlayJoinableUntilWave) continue;
      if (!best || z.size > best.size) best = z;
    }
    if (!best) {
      const id = this.nextZoneId;
      this.nextZoneId = (this.nextZoneId % 0xffffffff) + 1;
      best = new Zone(id, this.shared, this.codec, this.shared.constants.maps.default, (Math.random() * 0xffffffff) >>> 0, this.now(), mode);
      best.onResult = (r) => this.sink?.onResult(r);
      this.zones.set(id, best);
      log.info("zone created", { zone: id, map: best.mapId, mode: GameMode[mode] });
    }
    return { zone: best, member: best.join(client, accountId, this.now(), friend) };
  }

  start(): void {
    if (this.timer) return;
    this.startedAt = this.now();
    this.ticks = 0;
    this.schedule();
  }

  stop(): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    const now = this.now();
    for (const z of this.zones.values()) this.closeZone(z, now, "shutdown");
    this.zones.clear();
  }

  /** One scheduler step for every zone (public for tests). */
  tickAll(): void {
    const now = this.now();
    const grace = this.shared.constants.net.reconnectGraceSec * 1000;
    const ttl = this.shared.constants.zone.emptyZoneTtlSec * 1000;
    for (const [id, z] of this.zones) {
      const t0 = performance.now();
      z.tick(now);
      const ms = performance.now() - t0;
      this.tickMsSum += ms;
      this.tickMsMax = Math.max(this.tickMsMax, ms);
      this.statWindow += 1;
      z.expireDisconnected(now, grace);
      const finished = z.gameOverAt !== null && now - z.gameOverAt >= GAME_OVER_LINGER_MS;
      const abandoned = z.size === 0 && z.emptySince !== null && now - z.emptySince >= ttl;
      if (finished || abandoned) {
        this.closeZone(z, now, finished ? "game over" : "empty");
        this.zones.delete(id);
      }
    }
  }

  private closeZone(z: Zone, now: number, reason: MatchSummary["reason"]): void {
    z.close(now);
    log.info("zone closed", { zone: z.id, reason, wave: z.world.director.wave });
    if (z.peakPlayers > 0) {
      this.sink?.onMatch({
        mapId: z.mapId, startedAt: z.startedAtDate, endedAt: new Date(),
        wave: z.mode === GameMode.INFECTION ? (z.world.infection?.round ?? 0) : z.world.director.wave, players: z.peakPlayers, reason,
      });
    }
  }

  stats(): ZoneStats {
    let players = 0;
    let zombies = 0;
    for (const z of this.zones.values()) {
      players += z.size;
      zombies += z.world.zombies.size;
    }
    const s = {
      zones: this.zones.size, players, zombies,
      tickMsAvg: this.statWindow ? +(this.tickMsSum / this.statWindow).toFixed(3) : 0, tickMsMax: +this.tickMsMax.toFixed(3),
    };
    return s;
  }

  /** Fixed-rate loop: each tick is scheduled against the ideal timeline, so
   *  timer jitter does not accumulate; after a long stall it skips ahead. */
  private schedule(): void {
    const target = this.startedAt + (this.ticks + 1) * this.tickMs;
    const delay = Math.max(0, target - this.now());
    this.timer = setTimeout(() => {
      this.ticks += 1;
      const behind = (this.now() - (this.startedAt + this.ticks * this.tickMs)) / this.tickMs;
      if (behind > 5) {
        log.warn("tick loop stalled, skipping ahead", { ticksBehind: Math.round(behind) });
        this.startedAt = this.now() - this.ticks * this.tickMs;
      }
      try {
        this.tickAll();
      } catch (err) {
        log.error("tick failed", { error: (err as Error).stack });
      }
      if (this.timer) this.schedule();
    }, delay);
  }
}
