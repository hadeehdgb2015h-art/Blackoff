#!/usr/bin/env python3
"""Sets the import options of the sounds under client/assets/sfx (built by
tools/sfx/build_sfx.py from real recordings):
  - music_* loop forward and are QOA-compressed at 22 kHz (real music, dark and low);
  - short effects (under 0.8 s: shots, hits, steps, clicks) stay 16-bit PCM,
    whose sharp attacks QOA smears;
  - longer effects are QOA-compressed (a fifth of the size).
Prints the number of .import files changed (export_web.sh reimports if > 0)."""
import glob
import os
import re
import wave

ROOT = os.path.join(os.path.dirname(__file__), "..", "client")
PCM_MAX_SEC = 0.8
changed = 0
for imp in glob.glob(os.path.join(ROOT, "assets", "sfx", "*.import")):
    with open(imp, encoding="utf-8") as f:
        text = f.read()
    if 'importer="wav"' not in text:
        continue
    src = imp[: -len(".import")]
    music = os.path.basename(src).startswith("music_")
    with wave.open(src) as w:
        sec = w.getnframes() / float(w.getframerate())
    mode = "2" if music or sec >= PCM_MAX_SEC else "0"
    new = re.sub(r"^edit/loop_mode=.*$", "edit/loop_mode=" + ("1" if music else "0"), text, flags=re.M)
    new = re.sub(r"^compress/mode=.*$", "compress/mode=" + mode, new, flags=re.M)
    new = re.sub(r"^force/max_rate=.*$", "force/max_rate=" + ("true" if music else "false"), new, flags=re.M)
    new = re.sub(r"^force/max_rate_hz=.*$", "force/max_rate_hz=" + ("22050" if music else "44100"), new, flags=re.M)
    if new != text:
        with open(imp, "w", encoding="utf-8") as f:
            f.write(new)
        for dest in re.findall(r'dest_files=\["([^"]+)"', text):
            for p in glob.glob(os.path.join(ROOT, dest.replace("res://", "")) + "*"):
                os.remove(p)
        changed += 1
print(changed)
