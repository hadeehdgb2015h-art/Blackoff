#!/usr/bin/env python3
"""Interface translations (phase 24): client/data/i18n/<lang>.json.

Keys are the English texts. They come from every tr("...") (and
TranslationServer.translate("...")) literal in the client scripts, plus the
display names in the shared data (weapons, perks, zombies, power-ups), which
the client shows through I18n.name_of() / tr(name).

  python3 tools/i18n.py check          fails on a missing, empty or unused key,
                                        or a translation whose placeholders
                                        (%d %s %02d ...) differ from the English
  python3 tools/i18n.py keys           prints every key (one JSON string per line)
  python3 tools/i18n.py missing <lang> prints the keys <lang> lacks
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLIENT = ROOT / "client"
LANGS = ["ar", "ru"]
CALL = re.compile(r'(?<![A-Za-z0-9_])(?:tr|TranslationServer\.translate)\(\s*"((?:[^"\\]|\\.)*)"\s*[,)]')
PLACEHOLDER = re.compile(r"%(?:[-+0 #]*\d*(?:\.\d+)?[sdifxXc%])")
ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}


def unescape(s: str) -> str:
    return re.sub(r"\\(.)", lambda m: ESCAPES.get(m.group(1), m.group(0)), s)


def code_keys() -> dict:
    keys = {}
    for f in sorted(CLIENT.rglob("*.gd")):
        if ".godot" in f.parts or f.parts[-2] == "tests":
            continue
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for m in CALL.finditer(line):
                keys.setdefault(unescape(m.group(1)), f"{f.relative_to(ROOT)}:{n}")
    return keys


def data_keys() -> dict:
    keys = {}
    shared = ROOT / "shared"
    for name, group in [("weapons.json", "weapons"), ("perks.json", "perks"), ("zombies.json", "zombies")]:
        for k, v in json.loads((shared / name).read_text())[group].items():
            keys.setdefault(v["displayName"], f"shared/{name}:{k}")
    for k, v in json.loads((shared / "constants.json").read_text())["powerups"]["types"].items():
        keys.setdefault(v["displayName"], f"shared/constants.json:powerups.{k}")
    return keys


def all_keys() -> dict:
    keys = data_keys()
    keys.update(code_keys())
    return keys


def load(lang: str) -> dict:
    p = CLIENT / "data" / "i18n" / f"{lang}.json"
    return {k: v for k, v in json.loads(p.read_text(encoding="utf-8")).items() if not k.startswith("_")}


def placeholders(s: str) -> list:
    return sorted(m.group(0) for m in PLACEHOLDER.finditer(s) if m.group(0) != "%%")


def check() -> int:
    keys = all_keys()
    errors = []
    for lang in LANGS:
        try:
            tr = load(lang)
        except (OSError, json.JSONDecodeError) as e:
            errors.append(f"{lang}: cannot read: {e}")
            continue
        for k, where in keys.items():
            if k not in tr:
                errors.append(f"{lang}: missing {json.dumps(k, ensure_ascii=False)} ({where})")
            elif not str(tr[k]).strip():
                errors.append(f"{lang}: empty {json.dumps(k, ensure_ascii=False)}")
            elif placeholders(k) != placeholders(str(tr[k])):
                errors.append(f"{lang}: placeholders differ for {json.dumps(k, ensure_ascii=False)}: {placeholders(k)} vs {placeholders(str(tr[k]))}")
        for k in tr:
            if k not in keys:
                errors.append(f"{lang}: unused key {json.dumps(k, ensure_ascii=False)}")
    for e in errors:
        print("i18n:", e)
    print(f"i18n: {len(keys)} keys, {len(LANGS)} languages, {len(errors)} problems")
    return 1 if errors else 0


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "check":
        return check()
    if cmd == "keys":
        for k in all_keys():
            print(json.dumps(k, ensure_ascii=False))
        return 0
    if cmd == "missing":
        tr = load(sys.argv[2])
        for k, where in all_keys().items():
            if k not in tr:
                print(json.dumps(k, ensure_ascii=False), "#", where)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
