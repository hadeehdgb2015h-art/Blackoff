/** Authoritative state objects (mirrors of sim_player.gd, sim_zombie.gd,
 *  weapon_state.gd, player_intent.gd). */
import type { WeaponDef, ZombieDef } from "../shared/schemas.js";
import type { V2 } from "./math.js";

/** Input bits, identical to protocol.json `inputButtons`. */
export const Btn = { FIRE_HELD: 1, RELOAD: 2, INTERACT: 4, REVIVE: 8, SWITCH: 16, FIRE_PRESSED: 32 } as const;
export const BTN_MASK = 63;

export interface PlayerIntent {
  seq: number;
  /** x = strafe right, y = forward; length <= 1 */
  move: V2;
  yaw: number;
  pitch: number;
  buttons: number;
}

export const emptyIntent = (): PlayerIntent => ({ seq: 0, move: { x: 0, y: 0 }, yaw: 0, pitch: 0, buttons: 0 });

export class WeaponState {
  mag: number;
  reserve: number;
  constructor(readonly id: string, readonly def: WeaponDef) {
    this.mag = def.magSize;
    this.reserve = def.reserveStart;
  }
  canReload(): boolean { return this.mag < this.def.magSize && this.reserve > 0; }
  finishReload(): void {
    const take = Math.min(this.def.magSize - this.mag, this.reserve);
    this.mag += take;
    this.reserve -= take;
  }
  interval(): number { return 60 / this.def.fireRateRpm; }
  isAuto(): boolean { return this.def.fireMode === "auto"; }
}

export enum PlayerState { ALIVE = 0, DOWNED = 1, DEAD = 2 }

/** Infection mode sides (classic: everyone is a soldier). */
export enum Team { SOLDIER = 0, ZOMBIE = 1 }

export class SimPlayer {
  pos: V2 = { x: 0, y: 0 };
  prevPos: V2 = { x: 0, y: 0 };
  yaw = 0;
  pitch = 0;
  hp = 100;
  maxHp = 100;
  state = PlayerState.ALIVE;
  currency = 0;
  weapons: WeaponState[] = [];
  slot = 0;
  nextFireTime = 0;
  reloadEnd = 0;
  switchEnd = 0;
  lastDamageTime = -999;
  downedTime = 0;
  /** downed teammate this player is reviving (0 = none) */
  reviveTarget = 0;
  /** ticks the revive has been held */
  reviveTicks = 0;
  buttonsPrev = 0;
  moving = false;
  input: PlayerIntent = emptyIntent();
  kills = 0;
  headshots = 0;
  shotsFired = 0;
  downs = 0;
  revives = 0;
  /** owned perk ids (lost when downed) */
  perks: string[] = [];
  /** infection mode: soldier or infected */
  team = Team.SOLDIER;
  /** infection mode: sim time a dead infected player comes back */
  respawnAt = 0;
  deaths = 0;

  constructor(readonly id: number, public name: string) {}

  weapon(): WeaponState | null { return this.weapons[this.slot] ?? null; }
  findWeapon(id: string): number { return this.weapons.findIndex((w) => w.id === id); }
  isReloading(): boolean { return this.reloadEnd > 0; }
  isAlive(): boolean { return this.state === PlayerState.ALIVE; }
}

export enum ZombieState { CHASE = 0, WINDUP = 1 }

export class SimZombie {
  pos: V2 = { x: 0, y: 0 };
  prevPos: V2 = { x: 0, y: 0 };
  yaw = 0;
  hp = 100;
  maxHp = 100;
  speed = 1.5;
  state = ZombieState.CHASE;
  targetId = -1;
  attackReadyTime = 0;
  windupEnd = 0;
  path: V2[] = [];
  pathIndex = 0;
  pathGoal: V2 = { x: Infinity, y: Infinity };
  nextRepathTime = 0;
  stuckCheckTime = 0;
  stuckCheckPos: V2 = { x: 0, y: 0 };
  moving = false;

  constructor(readonly id: number, readonly type: string, readonly def: ZombieDef) {}
  radius(): number { return this.def.radius; }
}

/** Events are plain objects with a `type` (same names as the GDScript sim). */
export type SimEvent = { type: string; tick?: number; [k: string]: unknown };
