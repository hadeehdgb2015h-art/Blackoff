/** Phase 12: voice chat. The server relays opaque frames inside a zone; the
 *  codec lives in client/web/voice.js and is checked here with Node. */
import { createRequire } from "node:module";
import type { AddressInfo } from "node:net";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { Codec, CodecError, type Msg } from "../src/net/codec.js";
import { MemoryProfileStore } from "../src/db/profileStore.js";
import { TestClient } from "./client.js";
import { defs, sharedDir } from "./helpers.js";

const require = createRequire(import.meta.url);
interface VoiceCodec {
  RATE: number; FRAME: number; FRAME_BYTES: number; HEADER: number;
  Coder: new () => { encode(samples: Float32Array): Uint8Array; pred: number; idx: number };
  decodeFrame(bytes: Uint8Array): Float32Array;
  rms(samples: Float32Array): number;
}
const voice = require(path.join(sharedDir, "..", "client", "web", "voice.js")) as VoiceCodec;

const tone = (frames: number, hz = 440, amp = 0.5): Float32Array[] => {
  const out: Float32Array[] = [];
  for (let f = 0; f < frames; f++) {
    const s = new Float32Array(voice.FRAME);
    for (let i = 0; i < s.length; i++) s[i] = amp * Math.sin((2 * Math.PI * hz * (f * s.length + i)) / voice.RATE);
    out.push(s);
  }
  return out;
};

describe("voice codec (client/web/voice.js under Node)", () => {
  it("packs 40 ms into 324 bytes and decodes a tone with little error", () => {
    const coder = new voice.Coder();
    const frames = tone(10);
    let sig = 0, err = 0;
    for (const f of frames) {
      const bytes = coder.encode(f);
      expect(bytes.length).toBe(voice.FRAME_BYTES);
      expect(bytes[3]).toBe(1);
      const back = voice.decodeFrame(bytes);
      expect(back.length).toBe(voice.FRAME);
      for (let i = 0; i < f.length; i++) { sig += f[i]! ** 2; err += (f[i]! - back[i]!) ** 2; }
    }
    const snrDb = 10 * Math.log10(sig / err);
    expect(snrDb).toBeGreaterThan(20);
  });

  it("decodes every frame on its own thanks to the state header", () => {
    const coder = new voice.Coder();
    const frames = tone(4);
    const encoded = frames.map((f) => coder.encode(f));
    // decode only the last frame, as a client that joined late would
    const last = voice.decodeFrame(encoded[3]!);
    let sig = 0, err = 0;
    for (let i = 0; i < last.length; i++) { sig += frames[3]![i]! ** 2; err += (frames[3]![i]! - last[i]!) ** 2; }
    expect(10 * Math.log10(sig / err)).toBeGreaterThan(20);
    expect(voice.rms(frames[0]!)).toBeCloseTo(0.5 / Math.SQRT2, 2);
    expect(voice.rms(new Float32Array(voice.FRAME))).toBe(0);
  });
});

describe("bytes16 fields", () => {
  const codec = new Codec(defs().protocol);
  it("round-trip Uint8Array and byte arrays, reject bad values", () => {
    const data = Uint8Array.from({ length: 324 }, (_, i) => (i * 7) & 0xff);
    const bytes = codec.encode("C2S", "voice", { seq: 9, data });
    expect(bytes.length).toBe(1 + 2 + 2 + 324);
    const back = codec.decode("C2S", bytes);
    expect(back.msg.seq).toBe(9);
    expect(Array.from(back.msg.data as Uint8Array)).toEqual(Array.from(data));
    expect(codec.encode("C2S", "voice", { seq: 1, data: [1, 2, 3] }).length).toBe(8);
    expect(codec.encode("C2S", "voice", { seq: 1, data: new Uint8Array(0) }).length).toBe(5);
    expect(() => codec.encode("C2S", "voice", { seq: 1, data: "nope" })).toThrow(CodecError);
    expect(() => codec.decode("C2S", Uint8Array.from([8, 1, 0, 10, 0, 1, 2]))).toThrow(CodecError); // length says 10, 2 present
  });
});

