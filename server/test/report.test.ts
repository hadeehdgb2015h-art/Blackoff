import http from "node:http";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { TelegramBot, reportText, statsText } from "../src/bot/telegramBot.js";
import { loadEnv } from "../src/config/env.js";
import { MemoryProfileStore } from "../src/db/profileStore.js";
import { Codec } from "../src/net/codec.js";
import { ReportLimiter, ShotBuffer, cleanClientInfo, cleanDetails, isWebp } from "../src/report/report.js";
import { addDays, computeAnalytics, platformGroup, type ActivityRow } from "../src/stats/analytics.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

// Phase 29: the owner's statistics and problem reports from the game.
const row = (day: string, accountId: string, o: Partial<ActivityRow> = {}): ActivityRow => ({
  day, accountId, opens: 1, games: 0, seconds: 0, bestWave: 0, platform: "", lang: "", fpsSum: 0, fpsN: 0, ...o,
});
/** a tiny valid-looking WebP header plus padding */
const webp = (n: number) => {
  const b = Buffer.alloc(n, 7);
  b.write("RIFF", 0, "latin1");
  b.writeUInt32LE(n - 8, 4);
  b.write("WEBP", 8, "latin1");
  return b;
};

describe("statistics", () => {
  const today = "2026-10-20";
  const first = new Map<string, string>([
    ["a", addDays(today, -3)], // new 3 days ago, came back the next day, played 3 games, reached wave 4
    ["b", addDays(today, -3)], // new 3 days ago, opened and left
    ["c", addDays(today, -10)], // new 10 days ago, came back 5 days later
    ["d", today], // new today, one game
  ]);
  const rows = [
    row(addDays(today, -3), "a", { games: 2, seconds: 600, bestWave: 2, platform: "android", lang: "ar", fpsSum: 40, fpsN: 1 }),
    row(addDays(today, -2), "a", { games: 1, seconds: 300, bestWave: 4, platform: "android", lang: "ar", fpsSum: 50, fpsN: 1 }),
    row(addDays(today, -3), "b", { platform: "ios", lang: "en" }),
    row(addDays(today, -10), "c", { games: 1, seconds: 100, platform: "tdesktop", lang: "ru" }),
    row(addDays(today, -5), "c", { games: 1, seconds: 100, platform: "tdesktop", lang: "ru", fpsSum: 20, fpsN: 1 }),
    row(today, "d", { games: 1, seconds: 120, platform: "android", lang: "ar", fpsSum: 20, fpsN: 1 }),
    row(today, "old", { games: 4, seconds: 1200, platform: "weba", lang: "ar" }),
  ];

  it("counts days, retention, where new players stop, devices and languages", () => {
    const a = computeAnalytics(rows, first, today);
    expect(a.days).toHaveLength(7);
    expect(a.days[6]).toEqual({ day: today, active: 2, fresh: 1, games: 5, seconds: 1320 });
    expect(a.days[3]).toMatchObject({ active: 2, fresh: 2, games: 2 });
    expect(a.week).toEqual({ active: 5, fresh: 3, games: 9, seconds: 2320 });
    expect(a.nextDay).toEqual({ of: 2, n: 1 }); // a and b (d is today: not counted yet)
    expect(a.withinWeek).toEqual({ of: 1, n: 1 }); // c came back within 7 days
    expect(a.funnel).toEqual({ fresh: 3, played: 2, wave3: 1, games3: 1, returned: 1 });
    expect(a.devices[0]).toEqual({ platform: "android", players: 2, fps: 33 }); // a (45 avg) and d (20)
    expect(a.slow).toEqual({ of: 3, n: 2 }); // d at 20 and c at 20
    expect(a.langs[0]).toEqual({ lang: "ar", players: 3 });
    expect(platformGroup("tdesktop")).toBe("desktop");
    const text = statsText(a);
    expect(text).toContain("إحصائيات اللعبة");
    expect(text).toContain("رجعوا في اليوم التالي: <b>50%</b>");
    expect(text).toContain("أندرويد");
  });

  it("works with no data at all", () => {
    const a = computeAnalytics([], new Map(), today);
    expect(a.week.active).toBe(0);
    expect(statsText(a)).toContain("لا بيانات بعد");
  });

  it("keeps activity per account and day in the memory store", async () => {
    const s = new MemoryProfileStore();
    await s.load("tg:1", "A");
    await s.touchActivity("tg:1", { opens: 1, platform: "ios", lang: "ru" }, today);
    await s.touchActivity("tg:1", { games: 1, seconds: 61.6, wave: 5, fps: 44.6 }, today);
    await s.touchActivity("tg:1", { games: 1, seconds: 10, wave: 3, fps: 30 }, today);
    expect(await s.activitySince(today)).toEqual([
      { day: today, accountId: "tg:1", opens: 1, games: 2, seconds: 72, bestWave: 5, platform: "ios", lang: "ru", fpsSum: 75, fpsN: 2 },
    ]);
    expect((await s.firstSeenSince("2000-01-01")).has("tg:1")).toBe(true);
  });
});

