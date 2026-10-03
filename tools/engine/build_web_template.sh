#!/usr/bin/env bash
# Builds the stripped Godot web export template (tools/engine/blackoff_web.py).
#   tools/engine/build_web_template.sh <godot source dir> <emsdk dir> <out zip>
# The source must be the tag in tools/godot_version.env; the emsdk version
# matches the official templates (Emscripten 4.0.20 for Godot 4.7.2).
set -euo pipefail
src="$1"; emsdk="$2"; out="$3"
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"  # absolute: the build runs inside $src
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$emsdk/emsdk_env.sh" >/dev/null
cd "$src"
scons -j"$(nproc)" platform=web target=template_release profile="$here/blackoff_web.py"
zip="bin/godot.web.template_release.wasm32.nothreads.zip"
test -s "$zip"
mkdir -p "$(dirname "$out")"
cp "$zip" "$out"
unzip -l "$out"
