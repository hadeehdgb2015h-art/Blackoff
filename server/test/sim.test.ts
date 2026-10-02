import { describe, expect, it } from "vitest";
import { BotBrain } from "../src/sim/botBrain.js";
import { Btn, WeaponState } from "../src/sim/entities.js";
import { rayCharacter } from "../src/sim/hitTest.js";
import { MapData } from "../src/sim/mapData.js";
import { NavGrid } from "../src/sim/navGrid.js";
import { SimWorld, ZoneState } from "../src/sim/simWorld.js";
import { BoxState } from "../src/sim/boxSystem.js";
import { WaveDirector } from "../src/sim/waveDirector.js";
import { defs, intent } from "./helpers.js";

const world = (seed = 42) => new SimWorld(defs(), "facility_01", seed);

describe("map and navigation", () => {
  const map = new MapData(defs().maps.facility_01!, 0.4);
  const nav = new NavGrid(map, defs().constants.maps.navCellSize, defs().constants.maps.navAgentRadius);

  it("walls block movement, doors let players through, no tunnelling", () => {
    expect(map.moveCircle({ x: 2, y: 11 }, { x: 0, y: -3 }, 0.35).y).toBeGreaterThan(10.15 + 0.34);
    expect(map.moveCircle({ x: -3, y: 14 }, { x: -4, y: 0 }, 0.35).x).toBeCloseTo(-7.0, 2);
    expect(map.moveCircle({ x: 2, y: 11 }, { x: 0, y: -30 }, 0.35).y).toBeGreaterThan(10.0);
  });

  it("raycasts respect wall heights", () => {
    expect(map.raycast({ x: 0, y: 1.6, z: 14 }, { x: 0, y: 0, z: -1 }, 50)).toBeCloseTo(14 - 10.15, 2);
    expect(map.raycast({ x: -13, y: 0.5, z: 0 }, { x: 0, y: 0, z: -1 }, 10)).toBeCloseTo(3.0, 2);
    expect(map.raycast({ x: -13, y: 1.6, z: 0 }, { x: 0, y: 0, z: -1 }, 10)).toBeGreaterThan(5);
    expect(map.segmentClear({ x: -3, y: 14 }, { x: 3, y: 14 }, 0.3)).toBe(true);
    expect(map.segmentClear({ x: 0, y: 14 }, { x: 0, y: 5 }, 0.3)).toBe(false);
  });

  it("every zombie entry reaches every spawn, paths never cross walls", () => {
    for (const e of map.zombieEntries) {
      for (const s of map.playerSpawns) expect(nav.findPath(e.pos, s.pos).length, `${e.id}`).toBeGreaterThan(0);
    }
    const path = nav.findPath(map.zombieEntries[0]!.pos, map.playerSpawns[0]!.pos);
    for (let i = 1; i < path.length; i++) expect(map.segmentClear(path[i - 1]!, path[i]!, 0.05)).toBe(true);
    for (const it of map.interactables) expect(nav.findPath(map.playerSpawns[0]!.pos, it.pos).length).toBeGreaterThan(0);
  });
});

