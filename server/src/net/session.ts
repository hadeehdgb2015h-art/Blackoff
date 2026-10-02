/**
 * One WebSocket connection. Flow: hello (version + identity) → welcome →
 * quickPlay → zoneJoined, then input/buy/ping/leave. Every field is validated;
 * malformed frames get `error.badMessage` (5 strikes and the socket closes),
 * floods are rate-limited, and only intents ever reach the simulation.
 */
import crypto from "node:crypto";
import type { WebSocket } from "ws";
import type { Env } from "../config/env.js";
import type { SharedData } from "../shared/loadShared.js";
import { BTN_MASK, Btn, type PlayerIntent } from "../sim/entities.js";
import { clamp, limitLength } from "../sim/math.js";
import { log } from "../log.js";
import type { Zone, ZoneClient } from "../zone/zone.js";
import { ZoneState } from "../sim/simWorld.js";
import { CodecError, type Codec, type Msg } from "./codec.js";
import { cleanName, validateInitData } from "./telegramAuth.js";
import { emptyProfile, type MatchResult, type MatchSummary, type Profile, type ProfileStore } from "../db/profileStore.js";
import type { ZoneManager, ZoneSink } from "../zone/zoneManager.js";

export interface Account { id: string; name: string; playerId: number; profile: Profile }

interface ResumeEntry { account: Account; zoneId: number; entityId: number; expiresAt: number }

/** Server-wide session state: resume tokens, one live session per account, and
 *  the profile store (match results are written asynchronously). */
export class SessionHub implements ZoneSink {
  readonly resume = new Map<string, ResumeEntry>();
  readonly byAccount = new Map<string, Session>();
  private readonly playerIds = new Map<string, number>();
  private nextPlayerId = 1;

  private readonly pending = new Set<Promise<unknown>>();

  constructor(readonly env: Env, readonly shared: SharedData, readonly codec: Codec, readonly zones: ZoneManager, readonly store: ProfileStore) {
    zones.sink = this;
  }

  onResult(r: MatchResult): void {
    this.track(this.store.record(r).then(
      (profile) => this.byAccount.get(r.accountId)?.onProfile(profile),
      (err: Error) => log.warn("profile write failed", { account: r.accountId, error: err.message }),
    ));
  }

  onMatch(m: MatchSummary): void {
    this.track(this.store.recordMatch(m).catch((err: Error) => log.warn("match write failed", { error: err.message })));
  }

  /** Waits for every queued database write (shutdown, tests). */
  async flush(): Promise<void> {
    while (this.pending.size) await Promise.allSettled([...this.pending]);
  }

  private track(p: Promise<unknown>): void {
    this.pending.add(p);
    void p.finally(() => this.pending.delete(p));
  }

  playerIdFor(accountId: string): number {
    let id = this.playerIds.get(accountId);
    if (id === undefined) {
      id = this.nextPlayerId++;
      this.playerIds.set(accountId, id);
    }
    return id;
  }

  sweep(now: number): void {
    for (const [t, e] of this.resume) if (e.expiresAt < now) this.resume.delete(t);
  }
}

const HELLO_TIMEOUT_MS = 10_000;
const MAX_STRIKES = 5;
const ERR: Record<string, number> = {};

class Bucket {
  private tokens: number;
  private last = Date.now();
  constructor(private readonly rate: number, private readonly burst: number) {
    this.tokens = burst;
  }
  take(): boolean {
    const now = Date.now();
    this.tokens = Math.min(this.burst, this.tokens + ((now - this.last) / 1000) * this.rate);
    this.last = now;
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}

export class Session implements ZoneClient {
  account: Account | null = null;
  displayName = "Player";
  zone: Zone | null = null;
  entityId = 0;
  resumeToken = "";
  private strikes = 0;
  private helloPending = false;
  private dropped = 0;
  private readonly inputs: Bucket;
  private readonly other = new Bucket(10, 20);
  private helloTimer: NodeJS.Timeout | null;

  constructor(private readonly ws: WebSocket, private readonly hub: SessionHub, readonly ip: string) {
    if (Object.keys(ERR).length === 0) Object.assign(ERR, hub.shared.protocol.enums.errorCode);
    const rate = hub.shared.constants.net.maxInputsPerSecond;
    this.inputs = new Bucket(rate, rate);
    this.helloTimer = setTimeout(() => this.fail("authFailed", "hello timeout"), HELLO_TIMEOUT_MS);
    ws.on("message", (data, isBinary) => this.onFrame(data as Buffer, isBinary));
    ws.on("close", () => this.onClose());
  }