describe("report helpers", () => {
  it("cleans what the client says and limits reports", () => {
    expect(cleanClientInfo({ platform: "Android<script>", tgVersion: "8.0", lang: "xx", build: "abc-1", screen: "1080x2400" }))
      .toEqual({ platform: "androidscript", tgVersion: "8.0", lang: "", build: "abc-1", screen: "1080x2400" });
    expect(cleanDetails('{"quality":"low","sens":1.234,"tpp":true,"x":{"y":1},"bad<":"<b>hi</b>"}'))
      .toEqual({ quality: "low", sens: 1.23, tpp: true, bad: "bhi/b" });
    expect(cleanDetails("not json")).toEqual({});
    const l = new ReportLimiter();
    expect(l.take("a", 0)).toBe(true);
    expect(l.take("a", 30_000)).toBe(false);
    expect(l.take("a", 61_000)).toBe(true);
    expect(l.take("b", 61_000)).toBe(true);
  });

  it("puts a screenshot together from its parts, and only a WebP", () => {
    const img = webp(9000);
    const b = new ShotBuffer();
    expect(b.add(0, 3, img.subarray(0, 3800))).toBe(true);
    expect(b.add(1, 3, img.subarray(3800, 7600))).toBe(true);
    expect(b.add(2, 3, img.subarray(7600))).toBe(true);
    expect(b.take()?.equals(img)).toBe(true);
    expect(b.take()).toBeNull(); // emptied
    b.add(0, 2, img.subarray(0, 3800));
    expect(b.take()).toBeNull(); // a part is missing
    expect(b.add(0, 13, img.subarray(0, 10))).toBe(false); // too many parts
    expect(b.add(0, 1, Buffer.alloc(4000))).toBe(false); // part too big
    b.add(0, 1, Buffer.alloc(100, 1));
    expect(b.take()).toBeNull(); // not a WebP
    expect(isWebp(img)).toBe(true);
  });
});

