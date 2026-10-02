#!/usr/bin/env bash
# Builds the Web export into build/web/ and runs the headless client tests first.
#   GODOT (default: godot on PATH, else /opt/godot/godot)
#   EXPORT_MODE release|debug (default release)
#   WEB_TEMPLATE  path to the stripped engine template zip built by
#                 tools/engine/build_web_template.sh (release exports only;
#                 unset = Godot's official template, 3 MB more to download)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
mode="${EXPORT_MODE:-release}"

"$root/tools/sync_shared.sh"
# First run imports resources and generates .godot/ (needed for class cache and exports).
"$godot" --headless --path "$root/client" --import >/dev/null 2>&1 || true
if [ "$(python3 "$root/tools/fix_texture_imports.py")" != "0" ] || [ "$(python3 "$root/tools/fix_audio_imports.py")" != "0" ]; then
  "$godot" --headless --path "$root/client" --import >/dev/null 2>&1 || true
fi
"$godot" --headless --path "$root/client" --script res://tests/run_tests.gd

rm -rf "$root/build/web" && mkdir -p "$root/build/web"
presets="$root/client/export_presets.cfg"
if [ -n "${WEB_TEMPLATE:-}" ] && [ "$mode" = release ]; then
  test -s "$WEB_TEMPLATE" || { echo "WEB_TEMPLATE not found: $WEB_TEMPLATE" >&2; exit 1; }
  # the preset keeps an empty path in git; point it at the template for this export only
  cp "$presets" "$presets.orig"
  trap 'mv -f "$presets.orig" "$presets"' EXIT
  sed -i "s|^custom_template/release=.*|custom_template/release=\"$(realpath "$WEB_TEMPLATE")\"|" "$presets"
  echo "engine template: $WEB_TEMPLATE"
fi
"$godot" --headless --path "$root/client" "--export-${mode}" "Web" "$root/build/web/index.html"
test -s "$root/build/web/index.wasm" && test -s "$root/build/web/index.pck"
build_id="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo local)-$(date -u +%m%d%H%M)"
cp "$root/client/web/sw.js" "$root/build/web/sw.js"
cp "$root/client/web/voice.js" "$root/build/web/voice.js"
python3 "$root/tools/hash_web_build.py" "$root/build/web" "$build_id"
grep -q "BLACKOFF_BUILD = '$build_id'" "$root/build/web/index.html"
test ! -e "$root/build/web/index.wasm" && test -s "$root/build/web/manifest.json"
echo "build_id=$build_id" > "$root/build/web/version.txt"
du -sh "$root/build/web"/* | sort -h
echo "gzip size of wasm: $(gzip -9c "$root"/build/web/index.*.wasm | wc -c) bytes"
