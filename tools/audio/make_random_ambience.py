"""One-shot ambience for Database → Regions → Random ambience: a distant train (horn and
rumble), cicadas buzzing, and a flock of birds flapping off.
    python3 tools/audio/make_random_ambience.py
Writes assets/audio/ambience/train_distant.ogg, cicadas.ogg, birds_flutter.ogg."""
import numpy as np, subprocess, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "ambience")
rng = np.random.default_rng(23)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def bandnoise(n, lo, hi):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec *= (f > lo) & (f < hi)
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-9)


def lowpass(x, cutoff):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec *= 1 / (1 + (f / cutoff) ** 4)
    return np.fft.irfft(spec, len(x))


def fade(x, a, b):
    n = len(x)
    e = np.ones(n)
    ia, ib = int(SR * a), int(SR * b)
    e[:ia] = np.linspace(0, 1, ia) ** 2
    e[n - ib:] = np.linspace(1, 0, ib) ** 2
    return x * e


def reverb(x, amount=0.4, size=1.0):
    out = x.copy()
    for d, g in [(0.05, 0.5), (0.083, 0.42), (0.13, 0.36), (0.21, 0.3), (0.34, 0.22), (0.55, 0.15)]:
        n = int(d * size * SR)
        out[n:] += x[:-n] * g * amount * 2
    return out


def save(name, l, r=None):
    r = l if r is None else r
    d = np.stack([l, r], 1)
    d = d / (np.max(np.abs(d)) or 1) * 0.8
    raw = (d * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name + ".ogg")], input=raw, check=True)
    print("wrote", name)


os.makedirs(OUT, exist_ok=True)

# Train: a far-off two-note horn over a slow rumble and wheel clatter, all muffled by distance.
x = t(14.0)
rumble = lowpass(bandnoise(len(x), 30, 400), 180) * 0.6
clack = np.zeros(len(x))
for k in np.arange(0.4, 13.5, 0.62):
    for off in (0.0, 0.11):
        i = int((k + off) * SR)
        n = int(0.05 * SR)
        if i + n < len(x):
            clack[i:i + n] += bandnoise(n, 300, 1800) * np.exp(-np.arange(n) / SR / 0.012)
clack = lowpass(clack, 900) * 0.35
horn = np.zeros(len(x))
for start, dur in [(2.5, 1.6), (4.4, 2.4)]:
    h = t(dur)
    env = np.minimum(h / 0.15, 1) * np.minimum((dur - h) / 0.4, 1)
    tone = sum(a * np.sin(2 * np.pi * f * h) for f, a in [(277, 1), (349, 0.8), (415, 0.5), (554, 0.3), (698, 0.15)])
    i = int(start * SR)
    horn[i:i + len(h)] += tone * env
horn = lowpass(horn, 1200) * 0.5
train = (rumble + clack) * np.sin(np.pi * np.clip(x / 14.0, 0, 1)) ** 0.7 + horn
train = reverb(fade(train, 1.5, 3.0), 0.6, 2.0)
save("train_distant", train, np.roll(train, 400))

# Cicadas: rapid buzzing pulses in waves, a few insects slightly out of step.
x = t(11.0)
cic = np.zeros(len(x))
for k in range(4):
    carrier = bandnoise(len(x), 4200 + k * 400, 6800 + k * 300)
    pulse = (np.sin(2 * np.pi * (220 + k * 17) * x) > 0.2).astype(float)
    swell = np.clip(np.sin(np.pi * (x / 11.0) * (1.0 + k * 0.15) + k) * 1.2, 0, 1) ** 1.5
    cic += carrier * pulse * swell * (0.6 + 0.2 * k)
cic = fade(cic, 1.2, 2.0)
save("cicadas", cic, np.roll(cic, 900))

# Birds taking off: a burst of wing flaps (soft noise thumps) and a few chirps fading away.
x = t(3.2)
fl = np.zeros(len(x))
for bird in range(7):
    t0 = rng.uniform(0.0, 0.5)
    rate = rng.uniform(11, 16)
    for k in range(int(rng.uniform(10, 18))):
        i = int((t0 + k / rate) * SR)
        n = int(0.045 * SR)
        if i + n < len(x):
            fl[i:i + n] += bandnoise(n, 250, 2600) * np.sin(np.linspace(0, np.pi, n)) * np.exp(-k * 0.12)
