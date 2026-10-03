/**
 * Problem reports from the game (phase 29). A player taps REPORT A PROBLEM,
 * picks what went wrong, and the game sends an optional screenshot (WebP, in
 * parts that fit the message size limit) and a short description of its own
 * settings. The server adds what it knows itself (zone, wave, players, ping is
 * not needed), stores the report and the bot sends it to the owners; the
 * player can add details by writing to the bot, and the owner can answer.
 * Nothing the client sends here is trusted for play: it is only shown.
 */

export const REPORT_CATEGORIES = ["lag", "controls", "connection", "sound", "visual", "other"] as const;
export const MAX_SHOT_PARTS = 12;
export const MAX_SHOT_PART_BYTES = 3900;
export const MAX_SHOT_BYTES = 46_000;
/** one report a minute, ten a day per account */
export const REPORT_GAP_MS = 60_000;
export const REPORTS_PER_DAY = 10;

/** What the game says about the device it runs on (clientInfo). */
export interface ClientInfo { platform: string; tgVersion: string; lang: string; build: string; screen: string }

const clean = (v: unknown, max = 32) => String(v ?? "").replace(/[^\w.\-x: ]/g, "").slice(0, max);

export function cleanClientInfo(m: Record<string, unknown>): ClientInfo {
  const lang = clean(m.lang, 8);
  return {
    platform: clean(m.platform, 16).toLowerCase(),
    tgVersion: clean(m.tgVersion, 12),
    lang: ["ar", "en", "ru"].includes(lang) ? lang : "",
    build: clean(m.build, 40),
    screen: clean(m.screen, 16),
  };
}

/** The client's description of its settings: a small flat JSON object of short
 *  strings, numbers and booleans; anything else is dropped. */
export function cleanDetails(text: string): Record<string, string | number | boolean> {
  const out: Record<string, string | number | boolean> = {};
  let j: unknown;
  try {
    j = JSON.parse(text.slice(0, 2000));
  } catch {
    return out;
  }
  if (!j || typeof j !== "object" || Array.isArray(j)) return out;
  for (const [k, v] of Object.entries(j as Record<string, unknown>).slice(0, 20)) {
    const key = clean(k, 24);
    if (!key) continue;
    if (typeof v === "number" && Number.isFinite(v)) out[key] = Math.round(v * 100) / 100;
    else if (typeof v === "boolean") out[key] = v;
    else if (typeof v === "string") out[key] = v.replace(/[<>&\u0000-\u001f]/g, "").slice(0, 60);
  }
  return out;
}

/** A WebP file: "RIFF" size "WEBP". */
export function isWebp(b: Buffer): boolean {
  return b.length > 16 && b.toString("latin1", 0, 4) === "RIFF" && b.toString("latin1", 8, 12) === "WEBP";
}

/** Collects the parts of one screenshot. */
export class ShotBuffer {
  private parts: (Buffer | undefined)[] = [];
  private bytes = 0;
  private startedAt = 0;

  /** false when the part is not acceptable (the screenshot is then dropped) */
  add(part: number, total: number, data: Uint8Array, now = Date.now()): boolean {
    if (total < 1 || total > MAX_SHOT_PARTS || part >= total || data.length === 0 || data.length > MAX_SHOT_PART_BYTES) return this.drop();
    if (part === 0 || this.parts.length !== total || now - this.startedAt > 60_000) {
      this.parts = new Array<Buffer | undefined>(total);
      this.bytes = 0;
      this.startedAt = now;
    }
    if (this.parts[part]) this.bytes -= this.parts[part]!.length;
    this.parts[part] = Buffer.from(data);
    this.bytes += data.length;
    if (this.bytes > MAX_SHOT_BYTES) return this.drop();
    return true;
  }

  /** The whole screenshot when every part arrived and it is a WebP; empties the buffer. */
  take(now = Date.now()): Buffer | null {
    const parts = this.parts;
    const fresh = now - this.startedAt <= 60_000;
    this.drop();
    if (!fresh || parts.length === 0) return null;
    for (let i = 0; i < parts.length; i++) if (!parts[i]) return null; // holes: some() would skip them
    const b = Buffer.concat(parts as Buffer[]);
    return isWebp(b) ? b : null;
  }

  private drop(): false {
    this.parts = [];
    this.bytes = 0;
    return false;
  }
}

/** One report a minute and ten a day per account. */
export class ReportLimiter {
  private readonly seen = new Map<string, { at: number; day: string; n: number }>();

  take(accountId: string, now = Date.now()): boolean {
    const day = new Date(now).toISOString().slice(0, 10);
    const s = this.seen.get(accountId);
    if (s && now - s.at < REPORT_GAP_MS) return false;
    const n = s && s.day === day ? s.n : 0;
    if (n >= REPORTS_PER_DAY) return false;
    this.seen.set(accountId, { at: now, day, n: n + 1 });
    if (this.seen.size > 10_000) this.seen.delete(this.seen.keys().next().value!);
    return true;
  }
}
