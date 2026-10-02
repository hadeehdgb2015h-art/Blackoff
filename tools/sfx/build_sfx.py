#!/usr/bin/env python3
"""Builds the game's sounds (client/assets/sfx/*.wav) from real CC0 recordings
kept in art/sfx_sources/ (fetched by .github/workflows/fetch-sfx.yml).

Every sound is a recipe: one or more layers (source file, start, length, pitch,
ffmpeg filters, gain), then a trim, a fade-out that reaches silence before the
sound's end (web playback stops a voice abruptly when it is reused, so a tail
that is still loud clicks), a peak normalisation and 16-bit output with dither.
Music beds are cut into seamless crossfaded loops.

Phase 17 replaced the synthesized placeholders of tools/gen_sfx.py, which the
owner heard as crackly, cheap and repetitive (a 15.75 s music loop plus a
thunder clap every 9-20 s).

Run:  python tools/sfx/build_sfx.py [name ...]   (needs ffmpeg and numpy)
"""
import os
import subprocess
import sys
import wave
import zlib

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art", "sfx_sources")
OUT = os.path.join(ROOT, "client", "assets", "sfx")
SR = 44100

OGA = "oga/"
CZ = OGA + "gunshot-sounds/sounds/cz.wav"
SKS = OGA + "gunshot-sounds/sounds/sks.wav"
MOSIN = OGA + "gunshot-sounds/sounds/mosin.wav"
SHOTTY = OGA + "gunshot-sounds/sounds/shotty.wav"
ZOMBIE = OGA + "zombies-sound-pack/zombies/zombie-%d.wav"
RAIN = OGA + "rain-ambient-not-loopable-2-versions-available/Ove_Melaa_-_Rainy__28NOT_loopable_29_Long_Version.ogg"
RELOAD = OGA + "gun-reload-sounds/assaultriflereload1_0.wav"
K_IMPACT = "kenney_impact-sounds/"
K_UI = "kenney_interface-sounds/"
K_RPG = "kenney_rpg-audio/"
K_SCI = "kenney_sci-fi-sounds/"


def L(src, start=0.0, length=None, pitch=1.0, af="", gain_db=0.0, at=0.0, onset=False):
    """One layer: `at` places it on the sound's timeline (seconds)."""
    return dict(src=src, start=start, length=length, pitch=pitch, af=af, gain_db=gain_db, at=at, onset=onset)


