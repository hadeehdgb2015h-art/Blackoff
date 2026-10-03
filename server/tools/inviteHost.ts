/**
 * Invite end-to-end helper: logs in as <name>, starts a game, prints one JSON
 * line {inviteCode, botUsername, zoneId} and stays in the zone for <seconds>,
 * counting the roster, so a browser can join through ?startapp=sq<code>.
 *   npx tsx tools/inviteHost.ts <ws url> <name> <seconds>
 * Prints {"joined": <players seen>} at the end; exit code 1 when nobody joined.
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import WebSocket from "ws";
import { Codec, type Msg } from "../src/net/codec.js";
import { loadShared } from "../src/shared/loadShared.js";

const [url = "ws://127.0.0.1:8787/ws", name = "Host", secondsArg = "30"] = process.argv.slice(2);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const shared = loadShared(path.join(root, "shared"));
const codec = new Codec(shared.protocol);
let code = "";
let bot = "";
let most = 0;

const ws = new WebSocket(url);
const send = (n: string, m: Msg = {}) => ws.send(codec.encode("C2S", n, m));
ws.on("open", () => send("hello", { protocolVersion: shared.protocol.protocolVersion, initData: "dev:" + name, resumeToken: "" }));
ws.on("message", (data: Buffer) => {
  const { name: n, msg } = codec.decode("S2C", new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
  if (n === "welcome") {
    code = String(msg.inviteCode);
    bot = String(msg.botUsername);
    send("quickPlay", { mode: 0, friend: "" });
  } else if (n === "zoneJoined") {
    console.log(JSON.stringify({ inviteCode: code, botUsername: bot, zoneId: msg.zoneId }));
  } else if (n === "roster") {
    most = Math.max(most, (msg.players as unknown[]).length);
  }
});
setTimeout(() => {
  console.log(JSON.stringify({ joined: most }));
  ws.close();
  process.exit(most >= 2 ? 0 : 1);
}, Number(secondsArg) * 1000);