for c in range(5):
    i = int(rng.uniform(0.2, 1.6) * SR)
    h = t(rng.uniform(0.08, 0.16))
    f0 = rng.uniform(2800, 4200)
    ch = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.4 * np.sin(np.pi * h / h[-1]))) / SR) * np.sin(np.pi * h / h[-1])
    fl[i:i + len(ch)] += ch * 0.5
fl = reverb(fade(fl, 0.01, 1.0), 0.3)
save("birds_flutter", fl, np.roll(fl, 300))

# Peepers (spring frogs): a chorus of short high whistles, dozens overlapping, at dusk.
x = t(12.0)
pp = np.zeros(len(x))
for frog in range(26):
    f0 = rng.uniform(2300, 3400)
    rate = rng.uniform(0.9, 1.6)
    phase = rng.uniform(0, 3)
    loud = rng.uniform(0.25, 1.0)
    k = 0
    while True:
        start = phase + k / rate + rng.uniform(-0.05, 0.05)
        k += 1
        i = int(start * SR)
        if i >= len(x):
            break
        h = t(rng.uniform(0.11, 0.17))
        swell = np.clip(np.sin(np.pi * h / h[-1]), 0, None) ** 1.4
        peep = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.1 * h / h[-1])) / SR) * swell
        peep += 0.3 * np.sin(2 * np.pi * np.cumsum(2 * f0 * (1 + 0.1 * h / h[-1])) / SR) * swell
        n = min(len(peep), len(x) - i)
        pp[i:i + n] += peep[:n] * loud
pp = reverb(fade(pp, 2.0, 2.5), 0.3, 1.4)
save("peepers", pp, np.roll(pp, 1100))

# Owl: two or three soft hoots, each a breathy low whistle that dips.
x = t(5.0)
ow = np.zeros(len(x))
for start, loud in [(0.3, 1.0), (1.15, 0.9), (2.6, 0.75)]:
    h = t(0.55)
    f0 = 390 * (1 - 0.12 * (h / h[-1]) ** 2)
    swell = np.clip(np.sin(np.pi * (h / h[-1]) ** 0.7), 0, None) ** 1.6
    hoot = (np.sin(2 * np.pi * np.cumsum(f0) / SR) + 0.25 * np.sin(2 * np.pi * np.cumsum(2 * f0) / SR)) * swell
    hoot += bandnoise(len(h), 300, 1400) * swell * 0.12
    i = int(start * SR)
    ow[i:i + len(hoot)] += hoot * loud
ow = reverb(fade(lowpass(ow, 2600), 0.05, 1.5), 0.55, 2.2)
save("owl_hoot", ow, np.roll(ow, 1500))

# Rooster at dawn: the classic four-part crow, far off and echoing.
x = t(4.0)
rc = np.zeros(len(x))
for start, loud in [(0.25, 1.0), (2.1, 0.6)]:
    parts = [(0.0, 0.16, 620, 900), (0.17, 0.12, 980, 980), (0.3, 0.3, 880, 620), (0.62, 0.45, 700, 430)]
    for off, dur, fa, fb in parts:
        h = t(dur)
        k = h / h[-1]
        f0 = fa + (fb - fa) * k
        swell = np.minimum(k / 0.12, 1) * np.minimum((1 - k) / 0.25, 1)
        voice = sum(np.sin(2 * np.pi * np.cumsum(f0 * m) / SR) / (m ** 0.8) for m in range(1, 9))
        rasp = 0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 42 * h))
        i = int((start + off) * SR)
        n = min(len(h), len(x) - i)
        rc[i:i + n] += (voice * rasp * swell)[:n] * loud * 0.3
rc = reverb(fade(lowpass(rc, 3000), 0.02, 1.2), 0.5, 2.4)
save("rooster_crow", rc, np.roll(rc, 1300))
