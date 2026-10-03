/**
 * The game's Telegram bot (phase 20): answers players and gives the owner a
 * control panel, by long polling (no webhook, so nothing changes in nginx).
 *
 * Players: /start (welcome, Play button, invite, stats, weekly top, how to
 * play), /stats, /top, /invite, /help. Replies are in Arabic.
 * Owners (ADMIN_TELEGRAM_IDS): /admin opens a panel of buttons: live state of
 * every zone, player counts, weekly top, anti-cheat suspects, a message to all
 * players, find / ban / unban a player, TON per kill and a x2 event, give TON,
 * prize text, maintenance mode, recent warnings, restart. Switches persist
 * (RuntimeSettings). Actions that need a value ask for it, and the owner's
 * next message answers.
 * Phase 29: statistics (active and new players, retention, where new players
 * stop, devices and FPS, languages) and problem reports from the game: each
 * arrives with its screenshot; the player can add details by writing here for
 * a while, the owner can answer them, resolve or close the report.
 */
import crypto from "node:crypto";
import type { Env } from "../config/env.js";
import { recentProblems, log } from "../log.js";
import type { SessionHub } from "../net/session.js";
import { GameMode } from "../sim/simWorld.js";
import { weekLabel, weekStart } from "../db/profileStore.js";
import { levelFor, rankFor } from "../progression.js";
import { RANK_NAMES } from "../card/cardRender.js";
import type { ReportRow } from "../db/profileStore.js";
import { REPORT_CATEGORIES } from "../report/report.js";
import type { Analytics, Ratio } from "../stats/analytics.js";

type Json = Record<string, unknown>;
interface TgUser { id: number; first_name?: string; last_name?: string; username?: string }
interface TgMessage { message_id: number; chat: { id: number; type: string }; from?: TgUser; text?: string }
interface TgCallback { id: string; from: TgUser; message?: TgMessage; data?: string }
interface TgUpdate { update_id: number; message?: TgMessage; callback_query?: TgCallback }
type Button = { text: string; callback_data?: string; url?: string; web_app?: { url: string } };

/** Live numbers the bot cannot see from the hub alone (the app supplies them). */
export interface LiveInfo { connections: number; uptimeSec: number; version: string }

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const ton = (micro: number) => (micro / 1_000_000).toFixed(6).replace(/0+$/, "").replace(/\.$/, "");
const pct = (r: Ratio) => (r.of ? `${Math.round((100 * r.n) / r.of)}%` : "—");
const mins = (sec: number) => `${Math.round(sec / 60)} د`;
const WEEKDAYS_AR = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];
const PLATFORMS_AR: Record<string, string> = { android: "أندرويد", ios: "آيفون", desktop: "كمبيوتر", web: "متصفح", other: "أخرى", unknown: "غير معروف" };
const LANGS_AR: Record<string, string> = { ar: "العربية", en: "English", ru: "Русский" };
const CATEGORY_AR: Record<(typeof REPORT_CATEGORIES)[number], string> = {
  lag: "⚡ بطء أو تقطيع", controls: "🎯 التحكم أو التصويب", connection: "📶 الاتصال", sound: "🔊 الصوت", visual: "👁 خلل في الصورة", other: "❓ شيء آخر",
};
/** What the player reads after a report and around it, in their language. */
const REPORT_TEXT = {
  ar: {
    got: (id: number) => `✅ وصل بلاغك رقم <b>#${id}</b>، شكراً لك!\n\nإذا تريد تضيف تفاصيل (ماذا حدث بالضبط؟ متى؟) اكتبها هنا خلال 30 دقيقة وستصل للمطور مباشرة.`,
    added: (id: number) => `📝 أضيفت إلى بلاغك #${id}.`,
    reply: (id: number, t: string) => `📩 <b>رد المطور على بلاغك #${id}:</b>\n\n${t}\n\n<i>يمكنك الرد هنا.</i>`,
    fixed: (id: number) => `✅ تم إصلاح المشكلة التي أبلغت عنها (#${id}). شكراً لمساعدتك!`,
  },
  en: {
    got: (id: number) => `✅ Your report <b>#${id}</b> arrived, thank you!\n\nTo add details (what happened exactly? when?), write them here within 30 minutes and they go straight to the developer.`,
    added: (id: number) => `📝 Added to your report #${id}.`,
    reply: (id: number, t: string) => `📩 <b>The developer answered your report #${id}:</b>\n\n${t}\n\n<i>You can reply here.</i>`,
    fixed: (id: number) => `✅ The problem you reported (#${id}) is fixed. Thank you for your help!`,
  },
  ru: {
    got: (id: number) => `✅ Ваш отчёт <b>#${id}</b> получен, спасибо!\n\nЧтобы добавить подробности (что именно случилось? когда?), напишите их здесь в течение 30 минут — они сразу попадут к разработчику.`,
    added: (id: number) => `📝 Добавлено к отчёту #${id}.`,
    reply: (id: number, t: string) => `📩 <b>Разработчик ответил на ваш отчёт #${id}:</b>\n\n${t}\n\n<i>Можно ответить здесь.</i>`,
    fixed: (id: number) => `✅ Проблема из вашего отчёта (#${id}) исправлена. Спасибо за помощь!`,
  },
};
type ReportLang = keyof typeof REPORT_TEXT;
const FOLLOWUP_MS = 30 * 60_000;
const nameOf = (u: TgUser) => [u.first_name, u.last_name].filter(Boolean).join(" ") || u.username || "لاعب";

export class TelegramBot {
  private offset = 0;
  private running = false;
  private stopped = false;
  /** owner chat -> the value the panel asked for, and until when */
  private pending = new Map<number, { action: string; until: number }>();
  /** player chat -> the report their next messages add to, and until when (phase 29) */
  private followups = new Map<number, { id: number; until: number; left: number }>();

