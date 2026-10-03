import fs from "node:fs";
import path from "node:path";
import type { z } from "zod";
import {
  ConstantsSchema, MapSchema, PerksSchema, ProtocolSchema, WavesSchema, WeaponsSchema, ZombiesSchema,
  type Constants, type MapDef, type PerkDef, type ProtocolDef, type WavesDef, type WeaponDef, type ZombieDef,
} from "./schemas.js";

export interface SharedData {
  constants: Constants;
  protocol: ProtocolDef;
  weapons: Record<string, WeaponDef>;
  zombies: Record<string, ZombieDef>;
  waves: WavesDef;
  perks: Record<string, PerkDef>;
  maps: Record<string, MapDef>;
}

function readJson<S extends z.ZodTypeAny>(dir: string, file: string, schema: S): z.infer<S> {
  const full = path.join(dir, file);
  let raw: unknown;
  try {
    raw = JSON.parse(fs.readFileSync(full, "utf8"));
  } catch (err) {
    throw new Error(`shared/${file}: cannot read or parse (${(err as Error).message})`);
  }
  const res = schema.safeParse(raw);
  if (!res.success) {
    const issues = res.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new Error(`shared/${file}: invalid (${issues})`);
  }
  return res.data;
}

/** Loads and validates every shared JSON file, including cross-file references. */
export function loadShared(dir: string): SharedData {
  const constants = readJson(dir, "constants.json", ConstantsSchema);
  const protocol = readJson(dir, "protocol.json", ProtocolSchema);
  const weapons = readJson(dir, "weapons.json", WeaponsSchema).weapons;
  const zombies = readJson(dir, "zombies.json", ZombiesSchema).zombies;
  const waves = readJson(dir, "waves.json", WavesSchema);
  const perks = readJson(dir, "perks.json", PerksSchema).perks;
  const maps: Record<string, MapDef> = {};
  const mapDir = path.join(dir, "maps");
  const mapFiles = fs.existsSync(mapDir) ? fs.readdirSync(mapDir).filter((f) => f.endsWith(".json")) : [];
  for (const f of mapFiles) {
    const m = readJson(mapDir, f, MapSchema);
    maps[m.id] = m;
  }

  const errors: string[] = [];
  if (!weapons[constants.player.startWeapon]) errors.push(`player.startWeapon '${constants.player.startWeapon}' not in weapons.json`);
  if (constants.net.protocolVersion !== protocol.protocolVersion) errors.push("net.protocolVersion != protocol.protocolVersion");
  if (constants.zone.maxPlayers > constants.zone.maxPlayersHardCap) errors.push("zone.maxPlayers > zone.maxPlayersHardCap");
  for (const [id, w] of Object.entries(weapons)) {
    if (w.reserveStart > w.reserveMax) errors.push(`weapon ${id}: reserveStart > reserveMax`);
    if (w.magSize > 255) errors.push(`weapon ${id}: magSize must fit u8`);
  }
  for (const entry of waves.mix) {
    for (const zid of Object.keys(entry.weights)) {
      if (!zombies[zid]) errors.push(`waves.mix fromWave ${entry.fromWave}: unknown zombie '${zid}'`);
    }
  }
  if (!maps[constants.maps.default]) errors.push(`maps.default '${constants.maps.default}' has no shared/maps file`);
  for (const m of Object.values(maps)) {
    for (const it of m.interactables) {
      if (it.kind === "weapon" && (!it.item || !weapons[it.item])) errors.push(`map ${m.id}: interactable ${it.id} unknown weapon`);
      if (it.kind === "perk" && (!it.item || !perks[it.item])) errors.push(`map ${m.id}: interactable ${it.id} unknown perk`);
    }
  }
  if (waves.mix[0]?.fromWave !== 1) errors.push("waves.mix must start at fromWave 1");
  if (!zombies[waves.boss.type]) errors.push(`waves.boss: unknown zombie '${waves.boss.type}'`);
  const ids = new Set<number>();
  for (const dirKey of ["C2S", "S2C"] as const) {
    for (const [name, m] of Object.entries(protocol.messages[dirKey])) {
      if (ids.has(m.id)) errors.push(`protocol: duplicate message id ${m.id} (${name})`);
      ids.add(m.id);
    }
  }
  if (errors.length) throw new Error(`shared data cross-check failed: ${errors.join("; ")}`);

  return { constants, protocol, weapons, zombies, waves, perks, maps };
}
