#!/usr/bin/env python3
"""Stable, compact JSON formatting for shared/ data: 2-space indent, but
arrays/objects that fit on one line (<= 100 chars) stay inline."""
import json
import sys


def fmt(v, indent=0, width=100):
    one = json.dumps(v, ensure_ascii=False, separators=(", ", ": "))
    if not isinstance(v, (list, dict)) or len(one) + indent <= width and not (
        isinstance(v, dict) and any(isinstance(x, (dict, list)) and x for x in v.values()) and indent == 0
    ):
        return one
    pad = " " * (indent + 2)
    if isinstance(v, list):
        inner = [pad + fmt(x, indent + 2, width) for x in v]
        return "[\n" + ",\n".join(inner) + "\n" + " " * indent + "]"
    inner = [pad + json.dumps(k, ensure_ascii=False) + ": " + fmt(x, indent + 2, width) for k, x in v.items()]
    return "{\n" + ",\n".join(inner) + "\n" + " " * indent + "}"


if __name__ == "__main__":
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        with open(path, "w", encoding="utf-8") as f:
            f.write(fmt(data) + "\n")