  constructor(private readonly env: Env, private readonly hub: SessionHub, private readonly live: () => LiveInfo,
    private readonly apiBase = "https://api.telegram.org") {}

  get gameUrl(): string {
    if (this.env.GAME_URL) return this.env.GAME_URL;
    return this.env.BLACKOFF_DOMAIN ? `https://${this.env.BLACKOFF_DOMAIN}/` : "";
  }

  start(): void {
    if (this.running || !this.env.TELEGRAM_BOT_TOKEN) return;
    this.running = true;
    void this.loop();
  }

  stop(): void {
    this.stopped = true;
  }

  // ------------------------------------------------------------------ Telegram API

  /** A message the player can send to any chat from the Mini App (WebApp.shareMessage):
   *  their result card, a caption and a Play button with their invite link (Bot API
   *  savePreparedInlineMessage, phase 25). Its id, or "" when Telegram refused. */
  async prepareCard(userId: number, photoUrl: string, caption: string, button: string, link: string): Promise<string> {
    const r = await this.api("savePreparedInlineMessage", {
      user_id: userId,
      result: {
        type: "photo", id: crypto.randomBytes(8).toString("hex"), photo_url: photoUrl, thumbnail_url: photoUrl,
        photo_width: 1080, photo_height: 1350, caption, parse_mode: "HTML",
        reply_markup: { inline_keyboard: [[{ text: button, url: link }]] },
      },
      allow_user_chats: true, allow_group_chats: true, allow_channel_chats: true,
    }).catch((err: Error) => ({ ok: false, description: err.message } as { ok: boolean; result?: unknown; description?: string }));
    const id = r.ok ? String((r.result as { id?: string } | undefined)?.id ?? "") : "";
    if (!id) log.warn("prepared card message refused", { error: r.description });
    return id;
  }

