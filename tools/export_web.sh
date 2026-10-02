#!/usr/bin/env bash
# Builds the Web export into build/web/ and runs the headless client tests first.
#   GODOT (default: godot on PATH, else /opt/godot/godot)
#   EXPORT_MODE release|debug (default release)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
mode="${EXPORT_MODE:-release}"

"$root/tools/sync_shared.sh"
# First run imports resources and generates .godot/ (needed for class cache and exports).
"$godot" --headless --path "$root/client" --import >/dev/null 2>&1 || true
"$godot" --headless --path "$root/client" --script res://tests/run_tests.gd

rm -rf "$root/build/web" && mkdir -p "$root/build/web"
"$godot" --headless --path "$root/client" "--export-${mode}" "Web" "$root/build/web/index.html"
test -s "$root/build/web/index.wasm" && test -s "$root/build/web/index.pck"
echo "build_id=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo local)" > "$root/build/web/version.txt"
du -sh "$root/build/web"/* | sort -h
echo "gzip size of wasm: $(gzip -9c "$root/build/web/index.wasm" | wc -c) bytes"
