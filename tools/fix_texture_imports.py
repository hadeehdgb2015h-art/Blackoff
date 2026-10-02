#!/usr/bin/env python3
"""Forces GPU (VRAM) compression on every texture under client/assets.

Godot imports textures extracted from GLBs as lossless when importing
headless (the "detect 3D" switch only fires in the editor), which bloats the
web download and phone memory. Normal maps get normal-map compression.
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
    want = {"compress/mode": "2", "mipmaps/generate": "true"}
    want["compress/normal_map"] = "1" if "_normal." in imp else "0"
    # download budget: roughness/metal maps are low-frequency; the prop atlas is seen at mid range
    limit = 512 if "_orm." in imp else (1024 if "env_props_albedo" in imp else 0)
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
