#!/usr/bin/env python3
"""Sets the import mode of every texture under client/assets.

Lossy WebP: small download and no block artifacts (the phone decodes it to
plain RGBA). ETC2 VRAM compression was tried and made the art visibly blocky
and washed out on phones. Godot imports GLB textures as lossless when
importing headless, which would bloat the web download.
Prints the number of .import files changed (export_web.sh reimports if > 0).
"""
import glob
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..", "client")
changed = 0
for imp in glob.glob(os.path.join(ROOT, "assets", "**", "*.import"), recursive=True):
    with open(imp, encoding="utf-8") as f:
        text = f.read()
    if 'importer="texture"' not in text:
        continue
    # fx_ sprites are additive: lossy alpha noise would light up the whole quad
    want = {"compress/mode": "0" if os.path.basename(imp).startswith("fx_") else "1", "mipmaps/generate": "true"}
    want["compress/lossy_quality"] = "0.9" if "_normal." in imp else ("0.75" if "_orm." in imp else "0.85")
    if os.path.basename(imp).startswith("sky_vision_"):
        want["compress/lossy_quality"] = "0.72"  # soft glowing mirages: small files are enough
    want["compress/normal_map"] = "1" if "_normal." in imp else "0"
    # memory and download budget: roughness/metal maps are low-frequency, so a
    # character's or weapon's map is 256 px (the prop libraries' shared one 512)
    limit = 0
    if "_orm." in imp:
        limit = 512 if "_props_" in imp else 256
    want["process/size_limit"] = str(limit)
    new = text
    for k, v in want.items():
        new = re.sub(r"^%s=.*$" % re.escape(k), "%s=%s" % (k, v), new, flags=re.M)
    if new != text:
        with open(imp, "w", encoding="utf-8") as f:
            f.write(new)
        for dest in re.findall(r'dest_files=\["([^"]+)"', text):
            for p in glob.glob(os.path.join(ROOT, dest.replace("res://", "")) + "*"):
                os.remove(p)
        changed += 1
print(changed)
