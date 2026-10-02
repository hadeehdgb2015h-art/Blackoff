#!/usr/bin/env python3
"""Synthesises original placeholder sound effects (project-owned, CC0).
Output: client/assets/sfx/*.wav (mono, 16-bit, 22050 Hz). Deterministic."""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "client", "assets", "sfx")


def write(name, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    gain = 0.9 / peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))


def env(t, attack, decay):
    return (t / attack if t < attack else math.exp(-(t - attack) / decay))


def lowpass(x, a):
    y, out = 0.0, []
    for s in x:
        y += a * (s - y)
        out.append(y)
    return out


def gunshot(rng, dur, body_hz, decay, crack, lp):
    n = int(SR * dur)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    noise = lowpass(noise, lp)
    out = []
    for i in range(n):
        t = i / SR
        thump = math.sin(2 * math.pi * body_hz * t * (1 - t * 2)) * math.exp(-t / (decay * 0.6))
        c = rng.uniform(-1, 1) * math.exp(-t / 0.004) * crack
        out.append(noise[i] * env(t, 0.001, decay) + thump * 0.8 + c)
    return out


def click(rng, dur=0.05, hz=2400, decay=0.008):
    return [math.sin(2 * math.pi * hz * i / SR) * math.exp(-(i / SR) / decay) + rng.uniform(-0.2, 0.2) * math.exp(-(i / SR) / 0.004)
            for i in range(int(SR * dur))]


def concat(*parts, gap=0.0):
    out = []
    for p in parts:
        out += p + [0.0] * int(SR * gap)
    return out


def groan(rng, dur, f0, f1, rough):
    n = int(SR * dur)
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        f = f0 + (f1 - f0) * (t / dur) + math.sin(t * 7) * 6
        ph += 2 * math.pi * f / SR
        saw = (ph / math.pi) % 2 - 1
        s = saw * (0.6 + 0.4 * math.sin(t * 23)) + rng.uniform(-1, 1) * rough
        out.append(s * env(t, 0.08, dur * 0.5))
    return lowpass(out, 0.12)


def tone(dur, freqs, decay):
    return [sum(math.sin(2 * math.pi * f * i / SR) for f in freqs) * math.exp(-(i / SR) / decay) for i in range(int(SR * dur))]


def sweep(dur, f0, f1, amp_decay):
    out, ph = [], 0.0
    for i in range(int(SR * dur)):
        t = i / SR
        ph += 2 * math.pi * (f0 + (f1 - f0) * t / dur) / SR
        out.append(math.sin(ph) * (0.5 + 0.5 * math.sin(t * 6 * math.pi)) * math.exp(-t / amp_decay))
    return out


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    r = random.Random(11)
    write("pistol_shot", gunshot(r, 0.35, 140, 0.07, 0.8, 0.35))
    write("rifle_shot", gunshot(r, 0.3, 110, 0.06, 1.0, 0.5))
    write("dry_fire", click(r, 0.06, 1800, 0.01))
    write("reload", concat(click(r, 0.07, 900, 0.02), click(r, 0.06, 1400, 0.012), gap=0.25))
    write("switch", click(r, 0.08, 700, 0.03))
    write("zombie_groan1", groan(r, 1.1, 85, 70, 0.25))
    write("zombie_groan2", groan(r, 0.9, 110, 80, 0.35))
    write("zombie_attack", groan(r, 0.4, 150, 90, 0.6))
    write("zombie_hit", lowpass([r.uniform(-1, 1) * math.exp(-(i / SR) / 0.03) for i in range(int(SR * 0.12))], 0.25))
    write("zombie_death", groan(r, 0.8, 95, 45, 0.4))
    write("player_hurt", lowpass([(r.uniform(-1, 1) + math.sin(i / SR * 2 * math.pi * 90)) * math.exp(-(i / SR) / 0.08) for i in range(int(SR * 0.3))], 0.2))
    write("buy", concat(tone(0.09, [880, 1320], 0.05), tone(0.14, [1175, 1760], 0.08)))
    write("deny", tone(0.25, [196, 207], 0.12))
    write("wave_start", sweep(1.6, 300, 520, 0.9))
    write("wave_end", concat(tone(0.25, [523, 659], 0.15), tone(0.4, [784, 988], 0.25)))
    print("sfx written to", os.path.abspath(OUT))
