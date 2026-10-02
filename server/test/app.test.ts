import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { Codec } from "../src/net/codec.js";
import { signInitData, validateInitData } from "../src/net/telegramAuth.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

const BOT_TOKEN = "123456:TEST-token";
let app: App;
let url = "";
const codec = new Codec(defs().protocol);
const connect = () => TestClient.connect(url, codec);
const ERR = defs().protocol.enums.errorCode!;

beforeAll(async () => {
  const env = loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1", TELEGRAM_BOT_TOKEN: BOT_TOKEN });
  app = createApp(env, defs());
  await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
  url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
});
afterAll(() => app.close());

describe("telegram initData", () => {
  const now = Math.floor(Date.now() / 1000);
  const fields = { auth_date: String(now), query_id: "AAE", user: JSON.stringify({ id: 777, first_name: "Ali", last_name: "Z" }) };
  it("accepts a correctly signed payload and rejects tampering or age", () => {
    const ok = validateInitData(signInitData(fields, BOT_TOKEN), BOT_TOKEN, 3600);
    expect(ok).toEqual({ ok: true, user: { id: "777", name: "Ali Z", username: undefined } });
    expect(validateInitData(signInitData(fields, "other:token"), BOT_TOKEN, 3600).ok).toBe(false);
    const tampered = signInitData(fields, BOT_TOKEN).replace("Ali", "Bob");
    expect(validateInitData(tampered, BOT_TOKEN, 3600).ok).toBe(false);
    const old = signInitData({ ...fields, auth_date: String(now - 7200) }, BOT_TOKEN);
    expect(validateInitData(old, BOT_TOKEN, 3600)).toEqual({ ok: false, reason: "expired" });
  });
});

describe("server", () => {
  it("serves /healthz with zone stats", async () => {
    const res = await fetch(url.replace("ws://", "http://").replace("/ws", "/healthz"));
    const body = (await res.json()) as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(body.protocolVersion).toBe(1);
    expect(body).toHaveProperty("zones");
  });

  it("rejects a wrong protocol version and bad identities", async () => {
    const a = await connect();
    a.hello("dev:x", "", 99);
    expect((await a.waitFor("error")).code).toBe(ERR.badVersion);
    expect(await a.waitClosed()).toBe(4001);
    const b = await connect();
    b.hello("query_id=1&hash=" + "0".repeat(64));
    expect((await b.waitFor("error")).code).toBe(ERR.authFailed);
  });

  it("answers garbage with badMessage and closes after five strikes", async () => {
    const c = await connect();
    c.ws.send("text");
    expect((await c.waitFor("error")).code).toBe(ERR.badMessage);
    c.send("quickPlay"); // before hello
    for (let i = 0; i < 3; i++) c.ws.send(new Uint8Array([250]));
    expect(await c.waitClosed()).toBe(4001);
  });

  it("logs in with Telegram, joins a zone, moves by input, resumes after a drop", async () => {
    const now = Math.floor(Date.now() / 1000);
    const initData = signInitData({ auth_date: String(now), user: JSON.stringify({ id: 42, first_name: "Hadi" }) }, BOT_TOKEN);
    const a = await connect();
    a.hello(initData);
    const welcome = await a.waitFor("welcome");
    expect(welcome.displayName).toBe("Hadi");
    a.send("quickPlay");
    const joined = await a.waitFor("zoneJoined");
    expect(joined.mapId).toBe("facility_01");
    const self = await a.waitFor("selfState");
    expect(self.currency).toBe(defs().constants.player.startCurrency);
    const first = await a.waitFor("snapshot", (m) => (m.entities as Msg[]).some((e) => e.id === joined.entityId));
    const start = (first.entities as Msg[]).find((e) => e.id === joined.entityId)!;
    // walk forward for ~1 s at 20 Hz
    for (let i = 1; i <= 20; i++) {
      a.send("input", { seq: i, moveX: 0, moveY: 127, yaw: start.yaw as number, pitch: 0, buttons: 0 });
      await new Promise((r) => setTimeout(r, 50));
    }
    const since = a.inbox.length;
    const later = await a.waitFor("snapshot", (m) => (m.ackSeq as number) >= 15, 3000, since);
    const pos = (later.entities as Msg[]).find((e) => e.id === joined.entityId)!;
    const moved = Math.hypot((pos.x as number) - (start.x as number), (pos.y as number) - (start.y as number));
    expect(moved).toBeGreaterThan(1.5);

    // a second player lands in the same zone and sees both in the roster
    const b = await connect();
    b.hello("dev:Bob");
    await b.waitFor("welcome");
    b.send("quickPlay");
    const jb = await b.waitFor("zoneJoined");
    expect(jb.zoneId).toBe(joined.zoneId);
    const roster = await b.waitFor("roster", (m) => (m.players as Msg[]).length === 2);
    expect((roster.players as Msg[]).map((p) => p.name).sort()).toEqual(["Bob", "Hadi"]);

    // drop and resume with the token: same slot back
    a.close();
    await a.waitClosed();
    const a2 = await connect();
    a2.hello("", welcome.resumeToken as string);
    await a2.waitFor("welcome");
    expect((await a2.waitFor("zoneJoined")).entityId).toBe(joined.entityId);

    a2.send("ping", { clientTime: 1234 });
    expect((await a2.waitFor("pong")).clientTime).toBe(1234);
    a2.close();
    b.close();
  });

  it("rate-limits input floods without dropping the connection", async () => {
    const c = await connect();
    c.hello("dev:Flood");
    await c.waitFor("welcome");
    c.send("quickPlay");
    await c.waitFor("zoneJoined");
    for (let i = 1; i <= 400; i++) c.send("input", { seq: i, moveX: 0, moveY: 0, yaw: 0, pitch: 0, buttons: 1 });
    await new Promise((r) => setTimeout(r, 300));
    expect(c.closed).toBeNull();
    const snap = await c.waitFor("snapshot", () => true, 2000, c.inbox.length);
    expect(snap.ackSeq as number).toBeLessThan(400); // most of the flood was dropped
    c.close();
  });
});

type Msg = Record<string, unknown>;
