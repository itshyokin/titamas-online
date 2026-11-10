"""Creature sounds for Beast enemies (bats, the dragon boss):
    python3 tools/audio/make_beast_sounds.py
Writes assets/audio/creatures/dragon_roar.ogg, wing_flap.ogg, fire_breath.ogg, bat_screech.ogg,
dragon_land.ogg, and for the troll troll_roar.ogg, troll_grunt.ogg, rock_whoosh.ogg,
rock_impact.ogg, ground_smash.ogg."""
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
# --- Troll (added after the rest, so the files above come out the same as before) ---

# Roar: deeper and rougher than the dragon's, a gravelly bellow.
tt = t(2.4)
f0 = 48 + 22 * np.sin(np.pi * tt / 2.4) + 4 * np.sin(2 * np.pi * 6 * tt)
ph = 2 * np.pi * np.cumsum(f0) / SR
voice = sum(np.sin(ph * k) / k ** 0.6 for k in range(1, 18))
gravel = 0.55 + 0.45 * (rng.random(len(tt)) > 0.5)
gravel = np.convolve(gravel, np.ones(220) / 220, "same")
breath = bandnoise(len(tt), 120, 1800) * 0.4
save("troll_roar.ogg", (voice * gravel * 0.3 + breath) * env(len(tt), 0.2, 0.9))

# Grunt: a short heave of effort.
tt = t(0.55)
f0 = 75 - 25 * tt / 0.55
ph = 2 * np.pi * np.cumsum(f0) / SR
voice = sum(np.sin(ph * k) / k for k in range(1, 10))
save("troll_grunt.ogg", (voice * 0.4 + bandnoise(len(tt), 150, 1200) * 0.3) * env(len(tt), 0.03, 0.3))

# Whoosh: a rock flung through the air.
tt = t(0.7)
sweep = np.sin(np.pi * tt / 0.7) ** 2
save("rock_whoosh.ogg", bandnoise(len(tt), 150, 1400) * sweep)

# Impact: a heavy crunch with gravel rattling after.
tt = t(1.1)
thud = bandnoise(len(tt), 25, 260) * np.exp(-tt * 7)
crack = bandnoise(len(tt), 800, 5000) * np.exp(-tt * 30) * 0.6
rattle = np.zeros(len(tt))
for i in range(40):
    at = int(rng.uniform(0.05, 0.8) * SR)
    n = int(0.02 * SR)
    rattle[at:at + n] += bandnoise(n, 1500, 6000) * np.exp(-np.arange(n) / (n / 4)) * rng.uniform(0.1, 0.35)
save("rock_impact.ogg", thud + crack + rattle)

# Ground smash: a deep boom, a crack of breaking ground and a long rumble.
tt = t(2.2)
boom = np.sin(2 * np.pi * (55 - 20 * tt) * tt) * np.exp(-tt * 3.0)
low = bandnoise(len(tt), 20, 180) * np.exp(-tt * 1.6)
crack = bandnoise(len(tt), 600, 4500) * np.exp(-tt * 18) * 0.7
save("ground_smash.ogg", boom * 1.2 + low + crack)
print("done")
