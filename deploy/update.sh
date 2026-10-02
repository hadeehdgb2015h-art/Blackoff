#!/usr/bin/env bash
# Blackoff updater: installs a release into /opt/blackoff/releases/<version>,
# switches /opt/blackoff/current to it, restarts the "blackoff" pm2 app and
# rolls back if the new server does not answer /healthz.
#
#   update.sh --once            check the release URL once, update if newer
#   update.sh --loop [SECONDS]  keep checking (run by pm2 as "blackoff-updater")
#   update.sh --file TARBALL    install a local release tarball
#   update.sh --force           with --once: reinstall even if the version is current
#
# Touches nothing outside /opt/blackoff except `pm2 reload blackoff`.
set -euo pipefail

APP_DIR="${BLACKOFF_DIR:-/opt/blackoff}"
ENV_FILE="$APP_DIR/.env"
KEEP_RELEASES=3
MAX_DEFER_SEC=$((2 * 3600))   # an update waits for empty zones at most this long

log() { printf '%s [update] %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

env_get() { # value of KEY in .env (last one wins), empty if missing
  [ -f "$ENV_FILE" ] || return 0
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

PM2_BIN="$(env_get BLACKOFF_PM2)"; PM2_BIN="${PM2_BIN:-$(command -v pm2 || true)}"
PORT="$(env_get PORT)"; PORT="${PORT:-8787}"
RELEASE_URL="$(env_get BLACKOFF_RELEASE_URL)"
RELEASE_URL="${RELEASE_URL:-https://github.com/hadeehdgb2015h-art/Blackoff/releases/download/edge}"

current_version() { cat "$APP_DIR/current/VERSION" 2>/dev/null || true; }

health() { # wait up to $1 seconds for /healthz
  local i
  for i in $(seq 1 "$1"); do
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

players_online() {
  { curl -fsS --max-time 2 "http://127.0.0.1:$PORT/healthz" 2>/dev/null || true; } \
    | sed -n 's/.*"players":\([0-9]*\).*/\1/p' | head -n 1
}

app_registered() { [ -n "$PM2_BIN" ] && "$PM2_BIN" describe blackoff >/dev/null 2>&1; }

# Writes web/config.js so the client finds this server (same host, /ws).
write_site_config() {
  local dir="$1" domain scheme
  domain="$(env_get BLACKOFF_DOMAIN)"
  scheme="wss"; [ "$(env_get BLACKOFF_TLS)" = "0" ] && scheme="ws"
  [ -n "$domain" ] || return 0
  printf 'window.BLACKOFF_CONFIG = { server: "%s://%s/ws" };\n' "$scheme" "$domain" > "$dir/web/config.js"
}

# Unpacks a verified tarball into releases/<version>; prints the directory.
unpack() {
  local tarball="$1" tmp ver dest
  tmp="$(mktemp -d "$APP_DIR/releases/.unpack.XXXXXX")"
  tar -xzf "$tarball" -C "$tmp"
  [ -f "$tmp/blackoff/VERSION" ] && [ -f "$tmp/blackoff/server/server.mjs" ] && [ -f "$tmp/blackoff/web/index.html" ] \
    || { rm -rf "$tmp"; die "release archive is incomplete"; }
  ver="$(tr -cd 'A-Za-z0-9._-' < "$tmp/blackoff/VERSION")"
  [ -n "$ver" ] || { rm -rf "$tmp"; die "release has no version"; }
  dest="$APP_DIR/releases/$ver"
  rm -rf "$dest"
  mv "$tmp/blackoff" "$dest"
  rm -rf "$tmp"
  # nginx serves these pre-compressed (gzip_static); about 4x smaller downloads
  local f
  for f in "$dest"/web/*.wasm "$dest"/web/*.pck "$dest"/web/*.js "$dest"/web/*.html; do
    [ -f "$f" ] && gzip -9 -k -f "$f"
  done
  write_site_config "$dest"
  [ -f "$dest/web/config.js" ] && gzip -9 -k -f "$dest/web/config.js"
  echo "$dest"
}

switch_to() { # atomically points current at $1
  ln -sfn "$1" "$APP_DIR/current.new"
  mv -T "$APP_DIR/current.new" "$APP_DIR/current"
}

activate() {
  local dest="$1" prev
  [ -n "$dest" ] && [ -d "$dest" ] || { log "nothing to activate"; return 1; }
  prev="$(readlink -f "$APP_DIR/current" 2>/dev/null || true)"
  switch_to "$dest"
  # the updater updates itself too (takes effect on its next start)
  if cp "$dest/deploy/update.sh" "$APP_DIR/bin/update.sh.new" 2>/dev/null; then
    chmod 755 "$APP_DIR/bin/update.sh.new" && mv -f "$APP_DIR/bin/update.sh.new" "$APP_DIR/bin/update.sh"
  fi
  if app_registered; then
    "$PM2_BIN" restart blackoff >/dev/null
    if ! health 25; then
      log "new version $(basename "$dest") failed its health check"
      if [ -n "$prev" ] && [ -d "$prev" ] && [ "$prev" != "$dest" ]; then
        switch_to "$prev"
        "$PM2_BIN" restart blackoff >/dev/null || true
        health 25 && log "rolled back to $(basename "$prev")" || log "rollback did not come up either"
      fi
      echo "$(basename "$dest")" > "$APP_DIR/.bad-version"
      return 1
    fi
  fi
  log "now running $(basename "$dest")"
  rm -f "$APP_DIR/.bad-version" "$APP_DIR/.defer-since"
  prune
}

prune() {
  local keep cur
  cur="$(readlink -f "$APP_DIR/current")"
  keep="$({ ls -1dt "$APP_DIR"/releases/*/ 2>/dev/null || true; } | head -n "$KEEP_RELEASES" | xargs -r -n1 readlink -f)"
  local d
  for d in "$APP_DIR"/releases/*/; do
    d="$(readlink -f "$d")"
    [ "$d" = "$cur" ] && continue
    grep -qxF "$d" <<< "$keep" && continue
    rm -rf "$d"
  done
}

download_and_install() {
  local force="$1" remote cur tmp
  remote="$(curl -fsSL --max-time 20 "$RELEASE_URL/version.txt" | tr -cd 'A-Za-z0-9._-')" || { log "cannot reach $RELEASE_URL"; return 0; }
  [ -n "$remote" ] || { log "empty remote version"; return 0; }
  cur="$(current_version)"
  if [ "$remote" = "$cur" ] && [ "$force" != 1 ]; then return 0; fi
  if [ "$remote" = "$(cat "$APP_DIR/.bad-version" 2>/dev/null)" ] && [ "$force" != 1 ]; then return 0; fi
  # Do not restart under players unless the update has waited too long.
  local n since now
  n="$(players_online)"; now="$(date +%s)"
  if [ "${n:-0}" -gt 0 ] && [ "$force" != 1 ]; then
    [ -f "$APP_DIR/.defer-since" ] || echo "$now" > "$APP_DIR/.defer-since"
    since="$(cat "$APP_DIR/.defer-since")"
    if [ $((now - since)) -lt "$MAX_DEFER_SEC" ]; then
      log "version $remote is ready; waiting for $n player(s) to finish"
      return 0
    fi
  fi
  log "updating ${cur:-none} -> $remote"
  tmp="$(mktemp -d)"
  if curl -fsSL --max-time 600 -o "$tmp/blackoff.tar.gz" "$RELEASE_URL/blackoff.tar.gz" \
    && curl -fsSL --max-time 20 -o "$tmp/blackoff.tar.gz.sha256" "$RELEASE_URL/blackoff.tar.gz.sha256"; then
    if (cd "$tmp" && sha256sum -c --status blackoff.tar.gz.sha256); then
      activate "$(unpack "$tmp/blackoff.tar.gz")" || true
    else
      log "checksum mismatch, skipping"
    fi
  else
    log "download failed"
  fi
  rm -rf "$tmp"
}

trim_logs() { # our own pm2 logs only
  local f
  for f in "$APP_DIR"/logs/*.log; do
    [ -f "$f" ] && [ "$(stat -c %s "$f")" -gt $((20 * 1024 * 1024)) ] && truncate -s 0 "$f"
  done
  return 0
}

main() {
  [ -d "$APP_DIR" ] || die "$APP_DIR does not exist (run deploy/install.sh first)"
  mkdir -p "$APP_DIR/releases" "$APP_DIR/bin" "$APP_DIR/logs"
  exec 9> "$APP_DIR/.update.lock"
  local mode="${1:---once}" force=0
  if [ "${1:-}" = "--force" ] || [ "${2:-}" = "--force" ]; then force=1; fi
  case "$mode" in
    --file)
      [ -f "${2:-}" ] || die "usage: update.sh --file TARBALL"
      flock 9
      activate "$(unpack "$2")"
      ;;
    --once|--force)
      flock 9
      download_and_install "$force"
      ;;
    --loop)
      local every="${2:-300}"
      log "watching $RELEASE_URL every ${every}s (current: $(current_version))"
      while true; do
        if flock -n 9; then
          download_and_install 0 || true
          trim_logs
          flock -u 9
        fi
        sleep "$every"
      done
      ;;
    *) die "unknown option $mode" ;;
  esac
}

main "$@"
