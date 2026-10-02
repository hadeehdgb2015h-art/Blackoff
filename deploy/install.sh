#!/usr/bin/env bash
# Blackoff installer for a shared Linux server (pm2 + nginx + certbot).
#
#   curl -fsSL https://raw.githubusercontent.com/hadeehdgb2015h-art/Blackoff/claude/hopeful-cerf-elsmwp/deploy/install.sh | sudo bash
#   ... | sudo bash -s -- --domain play.example.com
#
# What it creates, and nothing else:
#   /opt/blackoff/                       releases, .env (secrets, mode 600), logs, bin/update.sh
#   pm2 apps "blackoff" (game server, 127.0.0.1:PORT) and "blackoff-updater"
#   /etc/nginx/sites-available/blackoff + its link in sites-enabled (only server_name DOMAIN)
#   one Let's Encrypt certificate for DOMAIN (webroot method, other sites untouched)
#   Postgres role + database "blackoff" in the local cluster, if one is reachable
# Other pm2 apps, nginx sites and certificates are never modified. nginx is only
# reloaded after `nginx -t` passes; if a step fails, our nginx file is removed again.
#
# Options (all optional; re-running is safe and keeps existing settings):
#   --domain NAME     game address; default: blackoff.<ip-with-dashes>.sslip.io (no DNS setup needed)
#   --port N          local port for the game server; default: first free in 8787-8799
#   --email ADDR      email for Let's Encrypt expiry notices
#   --release FILE    install this release tarball instead of downloading the latest
#   --no-tls          plain HTTP only (tests); no certificate
#   --yes             do not ask questions (Telegram token can come from $TELEGRAM_BOT_TOKEN)
set -euo pipefail

APP_DIR="${BLACKOFF_DIR:-/opt/blackoff}"
RELEASE_URL="${BLACKOFF_RELEASE_URL:-https://github.com/hadeehdgb2015h-art/Blackoff/releases/download/edge}"
NGINX_AVAIL=/etc/nginx/sites-available/blackoff
NGINX_ENABLED=/etc/nginx/sites-enabled/blackoff
MARKER="# managed by Blackoff deploy/install.sh"

DOMAIN="" PORT="" EMAIL="" RELEASE_FILE="" TLS=1 YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --release) RELEASE_FILE="${2:-}"; shift 2 ;;
    --no-tls) TLS=0; shift ;;
    --yes|-y) YES=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }
ok() { printf '    \033[32mok\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31mSTOPPED:\033[0m %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }
tty_ok() { [ "$YES" = 0 ] && { : < /dev/tty; } 2>/dev/null; }
env_get() { [ -f "$APP_DIR/.env" ] && sed -n "s/^$1=//p" "$APP_DIR/.env" | tail -n 1 || true; }
env_set() { # KEY VALUE (replaces or appends; file stays mode 600)
  local tmp
  tmp="$(mktemp "$APP_DIR/.env.XXXXXX")"
  grep -v "^$1=" "$APP_DIR/.env" > "$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$APP_DIR/.env"
}

# ------------------------------------------------------------------ checks
step "Checking this server (nothing is changed yet)"
[ "$(id -u)" = 0 ] || fail "run as root (… | sudo bash)"
for t in node curl tar gzip sha256sum flock ss openssl; do has "$t" || fail "missing tool: $t"; done
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 20 ] || fail "Node.js 20 or newer is needed (found $(node -v))"
PM2_BIN="$(command -v pm2 || true)"; [ -n "$PM2_BIN" ] || fail "pm2 is not installed"
NGINX_BIN="$(command -v nginx || echo /usr/sbin/nginx)"; [ -x "$NGINX_BIN" ] || fail "nginx is not installed"
[ -d /etc/nginx/sites-enabled ] || fail "/etc/nginx/sites-enabled not found (unsupported nginx layout)"
"$NGINX_BIN" -t >/dev/null 2>&1 || fail "the current nginx configuration already has errors (nginx -t). Fix that first; nothing was changed."
if [ "$TLS" = 1 ]; then has certbot || fail "certbot is not installed"; fi
if [ -e "$APP_DIR" ] && [ ! -f "$APP_DIR/.blackoff-install" ]; then
  fail "$APP_DIR exists but was not created by this installer; refusing to touch it"
