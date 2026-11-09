"""Grass clump pictures for GrassField (in the style of Saturn's tall grass): a dense clump
of blades leaning this way and that, with a dark outline. Grey, light at the tips: the
grass shader tints it with the ground colour under each clump.

  python tools/art/make_grass.py   ->  assets/textures/grass_clump.png (tall grass)
                                       assets/textures/grass_short.png
Needs Pillow.
"""
import random
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "assets" / "textures"


def clump(w, h, blades, seed, path):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    # Value ramp root -> tip (the shader multiplies the ground colour by this).
    ramp = [92, 112, 136, 160, 186, 210, 232, 250]
    for _ in range(blades):
        bx = min(w * 0.94, max(w * 0.06, rnd.gauss(w * 0.5, w * 0.2)))
        hgt = int(h * (0.5 + rnd.random() * 0.5))
        lean = (rnd.random() - 0.5) * w * 0.55
        width = rnd.choice([1, 1, 2, 2, 2, 3])
        shade = rnd.uniform(0.85, 1.05)
        for j in range(hgt):
            f = j / hgt
            x = bx + lean * f * f
            half = width * (1.0 - f * 0.8) * 0.5
            v = ramp[min(len(ramp) - 1, int(f * len(ramp) + (1 if rnd.random() < 0.12 else 0)))]
            v = max(0, min(255, int(v * shade)))
            y = h - 1 - j
            for xi in range(int(x - half), int(x + half) + 1):
                if 0 <= xi < w and 0 <= y < h:
                    px[xi, y] = (v, v, v, 255)
    # Dark outline round the blades (reads as pixel art, separates clumps).
    out = img.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            if px[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3]:
                    op[x, y] = (38, 38, 38, 255)
                    break
    out.save(path)
    print("wrote", path)


OUT.mkdir(parents=True, exist_ok=True)
clump(64, 80, 40, 41, OUT / "grass_clump.png")
clump(64, 40, 32, 7, OUT / "grass_short.png")