describe("combat", () => {
  it("separates head and body hits", () => {
    const o = { x: 0, y: 1.6, z: 0 };
    expect(rayCharacter(o, { x: 0, y: 0, z: -1 }, { x: 0, y: -5 }, 0.35, 1.62, 0.16)?.head).toBe(true);
    const d = { x: 0, y: 1.0 - 1.6, z: -5 };
    const l = Math.hypot(d.x, d.y, d.z);
    expect(rayCharacter(o, { x: 0, y: d.y / l, z: d.z / l }, { x: 0, y: -5 }, 0.35, 1.62, 0.16)?.head).toBe(false);
    expect(rayCharacter(o, { x: Math.SQRT1_2, y: 0, z: -Math.SQRT1_2 }, { x: 0, y: -5 }, 0.35, 1.62, 0.16)).toBeNull();
  });

  it("caps fire rate exactly (rifle 600 rpm: 21 shots in 2 s)", () => {
    const w = world();
    const pid = w.addPlayer("t");
    const p = w.players.get(pid)!;
    p.weapons[0] = new WeaponState("rifle", defs().weapons.rifle!);
    for (let i = 0; i < 40; i++) {
      w.setInput(pid, intent(Btn.FIRE_HELD, { pitch: 0.3 }));
      w.step();
    }
    expect(p.shotsFired).toBe(21);
    expect(p.weapons[0]!.mag).toBe(30 - 21);
  });

  it("semi-auto needs presses", () => {
    const w = world();
    const pid = w.addPlayer("t");
    w.setInput(pid, intent(Btn.FIRE_HELD | Btn.FIRE_PRESSED));
    w.step();
    for (let i = 0; i < 10; i++) {
      w.setInput(pid, intent(Btn.FIRE_HELD));
      w.step();
    }
    expect(w.players.get(pid)!.shotsFired).toBe(1);
  });

  it("reload moves rounds from reserve", () => {
    const w = world();
    const pid = w.addPlayer("t");
    const p = w.players.get(pid)!;
    const wp = p.weapon()!;
    wp.mag = 2;
    w.setInput(pid, intent(Btn.RELOAD));
    w.step();
    expect(p.isReloading()).toBe(true);
    w.setInput(pid, intent());
    for (let i = 0; i < Math.ceil(wp.def.reloadSec * 20) + 1; i++) w.step();
    expect(wp.mag).toBe(wp.def.magSize);
    expect(wp.reserve).toBe(wp.def.reserveStart - (wp.def.magSize - 2));
  });

  it("kills reward currency; shotgun pellets apply once per zombie", () => {
    const w = world();
    const pid = w.addPlayer("t");
    const p = w.players.get(pid)!;
    const start = p.currency;
    expect(w.zombieSys.spawn("walker", 1)).toBe(true);
    const z = [...w.zombies.values()][0]!;
    z.pos = { x: p.pos.x, y: p.pos.y - 4 };
    z.hp = 1;
    w.setInput(pid, intent(Btn.FIRE_PRESSED | Btn.FIRE_HELD, { pitch: Math.atan2(1.62 - 1.6, 4) }));
    w.step();
    expect(w.zombies.size).toBe(0);
    expect(p.kills).toBe(1);
    expect(p.currency).toBeGreaterThan(start);

    const w2 = world(3);
    const p2 = w2.players.get(w2.addPlayer("t"))!;
    p2.weapons[0] = new WeaponState("shotgun", defs().weapons.shotgun!);
    w2.zombieSys.spawn("walker", 50);
    const z2 = [...w2.zombies.values()][0]!;
    z2.pos = { x: p2.pos.x, y: p2.pos.y - 2.5 };
    const hp0 = z2.hp;
    w2.setInput(p2.id, intent(Btn.FIRE_PRESSED | Btn.FIRE_HELD, { pitch: Math.atan2(1.2 - 1.6, 2.5) }));
    w2.step();
    expect(w2.events.filter((e) => e.type === "zombie_hit").length).toBe(1);
    const shot = w2.events.find((e) => e.type === "shot")!;
    expect((shot.ends as unknown[]).length).toBe(defs().weapons.shotgun!.pellets);
    expect(hp0 - z2.hp).toBeGreaterThan(defs().weapons.shotgun!.damage * 3);
  });

  it("buys the rifle and its ammo only with enough currency", () => {
    const w = world();
    const pid = w.addPlayer("t");
    const p = w.players.get(pid)!;
    p.pos = { ...w.map.interactables.find((i) => i.kind === "weapon")!.pos };
    const press = () => {
      w.setInput(pid, intent());
      w.step();
      w.setInput(pid, intent(Btn.INTERACT));
      w.step();
    };
    press();
    expect(p.weapons.length).toBe(1);
    p.currency = 5000;
    press();
    expect(p.weapon()!.id).toBe("rifle");
    expect(p.currency).toBe(5000 - defs().weapons.rifle!.price);
    p.weapon()!.reserve = 0;
    press();
    expect(p.weapon()!.reserve).toBe(defs().weapons.rifle!.reserveMax);
  });
});

