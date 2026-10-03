/**
 * The owner's live switches (phase 20), changed from the bot's admin panel and
 * kept in the store's settings table so they survive restarts:
 * banned accounts, maintenance mode, TON per kill override and multiplier,
 * the weekly prize text. Defaults come from the environment.
 */
import type { Env } from "../config/env.js";
import type { ProfileStore } from "../db/profileStore.js";
import { log } from "../log.js";

const KEY = "runtime";

interface Saved {
  banned?: string[];
  maintenance?: boolean;
  maintenanceText?: string;
  tonPerKill?: number | null;
  tonMultiplier?: number;
  prizeText?: string | null;
  squadBots?: boolean;
}

export class RuntimeSettings {
  readonly banned = new Set<string>();
  maintenance = false;
  maintenanceText = "";
  /** null = TON_MICRO_PER_KILL from the environment */
  tonPerKillOverride: number | null = null;
  tonMultiplier = 1;
  /** null = TON_PRIZE_TEXT from the environment */
  prizeOverride: string | null = null;
  /** AI soldiers fill online squads (phase 30) */
  squadBots = true;

  constructor(private readonly env: Env, private readonly store: ProfileStore) {}

  /** TON points per kill in force (millionths). */
  tonPerKill(): number {
    return Math.round((this.tonPerKillOverride ?? this.env.TON_MICRO_PER_KILL) * this.tonMultiplier);
  }

  prizeText(): string {
    return (this.prizeOverride ?? this.env.TON_PRIZE_TEXT).slice(0, 200);
  }

  async load(): Promise<void> {
    try {
      const s = ((await this.store.getSetting(KEY)) ?? {}) as Saved;
      this.banned.clear();
      for (const id of s.banned ?? []) this.banned.add(String(id));
      this.maintenance = !!s.maintenance;
      this.maintenanceText = String(s.maintenanceText ?? "");
      this.tonPerKillOverride = typeof s.tonPerKill === "number" ? s.tonPerKill : null;
      this.tonMultiplier = typeof s.tonMultiplier === "number" && s.tonMultiplier > 0 ? s.tonMultiplier : 1;
      this.prizeOverride = typeof s.prizeText === "string" ? s.prizeText : null;
      this.squadBots = s.squadBots !== false;
    } catch (err) {
      log.warn("runtime settings load failed", { error: (err as Error).message });
    }
  }

  async save(): Promise<void> {
    const s: Saved = {
      banned: [...this.banned], maintenance: this.maintenance, maintenanceText: this.maintenanceText,
      tonPerKill: this.tonPerKillOverride, tonMultiplier: this.tonMultiplier, prizeText: this.prizeOverride, squadBots: this.squadBots,
    };
    try {
      await this.store.setSetting(KEY, s);
    } catch (err) {
      log.warn("runtime settings save failed", { error: (err as Error).message });
    }
  }
}