fi
if [ -e "$NGINX_AVAIL" ] && ! grep -qF "$MARKER" "$NGINX_AVAIL"; then
  fail "$NGINX_AVAIL exists and is not ours; refusing to touch it"
fi
ok "node $(node -v), pm2 $("$PM2_BIN" -v 2>/dev/null | tail -n 1), $("$NGINX_BIN" -v 2>&1 | cut -d' ' -f3)"

PUBLIC_IP="$(curl -fsS4 -m 8 https://api.ipify.org 2>/dev/null || curl -fsS4 -m 8 https://ifconfig.me 2>/dev/null || true)"
DOMAIN="${DOMAIN:-$(env_get BLACKOFF_DOMAIN)}"
if [ -z "$DOMAIN" ]; then
  [ -n "$PUBLIC_IP" ] || fail "cannot detect the public IP; pass --domain"
  DOMAIN="blackoff.${PUBLIC_IP//./-}.sslip.io"
fi
DOMAIN="$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z')"
printf '%s' "$DOMAIN" | grep -qE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' || fail "invalid domain: $DOMAIN"
# The domain must not already belong to another site on this server.
if grep -RslE "^\s*server_name\s[^;]*(\s|^)${DOMAIN//./\\.}(\s|;)" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null \
  | xargs -r readlink -f | grep -vxF "$(readlink -f "$NGINX_AVAIL" 2>/dev/null || echo none)" | grep -q .; then
  fail "$DOMAIN is already used by another nginx site on this server; choose another name"
fi
RESOLVED="$({ getent ahostsv4 "$DOMAIN" 2>/dev/null || true; } | awk 'NR==1{print $1}')"
if [ "$TLS" = 1 ]; then
  [ -n "$RESOLVED" ] || fail "$DOMAIN does not resolve yet. Add a DNS 'A' record: $DOMAIN -> ${PUBLIC_IP:-<server ip>}, wait a few minutes, then run this again."
  if [ -n "$PUBLIC_IP" ] && [ "$RESOLVED" != "$PUBLIC_IP" ]; then
    fail "$DOMAIN points to $RESOLVED, but this server is $PUBLIC_IP. Fix the DNS 'A' record, then run this again."
  fi
fi
ok "domain $DOMAIN${RESOLVED:+ -> $RESOLVED}"

PORT="${PORT:-$(env_get PORT)}"
port_used() { ss -ltnH "( sport = :$1 )" 2>/dev/null | grep -q .; }
ours_running() { "$PM2_BIN" describe blackoff >/dev/null 2>&1; }
if [ -z "$PORT" ]; then
  for p in $(seq 8787 8799); do port_used "$p" || { PORT=$p; break; }; done
  [ -n "$PORT" ] || fail "no free port in 8787-8799; pass --port"
elif port_used "$PORT" && ! ours_running; then
  fail "port $PORT is already in use by another program; pass a different --port"
fi
ok "local port $PORT"

# ------------------------------------------------------------------ files
step "Creating $APP_DIR"
mkdir -p "$APP_DIR"/{releases,bin,logs,acme,backups}
touch "$APP_DIR/.blackoff-install"
chmod 755 "$APP_DIR" "$APP_DIR/acme"
[ -f "$APP_DIR/.env" ] || { install -m 600 /dev/null "$APP_DIR/.env"; }
chmod 600 "$APP_DIR/.env"
env_set NODE_ENV production
env_set HOST 127.0.0.1
env_set PORT "$PORT"
env_set WS_PATH /ws
env_set SHARED_DIR "$APP_DIR/current/shared"
env_set ALLOW_DEV_AUTH 0
[ -n "$(env_get LOG_LEVEL)" ] || env_set LOG_LEVEL info
env_set BLACKOFF_DOMAIN "$DOMAIN"
env_set BLACKOFF_TLS "$TLS"
env_set BLACKOFF_PM2 "$PM2_BIN"
env_set BLACKOFF_RELEASE_URL "$RELEASE_URL"
ok ".env (mode 600, never printed)"

