import http from "node:http";
import { WebSocketServer } from "ws";
import type { Env } from "./config/env.js";
import type { SharedData } from "./shared/loadShared.js";
import { log } from "./log.js";

export interface App {
  server: http.Server;
  wss: WebSocketServer;
  close(): Promise<void>;
}

/**
 * Phase 0 skeleton: HTTP health endpoint + WebSocket endpoint that accepts
 * binary frames only. Zone simulation and protocol handling arrive in phase 2.
 */
export function createApp(env: Env, shared: SharedData): App {
  const startedAt = Date.now();
  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://local");
    if (url.pathname === "/healthz") {
      res.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
      res.end(JSON.stringify({
        ok: true,
        protocolVersion: shared.protocol.protocolVersion,
        uptimeSec: Math.round((Date.now() - startedAt) / 1000),
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
    log.debug("ws connected", { ip: req.socket.remoteAddress });
    ws.binaryType = "nodebuffer";
    ws.on("message", (_data, isBinary) => {
      if (!isBinary) ws.close(1003, "binary only");
    });
  });

  return {
    server,
    wss,
    close: () =>
      new Promise<void>((resolve) => {
        for (const c of wss.clients) c.terminate();
        wss.close(() => server.close(() => resolve()));
      }),
  };
}