# name -> recipe. length: final length in seconds; fade: fade-out length;
# peak: target peak in dBFS. Short gun tails keep fast weapons from stacking.
SOUNDS = {
    # ---- firearms (Tabasco's field recordings, 48 kHz, no clipping)
    "pistol_shot": dict(layers=[L(CZ, 0.20, 0.6, onset=True, af="highpass=f=70")], length=0.55, fade=0.35, peak=-1.0),
    "smg_shot": dict(layers=[L(CZ, 2.78, 0.3, pitch=1.10, onset=True, af="highpass=f=90")], length=0.24, fade=0.18, peak=-1.5),
    "rifle_shot": dict(layers=[L(SKS, 0.27, 0.5, onset=True, af="highpass=f=60")], length=0.36, fade=0.26, peak=-1.0),
    "lmg_shot": dict(layers=[L(SKS, 2.17, 0.5, pitch=0.90, onset=True, af="highpass=f=50,bass=g=3:f=110")], length=0.32, fade=0.22, peak=-1.0),
    "sniper_shot": dict(layers=[L(MOSIN, 0.40, 1.6, onset=True, af="highpass=f=40")], length=1.3, fade=0.9, peak=-1.0),
    "shotgun_shot": dict(layers=[L(SHOTTY, 0.0, 0.7, pitch=0.95, onset=True, af="highpass=f=45,bass=g=2:f=100")], length=0.68, fade=0.45, peak=-1.0),
    # energy weapons: Kenney's sci-fi set, darkened
    "arc_shot": dict(layers=[L(K_SCI + "laserLarge_000.ogg", 0, 0.5, pitch=0.80, af="lowpass=f=5000"),
                             L(CZ, 0.20, 0.3, onset=True, gain_db=-10, af="lowpass=f=1500")], length=0.42, fade=0.25, peak=-2.0),
    "gale_shot": dict(layers=[L(K_SCI + "forceField_000.ogg", 0, 0.9, pitch=0.75, af="lowpass=f=3500"),
                              L(SHOTTY, 0.0, 0.5, onset=True, gain_db=-8, af="lowpass=f=900")], length=0.85, fade=0.5, peak=-2.0),
    # ---- handling
    "reload": dict(layers=[L(RELOAD, 0, 1.56, af="highpass=f=120")], length=1.5, fade=0.15, peak=-3.0),
    "dry_fire": dict(layers=[L(K_RPG + "metalClick.ogg", 0, 0.16, onset=True, af="highpass=f=300")], length=0.14, fade=0.08, peak=-3.0),
    "switch": dict(layers=[L(K_RPG + "beltHandle1.ogg", 0, 0.32, onset=True), L(K_RPG + "metalLatch.ogg", 0, 0.2, gain_db=-8, at=0.12, onset=True)],
                   length=0.36, fade=0.12, peak=-3.0),
    # ---- zombies (artisticdude's zombie pack)
    "zombie_groan1": dict(layers=[L(ZOMBIE % 16, 0, None, pitch=0.94)], fade=0.12, peak=-2.0),
    "zombie_groan2": dict(layers=[L(ZOMBIE % 18, 0, None, pitch=0.94)], fade=0.12, peak=-2.0),
    "zombie_groan3": dict(layers=[L(ZOMBIE % 20, 0, None, pitch=0.92)], fade=0.12, peak=-2.0),
    "zombie_groan4": dict(layers=[L(ZOMBIE % 17, 0, None, pitch=0.96)], fade=0.15, peak=-2.0),
    "zombie_attack": dict(layers=[L(ZOMBIE % 10, 0, None, pitch=0.95)], fade=0.10, peak=-1.0),
    "zombie_death": dict(layers=[L(ZOMBIE % 21, 0, None, pitch=0.88), L(K_IMPACT + "impactSoft_heavy_000.ogg", 0, 0.4, gain_db=-6, at=0.55)],
                         fade=0.25, peak=-1.5),
    "zombie_hit": dict(layers=[L(K_IMPACT + "impactPunch_medium_000.ogg", 0, 0.25, pitch=0.85, onset=True, af="lowpass=f=4000")],
                       length=0.2, fade=0.12, peak=-2.0),
    "headshot": dict(layers=[L(K_IMPACT + "impactPunch_heavy_001.ogg", 0, 0.4, pitch=0.80, onset=True, af="lowpass=f=5000"),
                             L(K_IMPACT + "impactPlank_medium_002.ogg", 0, 0.2, gain_db=-9, onset=True)], length=0.32, fade=0.2, peak=-1.5),
    "player_hurt": dict(layers=[L(K_IMPACT + "impactPunch_heavy_002.ogg", 0, 0.45, pitch=0.85, onset=True, af="lowpass=f=2500"),
                                L(K_IMPACT + "impactSoft_heavy_001.ogg", 0, 0.4, gain_db=-4, onset=True)], length=0.4, fade=0.25, peak=-1.5),
    # the heartbeat: two soft body thumps (lub-dub), low-passed
    "heartbeat": dict(layers=[L(K_IMPACT + "impactSoft_heavy_000.ogg", 0, 0.3, pitch=0.6, onset=True, af="lowpass=f=160,lowpass=f=160"),
                              L(K_IMPACT + "impactSoft_heavy_002.ogg", 0, 0.3, pitch=0.6, onset=True, gain_db=-5, at=0.26, af="lowpass=f=140,lowpass=f=140")],
                      length=0.62, fade=0.2, peak=-1.0),
    # ---- footsteps: Kenney concrete steps, softened (they play quietly every half second)
    "step1": dict(layers=[L(K_IMPACT + "footstep_concrete_000.ogg", 0, None, onset=True, af="lowpass=f=3200,highpass=f=90")], fade=0.06, peak=-3.0),
    "step2": dict(layers=[L(K_IMPACT + "footstep_concrete_001.ogg", 0, None, onset=True, af="lowpass=f=3200,highpass=f=90")], fade=0.06, peak=-3.0),
    "step3": dict(layers=[L(K_IMPACT + "footstep_concrete_002.ogg", 0, None, onset=True, af="lowpass=f=3200,highpass=f=90")], fade=0.06, peak=-3.0),
    "step4": dict(layers=[L(K_IMPACT + "footstep_concrete_003.ogg", 0, None, onset=True, af="lowpass=f=3200,highpass=f=90")], fade=0.06, peak=-3.0),
    # ---- feedback
    "hit_tick": dict(layers=[L(K_UI + "tick_002.ogg", 0, None, onset=True, af="lowpass=f=6000")], fade=0.02, peak=-4.0),
    "buy": dict(layers=[L(K_RPG + "handleCoins.ogg", 0, None, onset=True)], fade=0.15, peak=-3.0),
    "deny": dict(layers=[L(K_UI + "error_004.ogg", 0, None, pitch=0.8, onset=True, af="lowpass=f=3000")], fade=0.08, peak=-4.0),
    "powerup": dict(layers=[L(K_UI + "maximize_006.ogg", 0, None, pitch=0.8),
                            L(K_IMPACT + "impactBell_heavy_002.ogg", 0, 1.0, pitch=1.2, gain_db=-12)], length=1.0, fade=0.5, peak=-3.0),
    "ui_click": dict(layers=[L(K_UI + "click_002.ogg", 0, None, onset=True, af="lowpass=f=5000")], fade=0.02, peak=-4.0),
    # ---- the supply box (a creaking chest, rattling contents, a bell when the weapon is offered)
    "box_open": dict(layers=[L(K_RPG + "creak1.ogg", 0, None, pitch=0.85, onset=True), L(K_RPG + "doorOpen_1.ogg", 0, None, gain_db=-8, pitch=0.8)],
                     length=0.9, fade=0.3, peak=-3.0),
    "box_roll": dict(layers=[L(K_RPG + "handleCoins2.ogg", 0, None, pitch=0.85), L(K_RPG + "handleSmallLeather.ogg", 0, None, at=0.45, gain_db=-4),
                             L(K_RPG + "handleCoins.ogg", 0, None, at=0.8, pitch=0.75, gain_db=-3)], length=1.6, fade=0.4, peak=-3.0),
    "box_offer": dict(layers=[L(K_IMPACT + "impactBell_heavy_003.ogg", 0, 1.4, pitch=0.9)], length=1.3, fade=0.8, peak=-3.0),
    # ---- waves: a deep bell toll to start, a lighter one to end
    "wave_start": dict(layers=[L(K_IMPACT + "impactBell_heavy_001.ogg", 0, None, pitch=0.55, af="lowpass=f=2500"),
                               L(K_IMPACT + "impactBell_heavy_004.ogg", 0, None, pitch=0.42, gain_db=-6, at=0.02, af="lowpass=f=1800")],
                       length=2.6, fade=1.4, peak=-1.5),
    "wave_end": dict(layers=[L(K_IMPACT + "impactBell_heavy_000.ogg", 0, None, pitch=0.8, af="lowpass=f=4000")], length=1.6, fade=0.9, peak=-2.0),
    # ---- distant thunder: a low rumble, long and soft (it plays rarely now)
    "thunder": dict(layers=[L(K_SCI + "lowFrequency_explosion_000.ogg", 0, None, pitch=0.55, af="lowpass=f=300,lowpass=f=300"),
                            L(K_SCI + "lowFrequency_explosion_001.ogg", 0, None, pitch=0.48, at=0.35, gain_db=-5, af="lowpass=f=220,lowpass=f=220")],
                    length=4.2, fade=2.4, peak=-2.0, fade_in=0.25),
}

