// Bundles the server into one ESM file for deployment (no node_modules needed
// on the host). Target is Node 20, the oldest runtime we support.
import { build } from "esbuild";
import fs from "node:fs";
import { createRequire } from "node:module";

await build({
  // the server, and the worker that draws result cards off the game loop (phase 25)
  entryPoints: { server: "src/index.ts", "card-worker": "src/card/cardWorker.ts" },
  outdir: "dist-bundle",
  outExtension: { ".js": ".mjs" },
  bundle: true,
  platform: "node",
  target: "node20",
  format: "esm",
  sourcemap: "linked",
  legalComments: "linked",
  // optional native add-ons that ws/pg only use when installed
  external: ["pg-native", "bufferutil", "utf-8-validate"],
  // CommonJS dependencies call require() for Node built-ins
  banner: { js: "import { createRequire as __blackoffRequire } from 'node:module'; const require = __blackoffRequire(import.meta.url);" },
  logLevel: "warning",
});
// the card renderer's WebAssembly, found next to the bundle at run time
fs.copyFileSync(createRequire(import.meta.url).resolve("@resvg/resvg-wasm/index_bg.wasm"), "dist-bundle/resvg.wasm");
console.log("wrote dist-bundle/server.mjs, card-worker.mjs, resvg.wasm");
