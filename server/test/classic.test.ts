/** Phase 8 rules: power-up drops, perk machines, energy/wind weapons
 *  (mirrored by client/tests/test_classic.gd). */
import { describe, expect, it } from "vitest";
import { Btn, WeaponState } from "../src/sim/entities.js";
import { SimWorld } from "../src/sim/simWorld.js";
import { defs, intent } from "./helpers.js";

/** A world whose shared data is a private copy (tests tweak drop chances). */
function world(seed = 5, tweak: (d: ReturnType<typeof defs>) => void = () => {}) {
  const d = structuredClone(defs());
  tweak(d);
  return new SimWorld(d, "facility_01", seed);
}

function spawnZombieAt(w: SimWorld, x: number, y: number, hp = 50) {
  const before = new Set(w.zombies.keys());
  w.zombieSys.spawn("walker", 1);
  const z = [...w.zombies.values()].find((z) => !before.has(z.id))!;
  z.pos = { x, y };
  z.hp = hp;
  return z;
}

describe("power-ups", () => {
  it("a kill drops one, walking over it applies it to everyone", () => {
    const w = world(5, (d) => { d.constants.powerups.dropChance = 1; });
    const a = w.players.get(w.addPlayer("A"))!;
    const b = w.players.get(w.addPlayer("B"))!;
    b.pos = { x: a.pos.x + 3, y: a.pos.y };
    const z = spawnZombieAt(w, a.pos.x, a.pos.y - 2, 1);
    w.zombieSys.applyDamage(z, 10, false, a, { x: 0, y: 1, z: 0 });
    const drop = [...w.powerups.drops.values()][0]!;
    expect(drop).toBeDefined();
    expect(w.events.some((e) => e.type === "powerup_dropped" && e.id === drop.id)).toBe(true);
    // second kill right away: no second drop (cooldown + max on ground)
    const z2 = spawnZombieAt(w, a.pos.x + 1, a.pos.y - 2, 1);
    w.zombieSys.applyDamage(z2, 10, false, a, { x: 0, y: 1, z: 0 });
    expect(w.powerups.drops.size).toBe(1);
    // B walks over it
    b.pos = { ...drop.pos };
    w.step();
    expect(w.powerups.drops.size).toBe(0);
    expect(w.events.some((e) => e.type === "powerup_taken" && e.pid === b.id && e.ptype === drop.type)).toBe(true);
  });

  it("insta-kill, double points, max ammo, nuke and fire sale do what they say", () => {
    const w = world(5);
    const a = w.players.get(w.addPlayer("A"))!;
    const pu = w.powerups as unknown as { apply(type: string, pid: number): void };
    // insta-kill: any hit is lethal
    pu.apply("instaKill", a.id);
    const z = spawnZombieAt(w, 0, 0, 500);
    w.zombieSys.applyDamage(z, 1, false, a, { x: 0, y: 1, z: 0 });
    expect(w.zombies.has(z.id)).toBe(false);
    // double points
    const cash = a.currency;
    pu.apply("doublePoints", a.id);
    w.addCurrency(a, 50, "hit");
    expect(a.currency).toBe(cash + 100);
    w.addCurrency(a, -30, "purchase");
    expect(a.currency).toBe(cash + 70); // spending is not doubled
    // max ammo
    const wp = a.weapon()!;
    wp.mag = 1;
    wp.reserve = 2;
    pu.apply("maxAmmo", a.id);
    expect([wp.mag, wp.reserve]).toEqual([wp.def.magSize, wp.def.reserveMax]);
    // nuke
    spawnZombieAt(w, 1, 1);
    spawnZombieAt(w, 2, 2);
    const before = a.currency;
    pu.apply("nuke", a.id);
    expect(w.zombies.size).toBe(0);
    expect(a.currency).toBe(before + 400 * 2); // double points still on
    expect(a.kills).toBe(1); // nuke kills are not credited
    // fire sale
    pu.apply("fireSale", a.id);
    expect(w.boxSys.price()).toBe(10);
    for (let i = 0; i < 31 * 20; i++) w.step();
    expect(w.boxSys.price()).toBe(defs().constants.supplyBox.price);
    expect(w.powerups.isActive("instaKill")).toBe(false);
  });
});

