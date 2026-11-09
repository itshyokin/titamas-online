"""UI sounds: the soft tick played while dialogue text types out.
    python3 tools/audio/make_ui_sounds.py
Writes assets/audio/sfx/text_tick.ogg (numpy + ffmpeg)."""
import numpy as np, subprocess, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")


def save(name, x):
    x = x / (np.max(np.abs(x)) or 1) * 10 ** (-3 / 20)
    raw = (x * 32767).astype(np.int16).tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name + ".ogg")], input=raw, check=True)
    print("wrote", name)


os.makedirs(OUT, exist_ok=True)
t = np.arange(int(SR * 0.045)) / SR
# A short rounded "blip": a sine with a fast pitch drop, soft attack, quick decay.
f = 820 * (1 + 0.25 * np.exp(-t * 90))
ph = 2 * np.pi * np.cumsum(f) / SR
tick = (np.sin(ph) + 0.25 * np.sin(ph * 2)) * np.minimum(t / 0.002, 1) * np.exp(-t * 70)
save("text_tick", tick)
