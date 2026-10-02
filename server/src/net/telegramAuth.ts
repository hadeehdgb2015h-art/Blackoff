/**
 * Telegram Mini App initData validation (server only; the client never decides
 * identity). https://core.telegram.org/bots/webapps#validating-data-received-via-the-mini-app
 *   secret = HMAC_SHA256(key="WebAppData", msg=botToken)
 *   hash   = hex(HMAC_SHA256(key=secret, msg=data_check_string))
 * data_check_string = all fields except `hash`, as key=value sorted by key, joined by \n.
 */
import crypto from "node:crypto";

export interface TelegramUser {
  id: string;
  name: string;
  username?: string;
}

export type AuthResult = { ok: true; user: TelegramUser } | { ok: false; reason: string };

export function validateInitData(initData: string, botToken: string, maxAgeSec: number, nowSec = Date.now() / 1000): AuthResult {
  if (!initData || initData.length > 4096) return { ok: false, reason: "empty or oversized initData" };
  const params = new URLSearchParams(initData);
  const hash = params.get("hash");
  if (!hash || !/^[0-9a-f]{64}$/.test(hash)) return { ok: false, reason: "missing hash" };
  params.delete("hash");
  const check = [...params.entries()]
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`)
    .join("\n");
  const secret = crypto.createHmac("sha256", "WebAppData").update(botToken).digest();
  const expected = crypto.createHmac("sha256", secret).update(check).digest();
  if (!crypto.timingSafeEqual(expected, Buffer.from(hash, "hex"))) return { ok: false, reason: "bad hash" };
  const authDate = Number(params.get("auth_date"));
  if (!Number.isFinite(authDate) || nowSec - authDate > maxAgeSec || authDate - nowSec > 300) {
    return { ok: false, reason: "expired" };
  }
  let user: { id?: unknown; first_name?: unknown; last_name?: unknown; username?: unknown };
  try {
    user = JSON.parse(params.get("user") ?? "");
  } catch {
    return { ok: false, reason: "bad user field" };
  }
  if (typeof user.id !== "number" && typeof user.id !== "string") return { ok: false, reason: "no user id" };
  const full = [user.first_name, user.last_name].filter((s) => typeof s === "string" && s).join(" ");
  const username = typeof user.username === "string" ? user.username : undefined;
  return { ok: true, user: { id: String(user.id), name: cleanName(full || username || "Player"), username } };
}

/** Display names: printable, single line, at most 24 characters. */
export function cleanName(s: string): string {
  const cleaned = s.replace(/[\p{C}]/gu, "").replace(/\s+/g, " ").trim();
  return [...cleaned].slice(0, 24).join("") || "Player";
}

/** Test helper: signs initData the way Telegram does. */
export function signInitData(fields: Record<string, string>, botToken: string): string {
  const check = Object.keys(fields).sort().map((k) => `${k}=${fields[k]}`).join("\n");
  const secret = crypto.createHmac("sha256", "WebAppData").update(botToken).digest();
  const hash = crypto.createHmac("sha256", secret).update(check).digest("hex");
  return new URLSearchParams({ ...fields, hash }).toString();
}
