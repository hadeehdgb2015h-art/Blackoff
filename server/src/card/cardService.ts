/**
 * Result cards on disk (phase 25): renders a card (in a worker thread when the
 * bundled card-worker.mjs is present, else inline: tests and `npm run dev`),
 * writes it as <cards dir>/<random id>.jpg and returns its public URL. nginx
 * already serves the web root, so in a release the cards live in web/cards and
 * need no new route. Cards are swept after a day: Telegram copies the photo
 * when the message is sent, so an old link is not needed any more.
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";
import { log } from "../log.js";
import { loadRenderer, type CardImages, type CardInput, type CardRenderer } from "./cardRender.js";

const KEEP_MS = 24 * 3600 * 1000;
const SWEEP_EVERY_MS = 10 * 60 * 1000;

export interface CardFile { id: string; url: string; file: string; preview: string }

export class CardService {
  private worker: Worker | null = null;
  private inline: Promise<CardRenderer> | null = null;
  private readonly waiting = new Map<number, { resolve: (b: CardImages) => void; reject: (e: Error) => void }>();
  private nextId = 1;
  private lastSweep = 0;

  /** dir: where cards are written; baseUrl: the public URL of that directory ("" = cards off). */
  constructor(readonly dir: string, readonly baseUrl: string) {}

  get enabled(): boolean {
    return this.dir !== "" && this.baseUrl !== "";
  }

  async make(input: CardInput): Promise<CardFile> {
    const { jpg, png } = await this.render(input);
    fs.mkdirSync(this.dir, { recursive: true });
    const id = crypto.randomBytes(12).toString("base64url");
    const file = path.join(this.dir, id + ".jpg");
    await fs.promises.writeFile(file, jpg);
    await fs.promises.writeFile(path.join(this.dir, id + ".png"), png);
    this.sweep();
    return { id, file, url: this.baseUrl + id + ".jpg", preview: this.baseUrl + id + ".png" };
  }

  render(input: CardInput): Promise<CardImages> {
    const workerFile = path.join(path.dirname(fileURLToPath(import.meta.url)), "card-worker.mjs");
    if (!fs.existsSync(workerFile)) {
      this.inline ??= loadRenderer();
      return this.inline.then((r) => r.render(input));
    }
    if (!this.worker) {
      this.worker = new Worker(workerFile);
      this.worker.unref();
      this.worker.on("message", (m: { id: number; jpg?: Uint8Array; png?: Uint8Array; error?: string }) => {
        const w = this.waiting.get(m.id);
        this.waiting.delete(m.id);
        if (m.jpg && m.png) w?.resolve({ jpg: Buffer.from(m.jpg), png: Buffer.from(m.png) });
        else w?.reject(new Error(m.error ?? "card render failed"));
      });
      this.worker.on("error", (err) => {
        log.warn("card worker failed", { error: err.message });
        for (const w of this.waiting.values()) w.reject(err);
        this.waiting.clear();
        this.worker = null;
      });
    }
    const id = this.nextId++;
    return new Promise<CardImages>((resolve, reject) => {
      this.waiting.set(id, { resolve, reject });
      this.worker!.postMessage({ id, input });
    });
  }

  /** Deletes cards older than a day (at most every 10 minutes). */
  sweep(now = Date.now()): void {
    if (now - this.lastSweep < SWEEP_EVERY_MS) return;
    this.lastSweep = now;
    void fs.promises.readdir(this.dir).then(async (names) => {
      for (const n of names) {
        if (!n.endsWith(".jpg") && !n.endsWith(".png")) continue;
        const f = path.join(this.dir, n);
        const st = await fs.promises.stat(f).catch(() => null);
        if (st && now - st.mtimeMs > KEEP_MS) await fs.promises.unlink(f).catch(() => undefined);
      }
    }).catch(() => undefined);
  }

  async close(): Promise<void> {
    await this.worker?.terminate();
    this.worker = null;
  }
}

/** Where cards go: CARDS_DIR, else web/cards next to the shared data of a
 *  release (/opt/blackoff/current/web/cards). "" in a source checkout. */
export function cardsDir(env: { CARDS_DIR: string; SHARED_DIR: string }): string {
  if (env.CARDS_DIR) return env.CARDS_DIR;
  const web = path.resolve(env.SHARED_DIR, "..", "web");
  return fs.existsSync(path.join(web, "index.html")) ? path.join(web, "cards") : "";
}

/** The public URL of the cards directory: CARD_BASE_URL, else GAME_URL or the domain + "cards/". */
export function cardsBaseUrl(env: { CARD_BASE_URL: string; GAME_URL: string; BLACKOFF_DOMAIN: string }): string {
  if (env.CARD_BASE_URL) return env.CARD_BASE_URL.endsWith("/") ? env.CARD_BASE_URL : env.CARD_BASE_URL + "/";
  const game = env.GAME_URL || (env.BLACKOFF_DOMAIN ? `https://${env.BLACKOFF_DOMAIN}/` : "");
  if (!game) return "";
  return (game.endsWith("/") ? game : game + "/") + "cards/";
}