  sendBytes(bytes: Uint8Array): void {
    // Slow clients are skipped instead of buffering without limit.
    if (this.ws.readyState === this.ws.OPEN && this.ws.bufferedAmount < 1 << 20) this.ws.send(bytes);
  }

  send(name: string, msg: Msg): void {
    this.sendBytes(this.hub.codec.encode("S2C", name, msg));
  }

  onZoneClosed(zone: Zone): void {
    if (this.zone !== zone) return;
    this.zone = null;
    this.entityId = 0;
  }

  private onFrame(data: Buffer, isBinary: boolean): void {
    if (!isBinary) return this.strike("text frames are not accepted");
    let decoded: { name: string; msg: Msg };
    try {
      decoded = this.hub.codec.decode("C2S", new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
    } catch (err) {
      return this.strike(err instanceof CodecError ? err.message : "decode error");
    }
    const { name, msg } = decoded;
    if (name === "input" ? !this.inputs.take() : !this.other.take()) {
      this.dropped += 1;
      if (this.dropped === 1 || this.dropped % 200 === 0) log.warn("rate limited", { ip: this.ip, account: this.account?.id, message: name, dropped: this.dropped });
      if (this.dropped > 2000) this.fail("rateLimited", "too many messages");
      return;
    }
    if (!this.account && name !== "hello") return this.strike("hello required first");
    switch (name) {
      case "hello": return void this.onHello(msg);
      case "quickPlay": return this.onQuickPlay();
      case "input": return this.onInput(msg);
      case "buy": return this.onBuy(msg);
      case "ping": return this.send("pong", { clientTime: msg.clientTime as number, serverTick: (this.zone?.world.tick ?? 0) >>> 0 });
      case "leave": return this.leaveZone();
      default: return this.strike("unexpected message " + name);
    }
  }

  private async onHello(msg: Msg): Promise<void> {
    if (this.account || this.helloPending) return this.strike("duplicate hello");
    const { env, shared } = this.hub;
    if (msg.protocolVersion !== shared.protocol.protocolVersion) return this.fail("badVersion", `server speaks protocol ${shared.protocol.protocolVersion}`);
    if (this.helloTimer) clearTimeout(this.helloTimer);
    this.helloTimer = null;
    // Resume a slot kept during the reconnect grace period.
    const token = String(msg.resumeToken ?? "");
    const entry = token ? this.hub.resume.get(token) : undefined;
    if (entry && entry.expiresAt >= Date.now()) {
      this.hub.resume.delete(token);
      this.adopt(entry.account, token, { zoneId: entry.zoneId, entityId: entry.entityId });
      if (this.zone) log.info("session resumed", { account: entry.account.id, zone: this.zone.id });
      return;
    }
    const initData = String(msg.initData ?? "");
    let id: string;
    let name: string;
    if (env.TELEGRAM_BOT_TOKEN && initData && !initData.startsWith("dev:")) {
      const res = validateInitData(initData, env.TELEGRAM_BOT_TOKEN, env.TELEGRAM_INIT_DATA_MAX_AGE_SEC);
      if (!res.ok) return this.fail("authFailed", "telegram identity rejected");
      id = "tg:" + res.user.id;
      name = res.user.name;
    } else if (env.ALLOW_DEV_AUTH) {
      // Browser testing outside Telegram: "dev:<name>" or anonymous guest.
      const devName = initData.startsWith("dev:") ? initData.slice(4) : "";
      id = "dev:" + (devName ? cleanName(devName) : crypto.randomBytes(6).toString("hex"));
      name = cleanName(devName || "Guest-" + id.slice(-4));
    } else {
      return this.fail("authFailed", "telegram identity required");
    }
    this.helloPending = true;
    let profile = emptyProfile();
    try {
      profile = await this.hub.store.load(id, name);
    } catch (err) {
      log.warn("profile load failed", { account: id, error: (err as Error).message });
    }
    this.helloPending = false;
    if (this.ws.readyState !== this.ws.OPEN) return; // left while we waited
    this.adopt({ id, name, playerId: this.hub.playerIdFor(id), profile }, crypto.randomBytes(18).toString("base64url"));
  }

  onProfile(profile: Profile): void {
    if (!this.account) return;
    this.account.profile = profile;
    this.send("profile", profileMsg(profile));
  }

  /** Becomes the single live session of this account. An older connection of the
   *  same account is closed and its zone slot moves to this one. */
  private adopt(account: Account, token: string, slot?: { zoneId: number; entityId: number }): void {
    const old = this.hub.byAccount.get(account.id);
    if (old && old !== this) slot = old.replaced() ?? slot;
    this.hub.byAccount.set(account.id, this);
    this.account = account;
    this.displayName = account.name;
    this.resumeToken = token;
    this.send("welcome", {
      playerId: account.playerId, displayName: account.name, resumeToken: token,
      tickRate: this.hub.shared.constants.sim.tickRate, ...profileMsg(account.profile),
    });
    const zone = slot ? this.hub.zones.zones.get(slot.zoneId) : undefined;
    if (zone && slot && zone.attach(slot.entityId, this)) {
      this.zone = zone;
      this.entityId = slot.entityId;
    }
  }

  /** Another connection took over this account: give up the zone slot quietly. */
  private replaced(): { zoneId: number; entityId: number } | undefined {
    const slot = this.zone ? { zoneId: this.zone.id, entityId: this.entityId } : undefined;
    this.zone = null;
    this.account = null;
    this.ws.close(4000, "replaced by a newer connection");
    return slot;
  }

  private onQuickPlay(): void {
    if (this.zone && this.zone.state === ZoneState.GAME_OVER) this.leaveZone(); // play again
    if (this.zone) return; // already playing; quickPlay is idempotent
    const { zone, member } = this.hub.zones.quickPlay(this, this.account!.id);
    this.zone = zone;
    this.entityId = member.entityId;
    log.info("joined zone", { account: this.account!.id, zone: zone.id, players: zone.size });
  }

  private onInput(msg: Msg): void {
    if (!this.zone) return;
    const mx = (msg.moveX as number) / 127;
    const my = (msg.moveY as number) / 127;
    const intent: PlayerIntent = {
      seq: msg.seq as number,
      move: limitLength({ x: clamp(mx, -1, 1), y: clamp(my, -1, 1) }, 1),
      yaw: msg.yaw as number,
      pitch: clamp(msg.pitch as number, -1.4, 1.4),
      buttons: (msg.buttons as number) & BTN_MASK,
    };
    this.zone.pushInput(this.entityId, intent);
  }

  /** Purchases go through the same interact rules as the USE button: the item
   *  must be what the player can interact with right now. */
  private onBuy(msg: Msg): void {
    if (!this.zone) return;
    const opt = this.zone.world.interactOption(this.entityId);
    if (!opt || (opt.item !== msg.itemId && opt.id !== msg.itemId)) return;
    const m = this.zone.members.get(this.entityId);
    if (m) m.latched |= Btn.INTERACT; // on the next tick
  }

  private leaveZone(): void {
    if (!this.zone) return;
    this.zone.remove(this.entityId, performance.now());
    this.zone = null;
    this.entityId = 0;
  }

  private onClose(): void {
    if (this.helloTimer) clearTimeout(this.helloTimer);
    if (this.account && this.hub.byAccount.get(this.account.id) === this) this.hub.byAccount.delete(this.account.id);
    if (this.zone && this.account) {
      this.zone.detach(this.entityId, performance.now());
      this.hub.resume.set(this.resumeToken, {
        account: this.account, zoneId: this.zone.id, entityId: this.entityId,
        expiresAt: Date.now() + this.hub.shared.constants.net.reconnectGraceSec * 1000,
      });
    }
    this.zone = null;
  }

  private strike(reason: string): void {
    this.strikes += 1;
    log.debug("bad message", { ip: this.ip, reason, strikes: this.strikes });
    if (this.strikes >= MAX_STRIKES) return this.fail("badMessage", "too many bad messages");
    this.send("error", { code: ERR.badMessage!, message: reason.slice(0, 120) });
  }

  private fail(code: string, message: string): void {
    this.send("error", { code: ERR[code]!, message });
    this.ws.close(4001, code);
  }
}

const profileMsg = (p: Profile) => ({
  games: Math.min(p.games, 0xffffffff), kills: Math.min(p.kills, 0xffffffff), bestWave: Math.min(p.bestWave, 0xffff),
});
