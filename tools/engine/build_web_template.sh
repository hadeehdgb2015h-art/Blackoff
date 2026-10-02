#!/usr/bin/env bash
# Builds the stripped Godot web export template (tools/engine/blackoff_web.py).
#   tools/engine/build_web_template.sh <godot source dir> <emsdk dir> <out zip>
# The source must be the tag in tools/godot_version.env; the emsdk version
# matches the official templates (Emscripten 4.0.20 for Godot 4.7.2).
set -euo pipefail
src="$1"; emsdk="$2"; out="$3"
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$emsdk/emsdk_env.sh" >/dev/null
cd "$src"
# ICU data without the word dictionaries of Chinese/Japanese, Khmer, Burmese,
# Lao and Thai (3 MB of the engine's 4.8 MB of text data; 2.3 MB of a 6.6 MB
# gzip download) and the time zone table: line breaking in those scripts falls
# back to breaking between characters. Needs icupkg (apt: icu-devtools).
dat=thirdparty/icu4c/icudt_godot.dat
git checkout -- "$dat"
pkg="$(grep -aoE -m1 'icudt[0-9]+[lb]' "$dat")"
pkg="${pkg%%$'\n'*}"  # the package name, e.g. icudt78l
tmp="$(mktemp -d)"
cp "$dat" "$tmp/$pkg.dat"
printf '%s\n' brkitr/cjdict.dict brkitr/khmerdict.dict brkitr/burmesedict.dict \
  brkitr/laodict.dict brkitr/thaidict.dict zoneinfo64.res > "$tmp/remove.txt"
icupkg --ignore-deps -r "$tmp/remove.txt" "$tmp/$pkg.dat"
cp "$tmp/$pkg.dat" "$dat"
rm -rf "$tmp"
echo "ICU data: $(stat -c %s "$dat") bytes"
scons -j"$(nproc)" platform=web target=template_release profile="$here/blackoff_web.py"
zip="bin/godot.web.template_release.wasm32.nothreads.zip"
test -s "$zip"
mkdir -p "$(dirname "$out")"
cp "$zip" "$out"
unzip -l "$out"