describe("waves", () => {
  it("formulas match the contract", () => {
    const c = defs().waves;
    expect(WaveDirector.countFor(c, 1, 1)).toBe(7);
    expect(WaveDirector.countFor(c, 5, 4)).toBeGreaterThan(WaveDirector.countFor(c, 5, 1));
    expect(WaveDirector.countFor(c, 10000, 8)).toBeLessThanOrEqual(c.count.max);
    expect(WaveDirector.spawnIntervalFor(c, 1)).toBeCloseTo(2.0, 3);
    expect(WaveDirector.spawnIntervalFor(c, 999)).toBeCloseTo(c.spawnIntervalSec.min, 3);
    const walker = defs().zombies.walker!;
    expect(WaveDirector.speedFor(walker, 999)).toBeCloseTo(walker.maxMoveSpeed, 3);
    const mix = WaveDirector.mixFor(c, 1);
    expect(mix.walker).toBeDefined();
    expect(mix.runner).toBeUndefined();
  });

  it("respects the alive cap and never clears a wave without kills", () => {
    const w = world(7);
    const pid = w.addPlayer("t");
    const p = w.players.get(pid)!;
    p.hp = 1e9;
    p.maxHp = 1e9;
    let maxAlive = 0;
    let started = 0;
    for (let i = 0; i < 20 * 90; i++) {
      w.setInput(pid, intent());
      w.step();
      maxAlive = Math.max(maxAlive, w.zombies.size);
      started += w.events.filter((e) => e.type === "wave_started").length;
    }
    expect(maxAlive).toBeLessThanOrEqual(defs().constants.zone.maxAliveZombies);
    expect(started).toBe(1);
    expect(w.director.spawned).toBe(w.director.toSpawn);
  });
});

describe("supply cache", () => {
  const setup = () => {
    const w = world(5);
    const p = w.players.get(w.addPlayer("t"))!;
    const b = [...w.boxSys.boxes.values()][0]!;
    p.pos = { ...b.pos };
    const press = () => {
      w.setInput(p.id, intent(Btn.INTERACT));
      w.step();
      w.setInput(p.id, intent());
      w.step();
    };
    return { w, p, b, press };
  };

  it("rolls, offers and gives a weapon the buyer does not own", () => {
    const { w, p, b, press } = setup();
    const price = defs().constants.supplyBox.price;
    p.currency = price - 1;
    press();
    expect(b.state).toBe(BoxState.IDLE);
    p.currency = price + 100;
    press();
    expect(b.state).toBe(BoxState.ROLLING);
    expect(p.currency).toBe(100);
    expect(defs().weapons[b.result]!.boxWeight).toBeGreaterThan(0);
    for (let i = 0; i < defs().constants.supplyBox.rollSec * 20 + 1; i++) w.step();
    expect(b.state).toBe(BoxState.OFFER);
    const result = b.result;
    press();
    expect(b.state).toBe(BoxState.IDLE);
    expect(p.weapon()!.id).toBe(result);
  });

  it("offer expires; distribution follows weights", () => {
    const { w, p, b, press } = setup();
    p.currency = 5000;
    press();
    const c = defs().constants.supplyBox;
    for (let i = 0; i < (c.rollSec + c.offerSec) * 20 + 2; i++) w.step();
    expect(b.state).toBe(BoxState.IDLE);
    expect(p.weapons.length).toBe(1);
    const counts: Record<string, number> = {};
    for (let i = 0; i < 3000; i++) {
      const r = w.boxSys.roll(p);
      counts[r] = (counts[r] ?? 0) + 1;
    }
    expect(counts.pistol).toBeUndefined();
    let total = 0;
    for (const [id, wd] of Object.entries(defs().weapons)) if (p.findWeapon(id) < 0) total += wd.boxWeight;
    for (const [id, n] of Object.entries(counts)) expect(Math.abs(n / 3000 - defs().weapons[id]!.boxWeight / total)).toBeLessThan(0.05);
  });
});

describe("bot playthrough", () => {
  it("a bot clears waves and a tick stays cheap", () => {
    const w = world(1234);
    const pid = w.addPlayer("bot");
    const bot = new BotBrain(pid, 99);
    const p = w.players.get(pid)!;
    p.weapons[0] = new WeaponState("rifle", defs().weapons.rifle!);
    p.weapons[0]!.reserve = 100000;
    let cleared = 0;
    let total = 0;
    const ticks = 20 * 240;
    for (let i = 0; i < ticks; i++) {
      w.setInput(pid, bot.think(w));
      const t0 = performance.now();
      w.step();
      total += performance.now() - t0;
      cleared += w.events.filter((e) => e.type === "wave_cleared").length;
      if (w.zoneState === ZoneState.GAME_OVER) break;
    }
    console.log(`bot: waves cleared=${cleared} kills=${p.kills} avg tick=${(total / ticks).toFixed(3)} ms`);
    expect(cleared).toBeGreaterThanOrEqual(2);
    expect(p.kills).toBeGreaterThanOrEqual(10);
    expect(total / ticks).toBeLessThan(2.0);
  });
});
