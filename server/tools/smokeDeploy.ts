/**
 * Deployment smoke test: logs in like a Telegram player (initData signed with the
 * bot token the server was given), plays briefly, leaves, and checks that the
 * profile counted the game.
 *   SMOKE_BOT_TOKEN=... npx tsx tools/smokeDeploy.ts ws://host/ws [telegram user id] [hold seconds]
 * With hold seconds the player stays in the zone that long before leaving (the
 * deploy rehearsal uses it to keep a zone busy while the updater must wait).
 * Prints one JSON line; exits non-zero on any failure.
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Codec } from "../src/net/codec.js";
import { loadShared } from "../src/shared/loadShared.js";
import { signInitData } from "../src/net/telegramAuth.js";
import { TestClient } from "../test/client.js";

const url = process.argv[2];
const userId = Number(process.argv[3] ?? "9001");
const holdSec = Number(process.argv[4] ?? "0");
const token = process.env.SMOKE_BOT_TOKEN;
if (!url || !token) {
  console.error("usage: SMOKE_BOT_TOKEN=... tsx tools/smokeDeploy.ts <ws url> [user id]");
  process.exit(2);
}
const shared = loadShared(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../shared"));
const codec = new Codec(shared.protocol);
const initData = signInitData(
  { auth_date: String(Math.floor(Date.now() / 1000)), user: JSON.stringify({ id: userId, first_name: "Smoke" }) },
  token,
);

const c = await TestClient.connect(url, codec);
c.hello(initData);
const welcome = await c.waitFor("welcome", () => true, 8000);
c.send("quickPlay", { mode: 0 });
const joined = await c.waitFor("zoneJoined", () => true, 8000);
await c.waitFor("snapshot", () => true, 8000);
if (holdSec > 0) {
  console.error(`holding the zone for ${holdSec} s`);
  await new Promise((r) => setTimeout(r, holdSec * 1000));
}
c.send("leave");
const profile = await c.waitFor("profile", () => true, 8000);
c.ws.close();
const result = { name: welcome.displayName, gamesBefore: welcome.games, gamesAfter: profile.games, zone: joined.zoneId };
console.log(JSON.stringify(result));
if (profile.games !== (welcome.games as number) + 1) {
  console.error("profile did not count the game");
  process.exit(1);
}
process.exit(0);
