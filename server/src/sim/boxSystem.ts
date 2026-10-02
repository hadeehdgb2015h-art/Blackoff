/** Supply cache (mirror of box_system.gd): pay, wait for the roll, take a random
 *  weapon. The result is decided when the box opens; clients learn it from
 *  `box_offer`. Weights: weapons.<id>.boxWeight, owned weapons excluded. */
import type { SimPlayer } from "./entities.js";
import type { V2 } from "./math.js";
import type { SimWorld } from "./simWorld.js";

export enum BoxState { IDLE = 0, ROLLING = 1, OFFER = 2 }

export class Box {
  state = BoxState.IDLE;
  ownerPid = -1;
  result = "";
  phaseEnd = 0;
  constructor(readonly id: string, readonly pos: V2) {}
}

export class BoxSystem {
  boxes = new Map<string, Box>();

  constructor(private readonly w: SimWorld) {
    for (const it of w.map.interactables) if (it.kind === "box") this.boxes.set(it.id, new Box(it.id, it.pos));
  }

  private get cfg() { return this.w.constants.supplyBox; }

  update(): void {
    const w = this.w;
    for (const b of this.boxes.values()) {
      if (b.state === BoxState.ROLLING && w.time >= b.phaseEnd) {
        b.state = BoxState.OFFER;
        b.phaseEnd = w.time + this.cfg.offerSec;
        w.emit({ type: "box_offer", box: b.id, pid: b.ownerPid, weapon: b.result, until: b.phaseEnd });
      } else if (b.state === BoxState.OFFER && (w.time >= b.phaseEnd || !w.players.has(b.ownerPid))) {
        this.close(b);
        w.emit({ type: "box_expired", box: b.id });
      }
    }
  }

  option(b: Box, p: SimPlayer): { action: string; cost: number; label: string; full: boolean; busy?: boolean; item?: string } {
    if (b.state === BoxState.IDLE) return { action: "box", cost: this.cfg.price, label: "Supply Cache", full: false };
    if (b.state === BoxState.ROLLING && b.ownerPid === p.id) return { action: "wait", cost: 0, label: "Rolling...", full: false, busy: true };
    if (b.state === BoxState.OFFER && b.ownerPid === p.id) {
      return { action: "take", item: b.result, cost: 0, label: this.w.defs.weapons[b.result]!.displayName, full: false };
    }
    return { action: "wait", cost: 0, label: "Supply Cache in use", full: false, busy: true };
  }

  open(b: Box, p: SimPlayer): boolean {
    const w = this.w;
    if (b.state !== BoxState.IDLE) return false;
    const result = this.roll(p);
    if (result === "") return false;
    b.state = BoxState.ROLLING;
    b.ownerPid = p.id;
    b.result = result;
    b.phaseEnd = w.time + this.cfg.rollSec;
    w.addCurrency(p, -this.cfg.price, "supply_box");
    w.emit({ type: "box_opened", box: b.id, pid: p.id, cost: this.cfg.price, until: b.phaseEnd });
    return true;
  }

  take(b: Box, p: SimPlayer): void {
    if (b.state !== BoxState.OFFER || b.ownerPid !== p.id) return;
    this.w.playerSys.giveWeapon(p, b.result);
    this.w.emit({ type: "box_taken", box: b.id, pid: p.id, weapon: b.result });
    this.close(b);
  }

  /** Weighted pick over weapons with boxWeight > 0 that p does not own (ids sorted, like the client). */
  roll(p: SimPlayer): string {
    const pool: [string, number][] = [];
    let total = 0;
    for (const id of Object.keys(this.w.defs.weapons).sort()) {
      const wt = this.w.defs.weapons[id]!.boxWeight ?? 0;
      if (wt > 0 && p.findWeapon(id) < 0) {
        pool.push([id, wt]);
        total += wt;
      }
    }
    if (total <= 0) return "";
    let r = this.w.rng.randf() * total;
    let last = "";
    for (const [id, wt] of pool) {
      last = id;
      r -= wt;
      if (r <= 0) return id;
    }
    return last;
  }

  private close(b: Box): void {
    b.state = BoxState.IDLE;
    b.ownerPid = -1;
    b.result = "";
  }
}