describe("perk machines", () => {
  it("sells once, applies health/reload/speed/swap multipliers, all lost when downed", () => {
    const w = world(5);
    const a = w.players.get(w.addPlayer("A"))!;
    const ironhide = w.map.interactables.find((it) => it.id === "perk_ironhide")!;
    a.pos = { ...ironhide.pos };
    a.currency = 10_000;
    expect(w.interactOption(a.id)).toMatchObject({ action: "perk", item: "ironhide", cost: 2500, full: false, affordable: true });
    w.setInput(a.id, intent(Btn.INTERACT));
    w.step();
    expect(a.perks).toEqual(["ironhide"]);
    expect(a.currency).toBe(7500);
    expect(a.maxHp).toBe(160);
    expect(a.hp).toBe(160);
    expect(w.interactOption(a.id)?.full).toBe(true);
    w.setInput(a.id, intent(Btn.INTERACT));
    w.step();
    expect(a.currency).toBe(7500); // not sold twice
    // other perks
    a.perks.push("quickhands", "longstride", "switchblade");
    expect(w.playerSys.perkMul(a, "reloadMul")).toBe(0.5);
    expect(w.playerSys.perkMul(a, "moveSpeedMul")).toBeCloseTo(1.12);
    expect(w.playerSys.perkMul(a, "switchMul")).toBeCloseTo(0.4);
    const wp = a.weapon()!;
    wp.mag = 0;
    w.setInput(a.id, intent(Btn.RELOAD));
    w.step();
    expect(a.reloadEnd - w.time).toBeCloseTo(wp.def.reloadSec * 0.5, 3);
    // downed: perks gone, health back to base
    w.damagePlayer(a, 1000, 0);
    expect(a.perks).toEqual([]);
    expect(a.maxHp).toBe(100);
  });
});

describe("energy and wind weapons", () => {
  it("the arc lance splashes nearby zombies; the gale cannon clears a cone in front only", () => {
    const w = world(5);
    const a = w.players.get(w.addPlayer("A"))!;
    a.pos = { x: 0, y: -14 }; // open yard
    a.weapons[0] = new WeaponState("arc", w.defs.weapons.arc!);
    const direct = spawnZombieAt(w, 0, -20, 1000);
    const near = spawnZombieAt(w, 1.5, -20.5, 1000);
    const far = spawnZombieAt(w, 6, -20, 1000);
    w.setInput(a.id, intent(Btn.FIRE_HELD | Btn.FIRE_PRESSED, { yaw: 0, pitch: -0.02 }));
    w.step();
    expect(direct.hp).toBeLessThan(1000);
    expect(near.hp).toBe(1000 - 120);
    expect(far.hp).toBe(1000);

    a.weapons[0] = new WeaponState("gale", w.defs.weapons.gale!);
    a.nextFireTime = 0;
    const front = spawnZombieAt(w, 0.5, -19, 100);
    const side = spawnZombieAt(w, 5, -16, 100);   // outside the 50 degree cone
    const behind = spawnZombieAt(w, 0, -9, 100);
    w.setInput(a.id, intent(Btn.FIRE_HELD | Btn.FIRE_PRESSED, { yaw: 0 }));
    w.step();
    expect(w.zombies.has(front.id)).toBe(false);
    expect(w.zombies.has(near.id)).toBe(false); // in the cone as well
    expect(side.hp).toBe(100);
    expect(behind.hp).toBe(100);
    expect(w.events.some((e) => e.type === "shot" && e.weapon === "gale" && e.hit === "zombie")).toBe(true);
  });
});
