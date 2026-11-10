"""Weather sounds (generated, no samples): light and heavy rain loops, thunder and winter wind loops.
    python3 tools/audio/make_weather_sounds.py
Writes assets/audio/weather/*.ogg (numpy + ffmpeg)."""
import pathlib, subprocess
import numpy as np

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parents[2] / "assets" / "audio" / "weather"
rng = np.random.default_rng(7)


def onepole(x, cutoff):
    k = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    out = np.empty_like(x)
    y = 0.0
    blk = 2048
    for s in range(0, len(x), blk):
        seg = x[s:s + blk]
        m = len(seg)
        conv = np.convolve(seg * k, (1 - k) ** np.arange(m))[:m]
        out[s:s + m] = (1 - k) ** np.arange(1, m + 1) * y + conv
        y = out[s + m - 1]
    return out


def seamless(a, fade):
    n = int(fade * RATE)
    body = a[:-n].copy()
    k = np.linspace(0, 1, n)
    body[:n] = a[:n] * k + a[-n:] * (1 - k)
    return body


def write(name, l, r=None):
    OUT.mkdir(parents=True, exist_ok=True)
    r = l if r is None else r
    d = np.stack([l, r], 1)
    d = d / (np.max(np.abs(d)) or 1) * 0.9
    pcm = (d * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", str(OUT / name)], input=pcm, check=True)
    print("wrote", OUT / name)


def rain(secs, drops_per_sec, body):
    n = int(secs * RATE)
    chans = []
    for c in range(2):
        hiss = onepole(rng.standard_normal(n), 3800) - onepole(rng.standard_normal(n), 400) * 0.6
        hiss *= body
        drops = np.zeros(n)
        count = int(drops_per_sec * secs)
        at = rng.integers(0, n - 2000, count)
        for a in at:
            ln = rng.integers(200, 900)
            env = np.exp(-np.arange(ln) / (ln / 5)) * rng.uniform(0.05, 0.35)
            drops[a:a + ln] += env * rng.standard_normal(ln)
        drops = drops - onepole(drops, 900)
        # slow swell
        swell = 1 + 0.15 * np.sin(np.arange(n) / RATE * 2 * np.pi * rng.uniform(0.05, 0.1))
        chans.append(seamless((hiss + drops) * swell, 1.5))
    return chans


def snow_wind(secs, strength):
    """A soft, hollow winter wind that swells and fades (snow, blizzards)."""
    n = int(secs * RATE)
    chans = []
    for c in range(2):
        t = np.arange(n) / RATE
        noise = rng.standard_normal(n)
        low = onepole(noise, 500) - onepole(noise, 90)
        whistle = onepole(rng.standard_normal(n), 1500) - onepole(rng.standard_normal(n), 900)
        swell = 0.55 + 0.3 * np.sin(t * 2 * np.pi * rng.uniform(0.07, 0.11) + rng.uniform(0, 6)) \
            + 0.15 * np.sin(t * 2 * np.pi * rng.uniform(0.19, 0.27) + rng.uniform(0, 6))
        chans.append(seamless((low * 1.6 + whistle * 0.35 * strength) * swell, 3.0))
    return chans


def thunder(seed, secs=7.0):
    r = np.random.default_rng(seed)
    n = int(secs * RATE)
    t = np.arange(n) / RATE
    noise = r.standard_normal(n)
    low = onepole(onepole(noise, 160), 120)
    crack = onepole(noise, 2200) * np.exp(-t * 9) * 0.6
    env = np.zeros(n)
    for _ in range(5):  # rolling rumbles
        start = r.uniform(0.05, 2.5)
        env += np.exp(-np.maximum(t - start, 0) * r.uniform(0.6, 1.4)) * (t > start) * r.uniform(0.4, 1.0)
    out = low * env * 5 + crack
    out *= np.minimum(t / 0.02, 1)
    return out


l, r = rain(16.0, 260, 0.35)
write("rain_loop.ogg", l, r)
l, r = rain(16.0, 700, 0.7)
write("heavy_rain_loop.ogg", l, r)
for i, s in enumerate([3, 11]):
    a = thunder(s)
    write("thunder_%d.ogg" % (i + 1), a, onepole(a, 3000))
# Winter (added after the rest, so the files above come out the same as before).
write("snow_wind_loop.ogg", *snow_wind(24.0, 0.6))
write("blizzard_loop.ogg", *snow_wind(24.0, 1.6))