# looping beds: (source, start, length, crossfade, filters, extra layers)
LOOPS = {
    # rain on stone, levelled (the recording swells every 40 s) and darkened
    "music_ambient": dict(src=RAIN, start=46.0, length=28.0, xfade=3.0,
                          af="dynaudnorm=f=500:g=31:p=0.5,highpass=f=60,lowpass=f=7000", peak=-6.0),
    # the same rain with a low engine-like drone under it while a wave is on
    "music_tension": dict(src=RAIN, start=126.0, length=24.0, xfade=3.0,
                          af="dynaudnorm=f=500:g=31:p=0.5,highpass=f=60,lowpass=f=6000", peak=-5.0,
                          drone=(K_SCI + "spaceEngineLow_000.ogg", 0.5, "lowpass=f=180,lowpass=f=180", -9.0)),
}


def load(rel, pitch=1.0, af=""):
    path = os.path.join(SRC, rel)
    filters = []
    if pitch != 1.0:
        # tape-style pitch (duration changes with it), done at a high rate
        filters.append("aresample=%d,asetrate=%d,aresample=%d" % (SR, int(SR * pitch), SR))
    if af:
        filters.append(af)
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR)]
    if filters:
        cmd += ["-af", ",".join(filters)]
    cmd += ["-f", "f32le", "-"]
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    x = np.frombuffer(raw, np.float32).astype(np.float64)
    if x.size == 0:
        raise SystemExit("empty decode: " + rel)
    return x


def first_onset(x, start):
    """Index of the first sample after `start` that reaches -24 dB of the
    loudest point after it, backed off 4 ms so the attack is kept whole."""
    seg = x[start:]
    pk = np.abs(seg).max()
    hit = np.nonzero(np.abs(seg) >= pk * 0.063)[0]
    i = start + (int(hit[0]) if hit.size else 0)
    return max(start, i - int(0.004 * SR))


