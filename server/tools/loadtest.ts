/**
 * Load-test bots: N WebSocket clients log in (dev auth), quick-play and send
 * 20 Hz inputs (wander, turn, shoot, reload) like real players.
 *   npm run loadtest -- --local --bots 16 --seconds 20     (in-process server)
 *   npm run loadtest -- --url ws://host:port/ws --bots 8   (server needs ALLOW_DEV_AUTH=1)
 * Prints traffic per client and the server tick cost from /healthz; with
 * --max-tick-ms N it exits non-zero when the average zone tick is slower.
 */
import path from "node:path";
import type { AddressInfo } from "node:net";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { Codec } from "../src/net/codec.js";
import { loadShared } from "../src/shared/loadShared.js";
import { setLogLevel } from "../src/log.js";
import { TestClient } from "../test/client.js";

const args = process.argv.slice(2);
const opt = (name: string, def: string) => {
  const i = args.indexOf("--" + name);
  return i >= 0 && args[i + 1] && !args[i + 1]!.startsWith("--") ? args[i + 1]! : def;
};
const bots = Number(opt("bots", "8"));
const seconds = Number(opt("seconds", "15"));
const maxTickMs = Number(opt("max-tick-ms", "0"));
const local = args.includes("--local");
const shared = loadShared(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../shared"));
const codec = new Codec(shared.protocol);

async function main(): Promise<void> {
  let url = opt("url", "ws://127.0.0.1:8787/ws");
  let close = async () => {};
  if (local) {
    setLogLevel("warn");
    const app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1", LOG_LEVEL: "warn" }), shared);
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
    close = () => app.close();
  }
  const clients: TestClient[] = [];
  const bytes: number[] = [];
  for (let i = 0; i < bots; i++) {
    const c = await TestClient.connect(url, codec);
    const idx = i;
    bytes[idx] = 0;
    c.ws.on("message", (d: Buffer) => (bytes[idx] = bytes[idx]! + d.length));
    c.hello(`dev:bot${i}`);
    await c.waitFor("welcome");
    c.send("quickPlay", { mode: 0 });
    await c.waitFor("zoneJoined");
    clients.push(c);
  }
  console.log(`${bots} bots connected to ${url}; running ${seconds}s`);
  let seq = 0;
  const yaw = clients.map(() => Math.random() * Math.PI * 2);
  const timer = setInterval(() => {
    seq = (seq + 1) % 65536;
    clients.forEach((c, i) => {
      yaw[i]! += (Math.random() - 0.5) * 0.4;
      const buttons = (Math.random() < 0.6 ? 1 : 0) | (Math.random() < 0.02 ? 2 : 0) | (seq % 3 === 0 ? 32 : 0);
      c.send("input", { seq, moveX: Math.round((Math.random() - 0.5) * 120), moveY: 100, yaw: ((yaw[i]! % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2), pitch: 0, buttons });
    });
  }, 50);
  await new Promise((r) => setTimeout(r, seconds * 1000));
  clearInterval(timer);
  const health = (await (await fetch(url.replace(/^ws/, "http").replace(/\/ws$/, "/healthz"))).json()) as Record<string, number>;
  const kbps = bytes.map((b) => b / seconds / 1024);
  const snapshots = clients.map((c) => c.inbox.filter((m) => m.name === "snapshot").length / seconds);
  console.log(`zones=${health.zones} players=${health.players} zombies=${health.zombies} tick avg=${health.tickMsAvg} ms max=${health.tickMsMax} ms`);
  console.log(`per client: ${avg(kbps).toFixed(1)} KiB/s down (max ${Math.max(...kbps).toFixed(1)}), ${avg(snapshots).toFixed(1)} snapshots/s`);
  for (const c of clients) c.close();
  await close();
  if (maxTickMs > 0 && health.tickMsAvg! > maxTickMs) {
    console.error(`FAIL: average tick ${health.tickMsAvg} ms > ${maxTickMs} ms`);
    process.exit(1);
  }
}

const avg = (a: number[]) => a.reduce((s, v) => s + v, 0) / Math.max(1, a.length);

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