describe("voice relay", () => {
  let app: App;
  let url = "";
  const codec = new Codec(defs().protocol);
  beforeAll(async () => {
    app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1" }), defs(), new MemoryProfileStore());
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
  });
  afterAll(() => app.close());

  async function join(name: string): Promise<{ c: TestClient; entityId: number; welcome: Msg }> {
    const c = await TestClient.connect(url, codec);
    c.hello("dev:" + name);
    const welcome = await c.waitFor("welcome");
    c.send("quickPlay");
    const j = await c.waitFor("zoneJoined");
    return { c, entityId: j.entityId as number, welcome };
  }

  it("sends a frame to the other listening members only, with the speaker's id", async () => {
    const a = await join("Alpha");
    const b = await join("Bravo");
    const d = await join("Delta");
    expect(a.welcome.voice).toBe(true);
    d.c.send("voiceListen", { on: false });
    await new Promise((r) => setTimeout(r, 50));
    const data = Uint8Array.from({ length: 324 }, (_, i) => i & 0xff);
    a.c.send("voice", { seq: 41, data });
    const got = await b.c.waitFor("voice");
    expect(got.entityId).toBe(a.entityId);
    expect(got.seq).toBe(41);
    expect(Array.from(got.data as Uint8Array)).toEqual(Array.from(data));
    await new Promise((r) => setTimeout(r, 150));
    expect(a.c.inbox.filter((m) => m.name === "voice")).toHaveLength(0); // not echoed to the speaker
    expect(d.c.inbox.filter((m) => m.name === "voice")).toHaveLength(0); // speaker off
    // the speaker back on: frames arrive again
    d.c.send("voiceListen", { on: true });
    await new Promise((r) => setTimeout(r, 50));
    a.c.send("voice", { seq: 42, data });
    expect((await d.c.waitFor("voice")).seq).toBe(42);
    // too big or empty: dropped without an error message
    a.c.send("voice", { seq: 43, data: new Uint8Array(401) });
    a.c.send("voice", { seq: 44, data: new Uint8Array(0) });
    a.c.send("voice", { seq: 45, data });
    const next = await b.c.waitFor("voice", (m) => (m.seq as number) >= 43);
    expect(next.seq).toBe(45);
    expect(a.c.inbox.filter((m) => m.name === "error")).toHaveLength(0);
    // a flood is thinned to the allowed rate, never a disconnect
    const before = b.c.inbox.filter((m) => m.name === "voice").length;
    for (let i = 0; i < 200; i++) a.c.send("voice", { seq: 100 + i, data });
    await new Promise((r) => setTimeout(r, 300));
    const relayed = b.c.inbox.filter((m) => m.name === "voice").length - before;
    expect(relayed).toBeGreaterThan(0);
    expect(relayed).toBeLessThanOrEqual(defs().constants.voice.maxFramesPerSecond * 3); // burst of 2 s plus the refill while sending
    expect(a.c.closed).toBeNull();
    for (const x of [a, b, d]) x.c.ws.close();
  });
});

describe("voice switched off on the server", () => {
  it("tells clients in welcome and relays nothing", async () => {
    const app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1", VOICE_CHAT: "0" }), defs(), new MemoryProfileStore());
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    const url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
    const codec = new Codec(defs().protocol);
    const a = await TestClient.connect(url, codec);
    a.hello("dev:A");
    expect((await a.waitFor("welcome")).voice).toBe(false);
    a.send("quickPlay");
    await a.waitFor("zoneJoined");
    const b = await TestClient.connect(url, codec);
    b.hello("dev:B");
    await b.waitFor("welcome");
    b.send("quickPlay");
    await b.waitFor("zoneJoined");
    a.send("voice", { seq: 1, data: new Uint8Array(324) });
    await new Promise((r) => setTimeout(r, 150));
    expect(b.inbox.filter((m) => m.name === "voice")).toHaveLength(0);
    a.ws.close();
    b.ws.close();
    await app.close();
  });
});
