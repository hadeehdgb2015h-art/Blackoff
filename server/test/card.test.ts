import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { cardName, cardSvg, clock } from "../src/card/cardRender.js";
import { CardService, cardsBaseUrl, cardsDir } from "../src/card/cardService.js";
import { Codec } from "../src/net/codec.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

// Phase 25: the shareable result card, drawn by the server from its own numbers.
const input = { lang: "en" as const, name: "Hadi", mode: 0, wave: 14, kills: 187, headshots: 63, seconds: 1234, bestWave: 17, bot: "Xv7bot" };

describe("card layout", () => {
  it("shows the server's numbers in the player's language and escapes the name", () => {
    const en = cardSvg({ ...input, name: `<b>"&'` }, "data:,");
    expect(en).toContain(">WAVE<");
    expect(en).toContain(">14<");
    expect(en).toContain(">187<");
    expect(en).toContain(">20:34<");
    expect(en).toContain("&lt;b&gt;&quot;&amp;&apos;");
    expect(en).not.toContain("<b>");
    expect(cardSvg({ ...input, lang: "ar" }, "data:,")).toContain("الموجة");
    expect(cardSvg({ ...input, lang: "ru", mode: 1 }, "data:,")).toContain("ЗАРАЖЕНИЕ");
    expect(clock(59)).toBe("0:59");
    expect(clock(3725)).toBe("1:02:05");
    expect(cardName("a‮b\u0007c")).toBe("abc");
    expect([...cardName("x".repeat(40))].length).toBe(24);
  });

  it("finds where cards go and their public address", () => {
    expect(cardsBaseUrl({ CARD_BASE_URL: "", GAME_URL: "", BLACKOFF_DOMAIN: "off.example.com" })).toBe("https://off.example.com/cards/");
    expect(cardsBaseUrl({ CARD_BASE_URL: "", GAME_URL: "https://x.io/game", BLACKOFF_DOMAIN: "" })).toBe("https://x.io/game/cards/");
    expect(cardsBaseUrl({ CARD_BASE_URL: "https://cdn.io/c", GAME_URL: "", BLACKOFF_DOMAIN: "a" })).toBe("https://cdn.io/c/");
    expect(cardsBaseUrl({ CARD_BASE_URL: "", GAME_URL: "", BLACKOFF_DOMAIN: "" })).toBe("");
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "rel-"));
    fs.mkdirSync(path.join(root, "web"));
    fs.mkdirSync(path.join(root, "shared"));
    expect(cardsDir({ CARDS_DIR: "", SHARED_DIR: path.join(root, "shared") })).toBe(""); // no web build yet
    fs.writeFileSync(path.join(root, "web", "index.html"), "");
    expect(cardsDir({ CARDS_DIR: "", SHARED_DIR: path.join(root, "shared") })).toBe(path.join(root, "web", "cards"));
    expect(cardsDir({ CARDS_DIR: "/x", SHARED_DIR: "/y" })).toBe("/x");
  });

  it("renders a 1080 x 1350 JPEG into the cards directory", async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cards-"));
    const svc = new CardService(dir, "https://example.com/cards/");
    const card = await svc.make({ ...input, lang: "ar", name: "علي" });
    const jpg = fs.readFileSync(card.file);
    expect(card.preview).toBe(`https://example.com/cards/${card.id}.png`);
    expect(fs.readFileSync(path.join(dir, card.id + ".png")).subarray(1, 4).toString()).toBe("PNG");
    expect(card.url).toBe(`https://example.com/cards/${card.id}.jpg`);
    expect([jpg[0], jpg[1]]).toEqual([0xff, 0xd8]);
    // SOF0 frame header: height then width
    const sof = jpg.indexOf(Buffer.from([0xff, 0xc0]));
    expect([jpg.readUInt16BE(sof + 5), jpg.readUInt16BE(sof + 7)]).toEqual([1350, 1080]);
    await svc.close();
  }, 20_000);
});

describe("card over the wire", () => {
  let app: App;
  let url = "";
  let dir = "";
  const codec = new Codec(defs().protocol);
  beforeAll(async () => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "cards-"));
    app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1", CARDS_DIR: dir, CARD_BASE_URL: "https://example.com/cards/" }), defs());
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
  });
  afterAll(() => app.close());

  it("draws the card from the zone's record, once per few seconds", async () => {
    const c = await TestClient.connect(url, codec);
    c.hello("dev:Carder");
    await c.waitFor("welcome");
    c.send("card", { lang: "en" });
    expect((await c.waitFor("card")).status).toBe(1); // nothing played yet
    c.send("quickPlay");
    const z = await c.waitFor("zoneJoined");
    const zone = app.hub.zones.zones.get(z.zoneId as number)!;
    zone.world.players.get(z.entityId as number)!.kills = 9;
    c.send("card", { lang: "ru" });
    const card = await c.waitFor("card", (m) => m.status === 0, 15_000);
    expect(String(card.url)).toMatch(/^https:\/\/example\.com\/cards\/[A-Za-z0-9_-]{16}\.jpg$/);
    expect(card.prepared).toBe(""); // dev account: no Telegram message
    expect(fs.existsSync(path.join(dir, String(card.url).split("/").pop()!))).toBe(true);
    c.send("card", { lang: "ru" });
    expect((await c.waitFor("card", (m) => m.status === 3)).status).toBe(3); // cooldown
  }, 30_000);
});
