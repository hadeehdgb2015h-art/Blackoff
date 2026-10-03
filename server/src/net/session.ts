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
import { GameMode, ZoneState } from "../sim/simWorld.js";
import { CodecError, type Codec, type Msg } from "./codec.js";
import { cleanName, validateInitData } from "./telegramAuth.js";
import { emptyProfile, weekLabel, weekStart, type MatchSummary, type Profile, type ProfileStore, type WeeklyStanding } from "../db/profileStore.js";
import type { ZoneManager, ZoneSink } from "../zone/zoneManager.js";
import type { ZoneResult } from "../zone/zone.js";
import { flagsFor } from "../anticheat.js";
import { RuntimeSettings } from "../admin/runtime.js";
import { applyDev } from "../admin/devPowers.js";
import { levelFor, rankFor, xpFor, type ProgressionDefs } from "../progression.js";
import { DailyService, type DailyUpdate } from "../daily/dailyService.js";
import { CardService, cardsBaseUrl, cardsDir } from "../card/cardService.js";
import type { CardLang } from "../card/cardRender.js";
import type { TelegramBot } from "../bot/telegramBot.js";
import { addDays, computeAnalytics, utcDay, type ActivityPatch, type Analytics } from "../stats/analytics.js";
import { REPORT_CATEGORIES, ReportLimiter, ShotBuffer, cleanClientInfo, cleanDetails, type ClientInfo } from "../report/report.js";

export interface Account { id: string; name: string; playerId: number; profile: Profile; weekly: WeeklyStanding }

interface ResumeEntry { account: Account; zoneId: number; entityId: number; expiresAt: number }

/** Server-wide session state: resume tokens, one live session per account, and
 *  the profile store (match results are written asynchronously). */
export class SessionHub implements ZoneSink {
  readonly resume = new Map<string, ResumeEntry>();
  readonly byAccount = new Map<string, Session>();
  private readonly playerIds = new Map<string, number>();
  private nextPlayerId = 1;

  private readonly pending = new Set<Promise<unknown>>();
  /** Invite code -> account, for accounts seen since the server started (a
   *  friend can only join someone who is playing, so memory is enough). */
  readonly invites = new Map<string, string>();
  /** The owner's live switches (bans, maintenance, TON), from the bot's admin panel. */
  readonly settings: RuntimeSettings;
  /** Telegram ids of the owners ("tg:<id>" accounts get dev powers). */
  readonly owners: Set<string>;
  /** Daily reward and missions (phase 23). */
  readonly daily: DailyService;
  /** Result cards (phase 25) and the bot that prepares them as messages to share. */
  readonly cards: CardService;
  bot: TelegramBot | null = null;
  /** Each account's last recorded game (its result card once it left the zone). */
  readonly lastResult = new Map<string, ZoneResult>();
  private readonly inviteKey: Buffer;
  botUsername: string;
  /** problem reports: one a minute, ten a day per account (phase 29) */
  readonly reportLimit = new ReportLimiter();

  constructor(readonly env: Env, readonly shared: SharedData, readonly codec: Codec, readonly zones: ZoneManager, readonly store: ProfileStore) {
    zones.sink = this;
    // stable across restarts when a bot token exists, so shared links keep working
    this.inviteKey = crypto.createHash("sha256").update("blackoff-invite:" + (env.TELEGRAM_BOT_TOKEN || crypto.randomBytes(16).toString("hex"))).digest();
    this.botUsername = env.TELEGRAM_BOT_USERNAME;
    this.settings = new RuntimeSettings(env, store);
    this.daily = new DailyService(store, shared.constants.daily, () => this.settings.tonPerKill());
    this.cards = new CardService(cardsDir(env), cardsBaseUrl(env));
    this.owners = new Set(env.ADMIN_TELEGRAM_IDS.split(",").map((s) => s.trim()).filter(Boolean).map((id) => "tg:" + id));
  }

  isOwner(accountId: string): boolean {
    return this.owners.has(accountId);
  }

