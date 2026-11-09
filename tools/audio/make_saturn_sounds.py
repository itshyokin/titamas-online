"""Music, ambience and a few effects for Titamas Online, several of them ported from the
Saturn (HD-2D engine) synthesiser (src/audio/synth.ts): the night crickets and the
"field" and "night" music. Also converts Saturn's recorded forest birds and its
ForestTune1 track.

  python tools/audio/make_saturn_sounds.py <path to the hd2dengine clone>

Writes .ogg files into assets/audio/{ambience,music,sfx,combat}. Needs numpy and ffmpeg.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np

RATE = 44100
ROOT = Path(__file__).resolve().parents[2]
SATURN = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "itshyokin" / "hd2dengine"


class Rng:
    """Saturn's xorshift, so the ported sounds come out the same."""

    def __init__(self, seed):
        self.s = (seed & 0xFFFFFFFF) or 1

    def __call__(self):
        s = self.s
        s ^= (s << 13) & 0xFFFFFFFF
        s ^= s >> 17
        s ^= (s << 5) & 0xFFFFFFFF
        self.s = s & 0xFFFFFFFF
        return (self.s % 100000) / 100000


def lowpass(a, cutoff, rate=RATE):
    k = 1 - np.exp(-2 * np.pi * cutoff / rate)
    out = np.empty_like(a)
    y = 0.0
    for i in range(len(a)):
        y += (a[i] - y) * k
        out[i] = y
    return out


def lowpass_fast(a, cutoff, rate=RATE):
    """One-pole low-pass via scipy-free IIR in chunks (vectorised with lfilter-like recursion)."""
    k = 1 - np.exp(-2 * np.pi * cutoff / rate)
    # y[n] = y[n-1] + k (x[n] - y[n-1])  ->  exponential smoothing; use cumulative trick per block
    out = np.empty_like(a)
    y = 0.0
    block = 4096
    decay = (1 - k) ** np.arange(1, block + 1)
    for s in range(0, len(a), block):
        x = a[s:s + block]
        m = len(x)
        d = decay[:m]
        # y_n = (1-k)^n y0 + sum_{j<=n} k (1-k)^(n-j) x_j
        conv = np.convolve(x * k, (1 - k) ** np.arange(m))[:m]
        out[s:s + m] = d * y + conv
        y = out[s + m - 1]
    return out


def seamless(l, r, fade):
    n = int(fade * RATE)
    ln = len(l) - n
    ol, orr = l[:ln].copy(), r[:ln].copy()
    k = np.arange(n) / n
    ol[:n] = l[:n] * k + l[ln:] * (1 - k)
    orr[:n] = r[:n] * k + r[ln:] * (1 - k)
    return ol, orr


def write_ogg(path, l, r=None, rate=RATE, quality=4):
    path.parent.mkdir(parents=True, exist_ok=True)
    r = l if r is None else r
    data = np.stack([l, r], axis=1)
    peak = np.max(np.abs(data)) or 1.0
    if peak > 0.98:
        data = data / peak * 0.98
    pcm = (data * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(rate), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(quality), str(path)], input=pcm, check=True)
    print("wrote", path)


def convert(src, dst, quality=4, seconds=None):
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src)]
    if seconds:
        cmd += ["-t", str(seconds)]
    subprocess.run(cmd + ["-c:a", "libvorbis", "-q:a", str(quality), str(dst)], check=True)
    print("wrote", dst)


def night_ambience():
    """Saturn's "night": a low breeze and crickets."""
    secs, n = 14, 14 * RATE
    R = Rng(len("night") * 131 + 7)
    l, r = np.zeros(n), np.zeros(n)
    noise = lambda: np.array([R() * 2 - 1 for _ in range(n)])
    a, b = lowpass(noise(), 350), lowpass(noise(), 350)
    t = np.arange(n) / RATE
    sw = 0.55 + 0.45 * np.sin(2 * np.pi * t / secs * 2 + 1.3)
    l += a * 0.45 * sw
    r += b * 0.45 * (1.1 - sw * 0.2)
    for _ in range(40):
        at = int(R() * (n - RATE))
        f = 4200 + R() * 900
        pan = R()
        tt = np.arange(int(0.4 * RATE)) / RATE
        c = np.sin(2 * np.pi * f * tt) * (np.sin(2 * np.pi * 30 * tt) > 0.2) * np.sin(np.pi * tt / 0.4)
        l[at:at + len(c)] += c * 0.04 * (1 - pan)
        r[at:at + len(c)] += c * 0.04 * pan
    return seamless(l, r, 1.5)


def hz(m):
    return 440 * 2 ** ((m - 69) / 12)