def layer(spec):
    x = load(spec["src"], spec["pitch"], spec["af"])
    s = int(spec["start"] * SR / spec["pitch"]) if spec["pitch"] != 1.0 else int(spec["start"] * SR)
    if spec["onset"]:
        s = first_onset(x, s)
    e = len(x) if spec["length"] is None else min(len(x), s + int(spec["length"] * SR))
    return x[s:e] * 10 ** (spec["gain_db"] / 20.0)


def build(name, r):
    parts = []
    for spec in r["layers"]:
        parts.append((int(spec["at"] * SR), layer(spec)))
    n = max(off + len(p) for off, p in parts)
    if r.get("length"):
        n = min(n, int(r["length"] * SR))
    y = np.zeros(n)
    for off, p in parts:
        m = min(len(p), n - off)
        if m > 0:
            y[off:off + m] += p[:m]
    y -= np.mean(y)  # no DC offset (it pops at the start and end)
    # short fade-in (2 ms) so no sound starts mid-waveform
    fi = max(int(r.get("fade_in", 0.002) * SR), 1)
    y[:fi] *= np.linspace(0.0, 1.0, fi) ** 2
    # fade-out: an exponential-ish curve that is silent at the last sample
    fo = min(n, int(r["fade"] * SR))
    if fo > 1:
        t = np.linspace(0.0, 1.0, fo)
        y[n - fo:] *= (1.0 - t) ** 3
    return normalize(y, r["peak"])


def build_loop(name, r):
    x = load(r["src"], 1.0, r["af"])
    x = level(x, 2.0)  # the recording swells and fades every 40 s; a loop must not
    s = int(r["start"] * SR)
    n = int(r["length"] * SR)
    xf = int(r["xfade"] * SR)
    seg = x[s:s + n + xf]
    if len(seg) < n + xf:
        raise SystemExit("%s: source too short" % name)
    # equal-power crossfade of the extra tail into the head: sample n wraps to 0
    t = np.linspace(0.0, 1.0, xf)
    head = seg[:xf] * np.sin(t * np.pi / 2) + seg[n:n + xf] * np.cos(t * np.pi / 2)
    y = np.concatenate([head, seg[xf:n]])
    if r.get("drone"):
        src, pitch, af, gain = r["drone"]
        d = load(src, pitch, af)
        # tile the drone with short crossfades to the loop's length, wrap included
        dx = int(0.4 * SR)
        tiled = np.zeros(n + dx)
        pos = 0
        w = np.linspace(0.0, 1.0, dx)
        while pos < n + dx:
            piece = d[: min(len(d), n + dx - pos)].copy()
            if pos > 0:
                piece[:dx] *= np.sin(w[: len(piece[:dx])] * np.pi / 2)
            m = len(piece)
            if pos + m < n + dx and m > dx:
                piece[-dx:] *= np.cos(w * np.pi / 2)
            tiled[pos:pos + m] += piece
            pos += max(m - dx, 1)
        wrap = tiled[:dx] * np.sin(w * np.pi / 2) + tiled[n:n + dx] * np.cos(w * np.pi / 2)
        drone = np.concatenate([wrap, tiled[dx:n]])
        drone *= (np.abs(y).max() / max(np.abs(drone).max(), 1e-9)) * 10 ** (gain / 20.0)
        y = y + drone
    y -= np.mean(y)
    return normalize(y, r["peak"])


def level(x, window):
    """Slow gain riding: divides out the loudness measured over `window`
    seconds, so the bed stays at one level all through the loop."""
    w = int(window * SR)
    c = np.concatenate([[0.0], np.cumsum(x * x)])
    i = np.arange(len(x))
    lo = np.clip(i - w // 2, 0, len(x))
    hi = np.clip(i + w // 2, 0, len(x))
    env = np.sqrt((c[hi] - c[lo]) / np.maximum(hi - lo, 1))
    g = np.median(env) / np.maximum(env, 1e-6)
    return x * np.clip(g, 0.25, 4.0)


def normalize(y, peak_db):
    pk = np.abs(y).max()
    if pk > 0:
        y = y * (10 ** (peak_db / 20.0) / pk)
    return y


def write(name, y):
    rng = np.random.default_rng(zlib.crc32(name.encode()))  # same file every run
    dither = (rng.random(len(y)) - rng.random(len(y))) / 32768.0  # TPDF, 1 LSB
    pcm = np.clip(np.round((y + dither) * 32767.0), -32768, 32767).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("[sfx] %-15s %5.2f s  %4d KB" % (name, len(y) / SR, os.path.getsize(path) // 1024))


def main():
    want = set(sys.argv[1:])
    for name, r in SOUNDS.items():
        if not want or name in want:
            write(name, build(name, r))
    for name, r in LOOPS.items():
        if not want or name in want:
            write(name, build_loop(name, r))


if __name__ == "__main__":
    main()