  /** The account's invite code: 10 characters, derived (HMAC) from the account id. */
  inviteCodeFor(accountId: string): string {
    const code = crypto.createHmac("sha256", this.inviteKey).update(accountId).digest("base64url").replace(/[-_]/g, "").slice(0, 10);
    this.invites.set(code, accountId);
    return code;
  }

  /** Asks Telegram for the bot's @username (invite links) unless it is configured. */
  async discoverBot(): Promise<void> {
    if (this.botUsername || !this.env.TELEGRAM_BOT_TOKEN) return;
    try {
      const res = await fetch(`https://api.telegram.org/bot${this.env.TELEGRAM_BOT_TOKEN}/getMe`, { signal: AbortSignal.timeout(8000) });
      const body = (await res.json()) as { ok?: boolean; result?: { username?: string } };
      if (body.ok && body.result?.username && /^[A-Za-z0-9_]{1,64}$/.test(body.result.username)) {
        this.botUsername = body.result.username;
        log.info("bot username", { bot: this.botUsername });
      }
    } catch (err) {
      log.warn("getMe failed; invite links are off until TELEGRAM_BOT_USERNAME is set", { error: (err as Error).message });
    }
  }

  /** A member left a zone: TON points for the kills, anti-cheat flags from the
   *  play statistics, then the profile and weekly standing are written, then
   *  the game counts towards the daily missions (which may pay more TON). */
  onResult(z: ZoneResult): void {
    this.lastResult.delete(z.accountId);
    this.lastResult.set(z.accountId, z);
    if (this.lastResult.size > 5000) this.lastResult.delete(this.lastResult.keys().next().value!);
    const flags = flagsFor({ shots: z.shots, hits: z.hits, headshots: z.headshots, kills: z.kills, seconds: z.seconds }, this.shared.constants.anticheat);
    if (flags.length) {
      log.warn("anticheat flags", { account: z.accountId, name: z.name, flags, shots: z.shots, hits: z.hits, headshots: z.headshots, kills: z.kills, seconds: Math.round(z.seconds) });
    }
    // TON points come from AI zombies only: infection kills are players, never farmed for prizes
    const r = {
      ...z, tonMicro: z.mode === GameMode.INFECTION ? 0 : z.kills * this.settings.tonPerKill(), flags,
      xp: xpFor(z, this.shared.constants.progression),
    };
    this.activity(z.accountId, { games: 1, seconds: z.seconds, wave: z.wave });
    this.track(this.store.record(r).then(
      async (profile) => {
        let daily: DailyUpdate | null = null;
        try {
          daily = await this.daily.onGame(r.accountId, {
            kills: z.kills, headshots: z.headshots, wave: z.wave, bossKills: z.bossKills, seconds: z.seconds, zombies: z.mode === GameMode.CLASSIC,
          });
        } catch (err) {
          log.warn("daily missions failed", { account: r.accountId, error: (err as Error).message });
        }
        const session = this.byAccount.get(r.accountId);
        if (!session) return;
        session.onProfile(daily?.profile ?? profile, await this.store.weekly(r.accountId));
        if (daily) session.send("daily", daily.msg);
      },
      (err: Error) => log.warn("profile write failed", { account: r.accountId, error: err.message }),
    ));
  }

  /** Adds to today's activity of an account (the owner's statistics, phase 29). */
  activity(accountId: string, patch: ActivityPatch): void {
    this.track(this.store.touchActivity(accountId, patch).catch((err: Error) => log.warn("activity write failed", { error: err.message })));
  }

