#!/usr/bin/env python3
"""Sets the import options of the generated sounds under client/assets/sfx:
music_* loops forward (edit/loop_mode=1), everything is QOA-compressed
(compress/mode=2, small and cheap to decode). Prints the number of .import
files changed (export_web.sh reimports if > 0)."""
import glob
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..", "client")
changed = 0
for imp in glob.glob(os.path.join(ROOT, "assets", "sfx", "*.import")):
    with open(imp, encoding="utf-8") as f:
        text = f.read()
    if 'importer="wav"' not in text:
        continue
    loop = "1" if os.path.basename(imp).startswith("music_") else "0"
    new = re.sub(r"^edit/loop_mode=.*$", "edit/loop_mode=" + loop, text, flags=re.M)
    new = re.sub(r"^compress/mode=.*$", "compress/mode=2", new, flags=re.M)
    if new != text:
        with open(imp, "w", encoding="utf-8") as f:
            f.write(new)
        for dest in re.findall(r'dest_files=\["([^"]+)"', text):
            for p in glob.glob(os.path.join(ROOT, dest.replace("res://", "")) + "*"):
                os.remove(p)
        changed += 1
print(changed)
