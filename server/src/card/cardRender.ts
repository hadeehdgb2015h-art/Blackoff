/**
 * The shareable result card (phase 25): a 1080 x 1350 JPEG drawn from the
 * server's own record of the game, never from anything the client sends.
 *
 * The background (the game's soldier and two of the dead against a blood
 * moon) is rendered once in Blender (art/blender/build_logo.py --card); the
 * text is an SVG laid over it and rasterised by resvg (WebAssembly, with the
 * game's fonts: Cinzel, Reem Kufi and Cairo for Arabic, Forum for Cyrillic),
 * then encoded with jpeg-js. About half a second of CPU, so the service runs
 * it in a worker thread.
 */
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { initWasm, Resvg } from "@resvg/resvg-wasm";
import jpeg from "jpeg-js";

export const CARD_W = 1080;
export const CARD_H = 1350;

export type CardLang = "en" | "ar" | "ru";

export interface CardInput {
  lang: CardLang;
  name: string;
  /** 0 zombies (co-op), 1 infection */
  mode: number;
  wave: number;
  kills: number;
  headshots: number;
  seconds: number;
  bestWave: number;
  /** the bot's @username for the footer ("" = no footer handle) */
  bot: string;
  /** the player's level and rank id (phase 26) */
  level: number;
  rank: string;
}

type CardText = Record<"zombies" | "infection" | "wave" | "kills" | "headshots" | "survived" | "best" | "challenge" | "play" | "level", string>;

const TEXT: Record<CardLang, CardText> = {
  en: {
    zombies: "ZOMBIES  ·  CO-OP", infection: "INFECTION", wave: "WAVE", kills: "KILLS", headshots: "HEADSHOTS",
    survived: "SURVIVED", best: "BEST WAVE", challenge: "Can you beat me?", play: "Play free in Telegram", level: "LEVEL",
  },
  ar: {
    zombies: "نجاة جماعية من الزومبي", infection: "العدوى", wave: "الموجة", kills: "القتلات", headshots: "في الرأس",
    survived: "مدة الصمود", best: "أفضل موجة", challenge: "هل تستطيع التفوّق عليّ؟", play: "العب مجاناً في تيليجرام", level: "المستوى",
  },
  ru: {
    zombies: "ЗОМБИ  ·  КООП", infection: "ЗАРАЖЕНИЕ", wave: "ВОЛНА", kills: "УБИЙСТВА", headshots: "В ГОЛОВУ",
    survived: "ВРЕМЯ", best: "ЛУЧШАЯ ВОЛНА", challenge: "Сможешь лучше?", play: "Играй бесплатно в Telegram", level: "УРОВЕНЬ",
  },
};

/** Rank names (phase 26, ids from shared constants.progression.ranks). */
export const RANK_NAMES: Record<CardLang, Record<string, string>> = {
  en: {
    recruit: "Recruit", private: "Private", corporal: "Corporal", sergeant: "Sergeant", staff_sergeant: "Staff Sergeant",
    master_sergeant: "Master Sergeant", lieutenant: "Lieutenant", captain: "Captain", major: "Major", colonel: "Colonel",
    general: "General", warden_slayer: "Warden Slayer", legend: "Legend",
  },
  ar: {
    recruit: "مجنَّد", private: "جندي", corporal: "عريف", sergeant: "رقيب", staff_sergeant: "رقيب أول",
    master_sergeant: "رئيس رقباء", lieutenant: "ملازم", captain: "نقيب", major: "رائد", colonel: "عقيد",
    general: "لواء", warden_slayer: "قاهر الحارس", legend: "أسطورة",
  },
  ru: {
    recruit: "Новобранец", private: "Рядовой", corporal: "Капрал", sergeant: "Сержант", staff_sergeant: "Штаб-сержант",
    master_sergeant: "Мастер-сержант", lieutenant: "Лейтенант", captain: "Капитан", major: "Майор", colonel: "Полковник",
    general: "Генерал", warden_slayer: "Убийца Надзирателя", legend: "Легенда",
  },
};

/** Display face per language: Cinzel first (Latin, digits, "·", the @handle), the
 *  script's own face for the letters Cinzel lacks. */
const DISPLAY: Record<CardLang, string> = { en: "Cinzel", ar: "Cinzel, Reem Kufi", ru: "Cinzel, Forum" };
/** Small text in the language's own script. resvg picks one font per text
 *  element (Arabic mixed with Latin in one element shows boxes, and tspans in
 *  other fonts are dropped), so lines are kept to one script each. */
