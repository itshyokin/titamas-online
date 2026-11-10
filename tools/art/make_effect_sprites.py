"""Built-in effect sprites for spells and skills (Database → Abilities → Effect sprites).
    python3 tools/art/make_effect_sprites.py
Writes assets/effects/builtin/*.png: white shapes on a see-through background, so the
"Glow" look can tint them with the ability's colour. Names ending in _N (burst_4) are
strips of N frames side by side, played left to right.
Your own drawings go in assets/effects/custom/ (or use "Load PNG…" on the Database page)."""
import math, pathlib, random
from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parents[2] / "assets" / "effects" / "builtin"
S = 64


def blank(w=S, h=S):
    return Image.new("RGBA", (w, h), (255, 255, 255, 0))


def from_alpha(fn, w=S, h=S):
    img = blank(w, h)
    px = img.load()
    for y in range(h):
        for x in range(w):
            a = max(0.0, min(1.0, fn((x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1)))
            px[x, y] = (255, 255, 255, int(a * 255))
    return img


def save(name, img):
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / (name + ".png"))
    print("wrote", OUT / (name + ".png"))


def glow(x, y):
    return (1 - math.hypot(x, y)) ** 2 if math.hypot(x, y) < 1 else 0


def ring(x, y, r=0.78, w=0.14):
    return 1 - abs(math.hypot(x, y) - r) / w


def star(x, y):
    d = math.hypot(x, y)
    if d >= 1:
        return 0
    arm = max(1 - abs(x) / 0.09, 1 - abs(y) / 0.09, 0) * (1 - d)
    return max(arm * 1.6, glow(x * 2.2, y * 2.2))


def diamond(x, y):
    return (1 - (abs(x) + abs(y) * 0.7) / 0.8) * 3


def flame(x, y):
    # A teardrop: round at the bottom, a point at the top that leans a little.
    t = (1 - y) / 2  # 0 at the bottom, 1 at the top
    if not 0.03 < t < 0.98:
        return 0
    width = 0.62 * math.sqrt(max(1 - ((t - 0.3) / 0.3) ** 2, 0)) if t < 0.3 else 0.62 * (1 - (t - 0.3) / 0.7) ** 1.4
    lean = 0.12 * math.sin(t * 3.0) * t
    return (1 - abs(x - lean) / max(width, 0.001)) * 3


def puff(x, y):
    a = 0.0
    for cx, cy, r in [(-0.3, 0.15, 0.5), (0.3, 0.2, 0.45), (0.0, -0.2, 0.55), (0.35, -0.25, 0.3), (-0.35, -0.3, 0.3)]:
        a = max(a, 1 - math.hypot(x - cx, y - cy) / r)
    return a * 1.6


def slash(x, y):
    # A crescent sweeping from lower left to upper right.
    d = math.hypot(x + 0.25, y - 0.25)
    ang = math.atan2(y - 0.25, x + 0.25)
    sweep = (ang + 1.9) / 2.6
    if not 0 < sweep < 1:
        return 0
    thick = 0.16 * math.sin(sweep * math.pi)
    return (1 - abs(d - 0.95) / max(thick, 0.001)) * 2


def snowflake(x, y):
    d = math.hypot(x, y)
    if d > 0.95:
        return 0
    a = 0.0
    ang = math.atan2(y, x)
    for k in range(6):
        t = ang - k * math.pi / 3
        along = d * math.cos(t)
        across = abs(d * math.sin(t))
        if along > 0:
            a = max(a, 1 - across / 0.07)
            for b in (0.45, 0.7):
                side = abs(along - b) + abs(across - (along - b) * 0 ) * 0
                a = max(a, 1 - (abs(across - abs(along - b) * 1.0) / 0.06) if abs(along - b) < 0.18 and along > b else 0)
    return a * 1.5


def rune():
    # A circle of marks for the ground: two rings, ticks and a six-pointed figure.
    n = 128
    img = blank(n, n)
    d = ImageDraw.Draw(img)
    c = n / 2
    for r, w in [(60, 3), (48, 2), (20, 2)]:
        d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, 255), width=w)
    for k in range(24):
        a = k * math.pi / 12
        r0, r1 = (49, 59) if k % 2 == 0 else (53, 59)
        d.line([c + math.cos(a) * r0, c + math.sin(a) * r0, c + math.cos(a) * r1, c + math.sin(a) * r1], fill=(255, 255, 255, 255), width=2)
    for start in (0, 1):
        pts = [(c + math.cos(start * math.pi / 3 + k * 2 * math.pi / 3 - math.pi / 2) * 47, c + math.sin(start * math.pi / 3 + k * 2 * math.pi / 3 - math.pi / 2) * 47) for k in range(3)]
        d.polygon(pts, outline=(255, 255, 255, 255))
        d.line(pts + [pts[0]], fill=(255, 255, 255, 255), width=2)
    return img


def burst_strip(frames=4):
    # A flash that opens into a ring and breaks up: frames side by side.
    random.seed(4)
    spikes = [(random.uniform(0, math.tau), random.uniform(0.6, 1.0)) for _ in range(9)]
    img = blank(S * frames, S)
    for i in range(frames):
        t = i / (frames - 1)

        def f(x, y, t=t):
            d = math.hypot(x, y)
            core = (1 - d / (0.55 - 0.35 * t)) * (1 - t) * 2 if d < 0.55 - 0.35 * t else 0
            r = 0.3 + 0.6 * t
            edge = (1 - abs(d - r) / (0.16 - 0.1 * t)) * (1 - t * 0.6)
            ang = math.atan2(y, x)
            ray = 0.0
            for a, ln in spikes:
                da = abs((ang - a + math.pi) % math.tau - math.pi)
                if da < 0.09 and r * 0.5 < d < r + ln * 0.3 * (1 - t):
                    ray = max(ray, (1 - da / 0.09) * (1 - t))
            return max(core, edge, ray)

        img.paste(from_alpha(f), (i * S, 0))
    return img


if __name__ == "__main__":
    save("glow", from_alpha(glow))
    save("ring", from_alpha(ring))
    save("spark", from_alpha(star))
    save("diamond", from_alpha(diamond))
    save("flame", from_alpha(flame))
    save("puff", from_alpha(puff).filter(ImageFilter.GaussianBlur(1.2)))
    save("slash", from_alpha(slash))
    save("snowflake", from_alpha(snowflake))
    save("rune_circle", rune())
    save("burst_4", burst_strip(4))
