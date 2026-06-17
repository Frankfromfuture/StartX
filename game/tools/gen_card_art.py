#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate detailed pixel-art (black & gray) card emblems as SVG.

Covers every card in the first two booster packs (garage_pack + hiring_fair)
plus the starting founder. 16x16 grid, one <rect> per horizontal run.

Style: silhouette + 1px auto black outline + 2~4 gray shading bands,
crisp pixels. Drawn in code so shapes stay symmetric and consistent.
"""
import os

N = 16
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "svg", "cards")

# palette: letter -> hex (None = transparent)
PAL = {
    ".": None,
    "o": "#161616",   # outline / ink
    "1": "#333333",   # darkest fill
    "2": "#525252",
    "3": "#727272",
    "4": "#969696",
    "5": "#b8b8b8",
    "6": "#dcdcdc",
    "7": "#f2f2f2",   # highlight
}


class C:
    def __init__(self):
        self.g = [["." for _ in range(N)] for _ in range(N)]

    def px(self, x, y, c):
        if 0 <= x < N and 0 <= y < N and c is not None:
            self.g[y][x] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.px(x, y, c)

    def hline(self, x0, x1, y, c):
        for x in range(x0, x1 + 1):
            self.px(x, y, c)

    def vline(self, x, y0, y1, c):
        for y in range(y0, y1 + 1):
            self.px(x, y, c)

    def disc(self, cx, cy, r, c):
        for y in range(N):
            for x in range(N):
                # use half-pixel centers for rounder look
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + r * 0.55:
                    self.px(x, y, c)

    def outline(self, col="o"):
        """Wrap the filled region with a 1px outline (4-neighbourhood)."""
        filled = [[self.g[y][x] != "." for x in range(N)] for y in range(N)]
        for y in range(N):
            for x in range(N):
                if filled[y][x]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < N and 0 <= ny < N and filled[ny][nx]:
                        self.g[y][x] = col
                        break

    def svg(self, pal=None):
        pal = pal or PAL
        runs = []
        for y in range(N):
            x = 0
            while x < N:
                c = self.g[y][x]
                if c == ".":
                    x += 1
                    continue
                x2 = x
                while x2 + 1 < N and self.g[y][x2 + 1] == c:
                    x2 += 1
                runs.append((x, y, x2 - x + 1, pal[c]))
                x = x2 + 1
        body = "".join(
            '<rect x="%d" y="%d" width="%d" height="1" fill="%s"/>' % (x, y, w, col)
            for (x, y, w, col) in runs
        )
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" '
            'viewBox="0 0 16 16" shape-rendering="crispEdges">%s</svg>' % body
        )


# ---------------------------------------------------------------- shared bits
def head(c, cx, cy, hair="1", skin="5", shade="3", light="6"):
    """A small head: hair cap + face + simple features."""
    c.disc(cx, cy, 3, skin)
    # hair on top
    for y in range(cy - 4, cy):
        for x in range(cx - 3, cx + 4):
            if (x - cx) ** 2 + (y - cy) ** 2 <= 11:
                c.px(x, y, hair)
    c.hline(cx - 2, cx + 2, cy - 4, hair)
    # shading on right cheek
    c.vline(cx + 2, cy - 1, cy + 2, shade)
    c.px(cx + 1, cy + 2, shade)
    # cheek highlight + eyes
    c.px(cx - 2, cy - 1, light)
    c.px(cx - 1, cy, "o")
    c.px(cx + 1, cy, "o")


def torso(c, x0, x1, top, bot, fill="2", shade="1", light="3"):
    c.rect(x0, top, x1, bot, fill)
    c.vline(x0, top, bot, light)
    c.vline(x1, top, bot, shade)


# ------------------------------------------------------------------- emblems
def founder():
    c = C()
    # star badge (mark of the founder)
    c.px(8, 0, "7"); c.hline(7, 9, 1, "7"); c.px(8, 2, "6")
    head(c, 8, 6, hair="o", skin="5")
    torso(c, 4, 12, 11, 15, fill="2", shade="1", light="3")
    # collar + tie
    c.px(7, 11, "6"); c.px(9, 11, "6")
    c.vline(8, 11, 14, "o")
    c.px(8, 12, "1")
    c.outline()
    return c


def intern():
    c = C()
    head(c, 8, 6, hair="2", skin="6")
    torso(c, 4, 12, 11, 15, fill="4", shade="2", light="5")
    # name-badge / lanyard
    c.vline(7, 11, 13, "o")
    c.rect(6, 13, 9, 14, "7"); c.px(7, 13, "3")
    c.outline()
    return c


def grad():
    c = C()
    head(c, 8, 8, hair="1", skin="5")
    # mortarboard cap
    c.rect(3, 3, 13, 4, "o")
    c.rect(5, 2, 11, 2, "1")
    c.hline(4, 12, 5, "2")
    c.px(8, 1, "1"); c.px(8, 0, "1")        # button
    c.vline(13, 4, 7, "o"); c.px(13, 8, "7")  # tassel
    torso(c, 5, 11, 13, 15, fill="2", shade="1", light="3")
    c.outline()
    return c


def cash():
    c = C()
    # three detailed banknote bundles side by side (a money pile)
    bundles = ((1, 4, 9), (6, 9, 6), (11, 14, 9))
    for x0, x1, top in bundles:
        c.rect(x0, top, x1, 14, "4")          # body of the stack
        c.hline(x0, x1, top, "6")             # bright top bill edge
        c.vline(x0, top, 14, "6")             # left highlight
        c.vline(x1, top, 14, "2")             # right shade
        for y in range(top + 1, 15, 2):       # individual bill seams
            c.hline(x0, x1, y, "2")
        # paper strap across the middle of the bundle
        my = (top + 14) // 2
        c.hline(x0, x1, my, "3")
        c.hline(x0, x1, my + 1, "3")
    # tiny $ on the tall middle bundle's strap
    mx = 7
    c.vline(mx, 9, 11, "7")
    c.px(mx - 1, 9, "7"); c.px(mx - 1, 11, "7"); c.px(mx + 1, 10, "7")
    c.outline()
    return c


def customer_pool():
    c = C()
    # three distinct people side by side (a customer base / crowd)
    for cx, hf, bf, sh in ((3, "4", "3", "1"), (13, "4", "3", "1"), (8, "5", "4", "2")):
        c.disc(cx, 6, 2, hf)
        torso(c, cx - 2, cx + 2, 9, 14, fill=bf, shade=sh, light=hf)
    # carve 1px gaps so heads read separately (outline fills them)
    c.vline(5, 0, 15, ".")
    c.vline(10, 0, 15, ".")
    c.outline()
    return c


def oss_repo():
    c = C()
    # code window </>  with branch nodes
    c.rect(1, 2, 14, 13, "1")
    c.rect(2, 5, 13, 12, "5")
    c.hline(2, 13, 4, "3")
    c.px(3, 3, "6"); c.px(5, 3, "6"); c.px(7, 3, "6")  # title dots
    # < / >
    c.px(4, 8, "o"); c.px(3, 9, "o"); c.px(4, 10, "o")
    c.px(11, 8, "o"); c.px(12, 9, "o"); c.px(11, 10, "o")
    c.px(8, 7, "o"); c.px(7, 9, "o"); c.px(8, 11, "o")
    c.outline()
    return c


def archive():
    c = C()
    # filing cabinet with two drawers
    c.rect(2, 1, 13, 14, "3")
    c.rect(2, 1, 13, 7, "4")
    c.rect(2, 8, 13, 14, "3")
    c.hline(2, 13, 7, "o")
    c.rect(6, 4, 9, 5, "6")    # handle top
    c.rect(6, 11, 9, 12, "6")  # handle bottom
    c.vline(2, 1, 14, "5"); c.vline(13, 1, 14, "1")
    c.outline()
    return c


def doc():
    c = C()
    # single sheet with folded corner + text lines
    c.rect(3, 1, 12, 15, "6")
    c.vline(3, 1, 15, "7"); c.vline(12, 1, 15, "4")
    # folded corner
    c.px(11, 1, "."); c.px(12, 1, "."); c.px(12, 2, ".")
    c.px(11, 1, "4"); c.px(11, 2, "3"); c.px(12, 2, "3")
    for y in (4, 6, 8, 10, 12):
        c.hline(5, 10, y, "2")
    c.outline()
    return c


def sales_kit():
    c = C()
    # briefcase (skill kit) with handshake star
    c.rect(2, 5, 13, 14, "3")
    c.rect(2, 5, 13, 7, "4")
    c.rect(6, 2, 9, 4, "2")       # handle
    c.rect(7, 3, 8, 4, "5")
    c.hline(2, 13, 9, "o")
    c.rect(7, 8, 8, 11, "6")      # clasp
    c.vline(2, 5, 14, "4"); c.vline(13, 5, 14, "1")
    c.outline()
    return c


def dev_kit():
    c = C()
    # wrench + gear (engineering kit)
    c.disc(10, 6, 3, "3")
    c.disc(10, 6, 1, "6")
    for dx, dy in ((10, 2), (10, 10), (6, 6), (14, 6), (7, 3), (13, 3), (7, 9), (13, 9)):
        c.px(dx, dy, "3")
    # wrench shaft
    for i in range(6):
        c.px(4 + i, 13 - i, "5")
        c.px(5 + i, 13 - i, "4")
    c.px(3, 14, "5"); c.px(4, 14, "5"); c.px(3, 13, "5")
    c.outline()
    return c


def lead():
    c = C()
    # magnifying glass over a target dot (a sales lead)
    c.disc(6, 6, 4, "5")
    c.disc(6, 6, 3, "6")
    c.disc(6, 6, 2, "5")
    c.disc(6, 6, 1, "o")     # the lead
    # handle
    for i in range(5):
        c.px(10 + i, 10 + i, "2")
        c.px(11 + i, 10 + i, "1")
    c.outline()
    return c


def university():
    c = C()
    # classical building: pediment + columns
    c.px(8, 1, "5")
    for i in range(6):
        c.hline(8 - i - 1, 8 + i, 2 + i, "4")  # roof triangle
    c.hline(2, 13, 7, "3")     # entablature
    c.rect(2, 7, 13, 8, "5")
    for x in (3, 6, 9, 12):    # columns
        c.vline(x, 9, 13, "5")
        c.px(x + 1, 9, "2")
    c.rect(1, 14, 14, 15, "3") # base
    c.outline()
    return c


def market_kit():
    c = C()
    # megaphone (marketing kit)
    c.rect(3, 6, 5, 9, "2")          # body back
    for i in range(6):
        c.vline(6 + i, 5 - i // 2, 10 + i // 2, "4")
    c.vline(11, 3, 12, "5")
    c.rect(11, 3, 12, 12, "5")
    c.px(11, 3, "6")
    c.vline(4, 9, 13, "2")           # handle
    # sound waves
    c.px(14, 5, "3"); c.px(15, 7, "3"); c.px(14, 9, "3")
    c.outline()
    return c


def admin_kit():
    c = C()
    # clipboard (admin kit)
    c.rect(2, 2, 13, 15, "4")
    c.rect(3, 3, 12, 14, "6")
    c.rect(6, 1, 9, 3, "2")      # clip
    c.rect(7, 1, 8, 2, "5")
    for y in (6, 8, 10, 12):
        c.hline(5, 11, y, "2")
    c.px(4, 6, "o"); c.px(4, 8, "o")  # check marks
    c.vline(2, 2, 15, "5"); c.vline(13, 2, 15, "2")
    c.outline()
    return c


def talent_pool():
    c = C()
    # podium / ranking of candidates: three pillars topped by heads, star on the winner
    pillars = ((3, 5, 9, "3"), (7, 9, 5, "5"), (11, 13, 8, "4"))
    for x0, x1, top, f in pillars:
        c.rect(x0, top, x1, 13, f)
        c.vline(x0, top, 13, "2")
    # heads on top of each pillar
    c.disc(4, 7, 1, "4")
    c.disc(8, 3, 2, "6")     # winner, larger
    c.disc(12, 6, 1, "4")
    # star above the winner
    c.px(8, 0, "7"); c.px(7, 1, "7"); c.px(9, 1, "7")
    c.rect(1, 14, 15, 15, "2")   # ground
    c.outline()
    return c


def meeting_room():
    c = C()
    # conference table (top view) with chairs
    c.disc(8, 8, 5, "3")
    c.disc(8, 8, 4, "4")
    c.rect(5, 7, 10, 9, "5")     # table sheen
    for cx, cy in ((8, 1), (8, 14), (1, 8), (14, 8), (3, 3), (13, 3), (3, 13), (13, 13)):
        c.disc(cx, cy, 1, "2")
    c.outline()
    return c


def data_kit():
    c = C()
    # bar chart + axis (data kit)
    c.vline(2, 2, 13, "2")       # y axis
    c.hline(2, 14, 13, "2")      # x axis
    bars = ((4, 9), (6, 6), (8, 10), (10, 4), (12, 7))
    for x, top in bars:
        c.rect(x, top, x + 1, 12, "5")
        c.vline(x, top, 12, "6")
    # trend dots
    c.px(4, 7, "o"); c.px(7, 5, "o"); c.px(10, 3, "o"); c.px(13, 5, "o")
    c.outline()
    return c


def finance_kit():
    c = C()
    # coins stack + up arrow (finance kit)
    for i, fy in enumerate((12, 9, 6)):
        c.disc(5, fy, 3, ("4", "5", "6")[i])
        c.hline(3, 7, fy, ("3", "4", "5")[i])
    c.vline(5, 4, 13, "o")          # $ on top coin
    c.px(4, 6, "o"); c.px(6, 5, "o")
    # rising arrow
    for i in range(5):
        c.px(9 + i, 12 - i, "2")
        c.px(10 + i, 12 - i, "1")
    c.px(13, 5, "2"); c.px(14, 6, "2"); c.px(12, 7, "2")  # arrow head
    c.outline()
    return c


# ----------------------------------------------------- pack-1 economy emblems
def neighborhood():
    c = C()
    # two little houses side by side (a residential block)
    def house(x0, roofc, wallc):
        for i in range(4):
            c.hline(x0 + 3 - i, x0 + 3 + i, 4 + i, roofc)  # roof
        c.rect(x0, 8, x0 + 6, 14, wallc)                    # wall
        c.rect(x0 + 2, 10, x0 + 4, 14, "1")                 # door
        c.px(x0 + 1, 9, "7"); c.px(x0 + 5, 9, "7")          # windows
    house(1, "2", "5")
    house(9, "3", "4")
    c.rect(0, 15, 15, 15, "2")  # ground
    c.outline()
    return c


def wholesale():
    c = C()
    # market stall: striped awning over crates
    for x in range(2, 14):
        c.px(x, 3, "2" if (x // 2) % 2 == 0 else "5")
        c.px(x, 4, "2" if (x // 2) % 2 == 0 else "5")
    c.hline(2, 13, 5, "1")
    c.vline(2, 5, 14, "3"); c.vline(13, 5, 14, "3")  # posts
    # crates
    c.rect(4, 8, 7, 11, "4"); c.rect(8, 8, 11, 11, "5")
    c.rect(4, 11, 7, 14, "5"); c.rect(8, 11, 11, 14, "4")
    for x0 in (4, 8):
        for y0 in (8, 11):
            c.px(x0 + 1, y0 + 1, "2")
    c.outline()
    return c


def rawprod():
    c = C()
    # a plain rough cardboard cube (no wrapping)
    c.rect(3, 5, 12, 14, "4")           # front
    for i in range(3):                   # top face
        c.hline(3 + i, 12 - i, 4 - i, "5")
    for i in range(3):                   # right face
        c.vline(12 + i, 5 - i, 14 - i, "3")
    c.px(7, 9, "2"); c.px(8, 10, "2")    # rough scuffs
    c.hline(5, 10, 12, "3")
    c.outline()
    return c


def package():
    c = C()
    # wrapped parcel with ribbon cross + bow (the polished product)
    c.rect(3, 5, 12, 14, "5")
    for i in range(3):
        c.hline(3 + i, 12 - i, 4 - i, "6")
        c.vline(12 + i, 5 - i, 14 - i, "4")
    c.vline(7, 5, 14, "1"); c.vline(8, 5, 14, "1")  # ribbon vertical
    c.hline(3, 12, 9, "1"); c.hline(3, 12, 10, "1")  # ribbon horizontal
    c.px(6, 3, "o"); c.px(9, 3, "o")                 # bow
    c.rect(6, 4, 9, 4, "2"); c.px(7, 3, "2"); c.px(8, 3, "2")
    c.outline()
    return c


def office():
    c = C()
    # office building facade with window grid
    c.rect(2, 1, 13, 15, "4")
    c.rect(2, 1, 13, 2, "3")
    for wy in (4, 7, 10):
        for wx in (3, 6, 9):
            c.rect(wx, wy, wx + 1, wy + 1, "6")
            c.px(wx, wy, "7")
    c.rect(6, 12, 9, 15, "1")   # door
    c.px(8, 13, "6")
    c.vline(2, 1, 15, "5"); c.vline(13, 1, 15, "2")
    c.outline()
    return c


def customer():
    c = C()
    # a reliable customer: person bust with a check badge
    head(c, 7, 6, hair="1", skin="5")
    torso(c, 3, 11, 11, 15, fill="3", shade="1", light="4")
    # check badge bottom-right
    c.disc(12, 12, 2, "6")
    c.px(11, 12, "o"); c.px(12, 13, "o"); c.px(13, 11, "o"); c.px(14, 10, "o")
    c.outline()
    return c


def youth():
    c = C()
    # a young neighbourhood recruit: hoodie + casual cap
    c.disc(8, 7, 3, "5")                 # face
    c.rect(4, 3, 12, 4, "2")             # cap brim + crown
    c.hline(5, 11, 2, "2"); c.px(12, 4, "1")
    c.px(6, 7, "o"); c.px(9, 7, "o")     # eyes
    c.vline(10, 6, 8, "3")               # cheek shade
    torso(c, 4, 12, 11, 15, fill="3", shade="1", light="4")
    c.rect(7, 11, 8, 15, "2")            # hoodie zip
    c.px(5, 11, "1"); c.px(11, 11, "1")  # hood shoulders
    c.outline()
    return c


# ------------------------------------------------- booster-pack cover emblem
def garage_pack():
    # 车库创业包：山墙车库 + 卷帘门 + 阁楼圆窗 + 灯泡点子（白/灰，画在黑卡包上）
    c = C()
    # 灯泡（点子）顶上一点点
    c.px(8, 0, "5")
    # 山墙屋顶（三角）
    roof = [(7, 8, 1), (6, 9, 2), (5, 10, 3), (4, 11, 4)]
    for x0, x1, y in roof:
        c.hline(x0, x1, y, "2")
    c.hline(4, 11, 4, "4")          # 屋檐高光
    # 阁楼圆窗
    c.rect(7, 2, 8, 3, "5")
    # 车库主体
    c.rect(3, 5, 12, 14, "2")
    c.vline(3, 5, 14, "4")          # 左高光
    c.vline(12, 5, 14, "1")         # 右暗
    # 卷帘门
    c.rect(5, 7, 10, 14, "3")
    for y in (8, 10, 12):           # 卷帘横缝
        c.hline(5, 10, y, "1")
    c.vline(5, 7, 14, "4")
    c.vline(10, 7, 14, "1")
    c.px(7, 13, "1"); c.px(8, 13, "1")   # 把手
    # 地面/车道
    c.rect(2, 15, 13, 15, "1")
    c.outline("o")
    return c


# pack-cover palette: white/gray on the black pack body (matches existing packs)
PACK_PAL = {
    ".": None,
    "o": "#f2f2f2",
    "1": "#565656",
    "2": "#9c9c9c",
    "3": "#c8c8c8",
    "4": "#f2f2f2",
    "5": "#ffffff",
    "6": "#ffffff",
    "7": "#ffffff",
}


CARDS = {
    "founder": founder,
    "intern": intern,
    "grad": grad,
    "cash": cash,
    "customer_pool": customer_pool,
    "oss_repo": oss_repo,
    "archive": archive,
    "sales_kit": sales_kit,
    "dev_kit": dev_kit,
    "doc": doc,
    "lead": lead,
    "university": university,
    "market_kit": market_kit,
    "admin_kit": admin_kit,
    "talent_pool": talent_pool,
    "meeting_room": meeting_room,
    "data_kit": data_kit,
    "finance_kit": finance_kit,
    # pack-1 economy (fresh p1_* ids)
    "p1_neighborhood": neighborhood,
    "p1_youth": youth,
    "p1_survey": admin_kit,
    "p1_customer": customer,
    "p1_university": university,
    "p1_intern": intern,
    "p1_wholesale": wholesale,
    "p1_rawprod": rawprod,
    "p1_marketing": market_kit,
    "p1_package": package,
    "p1_office": office,
}


# golden palette for the cash emblem (keys mirror PAL)
GOLD = {
    ".": None,
    "o": "#3a2806",
    "1": "#6e4f11",
    "2": "#946c16",
    "3": "#bb8a1d",
    "4": "#dca72b",
    "5": "#f0c54a",
    "6": "#ffdd76",
    "7": "#fff2bd",
}

# knocked-out (反白) palette for the founder emblem on its black card
FOUNDER = {
    ".": None,
    "o": "#8c8c8c",   # outline / inner lines -> mid gray (reads on white & on black)
    "1": "#d2d2d2",
    "2": "#e0e0e0",
    "3": "#ededed",
    "4": "#f6f6f6",
    "5": "#ffffff",
    "6": "#ffffff",
    "7": "#ffffff",
}

PALETTE_OVERRIDE = {"cash": GOLD, "founder": FOUNDER}


PACKS_OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "svg", "packs")
PACKS = {"garage_pack": garage_pack}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in CARDS.items():
        svg = fn().svg(PALETTE_OVERRIDE.get(name))
        with open(os.path.join(OUT, name + ".svg"), "w") as f:
            f.write(svg)
        print("wrote", name + ".svg")
    os.makedirs(PACKS_OUT, exist_ok=True)
    for name, fn in PACKS.items():
        svg = fn().svg(PACK_PAL)
        with open(os.path.join(PACKS_OUT, name + ".svg"), "w") as f:
            f.write(svg)
        print("wrote packs/" + name + ".svg")


if __name__ == "__main__":
    main()
