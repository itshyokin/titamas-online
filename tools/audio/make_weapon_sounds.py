"""Weapon swap sounds (drawing a weapon): one per weapon family.
    python3 tools/audio/make_weapon_sounds.py
Writes assets/audio/weapons/swap_<family>.ogg. Replace any of them with a real recording
of the same name (or point a weapon type at another file in data/weapon_types.json)."""
import numpy as np, subprocess, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "weapons")
rng = np.random.default_rng(11)

def t(sec): return np.arange(int(SR * sec)) / SR

def env(n, attack, decay):
    x = np.arange(n) / SR
    return np.minimum(x / max(attack, 1e-4), 1.0) * np.exp(-x / decay)

def bandnoise(n, lo, hi):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec *= (f > lo) & (f < hi)
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-9)

def ring(n, freqs, decay):
    x = t(n / SR)
    return sum(np.sin(2 * np.pi * f * x + rng.random() * 6) * a for f, a in freqs) * np.exp(-x / decay)

def at(total, sound, start):
    out = np.zeros(total)
    i = int(start * SR)
    out[i:i + len(sound)] += sound[:max(total - i, 0)]
    return out

def click(sec, freq_lo, freq_hi, decay=0.008):
    n = int(SR * sec)
    return bandnoise(n, freq_lo, freq_hi) * env(n, 0.0005, decay)

def shing(sec, freqs, sweep_lo, sweep_hi, decay):
    n = int(SR * sec)
    x = t(sec)
    # Blade on scabbard: a noise band sliding up, then the blade rings.
    slide = bandnoise(n, sweep_lo, sweep_hi) * np.clip(1 - x / (sec * 0.45), 0, 1) * np.minimum(x / 0.04, 1)
    return slide * 0.5 + ring(n, freqs, decay) * np.clip((x - sec * 0.25) / 0.02, 0, 1)

def save(name, x):
    x = x / np.max(np.abs(x)) * 10 ** (-3 / 20)
    fade = int(SR * 0.02)
    x[-fade:] *= np.linspace(1, 0, fade)
    raw = (x * 32767).astype(np.int16).tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name + ".ogg")], input=raw, check=True)
    print("wrote", name)

os.makedirs(OUT, exist_ok=True)
N = lambda s: int(SR * s)
save("swap_dagger", shing(0.4, [(4700, 1), (6900, 0.6), (9100, 0.3)], 3000, 9000, 0.09))
save("swap_sword", shing(0.7, [(2600, 1), (3900, 0.7), (5400, 0.4), (7600, 0.2)], 1500, 7000, 0.18))
heavy = np.zeros(N(0.8))
heavy += at(N(0.8), bandnoise(N(0.35), 300, 2500) * env(N(0.35), 0.03, 0.12) * 0.6, 0.0)  # scrape
heavy += at(N(0.8), np.sin(2 * np.pi * 70 * t(0.5)) * env(N(0.5), 0.002, 0.12) * 1.6, 0.28)  # thud
heavy += at(N(0.8), ring(N(0.5), [(820, 1), (1230, 0.6), (1870, 0.35)], 0.12) * 0.7, 0.28)  # clank
save("swap_heavy", heavy)
bow = np.zeros(N(0.6))
creak = bandnoise(N(0.3), 180, 900) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 38 * t(0.3)))) * env(N(0.3), 0.05, 0.12)
bow += at(N(0.6), creak * 0.7, 0.0)
bow += at(N(0.6), np.sin(2 * np.pi * 196 * t(0.3)) * np.sin(2 * np.pi * 3 * t(0.3) + 1) * env(N(0.3), 0.002, 0.08), 0.22)  # string
save("swap_bow", bow)
xbow = np.zeros(N(0.6))
for i, s in enumerate(np.arange(0.0, 0.22, 0.045)):  # ratchet
    xbow += at(N(0.6), click(0.02, 1500, 5000, 0.004) * 0.5, s)
xbow += at(N(0.6), click(0.06, 600, 3500, 0.02) * 1.2 + ring(N(0.06), [(1400, 0.4)], 0.02), 0.32)  # latch
save("swap_crossbow", xbow)
pistol = np.zeros(N(0.4))
pistol += at(N(0.4), click(0.03, 2500, 7000, 0.006), 0.0)  # half cock
pistol += at(N(0.4), click(0.05, 1800, 6000, 0.012) * 1.3 + ring(N(0.05), [(3100, 0.3)], 0.015), 0.16)  # full cock
save("swap_pistol", pistol)
rifle = np.zeros(N(0.75))
rifle += at(N(0.75), click(0.05, 1200, 5000, 0.01), 0.0)
rifle += at(N(0.75), bandnoise(N(0.18), 800, 4000) * env(N(0.18), 0.01, 0.06) * 0.5, 0.1)  # slide
rifle += at(N(0.75), click(0.08, 900, 4500, 0.02) * 1.3 + ring(N(0.08), [(1700, 0.35), (2600, 0.2)], 0.03), 0.34)
save("swap_rifle", rifle)

# Firing sounds.
def bang(sec, body_hz, tail):
    n = N(sec)
    x = bandnoise(n, 150, 9000) * env(n, 0.0008, tail * 0.4)
    x += bandnoise(n, 60, 600) * env(n, 0.002, tail) * 1.2
    x += np.sin(2 * np.pi * body_hz * t(sec)) * env(n, 0.001, 0.06) * 1.5
    return x
pan = bandnoise(N(0.12), 2000, 9000) * env(N(0.12), 0.01, 0.05) * 0.4  # flintlock pan flash
save("pistol_shot", at(N(0.9), pan, 0.0) + at(N(0.9), bang(0.8, 90, 0.25), 0.07))
save("rifle_shot", at(N(1.3), pan, 0.0) + at(N(1.3), bang(1.2, 70, 0.45) * 1.2, 0.07))
xf = np.zeros(N(0.5))
xf += at(N(0.5), click(0.03, 800, 5000, 0.01) * 1.2, 0.0)
xf += at(N(0.5), np.sin(2 * np.pi * 140 * t(0.4)) * np.sin(2 * np.pi * 9 * t(0.4)) * env(N(0.4), 0.001, 0.1), 0.0)
xf += at(N(0.5), bandnoise(N(0.15), 400, 3000) * env(N(0.15), 0.002, 0.05) * 0.7, 0.01)
save("crossbow_fire", xf)
reload = np.zeros(N(0.7))
for s in [0.0, 0.25, 0.45]:
    reload += at(N(0.7), click(0.04, 1000, 5000, 0.01), s)
save("gun_reload", reload)
