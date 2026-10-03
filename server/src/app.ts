import http from "node:http";
import { WebSocketServer } from "ws";
import type { Env } from "./config/env.js";
import type { SharedData } from "./shared/loadShared.js";
import { Codec } from "./net/codec.js";
import { Session, SessionHub } from "./net/session.js";
import { ZoneManager } from "./zone/zoneManager.js";
import { log } from "./log.js";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { TelegramBot } from "./bot/telegramBot.js";
import { MemoryProfileStore, weekLabel, weekStart, type ProfileStore } from "./db/profileStore.js";

export interface App {
  server: http.Server;
  wss: WebSocketServer;
  zones: ZoneManager;
  hub: SessionHub;
  bot: TelegramBot;
  close(): Promise<void>;
}

/**
 * HTTP health endpoint plus the game WebSocket endpoint. Each connection is a
 * Session; zones tick on one shared fixed-rate scheduler (ZoneManager).
 */
export function createApp(env: Env, shared: SharedData, store: ProfileStore = new MemoryProfileStore()): App {
  const startedAt = Date.now();
  const codec = new Codec(shared.protocol);
  const zones = new ZoneManager(shared, codec);
  const hub = new SessionHub(env, shared, codec, zones, store);
  void hub.settings.load(); // the owner's switches (bans, maintenance, TON) from the store
  const version = releaseVersion();

  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://local");
    if (url.pathname === "/healthz") {
      res.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
      res.end(JSON.stringify({
        ok: true,
        protocolVersion: shared.protocol.protocolVersion,
        uptimeSec: Math.round((Date.now() - startedAt) / 1000),
        connections: wss.clients.size,
        store: store.kind,
        ...zones.stats(),
      }));
      return;
    }
    if (url.pathname.startsWith("/admin/")) return void admin(url, res);
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found");
  });

  // Owner-only JSON (ADMIN_TOKEN in .env; ?token=... or X-Admin-Token header).
  // /admin/leaderboard[?week=YYYY-MM-DD] lists this week's hunters with their
  // account ids (to pay prizes); /admin/suspects lists anti-cheat flags.
  async function admin(url: URL, res: http.ServerResponse): Promise<void> {
    const want = env.ADMIN_TOKEN ?? "";
    const got = url.searchParams.get("token") ?? "";
    const ok = want.length > 0 && got.length === want.length && crypto.timingSafeEqual(Buffer.from(got), Buffer.from(want));
    if (!ok) {
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not found");
      return;
    }
    try {
      let body: unknown;
      if (url.pathname === "/admin/leaderboard") {
        const week = url.searchParams.get("week") ?? weekStart();
        body = { week, label: weekLabel(week), tonMicroPerKill: hub.settings.tonPerKill(), prize: hub.settings.prizeText(), entries: await store.leaderboard(100, week) };
      } else if (url.pathname === "/admin/suspects") {
        body = { suspects: await store.suspects(100) };
      } else {
        res.writeHead(404, { "content-type": "text/plain" });
        res.end("not found");
        return;
      }
      res.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
      res.end(JSON.stringify(body));
    } catch (err) {
      log.warn("admin request failed", { path: url.pathname, error: (err as Error).message });
      res.writeHead(500, { "content-type": "text/plain" });
      res.end("error");
    }
  }

  const wss = new WebSocketServer({
    server,
    path: env.WS_PATH,
    maxPayload: shared.constants.net.maxMessageBytes,
    perMessageDeflate: false,
  });
  wss.on("connection", (ws, req) => {
    ws.binaryType = "nodebuffer";
    // Behind nginx the client address comes from X-Forwarded-For (first hop).
    const fwd = String(req.headers["x-forwarded-for"] ?? "").split(",")[0]?.trim();
    const ip = fwd || req.socket.remoteAddress || "?";
    log.debug("ws connected", { ip });
    new Session(ws, hub, ip);
  });

  zones.start();
  const bot = new TelegramBot(env, hub, () => ({ connections: wss.clients.size, uptimeSec: Math.round((Date.now() - startedAt) / 1000), version }));
  hub.bot = bot;
  // never in tests; production and dev answer the bot when it has a token
  if (env.BOT_POLLING && env.NODE_ENV !== "test") bot.start();
  const sweeper = setInterval(() => hub.sweep(Date.now()), 10_000);
  sweeper.unref();

  return {
    server,
    wss,
    zones,
    hub,
    bot,
    close: () =>
      new Promise<void>((resolve) => {
        clearInterval(sweeper);
        bot.stop();
        void hub.cards.close();
        zones.stop();
        for (const c of wss.clients) c.terminate();
        wss.close(() => server.close(() => void hub.flush().then(resolve)));
      }),
  };
}

/** The release's VERSION file (next to server/ in a release), else "dev". */
function releaseVersion(): string {
  try {
    const here = path.dirname(fileURLToPath(import.meta.url));
    for (const p of [path.join(here, "..", "VERSION"), path.join(here, "..", "..", "VERSION")]) {
      if (fs.existsSync(p)) return fs.readFileSync(p, "utf8").trim().slice(0, 64);
    }
  } catch {
    // fall through
  }
  return "dev";
}
