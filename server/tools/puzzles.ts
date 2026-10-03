/**
 * The secret puzzle module's files (phase 31).
 *   npx tsx tools/puzzles.ts key            a new random key (give it to the owner, never commit it)
 *   npx tsx tools/puzzles.ts seal <key>     puzzles-private/*.ts -> assets/puzzles/pack.bin (the compiled
 *                                           module) and source.bin (the sources, for later edits)
 *   npx tsx tools/puzzles.ts open <key>     assets/puzzles/source.bin -> puzzles-private/ (to edit)
 *   npx tsx tools/puzzles.ts check <key>    loads pack.bin the way the server does
 * puzzles-private/ is git-ignored: only the sealed files are committed.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
import { loadModule, newKey, open, seal } from "../src/puzzles/pack.js";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const priv = path.join(root, "puzzles-private");
const out = path.join(root, "assets", "puzzles");
const [cmd, keyArg] = process.argv.slice(2);
const key = keyArg || process.env.PUZZLE_KEY || "";

if (cmd === "key") {
  console.log(newKey());
} else if (cmd === "seal") {
  const res = await build({
    entryPoints: [path.join(priv, "puzzles.ts")], bundle: true, write: false, format: "esm", platform: "neutral", target: "node20", minify: true, legalComments: "none",
  });
  const js = Buffer.from(res.outputFiles[0]!.contents);
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, "pack.bin"), seal(js, key));
  const files: Record<string, string> = {};
  for (const f of fs.readdirSync(priv)) if (/\.(ts|md|json)$/.test(f)) files[f] = fs.readFileSync(path.join(priv, f), "utf8");
  fs.writeFileSync(path.join(out, "source.bin"), seal(Buffer.from(JSON.stringify(files)), key));
  const m = await loadModule(key, fs.readFileSync(path.join(out, "pack.bin")));
  console.log(`sealed ${m.name}: pack ${js.length} bytes, sources ${Object.keys(files).join(", ")}`);
} else if (cmd === "open") {
  const files = JSON.parse(open(fs.readFileSync(path.join(out, "source.bin")), key).toString("utf8")) as Record<string, string>;
  fs.mkdirSync(priv, { recursive: true });
  for (const [f, text] of Object.entries(files)) fs.writeFileSync(path.join(priv, path.basename(f)), text);
  console.log("opened into puzzles-private/: " + Object.keys(files).join(", "));
} else if (cmd === "check") {
  const m = await loadModule(key, fs.readFileSync(path.join(out, "pack.bin")));
  console.log("ok: " + m.name);
} else {
  console.error("usage: tools/puzzles.ts key | seal <key> | open <key> | check <key>");
  process.exit(2);
}
