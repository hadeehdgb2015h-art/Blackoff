#!/usr/bin/env bash
# Copies the repository-level shared/*.json into the Godot project (res://shared/).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$root/client/shared"
mkdir -p "$root/client/shared"
cp -r "$root"/shared/*.json "$root"/shared/maps "$root/client/shared/"
echo "synced $(find "$root/client/shared" -name "*.json" | wc -l) shared files into client/shared"
