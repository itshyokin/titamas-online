"""Creature sounds for Beast enemies (bats, the dragon boss):
    python3 tools/audio/make_beast_sounds.py
Writes assets/audio/creatures/dragon_roar.ogg, wing_flap.ogg, fire_breath.ogg, bat_screech.ogg,
dragon_land.ogg."""
import numpy as np, subprocess, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "creatures")
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def bandnoise(n, lo, hi):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec *= (f > lo) & (f < hi)
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-9)


def env(n, a, d):
    e = np.ones(n)
    ia, idd = int(SR * a), int(SR * d)
    e[:ia] = np.linspace(0, 1, ia)
    e[n - idd:] = np.linspace(1, 0, idd) ** 2
    return e


def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.stack([x, x], 1) * 32767).astype(np.int16).tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name)], input=pcm, check=True)


# Roar: a growling low voice (pulsed harmonics sweeping up then down) under breathy noise.
tt = t(2.6)
f0 = 70 + 40 * np.sin(np.pi * tt / 2.6) + 6 * np.sin(2 * np.pi * 9 * tt)
ph = 2 * np.pi * np.cumsum(f0) / SR
voice = sum(np.sin(ph * k) / k ** 0.7 for k in range(1, 14))
growl = 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 28 * tt))
breath = bandnoise(len(tt), 200, 2500) * 0.35
save("dragon_roar.ogg", (voice * growl * 0.25 + breath) * env(len(tt), 0.25, 1.0))

# Wing flap: a heavy whump of low noise.
tt = t(0.6)
x = bandnoise(len(tt), 40, 500) * np.exp(-tt * 7) * (1 - np.exp(-tt * 60))
save("wing_flap.ogg", x)

# Fire breath: rushing roar with crackles.
tt = t(2.2)
x = bandnoise(len(tt), 80, 3000) * (0.7 + 0.3 * np.sin(2 * np.pi * 3 * tt))
crackle = (rng.random(len(tt)) > 0.9993) * rng.standard_normal(len(tt)) * 8
crackle = np.convolve(crackle, np.exp(-np.arange(200) / 30), "same")
save("fire_breath.ogg", (x + crackle * 0.5) * env(len(tt), 0.15, 0.5))

# Bat screech: quick high chirps.
tt = t(0.5)
x = np.zeros(len(tt))
for s in (0.0, 0.12, 0.26):
    i = int(s * SR)
    n = int(0.08 * SR)
    k = np.arange(n) / SR
    x[i:i + n] += np.sin(2 * np.pi * (5200 - 18000 * k) * k) * np.exp(-k * 30)
save("bat_screech.ogg", x)

# Landing thud.
tt = t(1.0)
x = bandnoise(len(tt), 20, 220) * np.exp(-tt * 4) + bandnoise(len(tt), 200, 1500) * np.exp(-tt * 12) * 0.3
save("dragon_land.ogg", x)
print("done")
