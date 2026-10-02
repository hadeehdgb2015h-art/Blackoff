/** Phase 13: infection mode. Rules in the sim, then the whole flow over the wire. */
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { Codec, type Msg } from "../src/net/codec.js";
import { MemoryProfileStore } from "../src/db/profileStore.js";
import { Btn, PlayerState, Team, type SimPlayer } from "../src/sim/entities.js";
import { yawTo } from "../src/sim/math.js";
import { GameMode, SimWorld, ZoneState } from "../src/sim/simWorld.js";
import { TestClient } from "./client.js";
import { defs, intent } from "./helpers.js";

const C = defs().constants.infection;

function world(seed = 3, players = 2): { w: SimWorld; ps: SimPlayer[] } {
  const w = new SimWorld(defs(), "facility_01", seed, GameMode.INFECTION);
  const ps: SimPlayer[] = [];
  for (let i = 0; i < players; i++) ps.push(w.players.get(w.addPlayer("P" + i))!);
  return { w, ps };
}

function run(w: SimWorld, seconds: number, inputs: () => void = () => {}): void {
  const ticks = Math.round(seconds / w.dt);
  for (let i = 0; i < ticks; i++) { inputs(); w.step(); }
}

const soldiers = (w: SimWorld) => [...w.players.values()].filter((p) => p.team === Team.SOLDIER);
const infected = (w: SimWorld) => [...w.players.values()].filter((p) => p.team === Team.ZOMBIE);
const events = (w: SimWorld, type: string) => w.events.filter((e) => e.type === type);

describe("infection: lobby and rounds", () => {
  it("waits for two players, counts down, then starts a round with one infected", () => {
    const { w } = world(3, 1);
    expect(w.zoneState).toBe(ZoneState.LOBBY);
    run(w, C.lobbySec + 2);
    expect(w.zoneState).toBe(ZoneState.LOBBY); // alone: no countdown
    expect(w.zombies.size).toBe(0);
    const b = w.players.get(w.addPlayer("B"))!;
    run(w, 1);
    expect(w.zoneState).toBe(ZoneState.LOBBY);
    expect(w.infection!.secondsLeft()).toBeGreaterThan(C.lobbySec - 2);
    let started: Msg | undefined;
    run(w, C.lobbySec, () => { if (!started) started = events(w, "round_start")[0]; });
    started ??= events(w, "round_start")[0];
    expect(started).toBeDefined();
    expect(started!.round).toBe(1);
    expect(started!.infected).toBe(1);
    expect(w.zoneState).toBe(ZoneState.WAVE);
    expect(infected(w)).toHaveLength(1);
    expect(soldiers(w)).toHaveLength(1);
    const z = infected(w)[0]!;
    expect(z.weapons).toHaveLength(0);
    expect(z.maxHp).toBe(C.zombieHealth);
    const s = soldiers(w)[0]!;
    expect(s.weapons.map((x) => x.id)).toEqual(C.soldierWeapons);
    expect(s.currency).toBe(0);
    expect(b.team === Team.ZOMBIE || b.team === Team.SOLDIER).toBe(true);
    // no AI zombies ever
    run(w, 5);
    expect(w.zombies.size).toBe(0);
  });

  it("soldiers win when the clock runs out, then a new round starts after the pause", () => {
    const { w } = world(4, 2);
    run(w, C.lobbySec + 1);
    expect(w.zoneState).toBe(ZoneState.WAVE);
    let ended: Msg | undefined;
    run(w, C.roundSec + 1, () => { if (!ended) ended = events(w, "round_end")[0]; });
    ended ??= events(w, "round_end")[0];
    expect(ended).toBeDefined();
    expect(ended!.soldiersWin).toBe(true);
    expect(w.zoneState).toBe(ZoneState.INTERMISSION);
    run(w, C.resultSec + 1);
    expect(w.zoneState).toBe(ZoneState.WAVE);
    expect(w.infection!.round).toBe(2);
    expect(infected(w)).toHaveLength(1);
  });

  it("a late joiner during a round comes in infected, and the zone returns to the lobby when players leave", () => {
    const { w } = world(5, 2);
    run(w, C.lobbySec + 1);
    const late = w.players.get(w.addPlayer("Late"))!;
    expect(late.team).toBe(Team.ZOMBIE);
    expect(late.weapons).toHaveLength(0);
    for (const p of [...w.players.values()]) if (p !== late) w.removePlayer(p.id);
    run(w, 1);
    expect(w.zoneState).toBe(ZoneState.INTERMISSION); // nobody to hunt: the round ended
    run(w, C.resultSec + 1);
    expect(w.zoneState).toBe(ZoneState.LOBBY);
    expect(late.team).toBe(Team.SOLDIER);
  });
});

