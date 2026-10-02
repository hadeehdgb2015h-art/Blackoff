#!/usr/bin/env bash
# Regenerates greybox map scenes and exports their gameplay data to shared/maps/.
#   tools/build_maps.sh          regenerate + export
#   tools/build_maps.sh --check  fail if committed outputs are out of date (CI)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
"$godot" --headless --path "$root/client" --import >/dev/null 2>&1 || true
"$godot" --headless --path "$root/client" --script res://tools/maps/build_facility_01.gd
"$godot" --headless --path "$root/client" --script res://tools/maps/export_map.gd -- \
  res://scenes/maps/facility_01.tscn "$root/shared/maps/facility_01.json"
python3 "$root/tools/fmt_json.py" "$root/shared/maps/facility_01.json"
if [ "${1:-}" = "--check" ]; then
  git -C "$root" diff --exit-code -- shared/maps client/scenes/maps \
    || { echo "map outputs are stale: run tools/build_maps.sh and commit" >&2; exit 1; }
fi
