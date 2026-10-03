import { loadEnv } from "./config/env.js";
import { loadShared } from "./shared/loadShared.js";
import { createApp } from "./app.js";
import { log, setLogLevel } from "./log.js";
import { MemoryProfileStore, type ProfileStore } from "./db/profileStore.js";
import { PgProfileStore } from "./db/pgStore.js";

async function main(): Promise<void> {
  const env = loadEnv();
  setLogLevel(env.LOG_LEVEL);
  const shared = loadShared(env.SHARED_DIR);
  let store: ProfileStore;
  if (env.DATABASE_URL) {
    store = await PgProfileStore.open(env.DATABASE_URL); // runs pending migrations
  } else {
    if (env.NODE_ENV === "production") log.warn("DATABASE_URL not set: profiles are kept in memory only");
    store = new MemoryProfileStore();
  }
  const app = createApp(env, shared, store);
  void app.hub.discoverBot(); // invite links need the bot's @username
  app.server.listen(env.PORT, env.HOST, () => {
    log.info("server listening", { host: env.HOST, port: env.PORT, ws: env.WS_PATH, store: store.kind });
  });
  const shutdown = (signal: string) => {
    log.info("shutting down", { signal });
    app.close().then(() => store.close()).then(() => process.exit(0));
    setTimeout(() => process.exit(1), 5000).unref();
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
}

main().catch((err: Error) => {
  log.error("fatal startup error", { error: err.message });
  process.exit(1);
});
