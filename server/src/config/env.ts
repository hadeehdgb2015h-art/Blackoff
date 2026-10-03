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
  /** Voice chat relay (phase 12). 0 switches it off for every player. */
  VOICE_CHAT: z
    .enum(["0", "1", "true", "false"])
    .default("1")
    .transform((v) => v === "1" || v === "true"),
  /** Protects /admin/* (leaderboard with account ids, suspects). Unset = endpoints off. */
  ADMIN_TOKEN: z.string().optional(),
});

export type Env = z.infer<typeof EnvSchema>;

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
