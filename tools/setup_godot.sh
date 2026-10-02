#!/usr/bin/env bash
# Downloads the pinned Godot editor (Linux x86_64) and the Web export templates
# from the official GitHub releases. Idempotent.
#   GODOT_DIR (default /opt/godot) – install location; exposes $GODOT_DIR/godot
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=godot_version.env
source "$here/godot_version.env"
tag="${GODOT_VERSION}-${GODOT_STATUS}"
base="https://github.com/godotengine/godot/releases/download/${tag}"
dir="${GODOT_DIR:-/opt/godot}"
tpl_dir="${HOME}/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_STATUS}"
bin="Godot_v${tag}_linux.x86_64"

mkdir -p "$dir" "$tpl_dir"
if [ ! -x "$dir/$bin" ]; then
  echo "Downloading Godot $tag editor"
  curl -fsSL --retry 4 -o "$dir/godot.zip" "$base/${bin}.zip"
  unzip -qo "$dir/godot.zip" -d "$dir" && rm "$dir/godot.zip"
fi
ln -sf "$dir/$bin" "$dir/godot"

if [ ! -f "$tpl_dir/web_nothreads_release.zip" ]; then
  echo "Downloading export templates (large, web templates are extracted only)"
  tmp="$(mktemp -d)"
  curl -fsSL --retry 4 -o "$tmp/t.tpz" "$base/Godot_v${tag}_export_templates.tpz"
  unzip -qoj "$tmp/t.tpz" 'templates/web_nothreads_*' 'templates/version.txt' -d "$tpl_dir"
  rm -rf "$tmp"
fi
"$dir/godot" --version