# ------------------------------------------------------------------ telegram
step "Telegram bot"
tg_check() { { curl -fsS -m 10 "https://api.telegram.org/bot$1/getMe" 2>/dev/null || true; } | sed -n 's/.*"username":"\([^"]*\)".*/\1/p'; }
TOKEN="$(env_get TELEGRAM_BOT_TOKEN)"
if [ -z "$TOKEN" ] && [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then TOKEN="$TELEGRAM_BOT_TOKEN"; env_set TELEGRAM_BOT_TOKEN "$TOKEN"; fi
if [ -z "$TOKEN" ] && tty_ok; then
  echo "    Paste the token of the game's bot from @BotFather (input is hidden), or press Enter to skip:"
  for _ in 1 2 3; do
    IFS= read -rs TOKEN < /dev/tty || TOKEN=""; echo
    TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]')"
    [ -z "$TOKEN" ] && break
    if [ -n "$(tg_check "$TOKEN")" ]; then env_set TELEGRAM_BOT_TOKEN "$TOKEN"; break; fi
    echo "    Telegram did not accept that token. Try again (or Enter to skip):"; TOKEN=""
  done
fi
BOT_USER=""
if [ -n "$TOKEN" ]; then
  BOT_USER="$(tg_check "$TOKEN")"
  [ -n "$BOT_USER" ] && ok "bot @$BOT_USER" || warn "token saved, but Telegram did not confirm it (check it later)"
else
  warn "no bot token yet: online play stays closed until one is added (run this installer again)"
fi

# ------------------------------------------------------------------ database
step "Database (Postgres)"
as_pg() { (cd / && runuser -u postgres -- "$@"); }
DB_URL="$(env_get DATABASE_URL)"
if [ -n "$DB_URL" ]; then
  ok "already configured"
elif has psql && id postgres >/dev/null 2>&1 && as_pg psql -XAtqc 'select 1' >/dev/null 2>&1; then
  # Only a fresh role + database are ours. Existing ones (someone else's, or left
  # by an earlier install whose .env is gone) are never altered.
  if as_pg psql -XAtqc "select 1 from pg_roles where rolname='blackoff'" | grep -q 1 \
    || as_pg psql -XAtqc "select 1 from pg_database where datname='blackoff'" | grep -q 1; then
    warn "a Postgres role or database named 'blackoff' already exists; not touching it (profiles stay in memory)"
  else
    PW="$(openssl rand -hex 24)"
    as_pg psql -Xqc "CREATE ROLE blackoff WITH LOGIN PASSWORD '$PW'" >/dev/null
    as_pg psql -Xqc "CREATE DATABASE blackoff OWNER blackoff" >/dev/null
    PGPORT_LOCAL="$(as_pg psql -XAtqc 'show port')"
    DB_URL="postgres://blackoff:$PW@127.0.0.1:${PGPORT_LOCAL:-5432}/blackoff"
    if PGCONNECT_TIMEOUT=5 psql "$DB_URL" -XAtqc 'select 1' >/dev/null 2>&1; then
      env_set DATABASE_URL "$DB_URL"
      ok "database 'blackoff' ready (own role, own database)"
    else
      warn "created role/database but cannot log in over 127.0.0.1 (pg_hba); profiles stay in memory"
    fi
  fi
else
  warn "no local Postgres reachable; profiles stay in memory (set DATABASE_URL in $APP_DIR/.env later)"
fi

# ------------------------------------------------------------------ release
step "Installing the game"
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
if [ -n "$RELEASE_FILE" ]; then
  cp "$RELEASE_FILE" "$WORK/blackoff.tar.gz"
else
  curl -fsSL -m 600 -o "$WORK/blackoff.tar.gz" "$RELEASE_URL/blackoff.tar.gz" || fail "cannot download the game from $RELEASE_URL"
  curl -fsSL -m 30 -o "$WORK/blackoff.tar.gz.sha256" "$RELEASE_URL/blackoff.tar.gz.sha256" || fail "cannot download the checksum"
  (cd "$WORK" && sha256sum -c --status blackoff.tar.gz.sha256) || fail "download is corrupt (checksum mismatch)"
fi
tar -xzf "$WORK/blackoff.tar.gz" -C "$WORK" blackoff/deploy/update.sh
install -m 755 "$WORK/blackoff/deploy/update.sh" "$APP_DIR/bin/update.sh"
BLACKOFF_DIR="$APP_DIR" "$APP_DIR/bin/update.sh" --file "$WORK/blackoff.tar.gz"
ok "version $(cat "$APP_DIR/current/VERSION")"