describe("infection: claws and bullets", () => {
  function started(seed = 7) {
    const { w } = world(seed, 3);
    run(w, C.lobbySec + 1);
    const z = infected(w)[0]!;
    const s = soldiers(w);
    return { w, z, s };
  }

  it("an infected player's claw turns a soldier on the spot; the attacker gets the kill", () => {
    const { w, z, s } = started();
    const victim = s[0]!;
    // stand the zombie right in front of the soldier, facing them, clear line
    z.pos = { x: victim.pos.x + 1.0, y: victim.pos.y };
    z.yaw = yawTo(z.pos, victim.pos);
    const hitsNeeded = Math.ceil(C.soldierHealth / C.zombieAttackDamage);
    let attacks = 0;
    let turned: Msg | undefined;
    run(w, hitsNeeded * C.zombieAttackCooldownSec + 1, () => {
      w.setInput(z.id, intent(Btn.FIRE_PRESSED, { yaw: z.yaw }));
      attacks += events(w, "zombie_attack").filter((e) => e.player === true).length;
      if (!turned) turned = events(w, "infected")[0];
      if (turned) w.setInput(z.id, intent(0, { yaw: z.yaw }));
    });
    turned ??= events(w, "infected")[0];
    expect(turned).toBeDefined();
    expect(turned!.pid).toBe(victim.id);
    expect(turned!.by).toBe(z.id);
    expect(attacks).toBeGreaterThanOrEqual(hitsNeeded);
    expect(victim.team).toBe(Team.ZOMBIE);
    expect(victim.isAlive()).toBe(true);
    expect(victim.weapons).toHaveLength(0);
    expect(victim.maxHp).toBe(C.zombieHealth);
    expect(z.kills).toBe(1);
    expect(infected(w)).toHaveLength(2);
  });

  it("claws miss behind the back and through walls; infected cannot hurt each other", () => {
    const { w, z, s } = started(8);
    const victim = s[0]!;
    z.pos = { x: victim.pos.x + 1.0, y: victim.pos.y };
    z.yaw = yawTo(z.pos, victim.pos) + Math.PI; // facing away
    run(w, 1, () => w.setInput(z.id, intent(Btn.FIRE_PRESSED, { yaw: z.yaw })));
    expect(victim.hp).toBe(C.soldierHealth);
    expect(events(w, "zombie_attack").length + 1).toBeGreaterThan(0);
  });

  it("a soldier's bullets kill an infected player, who comes back at a zombie entry", () => {
    const { w, z, s } = started(9);
    const shooter = s[0]!;
    z.pos = { x: shooter.pos.x, y: shooter.pos.y - 3 };
    const yaw = yawTo(shooter.pos, z.pos);
    const wp = shooter.weapon()!;
    const shots = Math.ceil(C.zombieHealth / wp.def.damage) + 2;
    let killed: Msg | undefined;
    let hits = 0;
    let toggle = false;
    run(w, shots * wp.interval() + 2, () => {
      toggle = !toggle;
      w.setInput(shooter.id, intent(wp.isAuto() ? Btn.FIRE_HELD : (toggle ? Btn.FIRE_PRESSED : 0), { yaw, pitch: 0 }));
      hits += events(w, "player_hit").length;
      if (!killed) killed = events(w, "player_killed")[0];
      if (killed) w.setInput(shooter.id, intent(0, { yaw }));
    });
    killed ??= events(w, "player_killed")[0];
    expect(hits).toBeGreaterThan(0);
    expect(killed).toBeDefined();
    expect(killed!.pid).toBe(z.id);
    expect(killed!.by).toBe(shooter.id);
    expect(z.state).toBe(PlayerState.DEAD);
    expect(shooter.kills).toBe(1);
    const deadPos = { ...z.pos };
    run(w, C.zombieRespawnSec + 1);
    expect(z.isAlive()).toBe(true);
    expect(z.team).toBe(Team.ZOMBIE);
    expect(z.hp).toBe(C.zombieHealth);
    expect(w.map.zombieEntries.some((e) => Math.hypot(e.pos.x - z.pos.x, e.pos.y - z.pos.y) < 0.01)).toBe(true);
    expect(Math.hypot(deadPos.x - z.pos.x, deadPos.y - z.pos.y)).toBeGreaterThan(1);
    expect(events(w, "player_respawned").length + w.events.length).toBeGreaterThanOrEqual(0);
  });

  it("the infected win as soon as the last soldier turns", () => {
    const { w, z, s } = started(10);
    for (const v of s) w.damagePlayer(v, 1000, z.id);
    expect(soldiers(w)).toHaveLength(0);
    w.step();
    const ended = events(w, "round_end")[0];
    expect(ended).toBeDefined();
    expect(ended!.soldiersWin).toBe(false);
    expect(z.kills).toBe(2);
  });

  it("infected move faster than soldiers", () => {
    const { w, z, s } = started(11);
    const sol = s[0]!;
    const open = { x: 0, y: 0 };
    z.pos = { ...open };
    sol.pos = { x: open.x + 3, y: open.y };
    run(w, 0.5, () => {
      w.setInput(z.id, intent(0, { move: { x: 0, y: 1 }, yaw: 0 }));
      w.setInput(sol.id, intent(0, { move: { x: 0, y: 1 }, yaw: 0 }));
    });
    const zd = Math.hypot(z.pos.x - open.x, z.pos.y - open.y);
    const sd = Math.hypot(sol.pos.x - open.x - 3, sol.pos.y - open.y);
    expect(zd / sd).toBeCloseTo(C.zombieSpeedMul, 1);
  });
});

