import { loadEnv } from "./config/env.js";
import { loadShared } from "./shared/loadShared.js";
import { createApp } from "./app.js";
import { log, setLogLevel } from "./log.js";

function main(): void {
  const env = loadEnv();
  setLogLevel(env.LOG_LEVEL);
  const shared = loadShared(env.SHARED_DIR);
  const app = createApp(env, shared);
  app.server.listen(env.PORT, env.HOST, () => {
    log.info("server listening", { host: env.HOST, port: env.PORT, ws: env.WS_PATH });
  });
  const shutdown = (signal: string) => {
    log.info("shutting down", { signal });
    app.close().then(() => process.exit(0));
    setTimeout(() => process.exit(1), 5000).unref();
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
}

try {
  main();
} catch (err) {
  log.error("fatal startup error", { error: (err as Error).message });
  process.exit(1);
}