# ------------------------------------------------------------------ pm2
step "Starting with pm2 (apps: blackoff, blackoff-updater)"
cat > "$APP_DIR/ecosystem.config.cjs" <<EOF
// $MARKER. Reads $APP_DIR/.env at start; secrets stay out of this file.
const fs = require("fs");
const env = {};
for (const line of fs.readFileSync("$APP_DIR/.env", "utf8").split("\n")) {
  const m = /^([A-Z_][A-Z0-9_]*)=(.*)\$/.exec(line);
  if (m) env[m[1]] = m[2];
}
const common = { cwd: "$APP_DIR", time: true, merge_logs: true, autorestart: true };
module.exports = {
  apps: [
    {
      ...common, name: "blackoff", script: "$APP_DIR/current/server/server.mjs",
      interpreter: "$(command -v node)", node_args: "--enable-source-maps",
      env, max_memory_restart: "400M", kill_timeout: 6000, restart_delay: 2000,
      out_file: "$APP_DIR/logs/server.log", error_file: "$APP_DIR/logs/server.log",
    },
    {
      ...common, name: "blackoff-updater", script: "$APP_DIR/bin/update.sh", args: "--loop 300",
      interpreter: "bash", env: { BLACKOFF_DIR: "$APP_DIR", PATH: process.env.PATH },
      restart_delay: 60000, out_file: "$APP_DIR/logs/updater.log", error_file: "$APP_DIR/logs/updater.log",
    },
  ],
};
EOF
for a in blackoff blackoff-updater; do "$PM2_BIN" delete "$a" >/dev/null 2>&1 || true; done
"$PM2_BIN" start "$APP_DIR/ecosystem.config.cjs" >/dev/null
for _ in $(seq 1 30); do curl -fsS -m 2 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS -m 2 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 || {
  tail -n 20 "$APP_DIR/logs/server.log" >&2 || true
  fail "the game server did not start (log above)"
}
ok "game server answers on 127.0.0.1:$PORT ($(curl -fsS "http://127.0.0.1:$PORT/healthz" | sed -n 's/.*"store":"\([a-z]*\)".*/\1/p') store)"
# Persist the process list for reboots; keep a copy of the previous one.
[ -f "${PM2_HOME:-$HOME/.pm2}/dump.pm2" ] && cp "${PM2_HOME:-$HOME/.pm2}/dump.pm2" "$APP_DIR/backups/dump.pm2.$(date +%Y%m%d%H%M%S)"
"$PM2_BIN" save >/dev/null && ok "pm2 save (previous list backed up in $APP_DIR/backups)"

