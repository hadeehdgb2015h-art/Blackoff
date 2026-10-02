import path from "node:path";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import WebSocket from "ws";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { loadShared } from "../src/shared/loadShared.js";

let app: App;
let port = 0;

beforeAll(async () => {
  const env = loadEnv({ NODE_ENV: "test", PORT: "1" });
  app = createApp(env, loadShared(path.resolve(__dirname, "../../shared")));
  await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
  port = (app.server.address() as AddressInfo).port;
});
afterAll(() => app.close());

describe("app", () => {
  it("serves /healthz", async () => {
    const res = await fetch(`http://127.0.0.1:${port}/healthz`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean; protocolVersion: number };
    expect(body.ok).toBe(true);
    expect(body.protocolVersion).toBe(1);
  });

  it("closes websocket on text frames", async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    await new Promise((r) => ws.on("open", r));
    const code = await new Promise<number>((r) => {
      ws.on("close", (c) => r(c));
      ws.send("hello");
    });
    expect(code).toBe(1003);
  });
});
