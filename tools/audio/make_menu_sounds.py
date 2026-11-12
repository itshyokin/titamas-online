"""Menu sounds (UiSounds): soft, wooden and papery to suit the Codex book.
    python3 tools/audio/make_menu_sounds.py
Writes assets/audio/ui/ui_hover, ui_click, ui_toggle, ui_tab, ui_open, ui_close, ui_back,
ui_error, ui_slider (.ogg; numpy + ffmpeg). Original, synthesised."""
import os
import subprocess

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "ui")
rng = np.random.default_rng(11)


def save(name, x, peak_db=-3.0):
	x = x / (np.max(np.abs(x)) or 1) * 10 ** (peak_db / 20)
	raw = (x * 32767).astype(np.int16).tobytes()
	os.makedirs(OUT, exist_ok=True)
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
		"-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name + ".ogg")], input=raw, check=True)
	print("wrote", name)


def t_of(seconds):
	return np.arange(int(SR * seconds)) / SR


def band_noise(n, lo, hi):
	spec = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1 / SR)
	spec *= (f > lo) & (f < hi)
	x = np.fft.irfft(spec, n)
	return x / (np.std(x) + 1e-9)


def env(t, attack, decay):
	return np.minimum(t / max(attack, 1e-4), 1) * np.exp(-t / decay)


def knock(freq, seconds=0.09, decay=0.018, partials=(1, 2.7, 5.1)):
	"""A small wooden knock: a few inharmonic partials, fast decay, a breath of noise."""
	t = t_of(seconds)
	x = sum(np.sin(2 * np.pi * freq * p * t) / (i + 1) ** 1.3 for i, p in enumerate(partials))
	x = x * env(t, 0.0015, decay)
	x += band_noise(len(t), 800, 5000) * env(t, 0.0005, 0.004) * 0.35
	return x


def paper(seconds, lo, hi, attack, decay):
	t = t_of(seconds)
	return band_noise(len(t), lo, hi) * env(t, attack, decay)


def main():
	save("ui_hover", knock(1500, 0.05, 0.008, (1, 2.4)), -14.0)
	save("ui_click", knock(620, 0.12, 0.025), -5.0)
	save("ui_toggle", np.concatenate([knock(900, 0.04, 0.008), knock(700, 0.08, 0.015)]), -6.0)
	save("ui_slider", knock(1800, 0.03, 0.005, (1,)), -16.0)
	# A page turned: a quick papery swish.
	t = t_of(0.16)
	swish = band_noise(len(t), 1500, 9000) * np.sin(np.pi * np.clip(t / 0.16, 0, 1)) ** 2
	save("ui_tab", swish + knock(500, 0.16, 0.02) * 0.15, -8.0)
	# The book opened: a soft rising whoosh of pages, then a low cover thump.
	t = t_of(0.45)
	rise = band_noise(len(t), 400, 7000) * np.sin(np.pi * np.clip(t / 0.32, 0, 1)) ** 2 * (t < 0.32)
	thump = np.zeros(len(t))
	k = knock(140, 0.3, 0.06, (1, 1.9, 3.1))
	start = int(0.26 * SR)
	thump[start:start + len(k)] += k[: len(t) - start]
	save("ui_open", rise * 0.6 + thump, -4.0)
	# Closed: thump first, then a short settle of paper.
	t = t_of(0.35)
	close = np.zeros(len(t))
	k = knock(120, 0.3, 0.05, (1, 1.9, 3.1))
	close[: len(k)] += k
	close += paper(0.35, 2000, 8000, 0.01, 0.05) * 0.25
	save("ui_close", close, -4.0)
	save("ui_back", np.concatenate([knock(700, 0.05, 0.01), knock(480, 0.1, 0.02)]), -6.0)
	t = t_of(0.22)
	buzz = np.sign(np.sin(2 * np.pi * 150 * t)) * 0.4 + np.sin(2 * np.pi * 150 * t)
	buzz *= ((t < 0.08) | ((t > 0.11) & (t < 0.2))) * env(t, 0.002, 0.2)
	save("ui_error", buzz, -9.0)


if __name__ == "__main__":
	main()
