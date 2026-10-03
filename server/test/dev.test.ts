import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { DevCmd } from "../src/admin/devPowers.js";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { Codec } from "../src/net/codec.js";
import { signInitData } from "../src/net/telegramAuth.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

// Phase 20: the owner's in-game powers, honoured for ADMIN_TELEGRAM_IDS only.
const TOKEN = "123456:TEST-token";
let app: App;
let url = "";
const codec = new Codec(defs().protocol);
const connect = () => TestClient.connect(url, codec);
const login = (id: number, name: string) =>
  signInitData({ auth_date: String(Math.floor(Date.now() / 1000)), user: JSON.stringify({ id, first_name: name }) }, TOKEN);

beforeAll(async () => {
  app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1", TELEGRAM_BOT_TOKEN: TOKEN, ADMIN_TELEGRAM_IDS: "40194242" }), defs());
  await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
  url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
});
afterAll(() => app.close());

describe("owner dev powers", () => {
  it("the owner gets dev in welcome and can use god mode, money, the boss and wave jumps", async () => {
    const o = await connect();
    o.hello(login(40194242, "Owner"));
    expect((await o.waitFor("welcome")).dev).toBe(true);
    o.send("quickPlay");
    const z = await o.waitFor("zoneJoined");
    const zone = app.hub.zones.zones.get(z.zoneId as number)!;
    const me = zone.world.players.get(z.entityId as number)!;
    const send = (cmd: number, arg = 0) => o.send("dev", { cmd, arg });
    const until = async (ok: () => boolean) => {
      for (let i = 0; i < 100 && !ok(); i++) await new Promise((r) => setTimeout(r, 20));
      expect(ok()).toBe(true);
    };
    send(DevCmd.GOD);
    await until(() => me.god);
    zone.world.damagePlayer(me, 50, 0);
    expect(me.hp).toBe(me.maxHp);
    const before = me.currency;
    send(DevCmd.MONEY, 10000);
    await until(() => me.currency === before + 10000);
    send(DevCmd.GOTO_WAVE, 9);
    await until(() => zone.world.director.wave >= 9);
    send(DevCmd.SPAWN_BOSS);
    await until(() => [...zone.world.zombies.values()].some((zz) => zz.type === "boss"));
    send(DevCmd.KILL_ALL);
    await until(() => zone.world.zombies.size === 0 || ![...zone.world.zombies.values()].some((zz) => zz.type === "boss"));
  });

  it("anyone else is refused", async () => {
    const c = await connect();
    c.hello(login(777, "Player"));
    expect((await c.waitFor("welcome")).dev).toBe(false);
    c.send("quickPlay");
    const z = await c.waitFor("zoneJoined");
    c.send("dev", { cmd: DevCmd.GOD, arg: 0 });
    expect((await c.waitFor("error")).code).toBe(defs().protocol.enums.errorCode!.badMessage);
    const me = app.hub.zones.zones.get(z.zoneId as number)!.world.players.get(z.entityId as number)!;
    expect(me.god).toBe(false);
  });
});
