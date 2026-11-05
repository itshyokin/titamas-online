import sys, subprocess, numpy as np
SR = 44100
for path in sys.argv[1:]:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.int16) / 32768
    # Onset: first 10 ms window within 12 dB of the loudest one.
    w10 = int(0.01 * SR)
    env = np.array([np.sqrt(np.mean(x[i:i + w10] ** 2)) for i in range(0, len(x) - w10, w10 // 2)])
    first = int(np.argmax(env > env.max() * 0.25)) * (w10 // 2)
    start = max(first - int(0.006 * SR), 0)
    x = x[start:].copy()
    x[: int(0.003 * SR)] *= np.linspace(0, 1, int(0.003 * SR))
    w = int(0.05 * SR)
    rms = max(np.sqrt(np.mean(x[i:i + w] ** 2)) for i in range(0, max(len(x) - w, 1), w // 4))
    x *= 10 ** (-16 / 20) / rms
    x = np.clip(x, -0.98, 0.98)
    x[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
    print(path, "cut %.3fs" % (start / SR), "len %.2fs" % (len(x) / SR), "peak %.2f" % np.max(np.abs(x)))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "5", path],
                   input=(x * 32767).astype(np.int16).tobytes(), check=True)
