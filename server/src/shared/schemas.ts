import { z } from "zod";

const num = z.number().finite();
const pos = num.nonnegative();

export const ConstantsSchema = z.object({
  schemaVersion: z.literal(1),
  sim: z.object({ tickRate: z.number().int().positive(), snapshotRate: z.number().int().positive(), floorHeight: pos, gravity: num }),
  zone: z.object({
    maxPlayers: z.number().int().positive(),
    maxPlayersHardCap: z.number().int().positive(),
    maxAliveZombies: z.number().int().positive(),
    emptyZoneTtlSec: pos,
    quickPlayJoinableUntilWave: z.number().int().nonnegative(),
  }),
  player: z.object({
    maxHealth: pos, radius: pos, height: pos, eyeHeight: pos, headCenterHeight: pos, headRadius: pos,
    moveSpeed: pos, healthRegenDelaySec: pos, healthRegenPerSec: pos, downedBleedoutSec: pos,
    reviveTimeSec: pos, reviveRange: pos, interactRange: pos, startCurrency: z.number().int().nonnegative(),
    startWeapon: z.string(), maxWeaponSlots: z.number().int().positive(), weaponSwitchSec: pos, stepHeight: pos,
  }),
  economy: z.object({ hitReward: pos, headshotKillBonus: pos, reviveReward: pos }),
  maps: z.object({ default: z.string(), navCellSize: num.positive(), navAgentRadius: pos }),
  supplyBox: z.object({ price: z.number().int().nonnegative(), rollSec: num.positive(), offerSec: num.positive() }),
  progression: z.object({
    xpPerKill: pos, xpPerHeadshot: pos, xpPerWaveReached: pos, levelXpBase: pos, levelXpGrowth: num.min(1),
    maxLevel: z.number().int().positive(),
  }),
  net: z.object({
    protocolVersion: z.number().int().positive(), maxMessageBytes: z.number().int().positive(), interestRadius: pos,
    reconnectGraceSec: pos, clientInterpDelayMs: pos, inputRate: pos, maxInputsPerSecond: pos,
  }),
  anticheat: z.object({ speedToleranceFactor: num.min(1), fireRateToleranceMs: pos, logOnly: z.boolean() }),
  powerups: z.object({
    dropChance: num.min(0).max(1), minSecondsBetween: pos, lifetimeSec: num.positive(), pickupRadius: num.positive(),
    maxOnGround: z.number().int().positive(),
    types: z.record(z.string(), z.object({
      displayName: z.string(), weight: pos, durationSec: pos, reward: pos.optional(), boxPrice: z.number().int().nonnegative().optional(),
    })),
  }),
});

export const PerkSchema = z.object({
  displayName: z.string(), price: z.number().int().nonnegative(), color: z.string(),
  maxHealthMul: num.positive().optional(), reloadMul: num.positive().optional(), moveSpeedMul: num.positive().optional(),
  switchMul: num.positive().optional(),
});
export const PerksSchema = z.object({ schemaVersion: z.literal(1), perks: z.record(z.string(), PerkSchema) });

export const WeaponSchema = z.object({
  displayName: z.string(),
  slot: z.enum(["primary", "secondary"]),
  fireMode: z.enum(["semi", "auto"]),
  damage: pos, headMultiplier: num.min(1), fireRateRpm: num.positive(),
  magSize: z.number().int().positive(), reserveStart: z.number().int().nonnegative(), reserveMax: z.number().int().nonnegative(),
  reloadSec: pos, range: num.positive(), spreadDeg: pos, moveSpreadDeg: pos, pellets: z.number().int().positive(),
  price: z.number().int().nonnegative(), ammoPrice: z.number().int().nonnegative(),
  boxWeight: z.number().nonnegative(),
  /** area damage around the hit point (energy weapons) */
  splashRadius: pos.default(0), splashDamage: pos.default(0),
  /** a cone blast instead of a ray: every zombie within `range` and this angle is hit */
  coneDeg: pos.default(0),
});
export const WeaponsSchema = z.object({ schemaVersion: z.literal(1), weapons: z.record(z.string(), WeaponSchema) });

export const ZombieSchema = z.object({
  displayName: z.string(),
  baseHealth: num.positive(), healthPerWave: pos, moveSpeed: num.positive(), moveSpeedPerWave: pos, maxMoveSpeed: num.positive(),
  attackDamage: pos, attackRange: num.positive(), attackCooldownSec: num.positive(), attackWindupSec: pos,
  radius: num.positive(), height: num.positive(), headCenterHeight: num.positive(), headRadius: num.positive(),
  killReward: pos, xp: pos,
});
export const ZombiesSchema = z.object({ schemaVersion: z.literal(1), zombies: z.record(z.string(), ZombieSchema) });

export const WavesSchema = z.object({
  schemaVersion: z.literal(1),
  firstWaveDelaySec: pos,
  intermissionSec: pos,
  count: z.object({ base: pos, perWave: pos, perExtraPlayer: pos, exponent: num.min(1), max: z.number().int().positive() }),
  spawnIntervalSec: z.object({ start: num.positive(), perWave: num, min: num.positive() }),
  mix: z
    .array(z.object({ fromWave: z.number().int().positive(), weights: z.record(z.string(), pos) }))
    .min(1),
});

const FieldSchema = z.tuple([z.string(), z.string()]);
const MessageSchema = z.object({ id: z.number().int().min(1).max(255), fields: z.array(FieldSchema) });
export const ProtocolSchema = z.object({
  schemaVersion: z.literal(1),
  protocolVersion: z.number().int().positive(),
  endianness: z.literal("little"),
  quantization: z.object({ posScale: num.positive() }),
  enums: z.record(z.string(), z.record(z.string(), z.number().int())),
  types: z.record(z.string(), z.union([z.string(), z.array(FieldSchema)])),
  messages: z.object({ C2S: z.record(z.string(), MessageSchema), S2C: z.record(z.string(), MessageSchema) }),
});

export type Constants = z.infer<typeof ConstantsSchema>;
export type WeaponDef = z.infer<typeof WeaponSchema>;
export type ZombieDef = z.infer<typeof ZombieSchema>;
export type WavesDef = z.infer<typeof WavesSchema>;
export type ProtocolDef = z.infer<typeof ProtocolSchema>;

const v2 = z.tuple([num, num]);
const v3 = z.tuple([num, num, num]);
export const MapSchema = z.object({
  schemaVersion: z.literal(1),
  id: z.string(),
  floorHeight: num.positive(),
  bounds: z.object({ min: v2, max: v2 }),
  walkable: z.array(z.object({ min: v2, max: v2 })).min(1),
  walls: z.array(z.object({ min: v3, max: v3 })),
  playerSpawns: z.array(z.object({ pos: v2, yaw: num })).min(1),
  zombieEntries: z.array(z.object({ id: z.string(), pos: v2, inside: v2 })).min(1),
  interactables: z.array(z.object({
    id: z.string(), kind: z.enum(["weapon", "ammo", "box", "perk"]), item: z.string().optional(), pos: v2, radius: num.positive(), yaw: num.optional(),
  })),
  safeArea: z.object({ min: v2, max: v2 }),
});
export type MapDef = z.infer<typeof MapSchema>;
export type PerkDef = z.infer<typeof PerkSchema>;
