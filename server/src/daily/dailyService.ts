/**
 * The daily reward and missions of every account (phase 23): loads the state
 * from the store, rolls it to today, applies a claim or a finished game, saves
 * it and pays the TON points. Work for one account runs one step at a time, so
 * a claim and a game result arriving together never pay twice.
 */
import type { Msg } from "../net/codec.js";
import type { Profile, ProfileStore } from "../db/profileStore.js";
import { log } from "../log.js";
import {
  MISSION_KINDS, applyGame, claimStreak, dayKey, parseDaily, rollover, secondsToReset, streakStatus,
  type DailyDefs, type DailyState, type GameStats,
} from "./daily.js";

/** What a `daily` message just paid (protocol enum dailyPaid). */
export const Paid = { NONE: 0, STREAK: 1, MISSIONS: 2 } as const;

export interface DailyUpdate {
  /** fields of the S2C `daily` message */
  msg: Msg;
  /** the profile after a payment, null when nothing was paid */
  profile: Profile | null;
}

export class DailyService {
  private readonly queues = new Map<string, Promise<unknown>>();

  constructor(
    private readonly store: ProfileStore,
    private readonly defs: DailyDefs,
    private readonly tonPerKill: () => number,
    private readonly now: () => Date = () => new Date(),
  ) {}

  /** Today's state of the account. */
  view(accountId: string): Promise<DailyUpdate> {
    return this.step(accountId, (s) => ({ state: s, paidKills: 0, kind: Paid.NONE }));
  }

  /** Takes today's streak reward (nothing happens if it was already taken). */
  claim(accountId: string): Promise<DailyUpdate> {
    return this.step(accountId, (s, day) => ({ ...claimStreak(s, day, this.defs), kind: Paid.STREAK }));
  }

  /** A finished game: mission progress, and payment for the missions it completes. */
  onGame(accountId: string, game: GameStats): Promise<DailyUpdate> {
    return this.step(accountId, (s) => ({ ...applyGame(s, game, this.defs), kind: Paid.MISSIONS }));
  }

  private step(accountId: string, change: (s: DailyState, day: string) => { state: DailyState; paidKills: number; kind: number }): Promise<DailyUpdate> {
    const prev = this.queues.get(accountId) ?? Promise.resolve();
    const run = prev.catch(() => undefined).then(() => this.apply(accountId, change));
    this.queues.set(accountId, run);
    void run.finally(() => {
      if (this.queues.get(accountId) === run) this.queues.delete(accountId);
    }).catch(() => undefined);
    return run;
  }

  private async apply(accountId: string, change: (s: DailyState, day: string) => { state: DailyState; paidKills: number; kind: number }): Promise<DailyUpdate> {
    const at = this.now();
    const day = dayKey(at);
    const loaded = parseDaily(await this.store.getDaily(accountId));
    const rolled = rollover(loaded, accountId, day, this.defs);
    const { state, paidKills, kind } = change(rolled, day);
    if (state !== loaded) await this.store.setDaily(accountId, state);
    const perKill = this.tonPerKill();
    const paidMicro = Math.round(paidKills * perKill);
    let profile: Profile | null = null;
    if (paidMicro > 0) {
      profile = await this.store.addTon(accountId, paidMicro);
      log.info("daily paid", { account: accountId, what: kind === Paid.STREAK ? `streak day ${state.streak}` : "missions", tonMicro: paidMicro });
    }
    return { msg: this.message(state, day, at, perKill, paidKills > 0 ? paidMicro : 0, paidKills > 0 ? kind : Paid.NONE), profile };
  }

  private message(s: DailyState, day: string, at: Date, perKill: number, paidMicro: number, paidKind: number): Msg {
    const micro = (kills: number) => Math.min(0xffffffff, Math.round(kills * perKill));
    const st = streakStatus(s, day);
    return {
      day,
      streak: st.canClaim ? st.nextDay - 1 : s.streak,
      canClaim: st.canClaim,
      nextDay: st.nextDay,
      rewards: this.defs.streakKills.map((k) => ({ tonMicro: micro(k) })),
      missions: s.missions.map((m) => ({
        kind: MISSION_KINDS.indexOf(m.kind), goal: Math.min(m.goal, 0xffff), progress: Math.min(m.progress, 0xffff), tonMicro: micro(m.rewardKills), done: m.done,
      })),
      bonusMicro: micro(this.defs.allMissionsBonusKills),
      bonusDone: s.bonusDone,
      resetSec: secondsToReset(at),
      paidMicro: Math.min(0xffffffff, paidMicro),
      paidKind,
    };
  }
}
