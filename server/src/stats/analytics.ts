/**
 * The owner's statistics (phase 29), computed from per-day activity rows. Each
 * row is one account's activity on one UTC day: times the game was opened,
 * games played, seconds, best wave, device (Telegram platform), interface
 * language and average FPS. Nothing here is used for play; the device fields
 * come from the client and are only descriptive.
 *
 * - days: active and new players, games and minutes for each of the last 7 days
 * - retention: new players who came back the next day (cohorts of 7 complete
 *   days), and who came back within a week (cohorts that had their full week)
 * - funnel: of the last 7 days' new players, how many played, reached wave 3,
 *   played 3 games, came back another day: where people stop
 * - devices: platform shares with their average FPS, slow devices, languages
 */

export interface ActivityRow {
  day: string; // YYYY-MM-DD (UTC)
  accountId: string;
  opens: number;
  games: number;
  seconds: number;
  bestWave: number;
  platform: string;
  lang: string;
  fpsSum: number;
  fpsN: number;
}

/** Fields added to (counts) or replacing (platform, lang) an activity row. */
export interface ActivityPatch {
  opens?: number;
  games?: number;
  seconds?: number;
  wave?: number;
  platform?: string;
  lang?: string;
  fps?: number;
}

export interface DayStats { day: string; active: number; fresh: number; games: number; seconds: number }
export interface Ratio { of: number; n: number }
export interface DeviceStats { platform: string; players: number; fps: number }

export interface Analytics {
  today: string;
  /** the last 7 days, oldest first */
  days: DayStats[];
  week: { active: number; fresh: number; games: number; seconds: number };
  nextDay: Ratio;
  withinWeek: Ratio;
  funnel: { fresh: number; played: number; wave3: number; games3: number; returned: number };
  devices: DeviceStats[];
  slow: Ratio;
  langs: { lang: string; players: number }[];
}

export const LOW_FPS = 25;

export function utcDay(at: Date = new Date()): string {
  return at.toISOString().slice(0, 10);
}

export function addDays(day: string, n: number): string {
  const d = new Date(day + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** The platform group shown to the owner. */
export function platformGroup(p: string): string {
  if (p === "android" || p === "android_x") return "android";
  if (p === "ios") return "ios";
  if (p === "tdesktop" || p === "macos" || p === "unigram") return "desktop";
  if (p === "weba" || p === "webk" || p === "web") return "web";
  return p ? "other" : "unknown";
}

/**
 * @param rows activity rows of at least the last 15 days
 * @param firstDay the day each account first appeared, for accounts created in the last 15 days
 */
export function computeAnalytics(rows: ActivityRow[], firstDay: Map<string, string>, today = utcDay()): Analytics {
  const from7 = addDays(today, -6);
  const byAccount = new Map<string, ActivityRow[]>();
  for (const r of rows) {
    let a = byAccount.get(r.accountId);
    if (!a) byAccount.set(r.accountId, (a = []));
    a.push(r);
  }
  const activeOn = (id: string, day: string) => (byAccount.get(id) ?? []).some((r) => r.day === day);

  const days: DayStats[] = [];
  for (let i = 6; i >= 0; i--) {
    const day = addDays(today, -i);
    const on = rows.filter((r) => r.day === day);
    days.push({
      day, active: on.length, fresh: [...firstDay.values()].filter((d) => d === day).length,
      games: on.reduce((s, r) => s + r.games, 0), seconds: on.reduce((s, r) => s + r.seconds, 0),
    });
  }
  const recent = rows.filter((r) => r.day >= from7 && r.day <= today);
  const week = {
    active: new Set(recent.map((r) => r.accountId)).size,
    fresh: [...firstDay.values()].filter((d) => d >= from7 && d <= today).length,
    games: recent.reduce((s, r) => s + r.games, 0),
    seconds: recent.reduce((s, r) => s + r.seconds, 0),
  };

  // retention: only cohorts whose window has fully passed
  const nextDay: Ratio = { of: 0, n: 0 };
  const withinWeek: Ratio = { of: 0, n: 0 };
  for (const [id, first] of firstDay) {
    if (first >= addDays(today, -7) && first <= addDays(today, -1)) {
      nextDay.of += 1;
      if (activeOn(id, addDays(first, 1))) nextDay.n += 1;
    }
    if (first >= addDays(today, -14) && first <= addDays(today, -7)) {
      withinWeek.of += 1;
      const last = addDays(first, 7);
      if ((byAccount.get(id) ?? []).some((r) => r.day > first && r.day <= last)) withinWeek.n += 1;
    }
  }

  const funnel = { fresh: 0, played: 0, wave3: 0, games3: 0, returned: 0 };
  for (const [id, first] of firstDay) {
    if (first < from7 || first > today) continue;
    const mine = (byAccount.get(id) ?? []).filter((r) => r.day >= first);
    funnel.fresh += 1;
    const games = mine.reduce((s, r) => s + r.games, 0);
    if (games >= 1) funnel.played += 1;
    if (mine.some((r) => r.bestWave >= 3)) funnel.wave3 += 1;
    if (games >= 3) funnel.games3 += 1;
    if (mine.some((r) => r.day > first)) funnel.returned += 1;
  }

  // devices and languages: each account once, with its latest known values in the week
  const latest = new Map<string, { platform: string; lang: string; fpsSum: number; fpsN: number }>();
  for (const r of [...recent].sort((a, b) => a.day.localeCompare(b.day))) {
    const l = latest.get(r.accountId) ?? { platform: "", lang: "", fpsSum: 0, fpsN: 0 };
    if (r.platform) l.platform = r.platform;
    if (r.lang) l.lang = r.lang;
    l.fpsSum += r.fpsSum;
    l.fpsN += r.fpsN;
    latest.set(r.accountId, l);
  }
  const groups = new Map<string, { players: number; fpsSum: number; fpsN: number }>();
  const langs = new Map<string, number>();
  const slow: Ratio = { of: 0, n: 0 };
  for (const l of latest.values()) {
    const g = platformGroup(l.platform);
    const e = groups.get(g) ?? { players: 0, fpsSum: 0, fpsN: 0 };
    e.players += 1;
    if (l.fpsN > 0) {
      const fps = l.fpsSum / l.fpsN;
      e.fpsSum += fps;
      e.fpsN += 1;
      slow.of += 1;
      if (fps < LOW_FPS) slow.n += 1;
    }
    groups.set(g, e);
    if (l.lang) langs.set(l.lang, (langs.get(l.lang) ?? 0) + 1);
  }
  const devices = [...groups.entries()]
    .map(([platform, e]) => ({ platform, players: e.players, fps: e.fpsN ? Math.round(e.fpsSum / e.fpsN) : 0 }))
    .sort((a, b) => b.players - a.players);
  return {
    today, days, week, nextDay, withinWeek, funnel, devices, slow,
    langs: [...langs.entries()].map(([lang, players]) => ({ lang, players })).sort((a, b) => b.players - a.players),
  };
}

/** Adds a patch to a row (the memory store; Postgres does the same in SQL). */
export function applyPatch(r: ActivityRow, p: ActivityPatch): ActivityRow {
  return {
    ...r,
    opens: r.opens + (p.opens ?? 0),
    games: r.games + (p.games ?? 0),
    seconds: r.seconds + Math.round(p.seconds ?? 0),
    bestWave: Math.max(r.bestWave, p.wave ?? 0),
    platform: p.platform || r.platform,
    lang: p.lang || r.lang,
    fpsSum: r.fpsSum + (p.fps ? Math.round(p.fps) : 0),
    fpsN: r.fpsN + (p.fps ? 1 : 0),
  };
}
