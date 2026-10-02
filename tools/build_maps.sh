#!/usr/bin/env bash
# Map pipeline: (greybox generator ->) scene -> shared/maps/<id>.json
#   tools/build_maps.sh          regenerate greybox scene + export JSON
#   tools/build_maps.sh --check  export from the committed scene and fail if
#                                shared/maps differs (CI guard: scene and JSON in sync)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
"$godot" --headless --path "$root/client" --import >/dev/null 2>&1 || true
if [ "${1:-}" != "--check" ]; then
  "$godot" --headless --path "$root/client" --script res://tools/maps/build_facility_01.gd
fi
"$godot" --headless --path "$root/client" --script res://tools/maps/export_map.gd -- \
  res://scenes/maps/facility_01.tscn "$root/shared/maps/facility_01.json"
python3 "$root/tools/fmt_json.py" "$root/shared/maps/facility_01.json"
if [ "${1:-}" = "--check" ]; then
  git -C "$root" diff --exit-code -- shared/maps \
    || { echo "shared/maps is stale: run tools/build_maps.sh and commit" >&2; exit 1; }
fi
