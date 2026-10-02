/**
 * Voice bot for end-to-end tests: joins a zone, talks (a 440 Hz tone encoded
 * with the real client codec, client/web/voice.js) and counts the voice frames
 * it hears from other players.
 *   npx tsx tools/voiceBot.ts <ws url> <name> <seconds> [--expect-receive]
 * Prints one JSON line {sent, received, speakers, decoded}; with --expect-receive
 * the exit code is 1 when nothing was heard.
 */
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";
import WebSocket from "ws";
import { Codec, type Msg } from "../src/net/codec.js";
import { loadShared } from "../src/shared/loadShared.js";

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const voice = require(path.join(root, "client/web/voice.js")) as {
  RATE: number; FRAME: number; FRAME_MS: number; FRAME_BYTES: number;
  Coder: new () => { encode(s: Float32Array): Uint8Array };
  decodeFrame(b: Uint8Array): Float32Array;
};

const [url = "ws://127.0.0.1:8787/ws", name = "VoiceBot", secondsArg = "10", ...flags] = process.argv.slice(2);
const seconds = Number(secondsArg);
const expectReceive = flags.includes("--expect-receive");
const shared = loadShared(path.join(root, "shared"));
const codec = new Codec(shared.protocol);

const stats = { sent: 0, received: 0, decoded: 0, speakers: {} as Record<string, number> };
const coder = new voice.Coder();
let phase = 0;
let seq = 0;
let talk: NodeJS.Timeout | null = null;

const ws = new WebSocket(url);
const send = (n: string, m: Msg = {}) => ws.send(codec.encode("C2S", n, m));
ws.on("open", () => send("hello", { protocolVersion: shared.protocol.protocolVersion, initData: "dev:" + name, resumeToken: "" }));
ws.on("message", (data: Buffer) => {
  const { name: n, msg } = codec.decode("S2C", new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
  if (n === "welcome") {
    if (!msg.voice) { console.error("server has voice chat off"); process.exit(2); }
    send("quickPlay", { mode: 0 });
  } else if (n === "zoneJoined") {
    talk = setInterval(() => {
      const s = new Float32Array(voice.FRAME);
      for (let i = 0; i < s.length; i++) { s[i] = 0.4 * Math.sin(phase); phase += (2 * Math.PI * 440) / voice.RATE; }
      send("voice", { seq: seq++ & 0xffff, data: coder.encode(s) });
      stats.sent += 1;
    }, voice.FRAME_MS);
  } else if (n === "voice") {
    stats.received += 1;
    const id = String(msg.entityId);
    stats.speakers[id] = (stats.speakers[id] ?? 0) + 1;
    const bytes = msg.data as Uint8Array;
    if (bytes.length === voice.FRAME_BYTES && voice.decodeFrame(bytes).length === voice.FRAME) stats.decoded += 1;
  } else if (n === "error") {
    console.error("server error", msg);
  }
});
ws.on("error", (e) => { console.error(String(e)); process.exit(2); });

setTimeout(() => {
  if (talk) clearInterval(talk);
  try { send("leave"); } catch { /* closing */ }
  ws.close();
  console.log(JSON.stringify(stats));
  process.exit(expectReceive && stats.received === 0 ? 1 : 0);
}, seconds * 1000);
