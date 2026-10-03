/**
 * Writes shared/tests/golden.json: cross-language contract cases computed by
 * the server code. The server tests (test/golden.test.ts) and the client tests
 * (client/tests/test_golden.gd) both check them, so the TypeScript server and
 * the GDScript client sim cannot drift apart unnoticed.
 *   npm run gen:golden   (commit the result)
 */
import { levelFor, rankFor, xpFor, xpToReach } from "../src/progression.js";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Codec, type Dir, type Msg } from "../src/net/codec.js";
import { loadShared } from "../src/shared/loadShared.js";
import { rayCharacter } from "../src/sim/hitTest.js";
import { MapData } from "../src/sim/mapData.js";
import { Rng } from "../src/sim/rng.js";
import { WaveDirector } from "../src/sim/waveDirector.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const shared = loadShared(path.join(root, "shared"));
const codec = new Codec(shared.protocol);
const rng = new Rng(2026);
const r6 = (v: number) => Math.round(v * 1e6) / 1e6;

// ---- codec vectors: every message, values exactly representable after quantization
function sample(type: string): unknown {
  const arr = /^array(8|16):(.+)$/.exec(type);
  if (arr) return Array.from({ length: 1 + (rng.next() % 3) }, () => sample(arr[2]!));
  const struct = shared.protocol.types[type];
  if (Array.isArray(struct)) return Object.fromEntries(struct.map(([n, t]) => [n, sample(t)]));
  const ri = (lo: number, hi: number) => lo + (rng.next() % (hi - lo + 1));
  switch (type) {
    case "u8": return ri(0, 255);
    case "u16": return ri(0, 65535);
    case "u32": return rng.next();
    case "i8": return ri(-128, 127);
    case "i16": return ri(-32768, 32767);
    case "f32": return ri(-800, 800) / 8;
    case "bool": return rng.next() % 2 === 1;
    case "varuint": return [0, 127, 128, 300, 70000, 4294967295][rng.next() % 6];
    case "str8": case "str16": return ["", "zombie", "Ali_99", "علي", "hello world"][rng.next() % 5];
    // opaque bytes are written to golden.json as plain arrays of byte values
    case "bytes16": return Array.from({ length: rng.next() % 40 }, () => rng.next() % 256);
    case "pos": return ri(-32768, 32767) / shared.protocol.quantization.posScale;
    case "angle": return (ri(0, 65535) / 65536) * Math.PI * 2;
    case "pitch": return (ri(-32767, 32767) / 32767) * (Math.PI / 2);
    default: throw new Error("no sampler for " + type);
  }
}
const codecCases: { dir: Dir; name: string; msg: Msg; hex: string }[] = [];
for (const dir of ["C2S", "S2C"] as const) {
  for (const name of codec.messageNames(dir)) {
    const spec = shared.protocol.messages[dir][name]!;
    for (let k = 0; k < 2; k++) {
      const msg = Object.fromEntries(spec.fields.map(([n, t]) => [n, sample(t)]));
      codecCases.push({ dir, name, msg, hex: Buffer.from(codec.encode(dir, name, msg)).toString("hex") });
    }
  }
}

// ---- wave formulas
const waves = [];
for (let wave = 1; wave <= 40; wave += 3) {
  const row: Record<string, unknown> = { wave, interval: r6(WaveDirector.spawnIntervalFor(shared.waves, wave)), count: [] as number[] };
  for (let pl = 1; pl <= 8; pl++) (row.count as number[]).push(WaveDirector.countFor(shared.waves, wave, pl));
  for (const [id, z] of Object.entries(shared.zombies)) {
    row[id] = { health: r6(WaveDirector.healthFor(z, wave)), speed: r6(WaveDirector.speedFor(z, wave)) };
  }
  row.mix = WaveDirector.mixFor(shared.waves, wave);
  waves.push(row);
}

// ---- hit shapes (rays from an eye towards points around a character)
const hits = [];
for (let i = 0; i < 40; i++) {
  const pos = { x: r6(rng.range(-3, 3)), y: r6(rng.range(-12, -2)) };
  const o = { x: 0, y: 1.6, z: 0 };
  const aim = { x: pos.x + rng.range(-0.6, 0.6), y: rng.range(0.0, 2.1), z: pos.y + rng.range(-0.4, 0.4) };
  const l = Math.hypot(aim.x - o.x, aim.y - o.y, aim.z - o.z);
  const d = { x: r6((aim.x - o.x) / l), y: r6((aim.y - o.y) / l), z: r6((aim.z - o.z) / l) };
  const h = rayCharacter(o, d, pos, 0.35, 1.62, 0.16);
  hits.push({ o, d, pos, radius: 0.35, headY: 1.62, headR: 0.16, t: h ? r6(h.t) : -1, head: h ? h.head : false });
}

// ---- movement and raycasts on the real map
const map = new MapData(shared.maps[shared.constants.maps.default]!, shared.constants.player.stepHeight);
const moves = [];
const rays = [];
for (let i = 0; i < 40; i++) {
  const walk = map.walkable[rng.next() % map.walkable.length]!;
  const pos = { x: r6(walk.x + rng.range(0.4, walk.w - 0.4)), y: r6(walk.y + rng.range(0.4, walk.h - 0.4)) };
  const a = rng.range(0, Math.PI * 2);
  const l = rng.range(0.2, 4);
  const delta = { x: r6(Math.cos(a) * l), y: r6(Math.sin(a) * l) };
  const res = map.moveCircle(pos, delta, 0.35);
  moves.push({ pos, delta, radius: 0.35, result: { x: r6(res.x), y: r6(res.y) } });
  const dir = { x: r6(Math.cos(a)), y: 0, z: r6(Math.sin(a)) };
  rays.push({ o: { x: pos.x, y: 1.6, z: pos.y }, d: dir, max: 60, t: r6(map.raycast({ x: pos.x, y: 1.6, z: pos.y }, dir, 60)) });
}

// ---- progression (phase 26): xp of sample games, level and rank of sample totals
const prog = shared.constants.progression;
const levels = [0, 1, 499, 500, 1149, 1150, 9_900, 50_000, 200_900, 777_149, 777_150, 5_000_000].map((xp) => {
  const level = levelFor(xp, prog);
  return { xp, level, rank: rankFor(level, prog).id, next: xpToReach(Math.min(prog.maxLevel, level + 1), prog) };
});
const xpGames = [
  { kills: 0, headshots: 0, wave: 0, seconds: 30, mode: 0 },
  { kills: 87, headshots: 23, wave: 9, seconds: 640, mode: 0 },
  { kills: 12, headshots: 4, wave: 3, seconds: 425, mode: 1 },
].map((g) => ({ ...g, xp: xpFor(g, prog) }));

const out = {
  _comment: "Generated by server/tools/genGolden.ts. Checked by server/test/golden.test.ts and client/tests/test_golden.gd.",
  map: map.id,
  codec: codecCases,
  waves,
  hits,
  moves,
  rays,
  levels,
  xpGames,
};
const file = path.join(root, "shared", "tests", "golden.json");
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify(out, null, 1) + "\n");
console.log(`wrote ${path.relative(root, file)}: ${codecCases.length} codec, ${waves.length} wave rows, ${hits.length} hits, ${moves.length} moves, ${rays.length} rays`);
