"""Putting gear on: cloth rustle, leather creak, metal (chain/plate) clink, jewellery tinkle.
    python3 tools/audio/make_equip_sounds.py
Writes assets/audio/sfx/equip_<cloth|leather|metal|jewelry>.ogg (numpy + ffmpeg). Weapons
use their weapon type's swap sound. Items can point at any file (items.json equip_sound)."""
import numpy as np, subprocess, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")
rng = np.random.default_rng(7)


def bandnoise(n, lo, hi):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec *= (f > lo) & (f < hi)
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-9)


def env(n, attack, decay):
    x = np.arange(n) / SR
    return np.minimum(x / max(attack, 1e-4), 1.0) * np.exp(-x / decay)


def place(buf, s, at):
    i = int(at * SR)
    buf[i:i + len(s)] += s[:max(0, len(buf) - i)]


def ring(sec, freqs, decay):
    x = np.arange(int(SR * sec)) / SR
    return sum(a * np.sin(2 * np.pi * f * x + rng.random() * 6) for f, a in freqs) * np.exp(-x / decay)


def save(name, x):
    x = x / (np.max(np.abs(x)) or 1) * 10 ** (-4 / 20)
    fade = int(SR * 0.02)
    x[-fade:] *= np.linspace(1, 0, fade)
    raw = (x * 32767).astype(np.int16).tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name + ".ogg")], input=raw, check=True)
    print("wrote", name)


os.makedirs(OUT, exist_ok=True)

# Cloth: two soft swishes.
buf = np.zeros(int(SR * 0.55))
for at, d in [(0.0, 0.22), (0.2, 0.28)]:
    n = int(SR * d)
    sw = bandnoise(n, 900, 5000) * np.sin(np.linspace(0, np.pi, n)) ** 2
    place(buf, sw * 0.8, at)
save("equip_cloth", buf)

# Leather: a swish plus creaky stick-slip pulses and a strap tug.
buf = np.zeros(int(SR * 0.6))
n = int(SR * 0.25)
place(buf, bandnoise(n, 600, 3500) * np.sin(np.linspace(0, np.pi, n)) ** 2 * 0.6, 0.0)
for k in range(9):
    m = int(SR * 0.012)
    place(buf, bandnoise(m, 300, 1600) * env(m, 0.001, 0.004) * rng.uniform(0.6, 1.0), 0.18 + k * 0.022 + rng.uniform(0, 0.006))
m = int(SR * 0.05)
place(buf, bandnoise(m, 150, 900) * env(m, 0.002, 0.02) * 1.2, 0.45)
save("equip_leather", buf)

# Metal: chain jingle (many tiny rings) and a dull plate clunk.
buf = np.zeros(int(SR * 0.8))
for k in range(26):
    f = rng.uniform(3500, 7500)
    place(buf, ring(0.12, [(f, 1), (f * 1.52, 0.4)], 0.03) * rng.uniform(0.2, 0.6), rng.uniform(0.0, 0.45))
m = int(SR * 0.3)
place(buf, ring(0.3, [(420, 1), (690, 0.6), (1130, 0.3)], 0.06) * 1.3 + bandnoise(m, 200, 2000) * env(m, 0.001, 0.015), 0.1)
save("equip_metal", buf)

# Jewellery: a couple of bright tinks.
buf = np.zeros(int(SR * 0.6))
for at, f in [(0.0, 5200), (0.09, 6900), (0.16, 4400)]:
    place(buf, ring(0.4, [(f, 1), (f * 2.76, 0.3)], 0.08) * 0.7, at)
save("equip_jewelry", buf)
