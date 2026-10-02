#!/usr/bin/env python3
"""Gives the web build content-addressed file names so phones keep them cached.

Run by tools/export_web.sh after the Godot export. The engine bundle (index.js,
index.wasm, audio worklets) gets one hash, the game data pack (index.pck) its
own, so a game update downloads only the pack and an engine update only the
engine. index.html references the hashed names; the unhashed files are removed.
Also writes manifest.json (file list + build id) for the service worker and
fills the build id into sw.js.

    hash_web_build.py <build dir> <build id>
"""
import hashlib
import json
import os
import re
import sys

ENGINE_SUFFIXES = [".js", ".wasm", ".audio.worklet.js", ".audio.position.worklet.js", ".side.wasm"]


def sha(paths):
    h = hashlib.sha256()
    for p in paths:
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()[:12]


def main(out, build):
    exe = "index"
    engine_files = [f"{exe}{s}" for s in ENGINE_SUFFIXES if os.path.exists(os.path.join(out, f"{exe}{s}"))]
    ehash = sha(os.path.join(out, f) for f in engine_files)
    phash = sha([os.path.join(out, f"{exe}.pck")])
    hashed = {}
    for f in engine_files:
        new = f"{exe}.{ehash}{f[len(exe):]}"
        os.rename(os.path.join(out, f), os.path.join(out, new))
        hashed[f] = new
    pck_new = f"{exe}.{phash}.pck"
    os.rename(os.path.join(out, f"{exe}.pck"), os.path.join(out, pck_new))
    hashed[f"{exe}.pck"] = pck_new

    html_path = os.path.join(out, "index.html")
    html = open(html_path, encoding="utf-8").read()
    m = re.search(r"const GODOT_CONFIG = (\{.*?\});", html)
    if not m:
        sys.exit("GODOT_CONFIG not found in index.html")
    cfg = json.loads(m.group(1))
    cfg["executable"] = f"{exe}.{ehash}"
    cfg["mainPack"] = pck_new
    sizes = cfg.get("fileSizes", {})
    cfg["fileSizes"] = {hashed.get(k, k): v for k, v in sizes.items()}
    html = html.replace(m.group(0), "const GODOT_CONFIG = " + json.dumps(cfg, separators=(",", ":")) + ";")
    html = html.replace(f'src="{exe}.js"', f'src="{hashed[exe + ".js"]}"')
    if f'src="{hashed[exe + ".js"]}"' not in html:
        sys.exit("engine script tag not rewritten")
    html = html.replace("__BLACKOFF_BUILD__", build)
    open(html_path, "w", encoding="utf-8").write(html)

    # Files the service worker keeps across visits (everything hashed, plus the small icons).
    cached = sorted(hashed.values()) + [f for f in ("index.icon.png", "index.png", "index.apple-touch-icon.png") if os.path.exists(os.path.join(out, f))]
    json.dump({"build": build, "engine": ehash, "pack": phash, "files": cached}, open(os.path.join(out, "manifest.json"), "w"), indent=1)
    sw_path = os.path.join(out, "sw.js")
    if os.path.exists(sw_path):
        sw = open(sw_path, encoding="utf-8").read().replace("__BLACKOFF_BUILD__", build)
        open(sw_path, "w", encoding="utf-8").write(sw)
    print(f"engine {ehash} pack {phash}: " + ", ".join(cached))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
