import http from "node:http";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { TelegramBot } from "../src/bot/telegramBot.js";
import { loadEnv } from "../src/config/env.js";
import { defs } from "./helpers.js";

// Phase 20: the bot against a fake Telegram API (getUpdates hands out queued
// updates, every other method is recorded).
const OWNER = 40194242;
const PLAYER = 555;
let app: App;
let api: http.Server;
let bot: TelegramBot;
const queue: unknown[] = [];
const calls: { method: string; body: Record<string, unknown> }[] = [];
let nextId = 1;

const msg = (from: number, text: string) => queue.push({ update_id: nextId++, message: { message_id: nextId, chat: { id: from, type: "private" }, from: { id: from, first_name: from === OWNER ? "Hadi" : "Ali" }, text } });
const tap = (from: number, data: string) => queue.push({ update_id: nextId++, callback_query: { id: "q" + nextId, from: { id: from, first_name: "x" }, message: { message_id: 1, chat: { id: from, type: "private" } }, data } });
async function sent(chat: number, has: string, timeoutMs = 3000): Promise<Record<string, unknown>> {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    const c = calls.find((x) => x.method === "sendMessage" && x.body.chat_id === chat && String(x.body.text).includes(has));
    if (c) return c.body;
    await new Promise((r) => setTimeout(r, 20));
  }
  throw new Error(`no message to ${chat} containing "${has}"; got ${calls.filter((c) => c.method === "sendMessage").map((c) => String(c.body.text).slice(0, 40)).join(" | ")}`);
}

beforeAll(async () => {
  api = http.createServer((req, res) => {
    let raw = "";
    req.on("data", (d) => (raw += d));
    req.on("end", () => {
      const method = String(req.url).split("/").pop()!;
      const body = raw ? (JSON.parse(raw) as Record<string, unknown>) : {};
      res.setHeader("content-type", "application/json");
      if (method === "getUpdates") {
        const out = queue.splice(0, queue.length);
        if (out.length) return res.end(JSON.stringify({ ok: true, result: out }));
        return setTimeout(() => res.end(JSON.stringify({ ok: true, result: queue.splice(0, queue.length) })), 50);
      }
      calls.push({ method, body });
      res.end(JSON.stringify({ ok: true, result: true }));
    });
  });
  await new Promise<void>((r) => api.listen(0, "127.0.0.1", r));
  const env = loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1", TELEGRAM_BOT_TOKEN: "1:T", TELEGRAM_BOT_USERNAME: "TestBot",
    ADMIN_TELEGRAM_IDS: String(OWNER), BLACKOFF_DOMAIN: "game.example" });
  app = createApp(env, defs());
  bot = new TelegramBot(env, app.hub, () => ({ connections: 0, uptimeSec: 1, version: "test" }), `http://127.0.0.1:${(api.address() as AddressInfo).port}`);
  bot.start();
});
afterAll(async () => {
  bot.stop();
  await app.close();
  api.close();
});

describe("telegram bot", () => {
  it("welcomes players with a Play button that opens the game", async () => {
    msg(PLAYER, "/start");
    const b = await sent(PLAYER, "BLACK OFF");
    const kb = JSON.stringify(b.reply_markup);
    expect(kb).toContain("https://game.example/");
    expect(kb).not.toContain("a:panel"); // players get no owner panel
  });

  it("answers stats, the weekly top and invites", async () => {
    tap(PLAYER, "u:stats");
    await sent(PLAYER, "إحصائيات");
    msg(PLAYER, "/top");
    await sent(PLAYER, "الأقوى هذا الأسبوع");
    msg(PLAYER, "/invite");
    expect(String((await sent(PLAYER, "t.me/TestBot?startapp=sq")).text)).toMatch(/startapp=sq[A-Za-z0-9]{10}/);
  });

  it("gives the owner the panel; a player asking for it gets the welcome", async () => {
    msg(OWNER, "/admin");
    const p = await sent(OWNER, "لوحة المطور");
    expect(JSON.stringify(p.reply_markup)).toContain("a:maint");
    msg(PLAYER, "/admin");
    await sent(PLAYER, "أهلاً");
  });

  it("bans and unbans, switches maintenance and TON from the panel", async () => {
    tap(OWNER, "a:ban");
    await sent(OWNER, "لحظره");
    msg(OWNER, String(PLAYER));
    await sent(OWNER, "حُظر");
    expect(app.hub.settings.banned.has("tg:" + PLAYER)).toBe(true);
    tap(OWNER, "a:unban");
    await sent(OWNER, "لفك حظره");
    msg(OWNER, String(PLAYER));
    await sent(OWNER, "فُك حظر");
    expect(app.hub.settings.banned.size).toBe(0);

    tap(OWNER, "a:maint");
    await sent(OWNER, "رسالة الصيانة");
    msg(OWNER, "back at 9");
    await sent(OWNER, "الصيانة تعمل");
    expect(app.hub.settings.maintenance).toBe(true);
    expect(app.hub.settings.maintenanceText).toBe("back at 9");
    tap(OWNER, "a:maint");
    await sent(OWNER, "انتهت الصيانة");

    tap(OWNER, "a:ton");
    await sent(OWNER, "كم TON");
    msg(OWNER, "0.002");
    await sent(OWNER, "TON لكل قتلة الآن: 0.002");
    tap(OWNER, "a:tonx");
    await sent(OWNER, "مضاعفة TON تعمل");
    expect(app.hub.settings.tonPerKill()).toBe(4000);
  });

  it("shows the live state of the zones", async () => {
    tap(OWNER, "a:live");
    await sent(OWNER, "الحالة الآن");
  });
});
