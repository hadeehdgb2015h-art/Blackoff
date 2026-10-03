import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { Codec } from "../src/net/codec.js";
import { PuzzleKind, type PuzzleApi, type PuzzleModule } from "../src/puzzles/api.js";
import { loadModule, newKey, open, puzzlesDir, seal } from "../src/puzzles/pack.js";
import { Zone, type ZoneClient } from "../src/zone/zone.js";
import { defs } from "./helpers.js";

// Phase 31: the host the secret puzzles run in. The real module is encrypted
// (only the owner's key opens it); these tests use a small stand-in module.
const codec = new Codec(defs().protocol);

function client(name: string, lang: string, got: { name: string; msg: Record<string, unknown> }[]): ZoneClient {
  return {
    displayName: name, lang,
    sendBytes: (b) => {
      const d = codec.decode("S2C", b);
      if (d.name.startsWith("puzzle")) got.push({ name: d.name, msg: d.msg as Record<string, unknown> });
    },
    onZoneClosed: () => {},
  };
}

/** A stand-in: a terminal that takes "42" and a lantern you shoot. */
function standIn(log: string[]): PuzzleModule {
  return {
    name: "test",
    explain: () => "test",
    create(api: PuzzleApi) {
      const term = api.add({ kind: PuzzleKind.TERMINAL, x: 0, y: 0, z: 14, label: { en: "Use", ar: "استخدم", ru: "Терминал" }, useRadius: 1.5, codeLength: 2 });
      const lamp = api.add({ kind: PuzzleKind.LANTERN, x: 0, y: 0, z: 8, shootRadius: 0.5, shootHeight: 2 });
      return {
        onUse(pid, id, code) {
          log.push(`use ${id === term ? "terminal" : id} ${code}`);
          if (code === "42") {
            api.update(term, { state: 2 });
            api.say({ en: "Opened", ar: "فُتح", ru: "Открыто" }, { big: true });
            api.giveWeapon(pid, "ember");
            api.reward([pid]);
          }
        },
        onShoot(_pid, id) {
          log.push(id === lamp ? "shot lamp" : "shot " + id);
          if (id === lamp) throw new Error("boom"); // a broken module must not take the zone down
        },
        answers: () => "42",
      };
    },
  };
}

describe("puzzle pack", () => {
  it("seals and opens with the key only", async () => {
    const key = newKey();
    expect(key).toHaveLength(43);
    const sealed = seal(Buffer.from("hello"), key);
    expect(open(sealed, key).toString()).toBe("hello");
    expect(() => open(sealed, newKey())).toThrow("wrong key");
    const mod = seal(Buffer.from('export default { name: "m", create() { return {}; }, explain() { return "x"; } };'), key);
    expect((await loadModule(key, mod)).name).toBe("m");
    await expect(loadModule(key, seal(Buffer.from("export default 1;"), key))).rejects.toThrow("not a puzzle module");
  });

  it("ships only sealed files: the real puzzles do not open without the owner's key", async () => {
    const dir = puzzlesDir();
    expect(dir).not.toBe("");
    const pack = fs.readFileSync(path.join(dir, "pack.bin"));
    expect(pack.subarray(0, 5).toString()).toBe("BOPZ1");
    expect(pack.toString("latin1")).not.toMatch(/lantern|terminal|export default/i);
    await expect(loadModule(newKey(), pack)).rejects.toThrow("wrong key");
    expect(fs.existsSync(path.join(dir, "source.bin"))).toBe(true);
  });
});

describe("puzzle host in a zone", () => {
  it("sends objects in each player's language, checks reach, hears shots, rewards and survives module errors", () => {
    const log: string[] = [];
    const zone = new Zone(1, defs(), codec, "facility_01", 3, 0);
    zone.botsAllowed = () => false;
    zone.startPuzzles(standIn(log), 9);
    const rewarded: string[] = [];
    zone.onPuzzleReward = (a) => rewarded.push(...a.map((x) => x.accountId));
    const gotAr: { name: string; msg: Record<string, unknown> }[] = [];
    const gotEn: { name: string; msg: Record<string, unknown> }[] = [];
    const a = zone.join(client("Ali", "ar", gotAr), "tg:1", 0);
    zone.join(client("Bob", "en", gotEn), "tg:2", 0);
    const objs = (m: typeof gotAr) => (m.filter((x) => x.name === "puzzleObjects").at(-1)!.msg.objects as { id: number; kind: number; label: string; codeLength: number }[]);
    expect(objs(gotAr).find((o) => o.kind === PuzzleKind.TERMINAL)).toMatchObject({ label: "استخدم", codeLength: 2 });
    expect(objs(gotEn).find((o) => o.kind === PuzzleKind.TERMINAL)!.label).toBe("Use");
    const term = objs(gotEn).find((o) => o.kind === PuzzleKind.TERMINAL)!.id;
    const p = zone.world.players.get(a.entityId)!;
    // too far: ignored
    p.pos = { x: 0, y: 20 };
    zone.puzzleUse(p.id, term, "42");
    expect(log).toEqual([]);
    p.pos = { x: 0.5, y: 14.5 };
    zone.puzzleUse(p.id, term, "4x2"); // only digits reach the module
    zone.puzzleUse(p.id, term, "42");
    expect(log).toEqual(["use terminal 42", "use terminal 42"]);
    expect(gotEn.find((m) => m.name === "puzzleMsg")!.msg).toEqual({ text: "Opened", big: true });
    expect(gotAr.find((m) => m.name === "puzzleMsg")!.msg.text).toBe("فُتح");
    expect(gotAr.some((m) => m.name === "puzzleState" && m.msg.id === term && m.msg.state === 2)).toBe(true);
    expect(p.weapon()!.id).toBe("ember");
    expect(rewarded).toEqual(["tg:1", "tg:1"]);
    expect(zone.puzzles!.answers()).toBe("42");
    // a shot passing the lantern (from the eye at 1.6 m towards 2 m up at the lantern)
    p.pos = { x: 0, y: 12 };
    zone.puzzles!.tick([{ type: "shot", pid: p.id, to: { x: 0, y: 2.4, z: 4 } }] as never);
    expect(log.at(-1)).toBe("shot lamp");
    // the module threw: puzzles are off in this zone, the game goes on
    zone.puzzles!.tick([{ type: "shot", pid: p.id, to: { x: 0, y: 2.4, z: 4 } }] as never);
    zone.puzzleUse(p.id, term, "42");
    expect(log.at(-1)).toBe("shot lamp");
    zone.tick(50);
  });

  it("gives no puzzles to infection games", () => {
    const zone = new Zone(2, defs(), codec, "facility_01", 3, 0, 1);
    zone.startPuzzles(standIn([]), 1);
    expect(zone.puzzles).toBeNull();
  });
});
