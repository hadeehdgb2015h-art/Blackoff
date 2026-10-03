/**
 * The contract between the game and the puzzle module (phase 31).
 *
 * The puzzles themselves are a secret the owner keeps: their rules live in an
 * encrypted module (server/assets/puzzles, see pack.ts) that only the owner's
 * key opens. This file is all the public code knows about them: a module
 * places generic objects in a zone (painted text, lanterns, a terminal, a
 * lever, a cage, a canister, a transmitter, a weapon case), hears what players
 * do with them (use, shoot, type a code) and what happens in the game, and can
 * talk to the players, spawn zombies, give a weapon and pay the reward.
 * Clients only draw the objects; they never learn the rules.
 */
import type { SimEvent, SimPlayer } from "../sim/entities.js";
import type { V2 } from "../sim/math.js";
import type { SimWorld } from "../sim/simWorld.js";

/** Protocol enum puzzleKind. */
export const PuzzleKind = { TEXT: 0, LANTERN: 1, TERMINAL: 2, LEVER: 3, CAGE: 4, CANISTER: 5, TRANSMITTER: 6, CASE: 7 } as const;
export type PuzzleKindId = (typeof PuzzleKind)[keyof typeof PuzzleKind];

/** A text in the three interface languages. */
export interface Texts { en: string; ar: string; ru: string }
export type Lang = keyof Texts;

export interface PuzzleObjectDef {
  kind: PuzzleKindId;
  x: number;
  /** height of the object's base (or of the text's centre) */
  y: number;
  z: number;
  yaw?: number;
  /** kind-specific size: text height, cage half-width (m) */
  size?: number;
  state?: number;
  /** what a text object shows (digits, marks), the same in every language */
  text?: string;
  /** the USE prompt; none = cannot be used */
  label?: Texts | null;
  useRadius?: number;
  /** > 0: shots passing this close to (x, y + shootHeight, z) count as hitting it */
  shootRadius?: number;
  shootHeight?: number;
  /** > 0: using it opens a keypad for this many digits */
  codeLength?: number;
}

export interface PuzzleObject extends Required<Omit<PuzzleObjectDef, "label">> {
  id: number;
  label: Texts | null;
}

/** What the game lets a puzzle module do in one zone. */
export interface PuzzleApi {
  readonly world: SimWorld;
  /** zone id, for the owner's answer sheet */
  readonly zoneId: number;
  /** deterministic random numbers in [0, 1) for this zone */
  random(): number;
  /** humans in the zone (not AI soldiers) */
  humans(): SimPlayer[];
  add(def: PuzzleObjectDef): number;
  update(id: number, patch: Partial<Pick<PuzzleObject, "state" | "text" | "x" | "y" | "z" | "yaw" | "label" | "useRadius" | "shootRadius" | "codeLength">>): void;
  remove(id: number): void;
  get(id: number): PuzzleObject | undefined;
  /** a line for everyone (or one player); big = a banner */
  say(text: Texts, opts?: { to?: number; big?: boolean }): void;
  /** spawns zombies of a type at entries (as the wave director would); returns how many came */
  spawnZombies(type: string, count: number): number;
  /** gives a player a weapon (replacing the one in hand when both slots are full) */
  giveWeapon(pid: number, weaponId: string): void;
  /** pays the reward to these human players (TON set by the owner) and tells the owner */
  reward(pids: number[]): void;
  /** walkable point near p */
  walkableNear(p: V2, radius: number): V2;
}

/** One zone's puzzles. Every hook is optional. */
export interface PuzzleInstance {
  /** each simulation tick, after the world stepped (events of the tick in `events`) */
  tick?(events: readonly SimEvent[]): void;
  onUse?(pid: number, objectId: number, code: string): void;
  onShoot?(pid: number, objectId: number): void;
  /** the answers of this match, for the owner's eyes only (Arabic) */
  answers?(): string;
}

export interface PuzzleModule {
  /** a short name and version, shown to the owner */
  readonly name: string;
  create(api: PuzzleApi): PuzzleInstance;
  /** how the puzzles are solved, for the owner only (Arabic) */
  explain(): string;
}