def music(name):
    """Saturn's simple looping music: pads, a bass and a gentle melody."""
    plan = {
        "field": dict(bpm=92, chords=[[0, 4, 7], [5, 9, 12], [-3, 0, 4], [7, 11, 14]], scale=[0, 2, 4, 7, 9], root=62, melody=0.9, pad=0.8, bright=0.8),
        "night": dict(bpm=66, chords=[[0, 3, 7], [-4, 0, 3], [-2, 2, 5], [-5, -2, 2]], scale=[0, 3, 5, 7, 10], root=57, melody=0.5, pad=1, bright=0.4),
    }[name]
    SR = RATE // 2
    R = Rng(len(name) * 53 + 11)
    beat = 60 / plan["bpm"]
    bar = beat * 4
    bars = len(plan["chords"]) * 2
    n = int(np.ceil(bars * bar * SR))
    l, r = np.zeros(n), np.zeros(n)

    def note(start, dur, f, gain, pan, kind):
        s = int(start * SR)
        ln = int((dur + (1.2 if kind == "pad" else 0.6)) * SR)
        t = np.arange(ln) / SR
        if kind == "pad":
            v = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.003 * t) + 0.15 * np.sin(np.pi * f * t)) \
                * np.minimum(1, t / 0.8) * np.where(t < dur, 1, np.exp(-(t - dur) * 3))
        elif kind == "bass":
            v = (np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t)) * np.minimum(1, t / 0.01) * np.exp(-t * 2.2)
        else:
            v = (np.sin(2 * np.pi * f * t) + plan["bright"] * 0.35 * np.sin(4 * np.pi * f * t) + plan["bright"] * 0.12 * np.sin(6 * np.pi * f * t)) \
                * np.minimum(1, t / 0.005) * np.exp(-t * 4)
        idx = (s + np.arange(ln)) % n
        np.add.at(l, idx, v * gain * (1 - pan))
        np.add.at(r, idx, v * gain * pan)

    for b in range(bars):
        chord = plan["chords"][b % len(plan["chords"])]
        t0 = b * bar
        for k, c in enumerate(chord):
            note(t0, bar, hz(plan["root"] + c - 12), 0.05 * plan["pad"], 0.3 + k * 0.2, "pad")
        note(t0, bar, hz(plan["root"] + chord[0] - 24), 0.16, 0.5, "bass")
        for s in range(4):
            if R() > plan["melody"] * 0.8:
                continue
            deg = plan["scale"][int(R() * len(plan["scale"]))] + (12 if R() < 0.3 else 0)
            note(t0 + s * bar / 4, bar / 4, hz(plan["root"] + deg), 0.09, 0.35 + R() * 0.3, "pluck")
    peak = max(np.max(np.abs(l)), np.max(np.abs(r)))
    return l * 0.7 / peak, r * 0.7 / peak, SR


def grunt(seed, pitch=115.0, dur=0.42, vowel=(640, 1190, 2390)):
    """A pained "ugh!": a falling voiced buzz through "uh" formants, with some breath."""
    rng = np.random.default_rng(seed)
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    f0 = pitch * (1.25 - 0.45 * t / dur) * (1 + 0.03 * rng.standard_normal())
    phase = np.cumsum(f0 / RATE)
    # Glottal pulses: a sawtooth-ish wave rich in harmonics.
    src = (phase % 1.0) * 2 - 1
    src = src - np.convolve(src, np.ones(8) / 8, "same") * 0.6
    breath = rng.standard_normal(n) * 0.35
    x = src + breath
    out = np.zeros(n)
    for i, (f, bw) in enumerate(zip(vowel, (90, 110, 160))):
        # Two-pole resonator.
        rr = np.exp(-np.pi * bw / RATE)
        a1, a2 = -2 * rr * np.cos(2 * np.pi * f / RATE), rr * rr
        y = np.zeros(n)
        for k in range(2, n):
            y[k] = x[k] - a1 * y[k - 1] - a2 * y[k - 2]
        out += y * (1.0, 0.6, 0.25)[i]
    env = np.minimum(1, t / 0.015) * np.exp(-np.maximum(0, t - 0.08) * 7)
    out *= env
    return out / np.max(np.abs(out)) * 0.9


def tone_loop(freqs, secs, shimmer, seed):
    """A seamless magical hum: detuned tones with a slow shimmer and soft noise."""
    rng = np.random.default_rng(seed)
    n = secs * RATE
    t = np.arange(n) / RATE
    l, r = np.zeros(n), np.zeros(n)
    for i, f in enumerate(freqs):
        # Whole numbers of cycles over the loop, so it wraps cleanly.
        f = round(f * secs) / secs
        lfo = 0.6 + 0.4 * np.sin(2 * np.pi * (i + 1) / secs * t + i)
        v = np.sin(2 * np.pi * f * t) * lfo / (i + 1)
        l += v * (0.6 + 0.4 * (i % 2))
        r += v * (1.0 - 0.4 * (i % 2))
    sh = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * (np.fft.rfftfreq(n, 1 / RATE) > 3000), n)
    sh /= np.std(sh)
    tw = 0.5 + 0.5 * np.sin(2 * np.pi * 3 / secs * t)
    l += sh * shimmer * tw
    r += sh * shimmer * (1 - tw)
    return l, r


