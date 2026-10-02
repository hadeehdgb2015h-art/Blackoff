import http from "node:http";
import { WebSocketServer } from "ws";
import type { Env } from "./config/env.js";
import type { SharedData } from "./shared/loadShared.js";
import { Codec } from "./net/codec.js";
import { Session, SessionHub } from "./net/session.js";
import { ZoneManager } from "./zone/zoneManager.js";
import { log } from "./log.js";
import { MemoryProfileStore, type ProfileStore } from "./db/profileStore.js";

export interface App {
  server: http.Server;
  wss: WebSocketServer;
  zones: ZoneManager;
  hub: SessionHub;
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
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found");
  });

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
  const sweeper = setInterval(() => hub.sweep(Date.now()), 10_000);
  sweeper.unref();

  return {
    server,
    wss,
    zones,
    hub,
    close: () =>
      new Promise<void>((resolve) => {
        clearInterval(sweeper);
        zones.stop();
        for (const c of wss.clients) c.terminate();
        wss.close(() => server.close(() => void hub.flush().then(resolve)));
      }),
  };
}