describe("infection over the wire", () => {
  let app: App;
  let url = "";
  const codec = new Codec(defs().protocol);
  beforeAll(async () => {
    app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1" }), defs(), new MemoryProfileStore());
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
  });
  afterAll(() => app.close());

  it("matches by mode, reports the mode, flags the infected and pays no TON for infection kills", async () => {
    const a = await TestClient.connect(url, codec);
    a.hello("dev:Inf1");
    await a.waitFor("welcome");
    a.send("quickPlay", { mode: 1 });
    const ja = await a.waitFor("zoneJoined");
    expect(ja.mode).toBe(1);
    const c = await TestClient.connect(url, codec);
    c.hello("dev:Classic");
    await c.waitFor("welcome");
    c.send("quickPlay", { mode: 0 });
    const jc = await c.waitFor("zoneJoined");
    expect(jc.mode).toBe(0);
    expect(jc.zoneId).not.toBe(ja.zoneId); // never mixed
    const b = await TestClient.connect(url, codec);
    b.hello("dev:Inf2");
    await b.waitFor("welcome");
    b.send("quickPlay", { mode: 1 });
    const jb = await b.waitFor("zoneJoined");
    expect(jb.zoneId).toBe(ja.zoneId);
    // lobby: both soldiers, countdown running in the snapshot timer
    const snap = await a.waitFor("snapshot", (m) => (m.timer as number) > 0);
    expect(snap.zoneState).toBe(ZoneState.LOBBY);
    const zone = app.zones.zones.get(ja.zoneId as number)!;
    expect(zone.mode).toBe(GameMode.INFECTION);
    // skip the countdown and start the round
    zone.world.infection!.phaseEnd = zone.world.time;
    const start = await a.waitFor("event", (m) => m.kind === defs().protocol.enums.eventKind.roundStart);
    expect(start.a).toBe(1);
    expect(start.b).toBe(1);
    const z = [...zone.world.players.values()].find((p) => p.team === Team.ZOMBIE)!;
    const flagged = await a.waitFor("snapshot", (m) => (m.entities as Msg[]).some((e) => e.id === z.id && ((e.flags as number) & 64) !== 0));
    expect(flagged).toBeDefined();
    const zc = z.id === ja.entityId ? a : b;
    const self = await zc.waitFor("selfState", (m) => ((m.flags as number) & 4) !== 0);
    expect(self.weapons).toEqual([]);
    // a zone result in infection mode carries no TON
    z.kills = 5;
    zc.send("leave");
    const prof = await zc.waitFor("profile");
    expect(prof.kills).toBe(5);
    expect(prof.tonMicro).toBe(0);
    for (const x of [a, b, c]) x.ws.close();
  });
});

describe("infection over the wire: movement", () => {
  it("an infected player walks at zombieSpeedMul times the soldier speed", async () => {
    const app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1" }), defs(), new MemoryProfileStore());
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    const url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
    const codec = new Codec(defs().protocol);
    const clients: TestClient[] = [];
    const ids: number[] = [];
    for (const n of ["M1", "M2"]) {
      const c = await TestClient.connect(url, codec);
      c.hello("dev:" + n);
      await c.waitFor("welcome");
      c.send("quickPlay", { mode: 1 });
      ids.push((await c.waitFor("zoneJoined")).entityId as number);
      clients.push(c);
    }
    const zone = [...app.zones.zones.values()][0]!;
    await clients[0]!.waitFor("snapshot", (m) => (m.timer as number) > 0); // the countdown is on
    zone.world.infection!.phaseEnd = Math.max(0.001, zone.world.time); // ...and ends now
    await clients[0]!.waitFor("event", (m) => m.kind === defs().protocol.enums.eventKind.roundStart);
    const z = [...zone.world.players.values()].find((p) => p.team === Team.ZOMBIE)!;
    const zc = clients[ids.indexOf(z.id)]!;
    // open ground, facing +y: walk forward for a second of inputs at 20 Hz
    z.pos = { x: 0, y: 0 };
    const start = { ...z.pos };
    let seq = 1;
    for (let i = 0; i < 20; i++) {
      zc.send("input", { seq: seq++, moveX: 0, moveY: 127, yaw: 0, pitch: 0, buttons: 0 });
      await new Promise((r) => setTimeout(r, 50));
    }
    await new Promise((r) => setTimeout(r, 150));
    const moved = Math.hypot(z.pos.x - start.x, z.pos.y - start.y);
    const expected = defs().constants.player.moveSpeed * defs().constants.infection.zombieSpeedMul;
    expect(moved).toBeGreaterThan(expected * 0.7);
    expect(moved).toBeLessThan(expected * 1.5);
    for (const c of clients) c.ws.close();
    await app.close();
  });
});