  /** The owner's statistics over the last two weeks of activity. */
  async analytics(today = utcDay()): Promise<Analytics> {
    const from = addDays(today, -15);
    const [rows, first] = await Promise.all([this.store.activitySince(from), this.store.firstSeenSince(from)]);
    return computeAnalytics(rows, first, today);
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
/** S2C reported status (protocol enum reportStatus). */
const ReportStatus = { OK: 0, TOO_SOON: 1, ERROR: 2 } as const;
/** S2C card status (protocol enum cardStatus). */
const CardStatus = { OK: 0, NOTHING: 1, UNAVAILABLE: 2, BUSY: 3, ERROR: 4 } as const;
const CARD_COOLDOWN_MS = 8_000;
const escHtml = (s: string) => s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]!);
/** The caption and button of a shared result card, in the player's language. */
const CARD_CAPTION: Record<CardLang, { zombies: (name: string, wave: number, kills: number) => string; infection: (name: string, kills: number) => string; button: string }> = {
  en: {
    zombies: (n, w, k) => `🧟 <b>${n}</b> held out to <b>wave ${w}</b> in BLACK OFF with <b>${k}</b> kills.\nCan you beat that? Join my squad 👇`,
    infection: (n, k) => `🧟 <b>${n}</b> made <b>${k}</b> kills in BLACK OFF infection.\nCan you beat that? Join my squad 👇`,
    button: "🎮 Play with me",
  },
  ar: {
    zombies: (n, w, k) => `🧟 صمد <b>${n}</b> حتى <b>الموجة ${w}</b> في BLACK OFF وقتل <b>${k}</b> زومبي.\nهل تستطيع التفوّق عليه؟ انضم إلى فرقتي 👇`,
    infection: (n, k) => `🧟 حقق <b>${n}</b> عدد <b>${k}</b> قتلات في وضع العدوى في BLACK OFF.\nهل تستطيع التفوّق عليه؟ انضم إلى فرقتي 👇`,
    button: "🎮 العب معي",
  },
  ru: {
    zombies: (n, w, k) => `🧟 <b>${n}</b> продержался до <b>волны ${w}</b> в BLACK OFF, убийств: <b>${k}</b>.\nСможешь лучше? Вступай в мой отряд 👇`,
    infection: (n, k) => `🧟 <b>${n}</b>: убийств в режиме заражения BLACK OFF — <b>${k}</b>.\nСможешь лучше? Вступай в мой отряд 👇`,
    button: "🎮 Играть со мной",
  },
};
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
  /** level shown to teammates in the roster (phase 26) */
  get level(): number {
    return this.account ? levelFor(this.account.profile.xp, this.hub.shared.constants.progression) : 1;
  }
  zone: Zone | null = null;
  entityId = 0;
  resumeToken = "";
  private strikes = 0;
  private helloPending = false;
  private dropped = 0;
  private lastCardAt = 0;
  /** the device the game runs on (clientInfo, phase 29): shown to the owner, never trusted */
  client: ClientInfo | null = null;
  private readonly shot = new ShotBuffer();
  private readonly inputs: Bucket;
  private readonly other = new Bucket(10, 20);
  private readonly voice: Bucket;
  /** speaker on (default): receive other players' voice frames */
  voiceListen = true;
  voiceSent = 0;
  private helloTimer: NodeJS.Timeout | null;

  constructor(private readonly ws: WebSocket, private readonly hub: SessionHub, readonly ip: string) {
    if (Object.keys(ERR).length === 0) Object.assign(ERR, hub.shared.protocol.enums.errorCode);
    const rate = hub.shared.constants.net.maxInputsPerSecond;
    this.inputs = new Bucket(rate, rate);
    const vr = hub.shared.constants.voice.maxFramesPerSecond;
    this.voice = new Bucket(vr, vr * 2);
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
    if (name === "voice") {
      // voice floods are dropped quietly: a lossy stream, never a strike
      if (this.voice.take()) this.onVoice(msg);
      return;
    }
    if (name === "input" ? !this.inputs.take() : !this.other.take()) {
      this.dropped += 1;
      if (this.dropped === 1 || this.dropped % 200 === 0) log.warn("rate limited", { ip: this.ip, account: this.account?.id, message: name, dropped: this.dropped });
      if (this.dropped > 2000) this.fail("rateLimited", "too many messages");
      return;
    }
    if (!this.account && name !== "hello") return this.strike("hello required first");
    switch (name) {
      case "hello": return void this.onHello(msg);
      case "quickPlay": return this.onQuickPlay(msg);
      case "input": return this.onInput(msg);
      case "buy": return this.onBuy(msg);
      case "ping": return this.send("pong", { clientTime: msg.clientTime as number, serverTick: (this.zone?.world.tick ?? 0) >>> 0 });
      case "leave": return this.leaveZone();
      case "leaderboard": return void this.onLeaderboard();
      case "voiceListen": this.voiceListen = !!msg.on; return;
      case "dev": return this.onDev(msg);
      case "daily": return void this.onDaily(false);
      case "claimDaily": return void this.onDaily(true);
      case "card": return void this.onCard(msg);
      case "clientInfo": return this.onClientInfo(msg);
      case "perf": return this.onPerf(msg);
      case "reportShot": this.shot.add(msg.part as number, msg.total as number, msg.data as Uint8Array); return;
      case "report": return void this.onReport(msg);
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
    if (this.hub.settings.banned.has(id)) return this.fail("authFailed", "this account is banned");
    this.helloPending = true;
    let profile = emptyProfile();
    let weekly: WeeklyStanding = { rank: 0, kills: 0, tonMicro: 0 };
    try {
      profile = await this.hub.store.load(id, name);
      weekly = await this.hub.store.weekly(id);
    } catch (err) {
      log.warn("profile load failed", { account: id, error: (err as Error).message });
    }
    this.helloPending = false;
    if (this.ws.readyState !== this.ws.OPEN) return; // left while we waited
    this.adopt({ id, name, playerId: this.hub.playerIdFor(id), profile, weekly }, crypto.randomBytes(18).toString("base64url"));
    this.hub.activity(id, { opens: 1 });
  }

  /** Once per connection: the device, for the owner's statistics and reports. */
  private onClientInfo(msg: Msg): void {
    if (this.client) return;
    this.client = cleanClientInfo(msg);
    this.hub.activity(this.account!.id, { platform: this.client.platform, lang: this.client.lang });
  }

  /** The average FPS of a game that just ended (statistics only). */
  private onPerf(msg: Msg): void {
    const fps = msg.fps as number;
    if (fps < 1 || fps > 240 || (msg.seconds as number) < 20) return;
    this.hub.activity(this.account!.id, { fps });
  }

  /** A problem report: stored with what the server knows, then sent to the owners by the bot. */
  private async onReport(msg: Msg): Promise<void> {
    const account = this.account!;
    const reply = (status: number, id = 0) => {
      if (this.ws.readyState === this.ws.OPEN) this.send("reported", { status, id });
    };
    const category = msg.category as number;
    if (category >= REPORT_CATEGORIES.length) return this.strike("bad report category");
    const shot = this.shot.take();
    if (!this.hub.reportLimit.take(account.id)) return reply(ReportStatus.TOO_SOON);
    const z = this.zone;
    const info = {
      where: String(msg.where ?? "").replace(/[^\w .:-]/g, "").slice(0, 24),
      fps: msg.fps as number,
      shot: !!shot,
      level: levelFor(account.profile.xp, this.hub.shared.constants.progression),
      games: account.profile.games,
      client: this.client ?? {},
      details: cleanDetails(String(msg.details ?? "")),
      zone: z ? { id: z.id, mode: GameMode[z.mode], wave: z.world.director.wave, players: z.size, state: ZoneState[z.state] } : null,
    };
    try {
      const id = await this.hub.store.addReport({ accountId: account.id, name: account.name, category, info });
      log.info("problem report", { id, account: account.id, category: REPORT_CATEGORIES[category], shot: !!shot });
      reply(ReportStatus.OK, id);
      const row = await this.hub.store.report(id);
      if (row && this.hub.bot) await this.hub.bot.onReport(row, shot);
    } catch (err) {
      log.warn("problem report failed", { account: account.id, error: (err as Error).message });
      reply(ReportStatus.ERROR);
    }
  }

  onProfile(profile: Profile, weekly: WeeklyStanding): void {
    if (!this.account) return;
    this.account.profile = profile;
    this.account.weekly = weekly;
    this.send("profile", profileMsg(profile, weekly, this.hub.settings.tonPerKill(), this.hub.shared.constants.progression));
  }

  /** This week's top hunters plus the player's own standing. */
  private async onLeaderboard(): Promise<void> {
    if (!this.account) return;
    const { store } = this.hub;
    try {
      const week = weekStart();
      const rows = await store.leaderboard(10, week);
      const me = await store.weekly(this.account.id, week);
      if (this.ws.readyState !== this.ws.OPEN) return;
      this.send("leaderboard", {
        week: weekLabel(week), prize: this.hub.settings.prizeText(),
        entries: rows.map((r, i) => ({ rank: i + 1, name: r.name.slice(0, 32), kills: Math.min(r.kills, 0xffffffff), tonMicro: Math.min(r.tonMicro, 0xffffffff) })),
        myRank: Math.min(me.rank, 0xffff), myKills: Math.min(me.kills, 0xffffffff), myTonMicro: Math.min(me.tonMicro, 0xffffffff),
      });
    } catch (err) {
      log.warn("leaderboard failed", { account: this.account.id, error: (err as Error).message });
    }
  }

  /** The daily reward and missions; with `claim`, takes today's streak reward first. */
  private async onDaily(claim: boolean): Promise<void> {
    const account = this.account;
    if (!account) return;
    try {
      const u = claim ? await this.hub.daily.claim(account.id) : await this.hub.daily.view(account.id);
      if (this.account !== account || this.ws.readyState !== this.ws.OPEN) return;
      if (u.profile) this.onProfile(u.profile, account.weekly);
      this.send("daily", u.msg);
    } catch (err) {
      log.warn("daily failed", { account: account.id, error: (err as Error).message });
    }
  }

  /** The result card of the game being played (or the last one recorded): a JPEG
   *  drawn by the server from its own numbers, plus a prepared Telegram message
   *  with it and a Play button for the player's invite link (phase 25). */
  private async onCard(msg: Msg): Promise<void> {
    const account = this.account;
    if (!account) return;
    const reply = (status: number, url = "", prepared = "", preview = "") => {
      if (this.account === account && this.ws.readyState === this.ws.OPEN) this.send("card", { status, url, prepared, preview });
    };
    const { cards } = this.hub;
    if (!cards.enabled) return reply(CardStatus.UNAVAILABLE);
    const now = Date.now();
    if (now - this.lastCardAt < CARD_COOLDOWN_MS) return reply(CardStatus.BUSY);
    const r = (this.zone ? this.zone.resultFor(this.entityId) : null) ?? this.hub.lastResult.get(account.id);
    if (!r || (r.wave === 0 && r.kills === 0)) return reply(CardStatus.NOTHING);
    this.lastCardAt = now;
    const lang: CardLang = msg.lang === "ar" || msg.lang === "ru" ? msg.lang : "en";
    try {
      const card = await cards.make({
        lang, name: account.name, mode: r.mode, wave: r.wave, kills: r.kills, headshots: r.headshots, seconds: r.seconds,
        bestWave: Math.max(account.profile.bestWave, r.wave), bot: this.hub.botUsername,
        level: levelFor(account.profile.xp, this.hub.shared.constants.progression),
        rank: rankFor(levelFor(account.profile.xp, this.hub.shared.constants.progression), this.hub.shared.constants.progression).id,
      });
      let prepared = "";
      const tg = /^tg:(\d+)$/.exec(account.id);
      if (tg && this.hub.bot && this.hub.botUsername) {
        const link = `https://t.me/${this.hub.botUsername}?startapp=sq${this.hub.inviteCodeFor(account.id)}`;
        const c = CARD_CAPTION[lang];
        const caption = r.mode === GameMode.INFECTION
          ? c.infection(escHtml(account.name), r.kills)
          : c.zombies(escHtml(account.name), r.wave, r.kills);
        prepared = await this.hub.bot.prepareCard(Number(tg[1]), card.url, caption, c.button, link);
      }
      log.info("result card", { account: account.id, wave: r.wave, kills: r.kills, prepared: prepared !== "" });
      reply(CardStatus.OK, card.url, prepared, card.preview);
    } catch (err) {
      log.warn("result card failed", { account: account.id, error: (err as Error).message });
      reply(CardStatus.ERROR);
    }
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
      tickRate: this.hub.shared.constants.sim.tickRate, ...profileMsg(account.profile, account.weekly, this.hub.settings.tonPerKill(), this.hub.shared.constants.progression),
      voice: this.hub.env.VOICE_CHAT,
      inviteCode: this.hub.inviteCodeFor(account.id), botUsername: this.hub.botUsername,
      dev: this.hub.isOwner(account.id),
    });
    void this.onDaily(false);
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

  private onQuickPlay(msg: Msg): void {
    const mode = msg.mode === GameMode.INFECTION ? GameMode.INFECTION : GameMode.CLASSIC;
    if (this.zone && (this.zone.state === ZoneState.GAME_OVER || this.zone.mode !== mode)) this.leaveZone(); // play again / other mode
    if (this.zone) return; // already playing; quickPlay is idempotent
    if (this.hub.settings.maintenance && !this.hub.isOwner(this.account!.id)) {
      return this.fail("serverShutdown", this.hub.settings.maintenanceText || "Maintenance: the game is back in a few minutes");
    }
    const placed = this.joinFriend(String(msg.friend ?? "")) ?? this.hub.zones.quickPlay(this, this.account!.id, mode,
      msg.friend ? { status: 2, name: "" } : undefined);
    this.zone = placed.zone;
    this.entityId = placed.member.entityId;
    log.info("joined zone", { account: this.account!.id, zone: placed.zone.id, mode: GameMode[placed.zone.mode], players: placed.zone.size, invite: !!msg.friend });
  }

  /** An invite code (from a friend's link): their zone, if they are playing
   *  and it has room. Never the player's own code. */
  private joinFriend(code: string): ReturnType<ZoneManager["quickPlay"]> | null {
    if (!/^[A-Za-z0-9]{10}$/.test(code)) return null;
    const friendId = this.hub.invites.get(code);
    if (!friendId || friendId === this.account!.id) return null;
    const friend = this.hub.byAccount.get(friendId);
    if (!friend?.zone || !friend.account) return null;
    return this.hub.zones.joinFriend(this, this.account!.id, friend.zone, friend.account.name);
  }

  /** The owner's in-game powers; anyone else sending one is struck. */
  private onDev(msg: Msg): void {
    if (!this.hub.isOwner(this.account!.id)) return this.strike("not allowed");
    const p = this.zone?.world.players.get(this.entityId);
    if (!this.zone || !p || this.zone.mode !== GameMode.CLASSIC) return;
    const what = applyDev(this.zone.world, p, msg.cmd as number, msg.arg as number);
    log.info("dev power", { account: this.account!.id, zone: this.zone.id, what });
  }

  /** A voice frame: relayed as-is to the other members of the zone. The
   *  server does not decode audio; size and rate are the only checks. */
  private onVoice(msg: Msg): void {
    if (!this.zone || !this.hub.env.VOICE_CHAT) return;
    const data = msg.data as Uint8Array;
    if (data.length === 0 || data.length > this.hub.shared.constants.voice.maxFrameBytes) return;
    this.voiceSent += 1;
    this.zone.relayVoice(this.entityId, msg.seq as number, data);
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

  /** Closes this connection with a reason the player sees (a ban from the owner's panel). */
  kick(reason: string): void {
    this.fail("authFailed", reason);
  }

  private fail(code: string, message: string): void {
    this.send("error", { code: ERR[code]!, message });
    this.ws.close(4001, code);
  }
}

const profileMsg = (p: Profile, w: WeeklyStanding, tonPerKill: number, prog: ProgressionDefs) => ({
  games: Math.min(p.games, 0xffffffff), kills: Math.min(p.kills, 0xffffffff), bestWave: Math.min(p.bestWave, 0xffff),
  tonMicro: Math.min(p.tonMicro, 0xffffffff), weekKills: Math.min(w.kills, 0xffffffff), weekRank: Math.min(w.rank, 0xffff),
  tonPerKill: Math.min(tonPerKill, 0xffffffff),
  xp: Math.min(p.xp, 0xffffffff), level: levelFor(p.xp, prog),
});
