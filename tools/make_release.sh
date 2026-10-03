#!/usr/bin/env bash
# Packs a deployable release: bundled server, shared data, web build, deploy scripts.
#   tools/make_release.sh <web build dir> <out dir> [version]
# Writes <out>/blackoff.tar.gz, blackoff.tar.gz.sha256 and version.txt
# (the files deploy/update.sh downloads). Needs `npm run bundle` first.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
web="$(cd "$1" && pwd)"; mkdir -p "$2"; out="$(cd "$2" && pwd)"
ver="${3:-$(date -u +%Y%m%d%H%M)-$(git -C "$root" rev-parse --short=7 HEAD)}"
[ -f "$root/server/dist-bundle/server.mjs" ] || { echo "run: (cd server && npm run bundle)" >&2; exit 1; }
[ -f "$web/index.html" ] && ls "$web"/index.*.wasm >/dev/null 2>&1 || { echo "no web build in $web" >&2; exit 1; }
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
b="$stage/blackoff"
mkdir -p "$b/server" "$b/shared" "$b/web" "$b/deploy"
cp "$root"/server/dist-bundle/*.mjs* "$root"/server/dist-bundle/resvg.wasm "$b/server/"
# result card background and fonts (phase 25)
cp -r "$root/server/assets" "$b/server/"
cp -r "$root"/shared/*.json "$root/shared/maps" "$b/shared/"
cp -r "$web"/. "$b/web/"
rm -f "$b"/web/config.js "$b"/web/*.gz
cp "$root"/deploy/{install.sh,update.sh,uninstall.sh,owner.env} "$b/deploy/"
echo "$ver" > "$b/VERSION"
tar -C "$stage" -czf "$out/blackoff.tar.gz" blackoff
(cd "$out" && sha256sum blackoff.tar.gz > blackoff.tar.gz.sha256)
echo "$ver" > "$out/version.txt"
echo "release $ver: $(du -h "$out/blackoff.tar.gz" | cut -f1)"
