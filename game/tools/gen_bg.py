#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the board backgrounds.

  bg_office.png  -> active canvas: empty one-floor office cross-section.
                    grid-tile floor, perimeter walls with windows + a door,
                    NO furniture.  (2.5D look comes from the board's quad warp)
  bg_street.png  -> outside the canvas: top-down city — roads, building
                    rooftops, sidewalks, crosswalks, street lamps, trees.

Cozy morandi / comic palette to match the cards.  Pure PIL, deterministic.
"""
import os
import random
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "assets")


def hx(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- empty office
def gen_office(path):
    W, H = 1820, 864
    img = Image.new("RGB", (W, H), hx("#e8e4db"))
    d = ImageDraw.Draw(img)

    WALL = hx("#efe9dc")      # cream wall
    WALL_SH = hx("#ded6c4")   # wall shadow / baseboard
    GLASS = hx("#cfe0e8")     # window glass
    GLASS2 = hx("#bcd4e0")    # glass lower band
    FRAME = hx("#c7bda8")     # window/door frame
    INK = hx("#3a352f")
    DOOR = hx("#b89a6a")
    DOOR_SH = hx("#9c7e50")

    TW = 168                  # top wall band height
    SW = 46                   # side wall strip width

    # ---- floor: warm grid tiles ----
    t1 = hx("#e9e5dc")
    t2 = hx("#e2ddd1")
    grout = hx("#d3ccbb")
    tile = 84
    for gy, y in enumerate(range(TW, H, tile)):
        for gx, x in enumerate(range(0, W, tile)):
            col = t1 if (gx + gy) % 2 == 0 else t2
            d.rectangle([x, y, x + tile - 1, y + tile - 1], fill=col)
    # grout lines
    for x in range(0, W + 1, tile):
        d.line([(x, TW), (x, H)], fill=grout, width=2)
    for y in range(TW, H + 1, tile):
        d.line([(0, y), (W, y)], fill=grout, width=2)
    # soft shading near the back wall (depth)
    shade = Image.new("RGBA", (W, 120), (90, 84, 72, 0))
    sd = ImageDraw.Draw(shade)
    for i in range(120):
        a = int(46 * (1 - i / 120))
        sd.line([(0, i), (W, i)], fill=(90, 84, 72, a))
    img.paste(Image.alpha_composite(
        img.crop((0, TW, W, TW + 120)).convert("RGBA"), shade).convert("RGB"),
        (0, TW))

    # ---- side walls (thin recessed strips) ----
    for x0 in (0, W - SW):
        d.rectangle([x0, TW, x0 + SW, H], fill=WALL_SH)
    # small windows on side walls
    for x0, inner in ((6, True), (W - SW + 6, False)):
        for wy in range(TW + 70, H - 120, 230):
            d.rectangle([x0, wy, x0 + SW - 12, wy + 130], fill=FRAME)
            d.rectangle([x0 + 4, wy + 4, x0 + SW - 16, wy + 126], fill=GLASS)
            d.line([(x0 + 4, wy + 65), (x0 + SW - 16, wy + 65)], fill=FRAME, width=3)

    # ---- back wall ----
    d.rectangle([0, 0, W, TW], fill=WALL)
    # baseboard / wall-floor seam
    d.rectangle([0, TW - 12, W, TW], fill=WALL_SH)
    d.line([(0, TW), (W, TW)], fill=INK, width=3)

    # door slot (centered)
    door_w, door_h = 150, 150
    dx = W // 2 - door_w // 2
    dy = TW - door_h
    d.rectangle([dx - 8, dy - 8, dx + door_w + 8, TW], fill=FRAME)
    d.rectangle([dx, dy, dx + door_w, TW], fill=DOOR)
    d.rectangle([dx, dy, dx + door_w, TW], outline=DOOR_SH, width=4)
    # door panels
    d.rectangle([dx + 18, dy + 16, dx + door_w - 18, dy + door_h // 2 - 8], outline=DOOR_SH, width=4)
    d.rectangle([dx + 18, dy + door_h // 2 + 4, dx + door_w - 18, TW - 16], outline=DOOR_SH, width=4)
    d.ellipse([dx + door_w - 30, dy + door_h // 2 - 8, dx + door_w - 16, dy + door_h // 2 + 6], fill=hx("#e8d28a"))

    # windows across the back wall, skipping the door zone
    win_w, win_h = 230, 116
    gap = 56
    wy = 28
    x = SW + 30
    while x + win_w < W - SW - 30:
        if not (x + win_w > dx - 40 and x < dx + door_w + 40):
            d.rectangle([x - 6, wy - 6, x + win_w + 6, wy + win_h + 6], fill=FRAME)
            d.rectangle([x, wy, x + win_w, wy + win_h], fill=GLASS)
            d.rectangle([x, wy + win_h // 2, x + win_w, wy + win_h], fill=GLASS2)
            # mullions
            d.line([(x + win_w // 2, wy), (x + win_w // 2, wy + win_h)], fill=FRAME, width=4)
            d.line([(x, wy + win_h // 2), (x + win_w, wy + win_h // 2)], fill=FRAME, width=4)
            # sill
            d.rectangle([x - 10, wy + win_h + 6, x + win_w + 10, wy + win_h + 16], fill=WALL_SH)
        x += win_w + gap

    # outer frame ink line of the whole office
    d.rectangle([0, 0, W - 1, H - 1], outline=INK, width=4)

    img.save(path)
    print("wrote", path, img.size)


# ---------------------------------------------------------------- street (top-down)
def gen_street(path, seed=7):
    rnd = random.Random(seed)
    W, H = 1536, 1120
    GROUND = hx("#9fb0a6")     # grass/ground base
    ROAD = hx("#8a8f95")       # asphalt
    ROAD_D = hx("#7c8187")
    SIDEWALK = hx("#cdc6b6")
    LINE = hx("#e8e2d0")       # road markings
    img = Image.new("RGB", (W, H), GROUND)
    d = ImageDraw.Draw(img)

    roof_pal = ["#b9a98f", "#a9bcc4", "#c2a9a2", "#b3b59a", "#9aa7b8",
                "#c8b894", "#a7b3a0", "#bfae9d"]

    # road grid
    road_w = 150
    block = 340
    vroads = list(range(-80, W + block, block))
    hroads = list(range(-60, H + block, block))

    def on_road(px, py):
        for vx in vroads:
            if vx <= px <= vx + road_w:
                return True
        for hy in hroads:
            if hy <= py <= hy + road_w:
                return True
        return False

    # building blocks first (between roads)
    for bi in range(len(vroads) - 1):
        for bj in range(len(hroads) - 1):
            x0 = vroads[bi] + road_w
            y0 = hroads[bj] + road_w
            x1 = vroads[bi + 1]
            y1 = hroads[bj + 1]
            if x1 - x0 < 30 or y1 - y0 < 30:
                continue
            # sidewalk around the block
            d.rectangle([x0, y0, x1, y1], fill=SIDEWALK)
            # split block into 1-2 buildings
            pad = 18
            bx0, by0, bx1, by1 = x0 + pad, y0 + pad, x1 - pad, y1 - pad
            splits = []
            if (bx1 - bx0) > 220 and rnd.random() < 0.6:
                mid = rnd.randint(bx0 + 80, bx1 - 80)
                splits = [(bx0, by0, mid - 8, by1), (mid + 8, by0, bx1, by1)]
            else:
                splits = [(bx0, by0, bx1, by1)]
            for (rx0, ry0, rx1, ry1) in splits:
                if rx1 - rx0 < 24 or ry1 - ry0 < 24:
                    continue
                roof = hx(rnd.choice(roof_pal))
                d.rectangle([rx0, ry0, rx1, ry1], fill=roof)
                # roof rim shadow (gives a touch of height)
                d.rectangle([rx0, ry0, rx1, ry1], outline=hx("#6f6a5e"), width=3)
                d.line([(rx0 + 3, ry1 - 4), (rx1 - 3, ry1 - 4)],
                       fill=hx("#7d7565"), width=6)
                # rooftop detail: AC units / skylights
                for _ in range(rnd.randint(1, 3)):
                    ux = rnd.randint(rx0 + 12, max(rx0 + 13, rx1 - 30))
                    uy = rnd.randint(ry0 + 12, max(ry0 + 13, ry1 - 30))
                    d.rectangle([ux, uy, ux + 22, uy + 18], fill=hx("#cfc9bb"),
                                outline=hx("#8a8275"), width=2)

    # roads on top
    for vx in vroads:
        d.rectangle([vx, 0, vx + road_w, H], fill=ROAD)
    for hy in hroads:
        d.rectangle([0, hy, W, hy + road_w], fill=ROAD)
    # intersections slightly darker
    for vx in vroads:
        for hy in hroads:
            d.rectangle([vx, hy, vx + road_w, hy + road_w], fill=ROAD_D)
    # center dashed lane lines
    for vx in vroads:
        cx = vx + road_w // 2
        for y in range(0, H, 60):
            d.rectangle([cx - 3, y, cx + 3, y + 32], fill=LINE)
    for hy in hroads:
        cy = hy + road_w // 2
        for x in range(0, W, 60):
            d.rectangle([x, cy - 3, x + 32, cy + 3], fill=LINE)
    # crosswalks near intersections
    for vx in vroads:
        for hy in hroads:
            for k in range(6):
                sx = vx + 14 + k * 22
                d.rectangle([sx, hy - 30, sx + 12, hy - 2], fill=LINE)
                d.rectangle([sx, hy + road_w + 2, sx + 12, hy + road_w + 30], fill=LINE)

    # street lamps + trees along sidewalk corners
    for vx in vroads[:-1]:
        for hy in hroads[:-1]:
            cx = vx + road_w + 26
            cy = hy + road_w + 26
            # lamp glow + post
            d.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=hx("#f0e6b8"))
            d.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=hx("#fff6cf"),
                      outline=hx("#9c8f55"), width=2)
            # a tree at the opposite corner
            tx = vx - 26
            ty = hy - 26
            if tx > 6 and ty > 6:
                d.ellipse([tx - 20, ty - 20, tx + 20, ty + 20], fill=hx("#8fae87"),
                          outline=hx("#6f8c69"), width=3)
                d.ellipse([tx - 8, ty - 8, tx + 6, ty + 6], fill=hx("#a6c39d"))

    # a few cars on the roads
    car_cols = ["#c98f86", "#8fa9c4", "#cdbf8c", "#9fb6a4", "#b5a0c0"]
    for _ in range(40):
        if rnd.random() < 0.5:
            vx = rnd.choice(vroads)
            cx = vx + road_w // 2 + rnd.choice([-30, 30])
            cy = rnd.randint(0, H)
            if not on_road(cx, cy):
                continue
            d.rounded_rectangle([cx - 14, cy - 26, cx + 14, cy + 26], radius=8,
                                fill=hx(rnd.choice(car_cols)), outline=hx("#55514a"), width=2)
            d.rectangle([cx - 10, cy - 14, cx + 10, cy + 8], fill=hx("#4f5a63"))
        else:
            hy = rnd.choice(hroads)
            cy = hy + road_w // 2 + rnd.choice([-30, 30])
            cx = rnd.randint(0, W)
            if not on_road(cx, cy):
                continue
            d.rounded_rectangle([cx - 26, cy - 14, cx + 26, cy + 14], radius=8,
                                fill=hx(rnd.choice(car_cols)), outline=hx("#55514a"), width=2)
            d.rectangle([cx - 14, cy - 10, cx + 8, cy + 10], fill=hx("#4f5a63"))

    img.save(path)
    print("wrote", path, img.size)


if __name__ == "__main__":
    gen_office(os.path.join(OUT, "bg_office.png"))
    gen_street(os.path.join(OUT, "bg_street.png"))