  private async api(method: string, body: Json = {}, timeoutMs = 15_000): Promise<{ ok: boolean; result?: unknown; error_code?: number; description?: string }> {
    const res = await fetch(`${this.apiBase}/bot${this.env.TELEGRAM_BOT_TOKEN}/${method}`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body), signal: AbortSignal.timeout(timeoutMs),
    });
    return (await res.json()) as { ok: boolean; result?: unknown; error_code?: number; description?: string };
  }

  private send(chatId: number, text: string, buttons?: Button[][]): Promise<unknown> {
    return this.api("sendMessage", {
      chat_id: chatId, text, parse_mode: "HTML", link_preview_options: { is_disabled: true },
      ...(buttons ? { reply_markup: { inline_keyboard: buttons } } : {}),
    }).catch((err: Error) => log.warn("bot send failed", { error: err.message }));
  }

  private async loop(): Promise<void> {
    let delay = 1000;
    // a webhook left by another program would make getUpdates fail
    await this.api("deleteWebhook", { drop_pending_updates: false }).catch(() => undefined);
    await this.setCommands().catch(() => undefined);
    log.info("bot polling started");
    while (!this.stopped) {
      try {
        const r = await this.api("getUpdates", { offset: this.offset, timeout: 25, allowed_updates: ["message", "callback_query"] }, 35_000);
        if (!r.ok) {
          if (r.error_code === 401 || r.error_code === 404) {
            log.warn("bot token rejected by Telegram; the bot stays silent", { code: r.error_code });
            return;
          }
          if (r.error_code === 409) log.warn("another program reads this bot's updates (409); retrying");
          throw new Error(r.description ?? "getUpdates failed");
        }
        delay = 1000;
        for (const u of (r.result as TgUpdate[]) ?? []) {
          this.offset = u.update_id + 1;
          try {
            await this.onUpdate(u);
          } catch (err) {
            log.warn("bot update failed", { error: (err as Error).message });
          }
        }
      } catch (err) {
        if (this.stopped) return;
        log.debug("bot poll error", { error: (err as Error).message });
        await new Promise((r) => setTimeout(r, delay));
        delay = Math.min(delay * 2, 60_000);
      }
    }
  }

  private async setCommands(): Promise<void> {
    await this.api("setMyCommands", {
      commands: [
        { command: "start", description: "ابدأ اللعب" },
        { command: "stats", description: "إحصائياتي" },
        { command: "top", description: "الأقوى هذا الأسبوع" },
        { command: "invite", description: "ادعُ أصدقاءك" },
        { command: "help", description: "طريقة اللعب" },
      ],
    });
  }

  // ------------------------------------------------------------------ routing

  private isOwner(u: TgUser | undefined): boolean {
    return !!u && this.hub.isOwner("tg:" + u.id);
  }

  private async onUpdate(u: TgUpdate): Promise<void> {
    if (u.callback_query) return this.onCallback(u.callback_query);
    const m = u.message;
    if (!m?.text || !m.from || m.chat.type !== "private") return;
    const text = m.text.trim();
    const chat = m.chat.id;
    const wait = this.pending.get(chat);
    if (wait && this.isOwner(m.from) && !text.startsWith("/")) {
      this.pending.delete(chat);
      if (Date.now() <= wait.until) return this.onAdminInput(chat, wait.action, text);
    }
    const follow = this.followups.get(chat);
    if (follow && !text.startsWith("/")) {
      if (Date.now() <= follow.until && follow.left > 0) return this.onFollowup(chat, m.from, follow, text);
      this.followups.delete(chat);
    }
    const [cmd = "", ...rest] = text.split(/\s+/);
    const arg = rest.join(" ");
    switch (cmd.split("@")[0]) {
      case "/start": return this.welcome(chat, m.from);
      case "/stats": return this.stats(chat, m.from);
      case "/top": return this.top(chat);
      case "/invite": return this.invite(chat, m.from);
      case "/help": return this.help(chat);
      case "/admin": case "/panel": return this.isOwner(m.from) ? this.panel(chat) : this.welcome(chat, m.from);
      case "/broadcast": return this.isOwner(m.from) && arg ? this.onAdminInput(chat, "bc", arg) : this.welcome(chat, m.from);
      default: return void this.send(chat, "اضغط «🎮 العب الآن» للدخول إلى اللعبة، أو اختر من القائمة.", this.userButtons(m.from));
    }
  }

  private async onCallback(q: TgCallback): Promise<void> {
    await this.api("answerCallbackQuery", { callback_query_id: q.id }).catch(() => undefined);
    const chat = q.message?.chat.id;
    if (!chat) return;
    const data = q.data ?? "";
    if (data === "u:stats") return this.stats(chat, q.from);
    if (data === "u:top") return this.top(chat);
    if (data === "u:help") return this.help(chat);
    if (data === "u:invite") return this.invite(chat, q.from);
    if (data.startsWith("a:") && this.isOwner(q.from)) return this.onAdmin(chat, data.slice(2));
  }

  // ------------------------------------------------------------------ players

  private userButtons(u: TgUser): Button[][] {
    const rows: Button[][] = [];
    if (this.gameUrl) rows.push([{ text: "🎮 العب الآن", web_app: { url: this.gameUrl } }]);
    rows.push([{ text: "👥 ادعُ أصدقاءك", callback_data: "u:invite" }]);
    rows.push([{ text: "📊 إحصائياتي", callback_data: "u:stats" }, { text: "🏆 الأقوى هذا الأسبوع", callback_data: "u:top" }]);
    rows.push([{ text: "❓ طريقة اللعب", callback_data: "u:help" }]);
    if (this.isOwner(u)) rows.push([{ text: "🛠 لوحة المطور", callback_data: "a:panel" }]);
    return rows;
  }

  private async welcome(chat: number, u: TgUser): Promise<void> {
    const name = esc(nameOf(u));
    await this.send(chat,
      `أهلاً <b>${name}</b> 👋\n\n` +
      "<b>BLACK OFF</b>: لعبة زومبي جماعية في عالم مظلم.\n" +
      "اصمد مع أصدقائك أمام موجات لا تنتهي، واهزم <b>الحارس</b> كل خمس موجات، واجمع نقاط <b>TON</b> مع كل قتلة.\n" +
      "🎁 مكافأة يومية تكبر كل يوم تعود فيه، وثلاث مهام جديدة كل يوم.\n\n" +
      "🎮 اضغط «العب الآن» وابدأ القتال.",
      this.userButtons(u));
  }

  private async stats(chat: number, u: TgUser): Promise<void> {
    const id = "tg:" + u.id;
    const p = await this.hub.store.load(id, nameOf(u));
    const w = await this.hub.store.weekly(id);
    const prog = this.hub.shared.constants.progression;
    const hours = Math.floor(p.playSeconds / 3600);
    const mins = Math.floor((p.playSeconds % 3600) / 60);
    await this.send(chat,
      `📊 <b>إحصائيات ${esc(nameOf(u))}</b>\n\n` +
      `🎖 الرتبة: <b>${RANK_NAMES.ar[rankFor(levelFor(p.xp, prog), prog).id] ?? ""}</b>، المستوى <b>${levelFor(p.xp, prog)}</b> (${p.xp} خبرة)\n` +
      `🎯 القتلى: <b>${p.kills}</b> (رأس: ${p.headshots})\n` +
      `🌊 أعلى موجة: <b>${p.bestWave}</b>\n` +
      `🕹 المباريات: <b>${p.games}</b>\n` +
      `⏱ وقت اللعب: ${hours} س ${mins} د\n` +
      `💎 نقاط TON: <b>${ton(p.tonMicro)}</b>\n` +
      (w.rank > 0 ? `🏆 ترتيبك هذا الأسبوع: <b>#${w.rank}</b> بـ ${w.kills} قتلة` : "🏆 لم تدخل ترتيب هذا الأسبوع بعد: العب واقتل!"),
      this.userButtons(u));
  }

  private async top(chat: number): Promise<void> {
    const rows = await this.hub.store.leaderboard(10);
    const medals = ["🥇", "🥈", "🥉"];
    const lines = rows.map((r, i) => `${medals[i] ?? `${i + 1}.`} ${esc(r.name)}: <b>${r.kills}</b> قتلة · ${ton(r.tonMicro)} TON`);
    const prize = this.hub.settings.prizeText();
    await this.send(chat,
      `🏆 <b>الأقوى هذا الأسبوع</b> (${weekLabel(weekStart())})\n\n` +
      (lines.length ? lines.join("\n") : "لا أحد بعد: كن الأول!") +
      (prize ? `\n\n🎁 الجائزة: ${esc(prize)}` : ""));
  }

  private async invite(chat: number, u: TgUser): Promise<void> {
    if (!this.hub.botUsername) return void this.send(chat, "الدعوات غير متاحة الآن.");
    const link = `https://t.me/${this.hub.botUsername}?startapp=sq${this.hub.inviteCodeFor("tg:" + u.id)}`;
    const share = `https://t.me/share/url?url=${encodeURIComponent(link)}&text=${encodeURIComponent("انضم لفرقتي في BLACK OFF واصمد معي أمام الزومبي!")}`;
    await this.send(chat,
      "👥 <b>ادعُ أصدقاءك</b>\n\nأرسل لهم هذا الرابط: من يفتحه وأنت داخل مباراة ينضم إلى فرقتك مباشرة.\n\n" + link,
      [[{ text: "📤 أرسل الرابط لصديق", url: share }]]);
  }

  private async help(chat: number): Promise<void> {
    await this.send(chat,
      "❓ <b>طريقة اللعب</b>\n\n" +
      "• عصا الحركة يساراً، واسحب بإصبعك يميناً للتصويب.\n" +
      "• FIRE للإطلاق، R لإعادة التعبئة، SWAP لتبديل السلاح.\n" +
      "• اقتل الزومبي لتجمع المال، واشترِ أسلحة وقدرات من الجدران والصندوق الغامض.\n" +
      "• إن سقط زميلك فاقترب منه لتنقذه قبل أن ينزف.\n" +
      "• كل خمس موجات يظهر <b>الحارس</b>: زعيم ضخم بجائزة كبيرة.\n" +
      "• نمط العدوى: جنود ضد زومبي حقيقيين حتى 10 لاعبين.\n" +
      "• كل قتلة أونلاين تمنحك نقاط TON، وأقوى صياد في الأسبوع يربح الجائزة.");
  }

  // ------------------------------------------------------------------ owner panel

  private panelButtons(): Button[][] {
    const s = this.hub.settings;
    return [
      [{ text: "📈 الإحصائيات", callback_data: "a:stats" }, { text: "🐞 البلاغات", callback_data: "a:reports" }],
      [{ text: "📊 الحالة الآن", callback_data: "a:live" }, { text: "👥 اللاعبون", callback_data: "a:users" }],
      [{ text: "🏆 المتصدرون", callback_data: "a:top" }, { text: "🕵️ المشتبه بهم", callback_data: "a:sus" }],
      [{ text: "📢 رسالة للجميع", callback_data: "a:bc" }, { text: "🔎 بحث عن لاعب", callback_data: "a:find" }],
      [{ text: "🚫 حظر لاعب", callback_data: "a:ban" }, { text: "✅ فك الحظر", callback_data: "a:unban" }],
      [{ text: `💰 TON لكل قتلة (${ton(s.tonPerKill())})`, callback_data: "a:ton" }, { text: s.tonMultiplier > 1 ? "✖️ إيقاف مضاعفة TON" : "✖️2 مضاعفة TON", callback_data: "a:tonx" }],
      [{ text: "🎁 منح TON للاعب", callback_data: "a:give" }, { text: "🏅 نص الجائزة", callback_data: "a:prize" }],
      [{ text: s.maintenance ? "🛠 إيقاف الصيانة" : "🛠 تشغيل الصيانة", callback_data: "a:maint" }, { text: "📝 آخر الأخطاء", callback_data: "a:logs" }],
      [{ text: "🔄 إعادة تشغيل السيرفر", callback_data: "a:restart" }, { text: "♻️ تحديث اللوحة", callback_data: "a:panel" }],
    ];
  }

  private async panel(chat: number): Promise<void> {
    const z = this.hub.zones.stats();
    const s = this.hub.settings;
    await this.send(chat,
      "🛠 <b>لوحة المطور</b>\n\n" +
      `🟢 متصلون الآن: <b>${z.players}</b> لاعب في ${z.zones} مباراة · ${z.zombies} زومبي\n` +
      `💰 TON لكل قتلة: ${ton(s.tonPerKill())}${s.tonMultiplier > 1 ? ` (مضاعفة ×${s.tonMultiplier})` : ""}\n` +
      `🛠 الصيانة: ${s.maintenance ? "<b>تعمل</b>" : "متوقفة"} · 🚫 محظورون: ${s.banned.size}\n` +
      `🐞 بلاغات مفتوحة: ${await this.hub.store.countOpenReports().catch(() => 0)}`,
      this.panelButtons());
  }

  private ask(chat: number, action: string, prompt: string): Promise<unknown> {
    this.pending.set(chat, { action, until: Date.now() + 5 * 60_000 });
    return this.send(chat, prompt + "\n\n<i>أرسل الآن (أو /admin للإلغاء)</i>");
  }

  private async onAdmin(chat: number, cmd: string): Promise<void> {
    const s = this.hub.settings;
    const rep = /^r([rsxv]):(\d+)$/.exec(cmd);
    if (rep) return this.onReportAction(chat, rep[1]!, Number(rep[2]));
    switch (cmd) {
      case "stats": return this.statsPanel(chat);
      case "reports": return this.reportList(chat);
      case "panel": return this.panel(chat);
      case "live": return this.live_(chat);
      case "users": {
        const o = await this.hub.store.overview();
        return void this.send(chat,
          `👥 <b>اللاعبون</b>\n\nالمسجلون: <b>${o.users}</b>\nجدد اليوم: ${o.newToday}\nنشطون آخر 24 ساعة: ${o.activeToday}\n` +
          `مباريات آخر 24 ساعة: ${o.matchesToday}\nمجموع القتلى: ${o.totalKills}\nالتخزين: ${this.hub.store.kind}`, [[{ text: "⬅️ اللوحة", callback_data: "a:panel" }]]);
      }
      case "top": return this.top(chat);
      case "sus": {
        const rows = await this.hub.store.suspects(10);
        const lines = rows.map((r) => `• ${esc(r.name || r.accountId)} (<code>${esc(r.accountId)}</code>): ${r.suspicion} تنبيه · دقة ${r.shots ? Math.round((100 * r.hits) / r.shots) : 0}%`);
        return void this.send(chat, "🕵️ <b>المشتبه بالغش</b>\n\n" + (lines.join("\n") || "لا أحد."), [[{ text: "⬅️ اللوحة", callback_data: "a:panel" }]]);
      }
      case "bc": return void this.ask(chat, "bc", "📢 اكتب الرسالة التي ستصل لكل اللاعبين:");
      case "find": return void this.ask(chat, "find", "🔎 أرسل اسم اللاعب أو رقمه في تيليجرام:");
      case "ban": return void this.ask(chat, "ban", "🚫 أرسل رقم اللاعب في تيليجرام لحظره:");
      case "unban": return void this.ask(chat, "unban", "✅ أرسل رقم اللاعب لفك حظره:" + (s.banned.size ? "\n\nالمحظورون: " + [...s.banned].map((b) => `<code>${esc(b.replace(/^tg:/, ""))}</code>`).join("، ") : ""));
      case "ton": return void this.ask(chat, "ton", `💰 كم TON لكل قتلة؟ الآن ${ton(s.tonPerKill())}\nمثال: 0.001 (أو «افتراضي» للعودة لإعداد السيرفر)`);
      case "tonx":
        s.tonMultiplier = s.tonMultiplier > 1 ? 1 : 2;
        await s.save();
        return void this.send(chat, s.tonMultiplier > 1 ? "✖️2 مضاعفة TON تعمل الآن لكل القتلى." : "عادت TON لقيمتها العادية.", this.panelButtons());
      case "give": return void this.ask(chat, "give", "🎁 أرسل: رقم اللاعب ثم المبلغ\nمثال: <code>123456789 0.5</code> (سالب للخصم)");
      case "prize": return void this.ask(chat, "prize", `🏅 اكتب نص الجائزة الأسبوعية (الآن: ${esc(s.prizeText() || "لا شيء")}):`);
      case "maint":
        if (s.maintenance) {
          s.maintenance = false;
          await s.save();
          return void this.send(chat, "✅ انتهت الصيانة: اللاعبون يدخلون من جديد.", this.panelButtons());
        }
        return void this.ask(chat, "maint", "🛠 اكتب رسالة الصيانة التي ستظهر للاعبين (لن تُقطع المباريات الجارية):");
      case "logs": {
        const lines = recentProblems.slice(-12).map((l) => {
          try {
            const j = JSON.parse(l) as Json;
            return `• ${String(j.t).slice(11, 19)} ${esc(String(j.msg))}`;
          } catch {
            return "• " + esc(l.slice(0, 80));
          }
        });
        return void this.send(chat, "📝 <b>آخر التحذيرات</b>\n\n" + (lines.join("\n") || "لا شيء: كل شيء سليم."), [[{ text: "⬅️ اللوحة", callback_data: "a:panel" }]]);
      }
      case "restart":
        return void this.send(chat, "🔄 متأكد؟ ستنقطع المباريات الجارية لثوانٍ.", [[{ text: "نعم، أعد التشغيل", callback_data: "a:restart!" }, { text: "إلغاء", callback_data: "a:panel" }]]);
      case "restart!":
        await this.send(chat, "🔄 يعاد التشغيل الآن… عد إلى اللوحة بعد عشر ثوانٍ.");
        log.warn("restart requested from the bot");
        setTimeout(() => process.exit(0), 800); // pm2 starts it again
        return;
    }
  }

  private async live_(chat: number): Promise<void> {
    const z = this.hub.zones.stats();
    const info = this.live();
    const mem = Math.round(process.memoryUsage().rss / 1048576);
    const zones = [...this.hub.zones.zones.values()].map((zone) => {
      const names = [...zone.members.values()].map((m) => esc(m.name)).join("، ");
      const mode = zone.mode === GameMode.INFECTION ? "عدوى" : "زومبي";
      return `• #${zone.id} ${mode} · الموجة ${zone.world.director.wave} · ${zone.size} لاعب: ${names || "—"}`;
    });
    const up = info.uptimeSec;
    await this.send(chat,
      "📊 <b>الحالة الآن</b>\n\n" +
      `🟢 لاعبون: <b>${z.players}</b> · اتصالات: ${info.connections}\n` +
      `🗺 مباريات: ${z.zones} · زومبي أحياء: ${z.zombies}\n` +
      `⚙️ زمن التحديث: ${z.tickMsAvg.toFixed(2)} مللي ث (الأقصى ${z.tickMsMax.toFixed(2)})\n` +
      `💾 الذاكرة: ${mem} MB · يعمل منذ ${Math.floor(up / 3600)} س ${Math.floor((up % 3600) / 60)} د\n` +
      `🏷 الإصدار: ${esc(info.version)}\n\n` + (zones.join("\n") || "لا مباريات الآن."),
      [[{ text: "♻️ تحديث", callback_data: "a:live" }, { text: "⬅️ اللوحة", callback_data: "a:panel" }]]);
  }

  // ------------------------------------------------------------------ statistics (phase 29)

  private async statsPanel(chat: number): Promise<void> {
    const a = await this.hub.analytics();
    await this.send(chat, statsText(a), [[{ text: "♻️ تحديث", callback_data: "a:stats" }, { text: "⬅️ اللوحة", callback_data: "a:panel" }]]);
  }

  // ------------------------------------------------------------------ problem reports (phase 29)

  private ownerChats(): number[] {
    return [...this.hub.owners].map((o) => Number(o.slice(3))).filter((n) => Number.isFinite(n) && n > 0);
  }

  private reportButtons(id: number): Button[][] {
    return [[{ text: "↩️ رد على اللاعب", callback_data: `a:rr:${id}` }],
      [{ text: "✅ تم الحل (أبلغه)", callback_data: `a:rs:${id}` }, { text: "🗑 إغلاق", callback_data: `a:rx:${id}` }]];
  }

  /** A new report from the game: to every owner (with the screenshot), and a
   *  receipt to the player, whose next messages here add details. */
  async onReport(r: ReportRow, shot: Buffer | null): Promise<void> {
    if (!this.env.TELEGRAM_BOT_TOKEN) return;
    const text = reportText(r);
    for (const chat of this.ownerChats()) {
      if (shot) {
        const short = text.length <= 1000;
        if (await this.sendPhoto(chat, shot, short ? text : `🐞 بلاغ #${r.id}`, short ? this.reportButtons(r.id) : undefined)) {
          if (!short) await this.send(chat, text, this.reportButtons(r.id));
          continue;
        }
      }
      await this.send(chat, text, this.reportButtons(r.id));
    }
    const tg = /^tg:(\d+)$/.exec(r.accountId);
    if (!tg) return;
    const chat = Number(tg[1]);
    this.followups.set(chat, { id: r.id, until: Date.now() + FOLLOWUP_MS, left: 10 });
    await this.send(chat, REPORT_TEXT[reportLang(r)].got(r.id));
  }

  private async onFollowup(chat: number, u: TgUser, f: { id: number; until: number; left: number }, text: string): Promise<void> {
    f.left -= 1;
    const r = await this.hub.store.report(f.id);
    if (!r) return;
    const line = text.slice(0, 1000);
    await this.hub.store.noteReport(r.id, "👤 " + line);
    for (const owner of this.ownerChats()) {
      if (owner === chat) continue;
      await this.send(owner, `📝 <b>تفاصيل البلاغ #${r.id}</b> من ${esc(nameOf(u))}:\n\n${esc(line)}`, this.reportButtons(r.id));
    }
    await this.send(chat, REPORT_TEXT[reportLang(r)].added(r.id));
  }

  private async reportList(chat: number): Promise<void> {
    const rows = await this.hub.store.reports(8, true);
    const lines = rows.map((r) => `• <b>#${r.id}</b> ${CATEGORY_AR[REPORT_CATEGORIES[r.category] ?? "other"]} · ${esc(r.name)} · ${ago(r.createdAt)}` +
      (r.notes ? `\n  ${esc(r.notes.split("\n").pop()!.slice(0, 80))}` : ""));
    const buttons: Button[][] = rows.map((r) => [
      { text: `#${r.id} 👁`, callback_data: `a:rv:${r.id}` },
      { text: `#${r.id} ↩️`, callback_data: `a:rr:${r.id}` },
      { text: `#${r.id} ✅`, callback_data: `a:rs:${r.id}` },
      { text: `#${r.id} 🗑`, callback_data: `a:rx:${r.id}` },
    ]);
    buttons.push([{ text: "⬅️ اللوحة", callback_data: "a:panel" }]);
    await this.send(chat, "🐞 <b>البلاغات المفتوحة</b>\n\n" + (lines.join("\n") || "لا بلاغات مفتوحة 🎉"), buttons);
  }

  private async onReportAction(chat: number, what: string, id: number): Promise<void> {
    const r = await this.hub.store.report(id);
    if (!r) return void this.send(chat, "لا يوجد بلاغ بهذا الرقم.");
    if (what === "v") return void this.send(chat, reportText(r), this.reportButtons(id));
    if (what === "r") {
      if (!/^tg:\d+$/.test(r.accountId)) return void this.send(chat, "هذا اللاعب ليس من تيليجرام: لا يمكن الرد عليه.");
      return void this.ask(chat, "rr:" + id, `↩️ اكتب ردك على ${esc(r.name)} (بلاغ #${id}):`);
    }
    const had = await this.hub.store.resolveReport(id);
    if (!had) return void this.send(chat, `البلاغ #${id} مغلق من قبل.`, [[{ text: "🐞 البلاغات", callback_data: "a:reports" }]]);
    const tg = /^tg:(\d+)$/.exec(r.accountId);
    if (what === "s" && tg) await this.send(Number(tg[1]), REPORT_TEXT[reportLang(r)].fixed(id));
    await this.send(chat, what === "s" ? `✅ البلاغ #${id} حُل وأُبلغ اللاعب.` : `🗑 أُغلق البلاغ #${id}.`, [[{ text: "🐞 البلاغات", callback_data: "a:reports" }]]);
  }

  private async sendPhoto(chatId: number, photo: Buffer, caption: string, buttons?: Button[][]): Promise<boolean> {
    for (const method of ["sendPhoto", "sendDocument"]) {
      try {
        const form = new FormData();
        form.set("chat_id", String(chatId));
        form.set("caption", caption);
        form.set("parse_mode", "HTML");
        if (buttons) form.set("reply_markup", JSON.stringify({ inline_keyboard: buttons }));
        form.set(method === "sendPhoto" ? "photo" : "document", new Blob([new Uint8Array(photo)], { type: "image/webp" }), "screen.webp");
        const res = await fetch(`${this.apiBase}/bot${this.env.TELEGRAM_BOT_TOKEN}/${method}`, { method: "POST", body: form, signal: AbortSignal.timeout(20_000) });
        const j = (await res.json()) as { ok: boolean; description?: string };
        if (j.ok) return true;
        log.warn("report screenshot refused", { method, error: j.description });
      } catch (err) {
        log.warn("report screenshot failed", { method, error: (err as Error).message });
      }
    }
    return false;
  }

  private async onAdminInput(chat: number, action: string, text: string): Promise<void> {
    const s = this.hub.settings;
    if (action.startsWith("rr:")) {
      const r = await this.hub.store.report(Number(action.slice(3)));
      const tg = r ? /^tg:(\d+)$/.exec(r.accountId) : null;
      if (!r || !tg) return void this.send(chat, "لا يوجد بلاغ بهذا الرقم.");
      const reply = text.slice(0, 2000);
      await this.hub.store.noteReport(r.id, "🛠 " + reply);
      const ok = await this.api("sendMessage", { chat_id: Number(tg[1]), text: REPORT_TEXT[reportLang(r)].reply(r.id, esc(reply)), parse_mode: "HTML" })
        .then((x) => x.ok).catch(() => false);
      if (ok) this.followups.set(Number(tg[1]), { id: r.id, until: Date.now() + FOLLOWUP_MS, left: 10 });
      return void this.send(chat, ok ? `📩 وصل ردك إلى ${esc(r.name)}.` : "لم يصل الرد: اللاعب لم يبدأ محادثة مع البوت أو حظره.", this.reportButtons(r.id));
    }
    const accountOf = (v: string) => (/^\d+$/.test(v) ? "tg:" + v : v);
    switch (action) {
      case "bc": {
        const ids = await this.hub.store.telegramIds(20_000);
        await this.send(chat, `📢 يرسل إلى ${ids.length} لاعب…`);
        let ok = 0;
        for (const id of ids) {
          const r = await this.api("sendMessage", { chat_id: Number(id.slice(3)), text: "📢 " + text }).catch(() => ({ ok: false }));
          if (r.ok) ok += 1;
          await new Promise((res) => setTimeout(res, 40)); // Telegram allows about 30 messages a second
        }
        return void this.send(chat, `✅ وصلت الرسالة إلى ${ok} من ${ids.length} (الباقون لم يبدؤوا محادثة مع البوت).`, this.panelButtons());
      }
      case "find": {
        const found = await this.hub.store.find(text.trim(), 8);
        const lines = found.map((f) => {
          const online = this.hub.byAccount.get(f.accountId)?.zone ? " 🟢" : "";
          const banned = s.banned.has(f.accountId) ? " 🚫" : "";
          return `• <b>${esc(f.name)}</b>${online}${banned} <code>${esc(f.accountId.replace(/^tg:/, ""))}</code>\n  قتلى ${f.profile.kills} · أعلى موجة ${f.profile.bestWave} · مباريات ${f.profile.games} · TON ${ton(f.profile.tonMicro)}`;
        });
        return void this.send(chat, "🔎 <b>النتائج</b>\n\n" + (lines.join("\n") || "لا أحد بهذا الاسم أو الرقم."), [[{ text: "⬅️ اللوحة", callback_data: "a:panel" }]]);
      }
      case "ban": {
        const id = accountOf(text.trim());
        if (this.hub.isOwner(id)) return void this.send(chat, "لا يمكن حظر صاحب اللعبة.");
        s.banned.add(id);
        await s.save();
        this.hub.byAccount.get(id)?.kick("this account is banned");
        return void this.send(chat, `🚫 حُظر <code>${esc(id)}</code> وأُخرج من اللعبة.`, this.panelButtons());
      }
      case "unban": {
        const id = accountOf(text.trim());
        const had = s.banned.delete(id);
        await s.save();
        return void this.send(chat, had ? `✅ فُك حظر <code>${esc(id)}</code>.` : "هذا الرقم ليس محظوراً.", this.panelButtons());
      }
      case "ton": {
        if (/^(افتراضي|default)$/i.test(text.trim())) {
          s.tonPerKillOverride = null;
        } else {
          const v = Number(text.trim().replace(",", "."));
          if (!Number.isFinite(v) || v < 0 || v > 100) return void this.send(chat, "رقم غير صالح. مثال: 0.001");
          s.tonPerKillOverride = Math.round(v * 1_000_000);
        }
        await s.save();
        return void this.send(chat, `💰 TON لكل قتلة الآن: ${ton(s.tonPerKill())}`, this.panelButtons());
      }
      case "give": {
        const [who = "", amount = ""] = text.trim().split(/\s+/);
        const v = Number(amount.replace(",", "."));
        if (!who || !Number.isFinite(v) || Math.abs(v) > 1000) return void this.send(chat, "الصيغة: رقم_اللاعب المبلغ (مثال: 123456789 0.5)");
        const p = await this.hub.store.addTon(accountOf(who), Math.round(v * 1_000_000));
        if (!p) return void this.send(chat, "لا يوجد لاعب بهذا الرقم.");
        const session = this.hub.byAccount.get(accountOf(who));
        if (session) session.onProfile(p, await this.hub.store.weekly(accountOf(who)));
        return void this.send(chat, `🎁 تم. رصيد اللاعب الآن ${ton(p.tonMicro)} TON.`, this.panelButtons());
      }
      case "prize":
        s.prizeOverride = text.slice(0, 200);
        await s.save();
        return void this.send(chat, "🏅 حُفظ نص الجائزة.", this.panelButtons());
      case "maint":
        s.maintenance = true;
        s.maintenanceText = text.slice(0, 200);
        await s.save();
        return void this.send(chat, "🛠 الصيانة تعمل: لا مباريات جديدة (عدا لك). المباريات الجارية تكمل.", this.panelButtons());
    }
  }
}

