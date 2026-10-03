#!/usr/bin/env python3
"""Fetches CC0 music candidates from OpenGameArt into art/music_sources/.

Runs in CI (.github/workflows/fetch-sfx.yml): the development session cannot
reach OpenGameArt. A page is kept only when its own "License(s)" field lists
CC0 and nothing else (phase 17 learned that pages mentioning CC0 elsewhere,
e.g. in collection names, can be CC-BY). Each kept page gets a SOURCE.txt
with its URL, author and the licence field as written on the page.

  python3 tools/sfx/fetch_music.py <out dir>
"""
import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request

OUT = sys.argv[1] if len(sys.argv) > 1 else "art/music_sources"
UA = "Mozilla/5.0 (X11; Linux x86_64) BlackoffAssetFetch/1.0"
MAX_FILE = 9 * 1024 * 1024
MAX_TOTAL = 60 * 1024 * 1024
# (query, pages to keep)
QUERIES = [("dark ambient", 5), ("horror ambient", 4), ("horror music", 3), ("creepy loop", 3),
           ("dungeon ambient", 3), ("tension music", 2), ("dark fantasy music", 3)]
total = 0
log = []


def get(url, binary=False):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=90) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def size_of(url):
    try:
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            return int(r.headers.get("Content-Length") or 0)
    except Exception:
        return 0


def licence_field(page):
    """The text of the page's "License(s):" field (tags stripped)."""
    text = " ".join(html.unescape(re.sub(r"<[^>]+>", " ", page)).split())
    m = re.search(r"License\(s\):\s*(.*?)\s*(?:Collections:|Favorites:|File\(s\):|Copyright|Attribution|$)", text)
    return m.group(1)[:120] if m else ""


def author_of(page):
    m = re.search(r'field-name-author-submitter.*?<a [^>]*>(.*?)</a>', page, re.S)
    return html.unescape(re.sub(r"<[^>]+>", "", m.group(1))).strip() if m else "?"


def main():
    global total
    os.makedirs(OUT, exist_ok=True)
    seen = set(os.listdir(OUT))
    for q, keep in QUERIES:
        url = ("https://opengameart.org/art-search-advanced?keys=%s&field_art_type_tid%%5B%%5D=12"
               "&field_art_license_tid%%5B%%5D=4&sort_by=count&sort_order=DESC&items_per_page=24") % urllib.parse.quote_plus(q)
        try:
            links = list(dict.fromkeys(re.findall(r'href="(/content/[a-z0-9-]+)"', get(url))))
        except Exception as e:
            log.append("search %r failed: %s" % (q, e))
            continue
        log.append("search %r: %d results" % (q, len(links)))
        n = 0
        for path in links:
            if n >= keep or total > MAX_TOTAL:
                break
            slug = path.rsplit("/", 1)[1]
            if slug in seen:
                continue
            seen.add(slug)
            page_url = "https://opengameart.org" + path
            try:
                page = get(page_url)
            except Exception:
                continue
            lic = licence_field(page)
            if "CC0" not in lic or re.search(r"BY|GPL|OGA", lic):
                log.append("  %s: licence %r, skipped" % (slug, lic))
                continue
            files = list(dict.fromkeys(re.findall(r'https://opengameart\.org/sites/default/files/[^"]+\.(?:ogg|mp3|wav|flac)', page)))
            if not files:
                continue
            d = os.path.join(OUT, slug)
            os.makedirs(d, exist_ok=True)
            got = []
            for f in files[:3]:
                sz = size_of(f)
                if sz > MAX_FILE or total + sz > MAX_TOTAL:
                    log.append("  %s: %s too big (%d)" % (slug, f, sz))
                    continue
                name = re.sub(r"[^A-Za-z0-9._-]", "_", urllib.parse.unquote(f.rsplit("/", 1)[1]))
                try:
                    data = get(f, binary=True)
                except Exception:
                    continue
                if data[:15].lower().startswith(b"<!doctype") or data[:5].lower() == b"<html":
                    continue
                with open(os.path.join(d, name), "wb") as fh:
                    fh.write(data)
                total += len(data)
                got.append(name)
            if not got:
                os.rmdir(d)
                continue
            n += 1
            with open(os.path.join(d, "SOURCE.txt"), "w") as fh:
                fh.write("Source: %s\nAuthor: %s\nLicence field: %s\nQuery: %s\nFiles: %s\n" % (page_url, author_of(page), lic, q, ", ".join(got)))
            log.append("  %s: kept %s (%s)" % (slug, ", ".join(got), lic))
    log.append("total %d KB" % (total // 1024))
    with open(os.path.join(OUT, "FETCH_LOG.txt"), "a") as fh:
        fh.write("\n".join(log) + "\n")
    print("\n".join(log))


main()
