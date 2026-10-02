#!/usr/bin/env bash
# Blackoff server check — READ ONLY. Changes nothing on this machine.
# Prints what the installer needs to know (OS, Node, pm2, nginx layout,
# certificates, free ports). Never prints secrets, env values or file contents.
#   curl -fsSL https://raw.githubusercontent.com/hadeehdgb2015h-art/Blackoff/claude/hopeful-cerf-elsmwp/deploy/check.sh | bash
set -u
say() { printf '%s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }
say "=== Blackoff check (read only) ==="
say "os: $( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || uname -s) | arch: $(uname -m) | cpus: $(nproc 2>/dev/null)"
say "ram: $(free -m 2>/dev/null | awk '/Mem:/{print $2" MB total, "$7" MB available"}') | disk free: $(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
say "user: $(id -un) | sudo without password: $(sudo -n true 2>/dev/null && echo yes || echo no)"
say "node: $(has node && node -v || echo missing) | npm: $(has npm && npm -v || echo missing) | git: $(has git && git --version | cut -d' ' -f3 || echo missing)"
if has pm2; then
  say "pm2: $(pm2 -v 2>/dev/null | tail -1) | apps: $(pm2 jlist 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')"
else
  say "pm2: missing"
fi
if has nginx || [ -x /usr/sbin/nginx ]; then
  NG=$(command -v nginx || echo /usr/sbin/nginx)
  say "nginx: $($NG -v 2>&1 | cut -d/ -f2)"
  for d in /etc/nginx/sites-enabled /etc/nginx/conf.d; do
    [ -d "$d" ] && say "  $d: $(ls "$d" 2>/dev/null | tr '\n' ' ')"
  done
  names=$(grep -RhoE '^\s*server_name\s+[^;]+' /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null | sed -E 's/^\s*server_name\s+//' | tr ' ' '\n' | grep -v '^_$' | sort -u | tr '\n' ' ')
  say "  domains served: ${names:-none found (or no permission)}"
else
  say "nginx: missing"
fi
if has certbot; then
  say "certbot: $(certbot --version 2>&1 | awk '{print $2}') | certificates: $(ls /etc/letsencrypt/live 2>/dev/null | grep -v README | tr '\n' ' ' || echo 'no permission')"
else
  say "certbot: missing"
fi
used=$( (ss -ltnH 2>/dev/null || netstat -ltn 2>/dev/null) | awk '{print $4}' | grep -oE '[0-9]+$' | sort -n -u)
free=""
for p in $(seq 8787 8799); do echo "$used" | grep -qx "$p" || { free=$p; break; }; done
say "listening ports: $(echo "$used" | tr '\n' ' ')"
say "suggested free port: ${free:-none in 8787-8799}"
say "public ip: $(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || echo unknown)"
say "=== end: copy everything above and send it ==="
