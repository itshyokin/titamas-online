# Makes several variants of each footstep so repeats don't sound identical.
#   python3 tools/audio/footstep_variants.py <source_dir> <out_dir>
# source_dir holds one recording per surface (<surface>.ogg). Variants change pitch,
# tone and texture slightly. "grass" is synthesised (soft thump + rustling blades);
# "dirt" is made from the grass recording (it sounds like packed earth).
import sys, subprocess, numpy as np
SR = 44100
src, out = sys.argv[1], sys.argv[2]
rng = np.random.default_rng(42)
COUNT = 6


def load(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.int16) / 32768.0


def save(path, x):
    w = int(0.05 * SR)
    rms = max(np.sqrt(np.mean(x[i:i + w] ** 2)) for i in range(0, max(len(x) - w, 1), w // 4))
    x = x * 10 ** (-16 / 20) / max(rms, 1e-6)
    x = np.clip(x, -0.98, 0.98)
    fade = min(int(0.01 * SR), len(x) // 4)
    x[-fade:] *= np.linspace(1, 0, fade)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", path], input=(x * 32767).astype(np.int16).tobytes(), check=True)


def one_pole(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def resample(x, factor):
    # factor > 1 = higher pitch (shorter).
    n = int(len(x) / factor)
    return np.interp(np.arange(n) * factor, np.arange(len(x)), x)


def envelope(x, ms=8):
    w = max(int(SR * ms / 1000), 1)
    return np.convolve(np.abs(x), np.ones(w) / w, mode="same")


def band_noise(n, lo, hi):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec *= (f > lo) & (f < hi)
    y = np.fft.irfft(spec, n)
    return y / (np.std(y) + 1e-9)


def variants(x, name):
    pitches = [0.9, 0.95, 1.0, 1.04, 1.09, 0.97]
    for k in range(COUNT):
        y = resample(x, pitches[k] * rng.uniform(0.98, 1.02))
        lp = one_pole(y, rng.uniform(0.25, 0.6))
        hp = y - one_pole(y, 0.05)
        tone = rng.uniform(-0.35, 0.35)
        y = y + (lp - y) * max(-tone, 0) + hp * max(tone, 0) * 0.8
        # A little fresh grit following the step's own envelope.
        grit = band_noise(len(y), 1500, 7000) * envelope(y) * rng.uniform(0.15, 0.35)
        y = y + grit
        save(f"{out}/{name}_{k + 1}.ogg", y)


def grass(k):
    n = int(SR * rng.uniform(0.28, 0.36))
    t = np.arange(n) / SR
    thump = band_noise(n, 50, 260) * np.exp(-t / 0.035) * 0.6
    rustle = np.zeros(n)
    for _ in range(int(rng.uniform(70, 110))):
        start = abs(rng.normal(0.03, 0.06))
        if rng.random() < 0.35:
            start = 0.09 + abs(rng.normal(0.02, 0.04))  # toe roll
        i = int(start * SR)
        m = int(rng.uniform(0.002, 0.007) * SR)
        if i + m >= n:
            continue
        g = band_noise(m * 4, rng.uniform(1500, 3000), rng.uniform(5000, 9000))[:m]
        rustle[i:i + m] += g * np.hanning(m) * rng.uniform(0.2, 1.0) * np.exp(-start / 0.12)
    y = thump + rustle * 0.9
    y[: int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))
    save(f"{out}/grass_{k + 1}.ogg", y)


for surface in ["stone", "wood", "water", "snow", "metal"]:
    variants(load(f"{src}/{surface}.ogg"), surface)
variants(load(f"{src}/grass.ogg"), "dirt")
for k in range(COUNT):
    grass(k)
