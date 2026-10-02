#!/usr/bin/env bash
# Fetches CC0 (public domain) sound sources for the game into art/sfx_sources/.
# Runs in CI (.github/workflows/fetch-sfx.yml): the development session cannot
# reach sound libraries, GitHub's runners can. Every file keeps a SOURCE.txt
# with its page, author and licence; nothing but CC0 is kept.
#   tools/sfx/fetch_sources.sh <out dir>
set -uo pipefail
out="${1:-art/sfx_sources}"
mkdir -p "$out"
UA="Mozilla/5.0 (X11; Linux x86_64) BlackoffAssetFetch/1.0"
MAX_FILE=$((8 * 1024 * 1024))    # skip single files above 8 MB
MAX_TOTAL=$((45 * 1024 * 1024))  # stop downloading above 45 MB in total
total=0
log() { printf '%s\n' "$*" | tee -a "$out/FETCH_LOG.txt"; }
: > "$out/FETCH_LOG.txt"

fetch() { # url dest -> 0 when saved
  local url="$1" dest="$2" size
  size=$(curl -sIL -A "$UA" -m 30 "$url" | awk 'tolower($1)=="content-length:"{v=$2} END{gsub("\r","",v); print v+0}')
  if [ "${size:-0}" -gt "$MAX_FILE" ]; then log "  skip (too big ${size}): $url"; return 1; fi
  if [ $((total + ${size:-0})) -gt "$MAX_TOTAL" ]; then log "  skip (budget): $url"; return 1; fi
  mkdir -p "$(dirname "$dest")"
  if curl -sSL -A "$UA" -m 120 -o "$dest" "$url"; then
    total=$((total + $(stat -c %s "$dest")))
    return 0
  fi
  rm -f "$dest"; return 1
}

# ---- Kenney (all CC0): real recordings of footsteps and impacts, interface clicks, sci-fi shots
for pack in impact-sounds interface-sounds rpg-audio sci-fi-sounds; do
  page="https://kenney.nl/assets/$pack"
  zip=$(curl -sSL -A "$UA" -m 60 "$page" | grep -oE 'https://kenney\.nl/media/pages/assets/[^"]+\.zip' | head -n1)
  if [ -z "$zip" ]; then log "kenney $pack: no zip link found"; continue; fi
  log "kenney $pack: $zip"
  tmp=$(mktemp -d)
  if fetch "$zip" "$tmp/pack.zip"; then
    mkdir -p "$out/kenney_$pack"
    unzip -q -o "$tmp/pack.zip" -d "$tmp/x"
    find "$tmp/x" -type f \( -iname '*.ogg' -o -iname '*.wav' \) -exec cp {} "$out/kenney_$pack/" \;
    find "$tmp/x" -type f -iname 'License*' -exec cp {} "$out/kenney_$pack/LICENSE.txt" \; -quit
    printf 'Source: %s\nAuthor: Kenney (www.kenney.nl)\nLicence: CC0 1.0\n' "$page" > "$out/kenney_$pack/SOURCE.txt"
    log "  kept $(ls "$out/kenney_$pack" | grep -ciE '\.(ogg|wav)$') files"
  fi
  rm -rf "$tmp"
done

# ---- OpenGameArt: sound effects (type 13) licensed CC0, per query; keep only pages that state CC0
oga_search() { # query max_pages
  local q="$1" max="$2" url links n=0
  url="https://opengameart.org/art-search-advanced?keys=$(printf '%s' "$q" | sed 's/ /+/g')&field_art_type_tid%5B%5D=13&field_art_license_tid%5B%5D=4&sort_by=count&sort_order=DESC&items_per_page=24"
  links=$(curl -sSL -A "$UA" -m 60 "$url" | grep -oE 'href="/content/[a-z0-9-]+"' | sed 's/href="//; s/"$//' | awk '!seen[$0]++')
  log "oga '$q': $(printf '%s\n' "$links" | grep -c . ) results"
  for path in $links; do
    [ "$n" -ge "$max" ] && break
    local page html slug lic author files
    page="https://opengameart.org$path"
    slug=$(basename "$path")
    [ -d "$out/oga/$slug" ] && continue
    html=$(curl -sSL -A "$UA" -m 60 "$page")
    lic=$(printf '%s' "$html" | grep -oE 'license-icon[^>]*title="[^"]+"|<a href="[^"]*creativecommons\.org/publicdomain/zero[^"]*"' | head -n3 | tr '\n' ' ')
    if ! printf '%s' "$lic $html" | grep -qiE 'publicdomain/zero|CC0'; then log "  $slug: not CC0, skipped"; continue; fi
    author=$(printf '%s' "$html" | grep -oE 'field-name-author-submitter.*?</a>' | sed -E 's/<[^>]+>//g' | head -n1)
    files=$(printf '%s' "$html" | grep -oE 'https://opengameart\.org/sites/default/files/[^"]+\.(ogg|wav|mp3|zip|flac)' | awk '!seen[$0]++')
    [ -z "$files" ] && { log "  $slug: no audio files"; continue; }
    n=$((n + 1))
    mkdir -p "$out/oga/$slug"
    printf 'Source: %s\nAuthor: %s\nLicence: CC0 1.0 (as stated on the page)\nQuery: %s\n' "$page" "$author" "$q" > "$out/oga/$slug/SOURCE.txt"
    for f in $files; do
      local name; name=$(basename "$f" | sed 's/%20/_/g; s/[^A-Za-z0-9._-]/_/g')
      if fetch "$f" "$out/oga/$slug/$name"; then
        case "$name" in
          *.zip) (cd "$out/oga/$slug" && unzip -q -o "$name" -x '__MACOSX/*' && rm -f "$name"
                  find . -type f ! \( -iname '*.ogg' -o -iname '*.wav' -o -iname '*.mp3' -o -iname '*.flac' -o -iname 'SOURCE.txt' -o -iname '*licen*' -o -iname '*readme*' \) -delete) ;;
        esac
        log "  $slug: $name"
      fi
    done
  done
}
oga_search "gunshot" 4
oga_search "pistol" 2
oga_search "shotgun" 2
oga_search "machine gun" 2
oga_search "reload" 2
oga_search "zombie" 4
oga_search "monster growl" 2
oga_search "footsteps" 2
oga_search "horror ambient" 2
oga_search "dark ambient loop" 2
oga_search "heartbeat" 1
oga_search "thunder" 1

log "total downloaded: $((total / 1024)) KB"
find "$out" -type f \( -iname '*.ogg' -o -iname '*.wav' -o -iname '*.mp3' -o -iname '*.flac' \) | sort > "$out/FILES.txt"
log "audio files: $(wc -l < "$out/FILES.txt")"