// ------------------------------------------------------------------ texts (phase 29)

function reportLang(r: ReportRow): ReportLang {
  const l = String((r.info.client as { lang?: string } | undefined)?.lang ?? "");
  return l === "en" || l === "ru" ? l : "ar";
}

function ago(at: Date): string {
  const m = Math.max(0, Math.round((Date.now() - at.getTime()) / 60_000));
  if (m < 60) return `قبل ${m} د`;
  if (m < 48 * 60) return `قبل ${Math.round(m / 60)} س`;
  return `قبل ${Math.round(m / 1440)} يوم`;
}

/** One report as the owner reads it. */
export function reportText(r: ReportRow): string {
  const i = r.info as {
    where?: string; fps?: number; shot?: boolean; level?: number; games?: number;
    client?: { platform?: string; tgVersion?: string; lang?: string; build?: string; screen?: string };
    details?: Record<string, string | number | boolean>;
    zone?: { id: number; mode: string; wave: number; players: number; state: string } | null;
  };
  const c = i.client ?? {};
  const tg = /^tg:(\d+)$/.exec(r.accountId);
  const lines = [
    `🐞 <b>بلاغ #${r.id}</b> · ${CATEGORY_AR[REPORT_CATEGORIES[r.category] ?? "other"]}${r.resolved ? " · ✅ مغلق" : ""}`,
    `👤 ${esc(r.name)} (<code>${esc(tg ? tg[1]! : r.accountId)}</code>) · المستوى ${i.level ?? 1} · ${i.games ?? 0} مباراة`,
    `📍 ${esc(i.where || "؟")}` + (i.zone ? ` · مباراة #${i.zone.id} ${i.zone.mode === "INFECTION" ? "عدوى" : "زومبي"} · الموجة ${i.zone.wave} · ${i.zone.players} لاعب` : " · خارج المباريات"),
    `📱 ${esc(PLATFORMS_AR[c.platform ?? ""] ?? c.platform ?? "؟")} (${esc(c.platform || "؟")}) · تيليجرام ${esc(c.tgVersion || "؟")} · ${esc(c.screen || "؟")} · ${esc(LANGS_AR[c.lang ?? ""] ?? "؟")}`,
    `🎮 FPS ${i.fps ?? 0}` + Object.entries(i.details ?? {}).map(([k, v]) => ` · ${esc(k)} ${esc(String(v))}`).join(""),
    `🏷 ${esc(c.build || "?")} · ${r.createdAt.toISOString().slice(0, 16).replace("T", " ")} UTC`,
  ];
  if (r.notes) lines.push("", "💬 " + esc(r.notes).slice(0, 1500));
  return lines.join("\n");
}

