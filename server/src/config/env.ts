import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

const here = path.dirname(fileURLToPath(import.meta.url));
// src/config -> server -> repo root (also valid from dist/config).
const defaultSharedDir = path.resolve(here, "../../../shared");

const EnvSchema = z.object({
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  HOST: z.string().default("127.0.0.1"),
  PORT: z.coerce.number().int().min(1).max(65535).default(8787),
  PUBLIC_BASE_PATH: z.string().default("/"),
  WS_PATH: z.string().default("/ws"),
  SHARED_DIR: z.string().default(defaultSharedDir),
  CLIENT_DIST_DIR: z.string().optional(),
  DATABASE_URL: z.string().optional(),
  TELEGRAM_BOT_TOKEN: z.string().optional(),
  /** The bot's @username for invite links (t.me/<bot>?startapp=...). Unset: asked from Telegram (getMe) at start. */
  TELEGRAM_BOT_USERNAME: z.string().regex(/^[A-Za-z0-9_]{0,64}$/).default(""),
  TELEGRAM_INIT_DATA_MAX_AGE_SEC: z.coerce.number().int().positive().default(86400),
  ALLOW_DEV_AUTH: z
    .enum(["0", "1", "true", "false"])
    .default("0")
    .transform((v) => v === "1" || v === "true"),
  LOG_LEVEL: z.enum(["debug", "info", "warn", "error"]).default("info"),
  /** TON points per zombie kill, in millionths of a TON (1000 = 0.001 TON). 0 disables. */
  TON_MICRO_PER_KILL: z.coerce.number().int().nonnegative().default(1000),
  /** Shown on the weekly leaderboard, e.g. "1 TON for the week's top hunter". */
  TON_PRIZE_TEXT: z.string().max(200).default(""),
  /** opens the encrypted puzzle module (phase 31); usually given through the bot instead */
  PUZZLE_KEY: z.string().default(""),
  /** TON points (millionths) for each player who solves the five puzzles; the bot can change it */
  PUZZLE_TON_MICRO: z.coerce.number().int().nonnegative().default(1_000_000),
  /** Voice chat relay (phase 12). 0 switches it off for every player. */
  VOICE_CHAT: z
    .enum(["0", "1", "true", "false"])
    .default("1")
    .transform((v) => v === "1" || v === "true"),
  /** Telegram user ids of the game's owners (comma separated): the bot's /admin panel and in-game dev powers. */
  ADMIN_TELEGRAM_IDS: z.string().regex(/^[0-9, ]*$/).default(""),
  /** The bot answers messages by long polling Telegram (0 = off, e.g. when another program owns the bot). */
  BOT_POLLING: z
    .enum(["0", "1", "true", "false"])
    .default("1")
    .transform((v) => v === "1" || v === "true"),
  /** Public host of the game (written by the installer); the bot's Play button opens https://<it>/. */
  BLACKOFF_DOMAIN: z.string().default(""),
  /** Full game URL when it is not https://BLACKOFF_DOMAIN/. */
  GAME_URL: z.string().default(""),
  /** Result cards (phase 25): where the JPEGs are written ("" = web/cards of a release) and their public URL ("" = GAME_URL or the domain + cards/). */
  CARDS_DIR: z.string().default(""),
  CARD_BASE_URL: z.string().default(""),
  /** Protects /admin/* (leaderboard with account ids, suspects). Unset = endpoints off. */
  ADMIN_TOKEN: z.string().optional(),
});

export type Env = z.infer<typeof EnvSchema>;

/**
 * Fills keys missing from `target` with the release's defaults file
 * (deploy/owner.env next to server/ in a release, or in the repository):
 * values the owner never has to type into .env, such as their Telegram id.
 */
export function applyDefaultsFile(target: NodeJS.ProcessEnv = process.env): string | null {
  const candidates = [
    target.BLACKOFF_DEFAULTS_FILE ?? "",
    path.resolve(here, "../deploy/owner.env"),      // release: server/server.mjs
    path.resolve(here, "../../../deploy/owner.env"), // repository: server/src/config or dist/config
  ].filter(Boolean);
  for (const file of candidates) {
    if (!fs.existsSync(file)) continue;
    for (const line of fs.readFileSync(file, "utf8").split("\n")) {
      const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
      if (m && !line.trimStart().startsWith("#") && target[m[1]!] === undefined) target[m[1]!] = m[2]!;
    }
    return file;
  }
  return null;
}

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = EnvSchema.safeParse(source);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new Error(`Invalid environment: ${issues}`);
  }
  const env = parsed.data;
  if (env.NODE_ENV === "production" && env.ALLOW_DEV_AUTH) {
    throw new Error("ALLOW_DEV_AUTH must not be enabled in production");
  }
  return env;
}