def burst(freq_start, freq_end, dur, noise, seed):
    """A release: a quick rising/falling tone with a noisy whoosh."""
    rng = np.random.default_rng(seed)
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    f = freq_start + (freq_end - freq_start) * (t / dur)
    v = np.sin(2 * np.pi * np.cumsum(f) / RATE)
    w = rng.standard_normal(n)
    w = np.convolve(w, np.ones(12) / 12, "same")
    env = np.minimum(1, t / 0.01) * np.exp(-t * 5 / dur)
    return (v * 0.7 + w * noise) * env


def clang(seed, base=1800.0, dur=0.6, wood=False):
    """Metal on stone (bright partials, quick ring) or a dull thunk into wood."""
    rng = np.random.default_rng(seed)
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    if wood:
        for f, d in ((180, 18), (310, 25), (520, 35)):
            out += np.sin(2 * np.pi * f * t) * np.exp(-t * d)
        out += rng.standard_normal(n) * np.exp(-t * 60) * 0.6
    else:
        for i, ratio in enumerate((1.0, 1.51, 2.24, 2.97, 3.8)):
            out += np.sin(2 * np.pi * base * ratio * t + i) * np.exp(-t * (6 + i * 4)) / (1 + i * 0.5)
        out += rng.standard_normal(n) * np.exp(-t * 90) * 0.8
    return out / np.max(np.abs(out)) * 0.9


def achievement_chime():
    """Saturn's "achievement unlocked": a soft two-note chime over a warm low bloom."""
    n = int(1.4 * RATE)
    t = np.arange(n) / RATE
    env = lambda t, a, d: np.where(t < a, t / a, np.exp(-(t - a) / d))
    n1 = np.sin(2 * np.pi * 659.3 * t) * env(t, 0.004, 0.5) * 0.32
    t2 = t - 0.16
    n2 = np.where(t2 > 0, (np.sin(2 * np.pi * 987.8 * t2) + np.sin(2 * np.pi * 1975.5 * t2) * 0.2) * env(np.maximum(t2, 0), 0.004, 0.7) * 0.3, 0)
    bloom = np.sin(2 * np.pi * 164.8 * t) * np.sin(np.pi * np.minimum(1, t / 1.2)) * 0.18
    return n1 + n2 + bloom


def main():
    A = ROOT / "assets" / "audio"
    birds = SATURN / "audio" / "ambience" / "forest_birds_day.wav"
    if birds.exists():
        convert(birds, A / "ambience" / "forest_day_loop.ogg")
    l, r = night_ambience()
    write_ogg(A / "ambience" / "forest_night_loop.ogg", l, r)
    tune = SATURN / "audio" / "music" / "ForestTune1.wav"
    if tune.exists():
        convert(tune, A / "music" / "forest_tune.ogg", quality=5)
    for name in ("field", "night"):
        l, r, sr = music(name)
        write_ogg(A / "music" / f"saturn_{name}.ogg", l, r, rate=sr)
    for i, (p, v) in enumerate(((118, (640, 1190, 2390)), (98, (600, 1040, 2250)), (135, (700, 1220, 2600)))):
        g = grunt(11 + i, p, 0.38 + 0.06 * i, v)
        write_ogg(A / "combat" / f"death_grunt_{i + 1}.ogg", g)
    l, r = tone_loop([220, 330, 440.5, 660], 4, 0.05, 3)
    write_ogg(A / "sfx" / "spell_charge_loop.ogg", l * 0.5, r * 0.5)
    write_ogg(A / "sfx" / "spell_release.ogg", burst(500, 1400, 0.45, 0.5, 4))
    l, r = tone_loop([196, 293.7, 392, 587.3, 784], 4, 0.08, 5)
    write_ogg(A / "sfx" / "hearth_channel_loop.ogg", l * 0.5, r * 0.5)
    write_ogg(A / "sfx" / "hearth_teleport.ogg", burst(300, 2400, 1.1, 0.6, 6))
    write_ogg(A / "sfx" / "achievement.ogg", achievement_chime())
    for i in range(2):
        write_ogg(A / "combat" / f"clang_stone_{i + 1}.ogg", clang(20 + i, 1700 + i * 260))
        write_ogg(A / "combat" / f"thunk_wood_{i + 1}.ogg", clang(30 + i, wood=True, dur=0.35))


if __name__ == "__main__":
    main()
