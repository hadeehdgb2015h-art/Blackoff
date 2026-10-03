/**
 * The encrypted puzzle module (phase 31). The repository is public, so the
 * puzzles' rules ship sealed: server/assets/puzzles/pack.bin is the module's
 * JavaScript and source.bin its TypeScript source (for later edits), each
 * AES-256-GCM encrypted with a key only the owner has. The owner gives the key
 * to the server once (the bot's 🧩 panel, or PUZZLE_KEY in .env); the server
 * opens the pack in memory and imports it. Without the key the game simply has
 * no puzzles. server/tools/puzzles.ts seals and opens the files.
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { PuzzleModule } from "./api.js";

const MAGIC = Buffer.from("BOPZ1");

/** A new random key (32 bytes, base64url: 43 characters). */
export function newKey(): string {
  return crypto.randomBytes(32).toString("base64url");
}

function keyBytes(key: string): Buffer {
  const k = Buffer.from(key.trim(), "base64url");
  if (k.length !== 32) throw new Error("the key must be 43 characters (32 bytes, base64url)");
  return k;
}

export function seal(plain: Buffer, key: string): Buffer {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv("aes-256-gcm", keyBytes(key), iv);
  const body = Buffer.concat([c.update(plain), c.final()]);
  return Buffer.concat([MAGIC, iv, c.getAuthTag(), body]);
}

/** Throws when the key is wrong or the file was changed. */
export function open(sealed: Buffer, key: string): Buffer {
  if (sealed.length < MAGIC.length + 28 || !sealed.subarray(0, MAGIC.length).equals(MAGIC)) throw new Error("not a puzzle pack");
  const iv = sealed.subarray(MAGIC.length, MAGIC.length + 12);
  const tag = sealed.subarray(MAGIC.length + 12, MAGIC.length + 28);
  const d = crypto.createDecipheriv("aes-256-gcm", keyBytes(key), iv);
  d.setAuthTag(tag);
  try {
    return Buffer.concat([d.update(sealed.subarray(MAGIC.length + 28)), d.final()]);
  } catch {
    throw new Error("wrong key");
  }
}

/** server/assets/puzzles next to the bundle in a release, or in the source tree. */
export function puzzlesDir(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  for (const d of [process.env.PUZZLES_DIR ?? "", path.join(here, "assets", "puzzles"), path.join(here, "..", "..", "assets", "puzzles")]) {
    if (d && fs.existsSync(path.join(d, "pack.bin"))) return d;
  }
  return "";
}

/** Opens and imports the module. The pack holds one self-contained ES module
 *  whose default export is a PuzzleModule. */
export async function loadModule(key: string, sealed: Buffer): Promise<PuzzleModule> {
  const js = open(sealed, key);
  const mod = (await import("data:text/javascript;base64," + js.toString("base64"))) as { default?: PuzzleModule };
  const m = mod.default;
  if (!m || typeof m.create !== "function" || typeof m.explain !== "function") throw new Error("the pack is not a puzzle module");
  return m;
}
