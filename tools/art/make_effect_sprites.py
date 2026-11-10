"""Built-in effect sprites for spells and skills (Database → Abilities → Effect sprites).
    python3 tools/art/make_effect_sprites.py
Writes assets/effects/builtin/*.png: white shapes on a see-through background, so the
"Glow" look can tint them with the ability's colour (insect_* are for Wildlife swarms,
tinted with the swarm's colour). Names ending in _N (burst_4) are
strips of N frames side by side, played left to right.
Your own drawings go in assets/effects/custom/ (or use "Load PNG…" on the Database page).
Pixel look, to match the grass: 24 px pictures (48 for the rune circle) with see-through
steps (0, 35 %, 70 %, 100 %) instead of smooth fades."""
import math, pathlib, random
from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parents[2] / "assets" / "effects" / "builtin"
S = 24
STEPS = (0.0, 0.35, 0.7, 1.0)


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


def step(a):
    """Snap a 0-255 alpha to the pixel-art steps."""
    f = a / 255
    if f < 0.18:
        return 0
    if f < 0.5:
        return int(STEPS[1] * 255)
    if f < 0.85:
        return int(STEPS[2] * 255)
    return 255


def save(name, img):
    OUT.mkdir(parents=True, exist_ok=True)
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            px[x, y] = (255, 255, 255, step(a))
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
    # A circle of marks for the ground: two rings, ticks and a six-pointed figure (drawn
    # big, then shrunk to the pixel size so its lines come out one pixel wide).
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
    return img.resize((48, 48), Image.BOX)


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


def firefly_strip(frames=2, n=12):
    # A beetle with a glowing tail: frame 1 tail lit, frame 2 dimmer (a slow pulse).
    img = blank(n * frames, n)
    px = img.load()
    for f in range(frames):
        for y in range(n):
            for x in range(n):
                u = (x + 0.5 - n / 2) / (n / 2)
                v = (y + 0.5 - n / 2) / (n / 2)
                a = 0
                if ((u + 0.25) / 0.32) ** 2 + (v / 0.22) ** 2 <= 1:
                    a = 90  # dark body (dim in the additive glow)
                if ((u - 0.25) / 0.36) ** 2 + ((v - 0.04) / 0.3) ** 2 <= 1:
                    a = 255 if f == 0 else 170  # the lantern
                if (((u + 0.05) / 0.38) ** 2 + ((v + 0.38) / 0.14) ** 2 <= 1):
                    a = max(a, 120)  # wings
                if a:
                    px[f * n + x, y] = (255, 255, 255, a)
    return img


def ant_strip(frames=2, n=12):
    # An ant seen from above, head to the right: three body parts and legs that swap.
    img = blank(n * frames, n)
    d = ImageDraw.Draw(img)
    for f in range(frames):
        o = f * n
        for cx, r in [(2.5, 1.6), (5.6, 1.1), (8.3, 1.3)]:
            d.ellipse([o + cx - r, 6 - r, o + cx + r, 6 + r], fill=(255, 255, 255, 255))
        for k, lx in enumerate((4.6, 5.6, 6.6)):
            sway = (1 if (k + f) % 2 == 0 else -1)
            d.line([o + lx, 6, o + lx + sway, 2.6], fill=(255, 255, 255, 255), width=1)
            d.line([o + lx, 6, o + lx - sway, 9.4], fill=(255, 255, 255, 255), width=1)
        d.line([o + 9.4, 5.4, o + 11.2, 4.0], fill=(255, 255, 255, 255), width=1)
        d.line([o + 9.4, 6.6, o + 11.2, 8.0], fill=(255, 255, 255, 255), width=1)
    return img


def insect_strip(body_len, wing, frames=2, n=16):
    # A tiny insect seen from the side, wings up then flat: frames side by side.
    img = blank(n * frames, n)
    px = img.load()
    for f in range(frames):
        ang = -1.15 if f == 0 else -0.35
        for y in range(n):
            for x in range(n):
                u = (x + 0.5 - n / 2) / (n / 2)
                v = (y + 0.5 - n / 2) / (n / 2)
                a = 0.0
                if (u / body_len) ** 2 + ((v - 0.15) / 0.22) ** 2 <= 1:
                    a = 1.0
                if ((u - body_len * 0.95) / 0.16) ** 2 + ((v - 0.12) / 0.16) ** 2 <= 1:
                    a = 1.0
                for side in (-1, 1):
                    wx = (u - side * 0.05) * side
                    wy = v - 0.05
                    lx = wx * math.cos(ang) + wy * math.sin(ang)
                    ly = -wx * math.sin(ang) + wy * math.cos(ang)
                    if 0 <= lx <= wing and abs(ly) <= 0.16 * (1 - lx / wing) + 0.04:
                        a = max(a, 0.55)
                if a > 0:
                    px[f * n + x, y] = (255, 255, 255, int(a * 255))
    return img


if __name__ == "__main__":
    save("insect_fly_2", insect_strip(0.42, 0.75))
    save("insect_mosquito_2", insect_strip(0.55, 0.6))
    save("firefly_2", firefly_strip())
    save("ant_2", ant_strip())
    save("glow", from_alpha(glow))
    save("ring", from_alpha(ring))
    save("spark", from_alpha(star))
    save("diamond", from_alpha(diamond))
    save("flame", from_alpha(flame))
    save("puff", from_alpha(puff))
    save("slash", from_alpha(slash))
    save("snowflake", from_alpha(snowflake))
    save("rune_circle", rune())
    save("burst_4", burst_strip(4))