# ------------------------------------------------------------------ nginx
step "nginx site for $DOMAIN"
LISTEN6=0; [ -f /proc/net/if_inet6 ] && LISTEN6=1
game_locations() {
  cat <<EOF
    root $APP_DIR/current/web;
    index index.html;
    gzip_static on;
    location = /ws {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }
    location = /healthz {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
    location ~ \.wasm\$ {
        types { }
        default_type application/wasm;
        add_header Cache-Control "no-cache";
    }
    location / {
        try_files \$uri \$uri/ =404;
        add_header Cache-Control "no-cache";
    }
EOF
}
write_nginx() { # $1 = http-only | redirect | tls
  {
    echo "$MARKER"
    echo "# Remove with: bash $APP_DIR/bin/uninstall.sh"
    echo "server {"
    echo "    listen 80;"
    [ "$LISTEN6" = 1 ] && echo "    listen [::]:80;"
    echo "    server_name $DOMAIN;"
    echo "    location ^~ /.well-known/acme-challenge/ { root $APP_DIR/acme; default_type text/plain; }"
    if [ "$1" = http-only ]; then game_locations; else echo "    location / { return 301 https://\$host\$request_uri; }"; fi
    echo "}"
    if [ "$1" = tls ]; then
      echo "server {"
      echo "    listen 443 ssl;"
      [ "$LISTEN6" = 1 ] && echo "    listen [::]:443 ssl;"
      echo "    server_name $DOMAIN;"
      echo "    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;"
      echo "    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;"
      if [ -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
        echo "    include /etc/letsencrypt/options-ssl-nginx.conf;"
      else
        echo "    ssl_protocols TLSv1.2 TLSv1.3;"
      fi
      game_locations
      echo "}"
    fi
  } > "$WORK/nginx.conf"
  local backup=""
  [ -f "$NGINX_AVAIL" ] && { backup="$WORK/nginx.prev"; cp "$NGINX_AVAIL" "$backup"; }
  install -m 644 "$WORK/nginx.conf" "$NGINX_AVAIL"
  ln -sfn "$NGINX_AVAIL" "$NGINX_ENABLED"
  if ! "$NGINX_BIN" -t >/dev/null 2>"$WORK/nginx.err"; then
    if [ -n "$backup" ]; then cp "$backup" "$NGINX_AVAIL"; else rm -f "$NGINX_ENABLED" "$NGINX_AVAIL"; fi
    cat "$WORK/nginx.err" >&2
    fail "nginx rejected the new site; it was removed again and nginx was NOT reloaded"
  fi
  systemctl reload nginx 2>/dev/null || "$NGINX_BIN" -s reload
}
if [ "$TLS" = 0 ]; then
  write_nginx http-only
  ok "http://$DOMAIN/ (no TLS)"
else
  if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    ok "certificate already exists"
  else
    write_nginx redirect
    step "Requesting a certificate for $DOMAIN (Let's Encrypt, webroot)"
    MAIL_ARGS=(--register-unsafely-without-email); [ -n "$EMAIL" ] && MAIL_ARGS=(-m "$EMAIL")
    if ! certbot certonly --webroot -w "$APP_DIR/acme" -d "$DOMAIN" --cert-name "$DOMAIN" \
        --non-interactive --agree-tos "${MAIL_ARGS[@]}" --keep-until-expiring \
        --deploy-hook "nginx -t && systemctl reload nginx" >"$WORK/certbot.log" 2>&1; then
      tail -n 15 "$WORK/certbot.log" >&2
      write_nginx http-only
      fail "Let's Encrypt refused the certificate (log above). The game runs on http://$DOMAIN/ for now, but Telegram only opens HTTPS. Try --domain with your own (sub)domain."
    fi
    ok "certificate issued (renews automatically with your other certificates)"
  fi
  write_nginx tls
  ok "https://$DOMAIN/"
fi

# ------------------------------------------------------------------ finish
install -m 755 "$WORK/blackoff/deploy/update.sh" "$APP_DIR/bin/update.sh"
if tar -xzf "$WORK/blackoff.tar.gz" -C "$WORK" blackoff/deploy/uninstall.sh 2>/dev/null; then
  install -m 755 "$WORK/blackoff/deploy/uninstall.sh" "$APP_DIR/bin/uninstall.sh"
fi
SCHEME=https; [ "$TLS" = 0 ] && SCHEME=http
GAME_URL="$SCHEME://$DOMAIN/"
step "Checking from outside in"
if curl -fsS -m 10 --resolve "$DOMAIN:$([ "$TLS" = 1 ] && echo 443 || echo 80):127.0.0.1" "${GAME_URL}healthz" >/dev/null 2>&1; then
  ok "${GAME_URL}healthz answers through nginx"
else
  warn "${GAME_URL}healthz did not answer through nginx yet"
fi
if [ -n "$BOT_USER" ] && [ "$TLS" = 1 ]; then
  if curl -fsS -m 10 "https://api.telegram.org/bot$TOKEN/setChatMenuButton" -H 'content-type: application/json' \
      -d "{\"menu_button\":{\"type\":\"web_app\",\"text\":\"Play\",\"web_app\":{\"url\":\"$GAME_URL\"}}}" | grep -q '"ok":true'; then
    ok "bot menu button 'Play' opens the game"
  else
    warn "could not set the bot's menu button"
  fi
fi

cat <<EOF

=================== Blackoff is installed ===================
 Game:     $GAME_URL
 Bot:      ${BOT_USER:+https://t.me/$BOT_USER}${BOT_USER:-not set (run the installer again to add the token)}
 Server:   127.0.0.1:$PORT  (pm2: blackoff, blackoff-updater)
 Updates:  automatic every 5 minutes (waits for running games)
 Logs:     pm2 logs blackoff
 Remove:   bash $APP_DIR/bin/uninstall.sh
=============================================================
EOF
