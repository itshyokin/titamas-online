"""Quest fanfares (generated, no samples): a short rising "quest accepted" motif and a
brighter "quest complete" fanfare with a held chord.
    python3 tools/audio/make_quest_sounds.py
Writes assets/audio/sfx/quest_start.ogg and quest_complete.ogg (numpy + ffmpeg)."""
import pathlib, subprocess
import numpy as np

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"


def note_freq(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def tone(freq, secs, kind="brass", vib=0.0):
    t = np.arange(int(secs * RATE)) / RATE
    f = freq * (1 + vib * np.sin(2 * np.pi * 5.5 * t) * np.clip(t * 3, 0, 1))
    ph = 2 * np.pi * np.cumsum(f) / RATE
    if kind == "brass":
        # Brassy: odd+even harmonics that brighten as the note swells.
        bright = np.clip(t / 0.08, 0, 1)
        w = sum((0.6 ** h) * np.sin(ph * (h + 1)) * (1 if h < 2 else bright) for h in range(7))
        env = np.clip(t / 0.03, 0, 1) * np.exp(-t * 1.2)
    else:
        # Bell / harp shimmer.
        w = np.sin(ph) + 0.4 * np.sin(ph * 2.01) + 0.2 * np.sin(ph * 3.98)
        env = np.clip(t / 0.005, 0, 1) * np.exp(-t * 3.0)
    tail = np.clip((secs - t) / 0.06, 0, 1)
    return w * env * tail


def place(buf, sig, at):
    i = int(at * RATE)
    buf[i:i + len(sig)] += sig[:max(0, len(buf) - i)]


def reverb(x, amount=0.3):
    out = x.copy()
    for d, g in [(0.031, 0.5), (0.047, 0.42), (0.073, 0.35), (0.11, 0.28), (0.17, 0.2)]:
        n = int(d * RATE)
        out[n:] += x[:-n] * g * amount * 2
    return out


def write(name, l, r=None):
    OUT.mkdir(parents=True, exist_ok=True)
    r = l if r is None else r
    d = np.stack([l, r], 1)
    d = d / (np.max(np.abs(d)) or 1) * 0.85
    pcm = (d * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", str(OUT / name)], input=pcm, check=True)
    print("wrote", OUT / name)


def quest_start():
    buf = np.zeros(int(1.6 * RATE))
    # G4 C5 E5 -> G5 (held), harp sparkle on top.
    for n, at, secs in [(67, 0.0, 0.18), (72, 0.14, 0.18), (76, 0.28, 0.2), (79, 0.44, 1.0)]:
        place(buf, tone(note_freq(n), secs, vib=0.006 if secs > 0.5 else 0), at)
    for k, n in enumerate([84, 88, 91]):
        place(buf, 0.35 * tone(note_freq(n), 0.9, "bell"), 0.46 + k * 0.06)
    return reverb(buf)


def quest_complete():
    buf = np.zeros(int(2.8 * RATE))
    # Fanfare: C5 C5 C5 | G4 A4 ... then a held C major chord with a bell run.
    seq = [(72, 0.0, 0.12), (72, 0.13, 0.12), (72, 0.26, 0.12), (72, 0.42, 0.34),
           (68, 0.78, 0.3), (70, 1.08, 0.3), (72, 1.38, 1.3)]
    for n, at, secs in seq:
        place(buf, tone(note_freq(n), secs, vib=0.007 if secs > 1 else 0), at)
    for n in [60, 64, 67]:
        place(buf, 0.45 * tone(note_freq(n), 1.3, vib=0.004), 1.38)
    for k, n in enumerate([84, 88, 91, 96]):
        place(buf, 0.3 * tone(note_freq(n), 1.0, "bell"), 1.4 + k * 0.07)
    return reverb(buf)


if __name__ == "__main__":
    s = quest_start()
    write("quest_start.ogg", s, np.roll(s, 90))
    c = quest_complete()
    write("quest_complete.ogg", c, np.roll(c, 90))
