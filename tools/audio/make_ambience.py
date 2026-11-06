# Procedural ambience/SFX for Titamas Online. Loops are filtered in the frequency domain
# over the loop length, so they wrap seamlessly.
import numpy as np, subprocess, sys
SR = 44100
rng = np.random.default_rng(7)
out = sys.argv[1]

def spectral_noise(n, shape):
    """Periodic noise of length n whose magnitude spectrum is shape(freqs)."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec *= shape(np.maximum(f, 1.0))
    x = np.fft.irfft(spec, n)
    return x / np.std(x)

def band(lo, hi, tilt=1.0):
    def s(f):
        return (1 / f ** (tilt / 2)) * (1 / (1 + (lo / f) ** 4)) * (1 / (1 + (f / hi) ** 4))
    return s

def smooth_env(n, points_per_sec, depth, seed):
    """Periodic slow random envelope in [1-depth, 1]."""
    r = np.random.default_rng(seed)
    k = max(int(n / SR * points_per_sec), 3)
    pts = r.random(k)
    # Periodic cubic-ish interpolation via FFT low-pass of a wrapped step sequence.
    idx = np.arange(n) * k / n
    i0 = np.floor(idx).astype(int) % k
    t = idx - np.floor(idx)
    t = t * t * (3 - 2 * t)
    v = pts[i0] * (1 - t) + pts[(i0 + 1) % k] * t
    return 1 - depth + depth * v

def periodic_lowpass_mix(a, b, w):
    return a * (1 - w) + b * w

def stereo(l, r):
    return np.stack([l, r], 1)

def save(name, x, peak_db=-3.0, loop=True):
    x = x / np.max(np.abs(x)) * 10 ** (peak_db / 20)
    if loop:
        # Tiny check: the wrap point shouldn't jump.
        jump = np.max(np.abs(x[0] - x[-1]))
        print(name, "len %.1fs" % (len(x) / SR), "wrap jump %.4f" % jump)
    raw = (x * 32767).astype(np.int16).tobytes()
    ch = 1 if x.ndim == 1 else x.shape[1]
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", str(ch), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", f"{out}/{name}.ogg"], input=raw, check=True)

def wind(seconds, lo, hi, gust_rate, gust_depth, whistle, seed):
    n = SR * seconds
    chans = []
    for c in range(2):
        low = spectral_noise(n, band(lo, hi * 0.5, 1.6))
        high = spectral_noise(n, band(hi * 0.4, hi * 1.6, 1.0))
        g = smooth_env(n, gust_rate, gust_depth, seed + c)
        # Gusts brighten the wind as well as making it louder.
        x = low * g + high * (g ** 3) * 0.45
        if whistle:
            w = spectral_noise(n, lambda f: np.exp(-((f - 720) / 30) ** 2) + 0.6 * np.exp(-((f - 1150) / 40) ** 2))
            x += w * (g ** 4) * whistle
        chans.append(x)
    return stereo(*chans)

# Gusty open-air wind (heights, exposed places).
save("wind_loop", wind(32, 60, 900, 0.35, 0.75, 0.10, 11))
# Soft breeze for calm countryside: quieter top end, gentle swells.
save("breeze_loop", wind(30, 80, 1500, 0.25, 0.5, 0.0, 21), peak_db=-6)

# Surf: waves rolling in and washing out over a 36 s loop.
def surf(seconds, seed):
    n = SR * seconds
    r = np.random.default_rng(seed)
    t = np.arange(n) / SR
    chans = []
    rumble = spectral_noise(n, band(30, 300, 2.0))
    env_c = np.zeros(n); env_w = np.zeros(n)
    if True:
        start = r.uniform(0, 2)
        while start < seconds:
            peak = start + r.uniform(1.8, 2.8)       # swell builds, then breaks
            dur = r.uniform(3.5, 6.0)                # foam washing up and draining
            amp = r.uniform(0.6, 1.0)
            for shift in (-seconds, 0, seconds):     # wrap around the loop
                tt = t - shift
                rise = np.clip((tt - start) / (peak - start), 0, 1) ** 2.5
                fall = np.exp(-np.clip(tt - peak, 0, None) / (dur * 0.35))
                env_c += amp * np.where(tt < peak, rise, fall) * (tt > start)
                drain = np.exp(-np.clip(tt - peak - 0.6, 0, None) / dur) * np.clip((tt - peak) / 0.6, 0, 1)
                env_w += amp * 0.5 * drain * (tt > peak)
            start = peak + r.uniform(2.5, 5.5)
    for c in range(2):
        crash = spectral_noise(n, band(250, 5000, 1.2))
        wash = spectral_noise(n, band(1200, 9000, 0.6))
        x = rumble * (0.12 + 0.5 * env_c) + crash * env_c * 0.9 + wash * env_w * 0.7
        chans.append(x)
    return stereo(*chans)
save("surf_loop", surf(36, 5), peak_db=-4)

# One-shots.
def burst(seconds, shape_fn, env_fn, seed):
    n = int(SR * seconds)
    global rng
    rng = np.random.default_rng(seed)
    x = spectral_noise(n * 2, shape_fn)[:n]
    t = np.arange(n) / SR
    return x * env_fn(t)

# Dodge/roll cloth whoosh: band sweeps upward then fades.
n = int(SR * 0.45); t = np.arange(n) / SR
lo = spectral_noise(n * 2, band(150, 900, 1.0))[:n]
hi = spectral_noise(n * 2, band(900, 4000, 1.0))[:n]
sweep = np.clip(t / 0.18, 0, 1)
env = np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 1.5
save("whoosh", (lo * (1 - sweep) + hi * sweep * 0.8) * env, peak_db=-6, loop=False)

# Splash into water: impact thump + spray + bubbly tail.
n = int(SR * 1.2); t = np.arange(n) / SR
thump = spectral_noise(n * 2, band(40, 250, 2.0))[:n] * np.exp(-t / 0.08)
spray = spectral_noise(n * 2, band(1500, 9000, 0.8))[:n] * np.exp(-t / 0.25) * np.clip(t / 0.02, 0, 1)
r2 = np.random.default_rng(3)
bub = np.zeros(n)
for _ in range(40):
    s = r2.uniform(0.03, 0.9); f0 = r2.uniform(500, 1600); d = r2.uniform(0.02, 0.06)
    i = int(s * SR); m = int(d * SR)
    if i + m >= n: continue
    tt = np.arange(m) / SR
    bub[i:i + m] += np.sin(2 * np.pi * f0 * (1 + tt * 6) * tt) * np.exp(-tt / (d * 0.3)) * np.exp(-s / 0.4)
save("splash", thump * 1.2 + spray * 0.9 + bub * 0.5, peak_db=-3, loop=False)

# Swim stroke: softer slosh.
n = int(SR * 0.55); t = np.arange(n) / SR
slosh = spectral_noise(n * 2, band(300, 3500, 1.0))[:n]
env = np.clip(t / 0.08, 0, 1) * np.exp(-np.clip(t - 0.08, 0, None) / 0.13)
am = 1 + 0.5 * np.sin(2 * np.pi * 23 * t)
save("swim_stroke", slosh * env * am, peak_db=-8, loop=False)

# Heal: soft rising chime (bell partials with shimmer).
n = int(SR * 1.4); t = np.arange(n) / SR
x = np.zeros(n)
for k, (f0, start) in enumerate([(523.25, 0.0), (659.25, 0.08), (783.99, 0.16), (1046.5, 0.24)]):
    tt = np.clip(t - start, 0, None)
    env = (t >= start) * np.clip(tt / 0.01, 0, 1) * np.exp(-tt / 0.45)
    for h, a in [(1, 1.0), (2.76, 0.25), (5.4, 0.08)]:
        x += a * env * np.sin(2 * np.pi * f0 * h * tt) * (1 + 0.15 * np.sin(2 * np.pi * 6 * tt))
save("heal_chime", x, peak_db=-8, loop=False)

# Body hit: short low thump with a slap on top.
n = int(SR * 0.35); t = np.arange(n) / SR
thump = np.sin(2 * np.pi * (110 - 140 * t) * t) * np.exp(-t / 0.06)
slap = spectral_noise(n * 2, band(600, 4000, 1.0))[:n] * np.exp(-t / 0.025)
save("hit_body", thump * 1.0 + slap * 0.5, peak_db=-3, loop=False)

# Item pickup: two quick bright notes.
n = int(SR * 0.35); t = np.arange(n) / SR
x = np.zeros(n)
for f0, start in [(880.0, 0.0), (1318.5, 0.07)]:
    tt = np.clip(t - start, 0, None)
    env = (t >= start) * np.clip(tt / 0.004, 0, 1) * np.exp(-tt / 0.09)
    x += env * (np.sin(2 * np.pi * f0 * tt) + 0.3 * np.sin(2 * np.pi * f0 * 2.01 * tt))
save("pickup", x, peak_db=-9, loop=False)

# Coins: a few metallic clinks.
n = int(SR * 0.5); t = np.arange(n) / SR
x = np.zeros(n)
r3 = np.random.default_rng(11)
for k in range(5):
    start = k * 0.06 + r3.uniform(0, 0.03)
    tt = np.clip(t - start, 0, None)
    env = (t >= start) * np.exp(-tt / 0.05)
    for f0 in [r3.uniform(2400, 3200), r3.uniform(4100, 5200), r3.uniform(6100, 7000)]:
        x += env * np.sin(2 * np.pi * f0 * tt) * r3.uniform(0.3, 0.7)
save("coins", x, peak_db=-10, loop=False)
