"""Sounds for event commands:
    python3 tools/audio/make_event_sounds.py
Writes assets/audio/events/rumble_loop.ogg (the Shake command's earth rumble)."""
import numpy as np, subprocess, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "events")
rng = np.random.default_rng(11)


def bandnoise(n, lo, hi):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec *= (f > lo) & (f < hi)
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-9)


def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.stack([x, x], 1) * 32767).astype(np.int16).tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name)], input=pcm, check=True)


if __name__ == "__main__":
    # A deep rolling rumble with stones knocking, made to loop.
    secs = 6.0
    n = int(SR * secs)
    tt = np.arange(n) / SR
    low = bandnoise(n, 18, 120) * (0.75 + 0.25 * np.sin(2 * np.pi * tt / secs * 3))
    mid = bandnoise(n, 120, 600) * 0.25
    knocks = np.zeros(n)
    for i in range(30):
        at = int(rng.uniform(0, secs - 0.1) * SR)
        k = int(0.06 * SR)
        knocks[at:at + k] += bandnoise(k, 300, 2500) * np.exp(-np.arange(k) / (k / 5)) * rng.uniform(0.1, 0.4)
    x = low + mid + knocks
    fade = int(0.5 * SR)  # cross-fade the ends so it loops
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    save("rumble_loop.ogg", x[:-fade])
    print("done")
