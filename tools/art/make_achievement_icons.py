"""Pixel icons for the achievements (and the pins on the backpack).

    python3 tools/art/make_achievement_icons.py           # writes only missing pictures
    python3 tools/art/make_achievement_icons.py --force   # redraws every one

32 x 32, transparent, a coloured glyph with a dark outline. The owner may draw over
these (assets/icons/achievements/<id>.png): without --force existing files are kept.
"""
import os
import sys

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "icons", "achievements")
S = 32
OUTLINE = (24, 18, 14, 255)


def canvas():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def outline(img):
    """Dark 1-px outline round everything drawn."""
    src = img.load()
    out = img.copy()
    o = out.load()
    for y in range(S):
        for x in range(S):
            if src[x, y][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < S and 0 <= ny < S and src[nx, ny][3] > 0:
                    o[x, y] = OUTLINE
                    break
    return out


def shade(img, light=(255, 255, 255, 70), dark=(0, 0, 0, 60)):
    """Light top-left edges, darker bottom-right ones, for a little volume."""
    src = img.load()
    out = img.copy()
    o = out.load()
    for y in range(S):
        for x in range(S):
            if src[x, y][3] == 0:
                continue
            up = y > 0 and src[x, y - 1][3] > 0
            left = x > 0 and src[x - 1, y][3] > 0
            down = y < S - 1 and src[x, y + 1][3] > 0
            right = x < S - 1 and src[x + 1, y][3] > 0
            c = src[x, y]
            if not up or not left:
                o[x, y] = blend(c, light)
            elif not down or not right:
                o[x, y] = blend(c, dark)
    return out


def blend(c, over):
    a = over[3] / 255.0
    return tuple(int(c[i] * (1 - a) + over[i] * a) for i in range(3)) + (c[3],)


# --- Glyphs ---------------------------------------------------------------------------

def sword(d, x0=7, y0=24, x1=24, y1=7, blade=(210, 220, 230, 255), hilt=(150, 100, 50, 255)):
    d.line([(x0 + 3, y0 - 3), (x1, y1)], fill=blade, width=3)
    d.line([(x0 - 1, y0 - 5), (x0 + 5, y0 + 1)], fill=(200, 160, 60, 255), width=2)
    d.line([(x0, y0), (x0 - 3, y0 + 3)], fill=hilt, width=3)


def g_crossed_swords(d):
    sword(d)
    sword(d, 24, 24, 7, 7)


def g_skull(d):
    bone = (232, 226, 210, 255)
    d.ellipse([7, 5, 24, 21], fill=bone)
    d.rectangle([10, 18, 21, 25], fill=bone)
    d.rectangle([10, 11, 14, 15], fill=(30, 20, 20, 255))
    d.rectangle([17, 11, 21, 15], fill=(30, 20, 20, 255))
    d.rectangle([15, 16, 16, 18], fill=(30, 20, 20, 255))
    for x in (12, 15, 18):
        d.line([(x, 22), (x, 25)], fill=(60, 50, 40, 255))


def g_drop(d, col=(200, 30, 40, 255)):
    d.polygon([(16, 4), (24, 18), (8, 18)], fill=col)
    d.ellipse([8, 12, 24, 27], fill=col)
    d.rectangle([12, 15, 13, 19], fill=(255, 150, 150, 255))


def g_mossy_rock(d):
    d.polygon([(5, 25), (8, 13), (15, 7), (24, 10), (28, 25)], fill=(120, 118, 112, 255))
    d.polygon([(8, 13), (15, 7), (24, 10), (20, 14), (12, 15)], fill=(90, 150, 60, 255))
    d.rectangle([14, 17, 18, 19], fill=(90, 88, 84, 255))


def g_helmet(d):
    steel = (180, 186, 196, 255)
    d.pieslice([6, 5, 26, 27], 180, 360, fill=steel)
    d.rectangle([6, 15, 26, 25], fill=steel)
    d.rectangle([9, 15, 23, 17], fill=(30, 30, 40, 255))
    d.rectangle([15, 17, 17, 25], fill=(140, 146, 156, 255))
    d.rectangle([14, 3, 18, 6], fill=(200, 40, 40, 255))


def chevrons(n):
    def g(d):
        gold = (240, 200, 70, 255)
        for i in range(n):
            y = 20 - i * 6
            d.line([(7, y), (16, y - 6), (25, y)], fill=gold, width=3)
    return g


def g_flame(d):
    d.polygon([(16, 3), (24, 15), (24, 22), (16, 28), (8, 22), (8, 14), (12, 17)], fill=(235, 90, 30, 255))
    d.polygon([(16, 12), (20, 20), (16, 25), (12, 21)], fill=(255, 210, 80, 255))


def g_golem(d, col=(140, 130, 118, 255), eyes=(120, 230, 255, 255)):
    d.rectangle([7, 6, 25, 26], fill=col)
    d.rectangle([7, 6, 25, 9], fill=tuple(max(0, c - 25) for c in col[:3]) + (255,))
    d.rectangle([10, 13, 13, 15], fill=eyes)
    d.rectangle([19, 13, 22, 15], fill=eyes)
    d.rectangle([11, 20, 21, 22], fill=(60, 55, 50, 255))


def g_bat(d):
    c = (70, 50, 90, 255)
    d.polygon([(3, 12), (10, 10), (13, 14), (16, 11), (19, 14), (22, 10), (29, 12), (25, 20), (21, 17), (16, 22), (11, 17), (7, 20)], fill=c)
    d.rectangle([13, 13, 14, 14], fill=(255, 80, 80, 255))
    d.rectangle([18, 13, 19, 14], fill=(255, 80, 80, 255))


def g_dagger(d):
    d.polygon([(16, 3), (19, 8), (18, 20), (14, 20), (13, 8)], fill=(210, 220, 230, 255))
    d.rectangle([10, 20, 22, 22], fill=(200, 160, 60, 255))
    d.rectangle([14, 23, 18, 28], fill=(110, 70, 40, 255))


def g_coin(d):
    d.ellipse([6, 6, 26, 26], fill=(240, 196, 60, 255))
    d.ellipse([9, 9, 23, 23], fill=(222, 170, 40, 255))
    d.rectangle([15, 11, 17, 21], fill=(255, 230, 130, 255))


def g_coins(d):
    for i, (x, y) in enumerate([(4, 15), (13, 11), (12, 18)]):
        d.ellipse([x, y, x + 14, y + 9], fill=(240, 196, 60, 255))
        d.ellipse([x + 2, y + 1, x + 12, y + 6], fill=(255, 220, 110, 255))


def g_chest(d):
    d.rectangle([5, 14, 27, 26], fill=(150, 95, 45, 255))
    d.pieslice([5, 6, 27, 22], 180, 360, fill=(170, 110, 55, 255))
    d.rectangle([5, 13, 27, 15], fill=(220, 180, 70, 255))
    d.rectangle([14, 13, 18, 19], fill=(240, 210, 90, 255))
    for x in (8, 12, 20, 24):
        d.rectangle([x, 9, x + 1, 10], fill=(255, 230, 120, 255))


def g_flower(d):
    stem = (70, 140, 60, 255)
    d.line([(16, 14), (16, 28)], fill=stem, width=2)
    d.polygon([(16, 22), (22, 18), (20, 23)], fill=stem)
    for i, y in enumerate(range(4, 16, 3)):
        d.ellipse([13, y, 19, y + 4], fill=(170, 120, 220, 255) if i % 2 == 0 else (200, 150, 240, 255))


def g_axe(d):
    d.line([(9, 27), (22, 6)], fill=(130, 85, 45, 255), width=3)
    d.polygon([(17, 5), (27, 8), (25, 17), (19, 12)], fill=(200, 205, 215, 255))


def g_pick(d):
    d.line([(10, 27), (20, 9)], fill=(130, 85, 45, 255), width=3)
    d.arc([6, 3, 30, 22], 200, 330, fill=(190, 195, 205, 255), width=3)


def g_berries(d):
    d.line([(16, 4), (16, 10)], fill=(70, 140, 60, 255), width=2)
    d.polygon([(16, 8), (24, 4), (21, 10)], fill=(80, 160, 70, 255))
    for x, y in ((9, 12), (17, 12), (13, 19), (21, 19)):
        d.ellipse([x, y, x + 7, y + 7], fill=(210, 40, 60, 255))
        d.rectangle([x + 2, y + 2, x + 2, y + 2], fill=(255, 160, 170, 255))


def g_monolith(d):
    d.polygon([(11, 28), (12, 6), (16, 3), (20, 6), (21, 28)], fill=(70, 75, 90, 255))
    d.line([(16, 8), (16, 24)], fill=(110, 220, 255, 255), width=1)
    d.line([(13, 14), (19, 14)], fill=(110, 220, 255, 255), width=1)
    d.rectangle([5, 27, 27, 28], fill=(90, 130, 70, 255))


def g_target(d):
    for r, c in ((12, (220, 60, 50, 255)), (9, (240, 235, 225, 255)), (6, (220, 60, 50, 255)), (3, (240, 235, 225, 255))):
        d.ellipse([16 - r, 16 - r, 16 + r, 16 + r], fill=c)


def g_crack(d):
    d.polygon([(4, 26), (28, 26), (28, 22), (4, 22)], fill=(130, 110, 85, 255))
    d.line([(16, 4), (12, 11), (19, 15), (13, 22)], fill=(250, 220, 90, 255), width=3)


def g_pin(d):
    d.ellipse([6, 4, 26, 24], fill=(70, 150, 220, 255))
    d.polygon([(16, 7), (18, 12), (23, 12), (19, 15), (21, 20), (16, 17), (11, 20), (13, 15), (9, 12), (14, 12)], fill=(255, 225, 90, 255))
    d.polygon([(12, 22), (20, 22), (16, 29)], fill=(70, 150, 220, 255))


def g_insignia(d):
    d.polygon([(6, 5), (26, 5), (26, 16), (16, 28), (6, 16)], fill=(150, 40, 40, 255))
    d.line([(10, 9), (22, 21)], fill=(230, 210, 170, 255), width=2)
    d.line([(22, 9), (10, 21)], fill=(230, 210, 170, 255), width=2)


def g_gold_nugget(d):
    d.polygon([(6, 20), (9, 10), (17, 6), (26, 11), (27, 21), (17, 26)], fill=(235, 190, 50, 255))
    d.polygon([(9, 10), (17, 6), (19, 12), (12, 14)], fill=(255, 235, 140, 255))


ICONS = {
    "BANDIT_BASHER": g_insignia, "FIRST_BLOOD": g_drop, "mossback_beat": g_mossy_rock,
    "knights_to_meet_ya": g_helmet, "level_5": chevrons(1), "level_8": chevrons(2),
    "level_max": chevrons(3), "slayer_25": g_crossed_swords, "slayer_100": g_skull,
    "dragonslayer": g_flame, "rock_bottom": g_golem, "fools_gold": g_gold_nugget,
    "batty": g_bat, "highway_cleaner": g_dagger, "pocket_change": g_coin,
    "fat_purse": g_coins, "tycoon": g_chest, "herbalist": g_flower,
    "lumberjack": g_axe, "quarryman": g_pick, "berry_picker": g_berries,
    "awakening": g_monolith, "practice_makes_perfect": g_target,
    "rumble_in_the_quarry": g_crack, "pin_collector": g_pin,
}


def main():
    force = "--force" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    for name, draw in ICONS.items():
        path = os.path.join(OUT, name + ".png")
        if os.path.exists(path) and not force:
            continue
        img, d = canvas()
        draw(d)
        img = shade(img)
        img = outline(img)
        img.save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
