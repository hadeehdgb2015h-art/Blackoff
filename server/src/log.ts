type Level = "debug" | "info" | "warn" | "error";
const order: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };
let threshold: Level = "info";

export function setLogLevel(level: Level): void {
  threshold = level;
}

/** The last warnings and errors, for the owner's panel in the bot. */
export const recentProblems: string[] = [];

function emit(level: Level, msg: string, data?: Record<string, unknown>): void {
  if (order[level] < order[threshold]) return;
  const line = JSON.stringify({ t: new Date().toISOString(), level, msg, ...data });
  if (order[level] >= order.warn) {
    recentProblems.push(line);
    if (recentProblems.length > 30) recentProblems.shift();
  }
  (level === "error" || level === "warn" ? process.stderr : process.stdout).write(line + "\n");
}

export const log = {
  debug: (m: string, d?: Record<string, unknown>) => emit("debug", m, d),
  info: (m: string, d?: Record<string, unknown>) => emit("info", m, d),
  warn: (m: string, d?: Record<string, unknown>) => emit("warn", m, d),
  error: (m: string, d?: Record<string, unknown>) => emit("error", m, d),
};