const bar = (n: number, max: number) => "▇".repeat(max ? Math.round((8 * n) / max) : 0) || "▏";

/** The statistics page of the owner's panel. */
export function statsText(a: Analytics): string {
  const t = a.days[a.days.length - 1]!;
  const y = a.days[a.days.length - 2]!;
  const per = (sec: number, n: number) => (n ? mins(sec / n) : "—");
  const maxActive = Math.max(...a.days.map((d) => d.active));
  const dayName = (day: string) => WEEKDAYS_AR[new Date(day + "T00:00:00Z").getUTCDay()]!;
  const f = a.funnel;
  const share = (n: number) => (f.fresh ? ` (${Math.round((100 * n) / f.fresh)}%)` : "");
  const players = a.devices.reduce((s, d) => s + d.players, 0);
  const langTotal = a.langs.reduce((s, l) => s + l.players, 0);
  return [
    "📈 <b>إحصائيات اللعبة</b> <i>(بتوقيت UTC)</i>",
    "",
    `<b>اليوم:</b> 👥 ${t.active} نشط · 🆕 ${t.fresh} جديد · 🕹 ${t.games} مباراة · ⏱ ${per(t.seconds, t.active)} للاعب`,
    `<b>أمس:</b> 👥 ${y.active} نشط · 🆕 ${y.fresh} جديد · 🕹 ${y.games} مباراة · ⏱ ${per(y.seconds, y.active)} للاعب`,
    `<b>آخر 7 أيام:</b> 👥 ${a.week.active} لاعب مختلف · 🆕 ${a.week.fresh} جديد · 🕹 ${a.week.games} مباراة`,
    "",
    "📅 <b>النشطون كل يوم</b>",
    ...a.days.map((d) => `<code>${d.day.slice(5)}</code> ${dayName(d.day)}: ${bar(d.active, maxActive)} ${d.active}`),
    "",
    "🔁 <b>هل يعودون؟</b>",
    `• رجعوا في اليوم التالي: <b>${pct(a.nextDay)}</b> (${a.nextDay.n} من ${a.nextDay.of} جديد)`,
    `• رجعوا خلال أسبوع: <b>${pct(a.withinWeek)}</b> (${a.withinWeek.n} من ${a.withinWeek.of} جديد)`,
    "",
    `🪜 <b>أين يتوقف الجدد</b> (آخر 7 أيام)`,
    `• فتحوا اللعبة: ${f.fresh}`,
    `• لعبوا مباراة واحدة على الأقل: ${f.played}${share(f.played)}`,
    `• وصلوا الموجة 3: ${f.wave3}${share(f.wave3)}`,
    `• لعبوا 3 مباريات: ${f.games3}${share(f.games3)}`,
    `• رجعوا في يوم آخر: ${f.returned}${share(f.returned)}`,
    "",
    "📱 <b>الأجهزة</b> (آخر 7 أيام)",
    ...(a.devices.length
      ? a.devices.map((d) => `• ${PLATFORMS_AR[d.platform] ?? d.platform}: ${Math.round((100 * d.players) / Math.max(1, players))}% (${d.players})` + (d.fps ? ` · متوسط ${d.fps} FPS` : ""))
      : ["• لا بيانات بعد"]),
    `🐢 أجهزة تحت 25 FPS: ${a.slow.n} من ${a.slow.of} (${pct(a.slow)})`,
    "🌐 اللغات: " + (a.langs.map((l) => `${LANGS_AR[l.lang] ?? l.lang} ${Math.round((100 * l.players) / Math.max(1, langTotal))}%`).join(" · ") || "—"),
  ].join("\n");
}