const SMALL: Record<CardLang, string> = { en: "Cinzel", ar: "Cairo", ru: "Cinzel, Forum" };
const BODY = "Cinzel, Cairo, Forum";

const esc = (s: string): string =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" })[c]!);

/** A name safe to draw: no control characters, at most 24 characters. */
export function cardName(name: string): string {
  const clean = [...name.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069]/g, "").trim()];
  return clean.length > 24 ? clean.slice(0, 23).join("") + "…" : clean.join("") || "?";
}

export function clock(seconds: number): string {
  const s = Math.max(0, Math.round(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = String(s % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
}

/** The text layer, laid over the background image. */
export function cardSvg(c: CardInput, background: string): string {
  const t = TEXT[c.lang] ?? TEXT.en;
  const rtl = c.lang === "ar" ? ` direction="rtl"` : "";
  const disp = DISPLAY[c.lang] ?? DISPLAY.en;
  const infection = c.mode === 1;
  const bigLabel = infection ? t.kills : t.wave;
  const bigValue = infection ? c.kills : c.wave;
  const stats: [string, string][] = infection
    ? [[t.headshots, String(c.headshots)], [t.survived, clock(c.seconds)], [t.best, String(c.bestWave)]]
    : [[t.kills, String(c.kills)], [t.headshots, String(c.headshots)], [t.survived, clock(c.seconds)]];
  const cols = c.lang === "ar" ? [870, 540, 210] : [210, 540, 870]; // Arabic reads right to left
  const small = SMALL[c.lang] ?? SMALL.en;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${CARD_W}" height="${CARD_H}" viewBox="0 0 ${CARD_W} ${CARD_H}">
  <defs>
    <linearGradient id="top" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#050304" stop-opacity="0.92"/>
      <stop offset="1" stop-color="#050304" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="bottom" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#050304" stop-opacity="0"/>
      <stop offset="0.35" stop-color="#050304" stop-opacity="0.85"/>
      <stop offset="1" stop-color="#030203" stop-opacity="1"/>
    </linearGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffd98a"/>
      <stop offset="1" stop-color="#c8862e"/>
    </linearGradient>
  </defs>
  <image href="${background}" x="0" y="0" width="${CARD_W}" height="${CARD_H}"/>
  <rect x="0" y="0" width="${CARD_W}" height="250" fill="url(#top)"/>
  <rect x="0" y="760" width="${CARD_W}" height="${CARD_H - 760}" fill="url(#bottom)"/>
  <rect x="22" y="22" width="${CARD_W - 44}" height="${CARD_H - 44}" rx="8" fill="none" stroke="#b08a45" stroke-opacity="0.55" stroke-width="2"/>
  <rect x="32" y="32" width="${CARD_W - 64}" height="${CARD_H - 64}" rx="6" fill="none" stroke="#b08a45" stroke-opacity="0.22" stroke-width="1"/>

  <text x="540" y="128" font-family="Cinzel" font-size="96" letter-spacing="10" fill="url(#gold)" text-anchor="middle">BLACK OFF</text>
  <line x1="300" y1="160" x2="470" y2="160" stroke="#b08a45" stroke-opacity="0.7" stroke-width="2"/>
  <line x1="610" y1="160" x2="780" y2="160" stroke="#b08a45" stroke-opacity="0.7" stroke-width="2"/>
  <rect x="533" y="153" width="14" height="14" transform="rotate(45 540 160)" fill="#c9a050"/>
  <text x="540" y="206" font-family="${small}" font-size="30" letter-spacing="${c.lang === "ar" ? 0 : 4}" fill="#cdb48a" text-anchor="middle"${rtl}>${esc(infection ? t.infection : t.zombies)}</text>

  <text x="540" y="910" font-family="${BODY}" font-size="52" fill="#efe8da" text-anchor="middle">${esc(cardName(c.name))}</text>
  <text x="540" y="952" font-family="${small}" font-size="26" letter-spacing="${c.lang === "ar" ? 0 : 3}" fill="#bfa77a" text-anchor="middle"${rtl}>${esc(levelLine(c, t))}</text>
  <text x="540" y="994" font-family="${disp}" font-size="30" letter-spacing="${c.lang === "ar" ? 0 : 6}" fill="#c9a050" text-anchor="middle"${rtl}>${esc(bigLabel)}</text>
  <text x="540" y="1116" font-family="Cinzel" font-size="126" fill="url(#gold)" text-anchor="middle">${bigValue}</text>
  <line x1="120" y1="1140" x2="960" y2="1140" stroke="#b08a45" stroke-opacity="0.45" stroke-width="1.5"/>
${stats.map(([label, value], i) => `  <text x="${cols[i]}" y="1200" font-family="Cinzel" font-size="56" fill="#f2ead8" text-anchor="middle">${esc(value)}</text>
  <text x="${cols[i]}" y="1236" font-family="${small}" font-size="24" letter-spacing="${c.lang === "ar" ? 0 : 2}" fill="#a8977a" text-anchor="middle"${rtl}>${esc(label)}</text>`).join("\n")}
  <text x="540" y="1278" font-family="${small}" font-size="26" fill="#d9a85a" text-anchor="middle"${rtl}>${esc(t.challenge + "  " + t.play)}</text>
${c.bot ? `  <text x="540" y="1308" font-family="Cinzel" font-size="24" letter-spacing="2" fill="#c9a050" text-anchor="middle">@${esc(c.bot)}</text>` : ""}
</svg>`;
}

/** The card for Telegram (JPEG, full size) and a small PNG preview for the game,
 *  whose web engine has no JPEG decoder. */
export interface CardImages { jpg: Buffer; png: Buffer }

export const PREVIEW_W = 432;

/** "LEVEL 12 · SERGEANT", Arabic "رقيب ، المستوى ١٢". */
function levelLine(c: CardInput, t: CardText): string {
  const rank = (RANK_NAMES[c.lang] ?? RANK_NAMES.en)[c.rank] ?? RANK_NAMES.en[c.rank] ?? "";
  const name = c.lang === "en" ? rank.toUpperCase() : c.lang === "ru" ? rank.toUpperCase() : rank;
  if (c.lang === "ar") {
    // one Arabic run: Arabic-Indic digits and the Arabic comma (the Arabic face has no Latin ones)
    const digits = String(c.level).replace(/[0-9]/g, (d) => String.fromCharCode(0x0660 + Number(d)));
    return `${name} ، ${t.level} ${digits}`;
  }
  return `${t.level} ${c.level}  ·  ${name}`;
}

export interface CardRenderer {
  render(c: CardInput): CardImages;
}

/** Where the card's background and fonts live: next to the bundle in a release
 *  (server/assets), or server/assets in the source tree. */
export function assetsDir(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  for (const d of [process.env.CARD_ASSETS_DIR ?? "", path.join(here, "assets"), path.join(here, "..", "..", "assets")]) {
    if (d && fs.existsSync(path.join(d, "card", "card_bg.jpg"))) return d;
  }
  throw new Error("card assets not found");
}

function wasmPath(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const bundled = path.join(here, "resvg.wasm");
  if (fs.existsSync(bundled)) return bundled;
  return createRequire(import.meta.url).resolve("@resvg/resvg-wasm/index_bg.wasm");
}

let wasmReady: Promise<void> | null = null;

export async function loadRenderer(dir = assetsDir()): Promise<CardRenderer> {
  wasmReady ??= initWasm(fs.readFileSync(wasmPath()));
  await wasmReady;
  const fontDir = path.join(dir, "fonts");
  const fonts = fs.readdirSync(fontDir).filter((f) => f.endsWith(".ttf")).map((f) => fs.readFileSync(path.join(fontDir, f)));
  const background = "data:image/jpeg;base64," + fs.readFileSync(path.join(dir, "card", "card_bg.jpg")).toString("base64");
  return {
    render(c: CardInput): CardImages {
      const svg = cardSvg(c, background);
      const font = { fontBuffers: fonts, loadSystemFonts: false, defaultFontFamily: "Cinzel" };
      const r = new Resvg(svg, { font });
      const img = r.render();
      const out = jpeg.encode({ data: img.pixels, width: img.width, height: img.height }, 86);
      img.free();
      r.free();
      const small = new Resvg(svg, { font, fitTo: { mode: "width", value: PREVIEW_W } });
      const prev = small.render();
      const png = Buffer.from(prev.asPng());
      prev.free();
      small.free();
      return { jpg: Buffer.from(out.data), png };
    },
  };
}
