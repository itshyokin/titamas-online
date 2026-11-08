"""Placeholder eye textures for the character creator.

Each style is two PNGs in assets/characters/eyes/:
  <id>.png       the eye (RGBA): lids/lashes, whites, pupil, highlight; the iris drawn in
                 light grey (it gets tinted by the chosen eye colour).
  <id>_iris.png  mask: white where the eye colour goes, black elsewhere.
Drawn as the character's eye seen from the front with the OUTER corner on the right;
the game mirrors it for the other eye. Replace them with your own drawings (same names,
any size, same 4:3 shape works best).
    python3 tools/art/make_eyes.py
"""
import math, os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "characters", "eyes")
W, H = 32, 24          # final size (pixel look)
S = 8                  # supersampling

STYLES = {
    # top/bottom lid heights (fraction of H), corner shape power, outer-corner lift,
    # iris radius (fraction of H), top-lid droop (covers the iris top), lash weight
    "round":  dict(top=0.36, bot=0.30, p=0.8, lift=0.00, iris=0.27, droop=0.0, lash=2.2),
    "almond": dict(top=0.32, bot=0.20, p=1.2, lift=0.10, iris=0.25, droop=0.0, lash=2.4),
    "narrow": dict(top=0.22, bot=0.14, p=1.3, lift=0.06, iris=0.22, droop=0.0, lash=2.8),
    "large":  dict(top=0.42, bot=0.34, p=0.7, lift=0.02, iris=0.32, droop=0.0, lash=2.0, sparkle=True),
    "sleepy": dict(top=0.30, bot=0.24, p=1.0, lift=-0.04, iris=0.26, droop=0.3, lash=2.6),
    "fierce": dict(top=0.30, bot=0.20, p=1.1, lift=0.16, iris=0.24, droop=0.0, lash=3.0, brow_tilt=True),
}


def outline(st, w, h):
    """Points of the eye opening, left (inner corner) to right (outer) along the top, back along the bottom."""
    x0, x1 = w * 0.08, w * 0.92
    cy = h * 0.55
    top, bot = [], []
    for i in range(41):
        t = i / 40
        x = x0 + (x1 - x0) * t
        s = math.sin(math.pi * t) ** st["p"]
        tilt = -st["lift"] * h * t          # outer corner higher
        ty = cy - st["top"] * h * s + tilt
        if st.get("brow_tilt"):
            ty += st["top"] * h * 0.35 * (1 - t) * s   # heavier inner top lid: a frown
        top.append((x, ty))
        bot.append((x, cy + st["bot"] * h * s + tilt * 0.5))
    return top, bot[::-1]


def make(name, st):
    w, h = W * S, H * S
    eye = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mask = Image.new("L", (w, h), 0)
    top, bot = outline(st, w, h)
    shape = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shape).polygon(top + bot, fill=255)
    d = ImageDraw.Draw(eye)
    d.polygon(top + bot, fill=(246, 242, 236, 255))
    # Iris and pupil, clipped to the opening; a lowered lid hides its top.
    cx, cy = w * 0.5, h * 0.55 - st["lift"] * h * 0.5
    r = st["iris"] * h
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(205, 205, 205, 255))
    ld.ellipse([cx - r * 0.72, cy - r * 0.72, cx + r * 0.72, cy + r * 0.72], fill=(232, 232, 232, 255))
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    pr = r * 0.42
    ld.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=(16, 12, 14, 255))
    ImageDraw.Draw(m).ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=0)
    hr = r * 0.22
    for (hx, hy, k) in [(cx + r * 0.32, cy - r * 0.38, 1.0)] + ([(cx - r * 0.35, cy + r * 0.35, 0.55)] if st.get("sparkle") else []):
        ld.ellipse([hx - hr * k, hy - hr * k, hx + hr * k, hy + hr * k], fill=(255, 255, 255, 255))
        ImageDraw.Draw(m).ellipse([hx - hr * k, hy - hr * k, hx + hr * k, hy + hr * k], fill=0)
    if st["droop"] > 0:
        cut = Image.new("L", (w, h), 255)
        lid_y = min(p[1] for p in top) + st["droop"] * (st["top"] + st["bot"]) * h
        ImageDraw.Draw(cut).rectangle([0, 0, w, lid_y], fill=0)
        layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", (w, h), 0), cut))
        m = Image.composite(m, Image.new("L", (w, h), 0), cut)
        d.rectangle([0, 0, w, lid_y], fill=(0, 0, 0, 0))
        eye.putalpha(Image.composite(eye.getchannel("A"), Image.new("L", (w, h), 0), cut))
        st["_lid"] = lid_y
    clipped = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    clipped.paste(layer, (0, 0), Image.composite(layer.getchannel("A"), Image.new("L", (w, h), 0), shape))
    eye = Image.alpha_composite(eye, clipped)
    mask = Image.composite(m, mask, shape)
    # Lids: a thick dark upper line with a lash flick at the outer corner, a thin lower line.
    d = ImageDraw.Draw(eye)
    lw = int(st["lash"] * S)
    lid_line = [p for p in top if "_lid" not in st or p[1] >= st["_lid"]] or top
    d.line(lid_line, fill=(28, 18, 18, 255), width=lw, joint="curve")
    ox, oy = top[-1]
    d.line([(ox - S * 3, oy - S * 0.5), (ox + S * 0.5, oy - S * 2.5)], fill=(28, 18, 18, 255), width=lw)
    if "_lid" in st:
        # The lowered lid: a lash line straight across, following the opening's edge.
        ly = st["_lid"]
        xs = [p[0] for p in top if p[1] <= ly]
        if xs:
            d.line([(min(xs), ly), (max(xs), ly)], fill=(28, 18, 18, 255), width=lw)
    d.line(bot, fill=(80, 50, 46, 255), width=max(S, lw // 3), joint="curve")
    eye = eye.resize((W, H), Image.BOX)
    a = eye.getchannel("A").point(lambda v: 255 if v >= 110 else 0)
    eye.putalpha(a)
    mask = mask.resize((W, H), Image.BOX).point(lambda v: 255 if v >= 120 else 0)
    eye.save(os.path.join(OUT, name + ".png"))
    mask.save(os.path.join(OUT, name + "_iris.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, st in STYLES.items():
        make(name, st)
        print("wrote", name)