describe("reports over the wire and in the bot", () => {
  const OWNER = 40194242;
  const PLAYER = 777;
  let app: App;
  let api: http.Server;
  let bot: TelegramBot;
  let url = "";
  const codec = new Codec(defs().protocol);
  const queue: unknown[] = [];
  const calls: { method: string; body: Record<string, unknown>; bytes: number }[] = [];
  let nextId = 1;
  const msg = (from: number, text: string) => queue.push({ update_id: nextId++, message: { message_id: nextId, chat: { id: from, type: "private" }, from: { id: from, first_name: "Ali" }, text } });
  const tap = (from: number, data: string) => queue.push({ update_id: nextId++, callback_query: { id: "q" + nextId, from: { id: from, first_name: "x" }, message: { message_id: 1, chat: { id: from, type: "private" } }, data } });
  async function call(method: string, pred: (c: { body: Record<string, unknown>; bytes: number }) => boolean): Promise<{ body: Record<string, unknown>; bytes: number }> {
    const until = Date.now() + 4000;
    while (Date.now() < until) {
      const c = calls.find((x) => x.method === method && pred(x));
      if (c) return c;
      await new Promise((r) => setTimeout(r, 20));
    }
    throw new Error(`no ${method}; got ${calls.map((c) => c.method + ":" + String(c.body.text ?? "").slice(0, 30)).join(" | ")}`);
  }
  const sent = (chat: number, has: string) => call("sendMessage", (c) => c.body.chat_id === chat && String(c.body.text).includes(has));

  beforeAll(async () => {
    api = http.createServer((req, res) => {
      const chunks: Buffer[] = [];
      req.on("data", (d: Buffer) => chunks.push(d));
      req.on("end", () => {
        const method = String(req.url).split("/").pop()!;
        const raw = Buffer.concat(chunks);
        const json = String(req.headers["content-type"]).includes("json");
        const body = json && raw.length ? (JSON.parse(raw.toString()) as Record<string, unknown>) : {};
        if (!json) { // multipart photo: keep the chat id and the caption
          const t = raw.toString("latin1");
          body.chat_id = Number(/name="chat_id"\r\n\r\n(\d+)/.exec(t)?.[1]);
          body.caption = Buffer.from(/name="caption"\r\n\r\n([\s\S]*?)\r\n--/.exec(t)?.[1] ?? "", "latin1").toString("utf8");
        }
        res.setHeader("content-type", "application/json");
        if (method === "getUpdates") {
          const out = queue.splice(0, queue.length);
          if (out.length) return res.end(JSON.stringify({ ok: true, result: out }));
          return setTimeout(() => res.end(JSON.stringify({ ok: true, result: queue.splice(0, queue.length) })), 50);
        }
        calls.push({ method, body, bytes: raw.length });
        res.end(JSON.stringify({ ok: true, result: true }));
      });
    });
    await new Promise<void>((r) => api.listen(0, "127.0.0.1", r));
    const env = loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1", TELEGRAM_BOT_TOKEN: "1:T", TELEGRAM_BOT_USERNAME: "TestBot", ADMIN_TELEGRAM_IDS: String(OWNER) });
    app = createApp(env, defs());
    bot = new TelegramBot(env, app.hub, () => ({ connections: 0, uptimeSec: 1, version: "test" }), `http://127.0.0.1:${(api.address() as AddressInfo).port}`);
    app.hub.bot = bot;
    bot.start();
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
  });
  afterAll(async () => {
    bot.stop();
    await app.close();
    api.close();
  });

  it("counts the visit and the device, then sends a report with its screenshot to the owner", async () => {
    const c = await TestClient.connect(url, codec);
    c.hello("dev:Reporter");
    await c.waitFor("welcome");
    c.send("clientInfo", { platform: "android", tgVersion: "8.0", lang: "en", build: "b1", screen: "1080x2400" });
    c.send("perf", { fps: 37, seconds: 300 });
    c.send("perf", { fps: 90, seconds: 5 }); // too short: ignored
    const img = webp(5000);
    c.send("reportShot", { part: 0, total: 2, data: img.subarray(0, 3000) });
    c.send("reportShot", { part: 1, total: 2, data: img.subarray(3000) });
    c.send("report", { category: 0, where: "menu", fps: 22, details: JSON.stringify({ quality: "low", tpp: true }) });
    const r = await c.waitFor("reported");
    expect(r.status).toBe(0);
    await app.hub.flush();
    const store = app.hub.store as MemoryProfileStore;
    const act = (await store.activitySince("2000-01-01")).find((x) => x.accountId === "dev:Reporter")!;
    expect(act).toMatchObject({ opens: 1, platform: "android", lang: "en", fpsSum: 37, fpsN: 1 });
    const photo = await call("sendPhoto", (x) => x.body.chat_id === OWNER);
    expect(String(photo.body.caption)).toContain(`بلاغ #${r.id}`);
    expect(String(photo.body.caption)).toContain("quality low");
    expect(photo.bytes).toBeGreaterThan(5000);
    const saved = (await store.report(r.id as number))!;
    expect(saved.info).toMatchObject({ where: "menu", fps: 22, shot: true, client: { platform: "android" }, details: { quality: "low", tpp: true } });
    // a second report within a minute is refused
    c.send("report", { category: 5, where: "menu", fps: 30, details: "{}" });
    expect((await c.waitFor("reported", (m) => m.status !== 0)).status).toBe(1);
    c.send("report", { category: 9, where: "menu", fps: 30, details: "{}" });
    expect((await c.waitFor("error")).code).toBe(defs().protocol.enums.errorCode.badMessage);
  });

  it("lets the player add details, the owner answer, resolve and see statistics", async () => {
    const store = app.hub.store;
    const id = await store.addReport({ accountId: "tg:" + PLAYER, name: "Ali", category: 1, info: { where: "game w3", fps: 40, client: { lang: "ar" } } });
    await bot.onReport((await store.report(id))!, null);
    await sent(OWNER, `بلاغ #${id}`);
    await sent(PLAYER, `بلاغك رقم <b>#${id}</b>`);
    msg(PLAYER, "the aim jumps when I reload");
    await sent(PLAYER, `أضيفت إلى بلاغك #${id}`);
    await sent(OWNER, "the aim jumps when I reload");
    expect((await store.report(id))!.notes).toContain("the aim jumps");
    tap(OWNER, `a:rr:${id}`);
    await sent(OWNER, "اكتب ردك");
    msg(OWNER, "Fixed in the next update");
    await sent(PLAYER, "Fixed in the next update");
    await sent(OWNER, "وصل ردك");
    tap(OWNER, "a:reports");
    await sent(OWNER, "البلاغات المفتوحة");
    tap(OWNER, `a:rs:${id}`);
    await sent(PLAYER, `(#${id})`);
    expect((await store.report(id))!.resolved).toBe(true);
    expect(reportText((await store.report(id))!)).toContain("مغلق");
    tap(OWNER, "a:stats");
    await sent(OWNER, "إحصائيات اللعبة");
    tap(PLAYER, "a:stats"); // not the owner: nothing
    await new Promise((r) => setTimeout(r, 300));
    expect(calls.some((c) => c.body.chat_id === PLAYER && String(c.body.text).includes("إحصائيات اللعبة"))).toBe(false);
  });
});
