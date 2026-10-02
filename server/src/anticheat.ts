/**
 * Statistical anti-cheat flags (log only, phase 11). The server already owns
 * movement, damage, ammo and fire rate, so a cheating client can only feed it
 * inputs. What inputs can still fake is aim, so we look at the end of each
 * zone for play that no thumb produces: near-perfect head-shot or hit rates
 * over many shots, or kills faster than the waves can deliver. Flags are
 * logged with the account id and counted in the profile ("suspicion"); nobody
 * is banned automatically. The owner checks /admin/suspects before paying
 * weekly prizes.
 */
import type { Constants } from "./shared/schemas.js";

export interface PlayStats {
  shots: number;
  hits: number;
  headshots: number;
  kills: number;
  seconds: number;
}

export function flagsFor(s: PlayStats, c: Constants["anticheat"]): string[] {
  const flags: string[] = [];
  if (s.shots >= c.minShotsForRates) {
    if (s.hits / s.shots > c.maxHitRate) flags.push("hitRate");
    if (s.hits > 0 && s.headshots / s.hits > c.maxHeadshotRate) flags.push("headshotRate");
  }
  if (s.seconds >= 60 && (s.kills / (s.seconds / 60)) > c.maxKillsPerMin) flags.push("killsPerMin");
  return flags;
}
