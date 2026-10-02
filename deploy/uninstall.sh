#!/usr/bin/env bash
# Removes everything deploy/install.sh created: the pm2 apps "blackoff" and
# "blackoff-updater", the nginx site file "blackoff", and /opt/blackoff.
# The certificate and the Postgres database (player profiles) are kept unless
# asked:  bash /opt/blackoff/bin/uninstall.sh [--delete-cert] [--drop-db] [--yes]
set -euo pipefail
APP_DIR="${BLACKOFF_DIR:-/opt/blackoff}"
MARKER="# managed by Blackoff deploy/install.sh"
DEL_CERT=0 DROP_DB=0 YES=0
for a in "$@"; do
  case "$a" in
    --delete-cert) DEL_CERT=1 ;; --drop-db) DROP_DB=1 ;; --yes|-y) YES=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
[ -f "$APP_DIR/.blackoff-install" ] || { echo "$APP_DIR is not a Blackoff install" >&2; exit 1; }
DOMAIN="$(sed -n 's/^BLACKOFF_DOMAIN=//p' "$APP_DIR/.env" 2>/dev/null | tail -n 1)"
if [ "$YES" = 0 ]; then
  printf 'Remove Blackoff (%s) from this server? [y/N] ' "${DOMAIN:-?}"
  read -r ans < /dev/tty || ans=""
  case "$ans" in y|Y|yes) ;; *) echo "cancelled"; exit 0 ;; esac
fi
PM2_BIN="$(command -v pm2 || true)"
if [ -n "$PM2_BIN" ]; then
  for a in blackoff-updater blackoff; do "$PM2_BIN" delete "$a" >/dev/null 2>&1 && echo "pm2: removed $a"; done
  "$PM2_BIN" save >/dev/null 2>&1 || true
fi
NG=/etc/nginx/sites-available/blackoff
if [ -f "$NG" ] && grep -qF "$MARKER" "$NG"; then
  rm -f /etc/nginx/sites-enabled/blackoff "$NG"
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || nginx -s reload
    echo "nginx: removed site blackoff"
  else
    echo "nginx -t fails after removing our site (not caused by it); nginx was not reloaded" >&2
  fi
fi
if [ "$DEL_CERT" = 1 ] && [ -n "$DOMAIN" ] && command -v certbot >/dev/null; then
  certbot delete --cert-name "$DOMAIN" --non-interactive >/dev/null 2>&1 && echo "certbot: deleted $DOMAIN"
fi
if [ "$DROP_DB" = 1 ] && grep -q '^DATABASE_URL=postgres://blackoff:' "$APP_DIR/.env"; then
  (cd / && runuser -u postgres -- psql -Xqc 'DROP DATABASE IF EXISTS blackoff' -c 'DROP ROLE IF EXISTS blackoff') && echo "postgres: dropped blackoff"
fi
rm -rf "$APP_DIR"
echo "Blackoff removed."
