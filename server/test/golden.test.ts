import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { Codec, CodecError, type Dir } from "../src/net/codec.js";
import { rayCharacter } from "../src/sim/hitTest.js";
import { MapData } from "../src/sim/mapData.js";
import { WaveDirector } from "../src/sim/waveDirector.js";
import { defs, sharedDir } from "./helpers.js";

// Regenerate with `npm run gen:golden` when a rule changes on purpose, then
// make the client (client/tests/test_golden.gd) agree.
const golden = JSON.parse(fs.readFileSync(path.join(sharedDir, "tests", "golden.json"), "utf8"));

describe("golden cross-language contract", () => {
  const codec = new Codec(defs().protocol);

  it("codec vectors encode to the same bytes and decode back", () => {
    for (const c of golden.codec) {
      expect(Buffer.from(codec.encode(c.dir as Dir, c.name, c.msg)).toString("hex"), c.name).toBe(c.hex);
      const back = codec.decode(c.dir as Dir, Buffer.from(c.hex, "hex"));
      expect(back.name).toBe(c.name);
      expect(back.msg).toEqual(c.msg);
    }
  });

  it("wave formulas", () => {
    for (const row of golden.waves) {
      expect(WaveDirector.spawnIntervalFor(defs().waves, row.wave)).toBeCloseTo(row.interval, 5);
      row.count.forEach((n: number, i: number) => expect(WaveDirector.countFor(defs().waves, row.wave, i + 1)).toBe(n));
      for (const [id, z] of Object.entries(defs().zombies)) {
        expect(WaveDirector.healthFor(z, row.wave)).toBeCloseTo(row[id].health, 5);
        expect(WaveDirector.speedFor(z, row.wave)).toBeCloseTo(row[id].speed, 5);
      }
    }
  });

  it("hit shapes, movement and raycasts", () => {
    for (const h of golden.hits) {
      const r = rayCharacter(h.o, h.d, h.pos, h.radius, h.headY, h.headR);
      expect(r ? r.t : -1).toBeCloseTo(h.t, 4);
      expect(r ? r.head : false).toBe(h.head);
    }
    const map = new MapData(defs().maps[golden.map]!, defs().constants.player.stepHeight);
    for (const m of golden.moves) {
      const r = map.moveCircle(m.pos, m.delta, m.radius);
      expect(r.x).toBeCloseTo(m.result.x, 4);
      expect(r.y).toBeCloseTo(m.result.y, 4);
    }
    for (const c of golden.rays) expect(map.raycast(c.o, c.d, c.max)).toBeCloseTo(c.t, 4);
  });
});

describe("codec strictness", () => {
  const codec = new Codec(defs().protocol);
  it("rejects unknown ids, short frames, trailing bytes and out-of-range values", () => {
    expect(() => codec.decode("C2S", new Uint8Array([200]))).toThrow(CodecError);
    expect(() => codec.decode("C2S", new Uint8Array([3, 1]))).toThrow(CodecError);
    const ping = codec.encode("C2S", "ping", { clientTime: 5 });
    expect(() => codec.decode("C2S", new Uint8Array([...ping, 0]))).toThrow(CodecError);
    expect(() => codec.encode("C2S", "ping", { clientTime: -1 })).toThrow(CodecError);
    expect(() => codec.encode("C2S", "buy", { itemId: "x".repeat(300) })).toThrow(CodecError);
    expect(() => codec.decode("S2C", ping)).toThrow(CodecError); // id 5 is not a server message
  });
  it("quantizes positions to 1/64 m and wraps angles", () => {
    const m = codec.decode("S2C", codec.encode("S2C", "shot", { playerId: 1, weapon: 0, toX: 1.01, toY: -600, toZ: 2, hit: 0 })).msg;
    expect(m.toX).toBeCloseTo(1.015625, 6);
    expect(m.toY).toBeCloseTo(-512, 6); // clamped to the i16 range
    const a = codec.decode("C2S", codec.encode("C2S", "input", { seq: 1, moveX: 0, moveY: 0, yaw: -Math.PI / 2, pitch: 0, buttons: 0 })).msg;
    expect(a.yaw).toBeCloseTo(1.5 * Math.PI, 3);
  });
});
