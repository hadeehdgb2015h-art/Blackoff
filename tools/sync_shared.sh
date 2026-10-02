#!/usr/bin/env bash
# Copies the repository-level shared/*.json into the Godot project (res://shared/).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$root/client/shared"
mkdir -p "$root/client/shared"
cp "$root"/shared/*.json "$root/client/shared/"
echo "synced $(ls "$root/client/shared" | wc -l) shared files into client/shared"
