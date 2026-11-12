#!/usr/bin/env python3
"""
Galveston Mines art generator.

Paints every texture and sprite the game uses (plus normal maps so Godot's 2D
lights can light the rock in 3D) into assets/art/. Re-run after tweaking a
palette or shape:

    python tools/gen_art.py

Then open the project in Godot (or run `godot --headless --import`) so the
new PNGs get imported. Requires numpy + Pillow.
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "art"

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def hexc(s):
    s = s.lstrip("#")
    return [int(s[i:i + 2], 16) for i in (0, 2, 4)]


def ink(s, a=255):
    return tuple(hexc(s)) + (a,)


def norm(a):
    a = a - a.min()
    m = a.max()
    return a / m if m > 0 else a


def pnoise(w, h, cx, cy, rng):
    """Tileable value noise with cx x cy lattice cells."""
    lat = rng.random((cy, cx))
    x = np.arange(w) / w * cx
    y = np.arange(h) / h * cy
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    x1 = (x0 + 1) % cx
    y1 = (y0 + 1) % cy
    a = lat[y0[:, None], x0[None, :]]
    b = lat[y0[:, None], x1[None, :]]
    c = lat[y1[:, None], x0[None, :]]
    d = lat[y1[:, None], x1[None, :]]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(w, h, rng, cx=4, cy=4, octaves=4):
    v = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        kx, ky = min(cx * 2 ** o, w), min(cy * 2 ** o, h)
        v += amp * pnoise(w, h, kx, ky, rng)
        tot += amp
        amp *= 0.5
    return v / tot


def voronoi(w, h, n, rng, sx=1.0, sy=1.0):
    """Tileable Voronoi. Returns F1, F2 distances and cell index."""
    pts = rng.random((n, 2)) * [w, h]
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.abs(xx[..., None] - pts[:, 0])
    dx = np.minimum(dx, w - dx) * sx
    dy = np.abs(yy[..., None] - pts[:, 1])
    dy = np.minimum(dy, h - dy) * sy
    d = np.sqrt(dx * dx + dy * dy)
    s = np.sort(d, axis=2)
    return s[..., 0], s[..., 1], np.argmin(d, axis=2)


def grad(h, wrap=True):
    if wrap:
        gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
        gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    else:
        gy, gx = np.gradient(h)
    return gx, gy


def lambert(h, strength=6.0, wrap=True):
    gx, gy = grad(h, wrap)
    n = np.stack([-gx * strength, -gy * strength, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    light = np.array([-0.45, -0.75, 0.55])
    light /= np.linalg.norm(light)
    return np.clip((n * light).sum(-1), 0, 1)


def normal_map(h, strength=6.0, wrap=True, alpha=None):
    """OpenGL convention (green = up), as Godot expects."""
    gx, gy = grad(h, wrap)
    n = np.stack([-gx * strength, gy * strength, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    rgb = ((n * 0.5 + 0.5) * 255).astype(np.uint8)
    a = np.full(h.shape, 255, np.uint8) if alpha is None else alpha
    return np.dstack([rgb, a])


def ramp(colors, t, dither=0.7):
    """Maps 0..1 to a palette with ordered dithering (crisp pixel-art bands)."""
    pal = np.array([hexc(c) for c in colors], dtype=np.uint8)
    hh, ww = t.shape
    b = np.tile(BAYER4, (hh // 4 + 1, ww // 4 + 1))[:hh, :ww]
    tt = t * len(pal) + (b - 0.5) * dither
    idx = np.clip(np.floor(tt).astype(int), 0, len(pal) - 1)
    return pal[idx]


def save(rgb, path, alpha=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if alpha is None:
        alpha = np.full(rgb.shape[:2], 255, np.uint8)
    Image.fromarray(np.dstack([rgb.astype(np.uint8), alpha.astype(np.uint8)]), "RGBA").save(path)


def save_n(nrm, path):
    Image.fromarray(nrm, "RGBA").save(path)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------
# Level themes
# ---------------------------------------------------------------------------

WOOD = ["#160e08", "#24170d", "#352214", "#48301b", "#5e3f23", "#76512d", "#906639", "#a87c48"]
WOOD_CHAR = ["#0c0807", "#15100c", "#1f1711", "#2a1f16", "#37291c", "#463423", "#57422c", "#69513a"]

THEMES = [
    dict(key="shafts", rock=["#120c09", "#1d1410", "#2a1d16", "#38281d", "#4a3524", "#5e442e", "#755639", "#8e6a47", "#a8805a"],
         wood=WOOD, strata=0.22, chunks=12, ore=["#5a2a14", "#9a4a22", "#d9773a", "#f2a35e"]),
    dict(key="granite", rock=["#0b0c0f", "#13161b", "#1c2027", "#262c34", "#313943", "#3e4854", "#4f5b69", "#636f7e", "#7b8796"],
         wood=WOOD, strata=0.05, chunks=16, ore=["#3c4450", "#7d8a99", "#c3ccd6", "#eef2f6"]),
    dict(key="flooded", rock=["#070c0b", "#0d1513", "#141f1b", "#1b2a24", "#24372f", "#2f463c", "#3c584c", "#4c6d5f", "#638a78"],
         wood=WOOD_CHAR, strata=0.10, chunks=14, wet=True, ore=["#2a4a3c", "#3f7d63", "#6fc29a", "#b5f0d0"]),
    dict(key="coal", rock=["#060505", "#0c0a0a", "#131111", "#1a1717", "#221e1d", "#2c2725", "#38322f", "#47403c", "#5b524c"],
         wood=WOOD_CHAR, strata=0.08, chunks=20, glints=True, ore=["#4a1a08", "#a1380f", "#ef6a1f", "#ffc25a"]),
    dict(key="crystal", rock=["#08070d", "#0f0d16", "#171320", "#1f1a2b", "#292237", "#342c45", "#413756", "#51456b", "#655782"],
         wood=WOOD_CHAR, strata=0.04, chunks=10, veins="#8a6cff", ore=["#2c1f5c", "#5b3fc4", "#8f7dff", "#d4ccff"]),
    dict(key="halls", rock=["#0a0505", "#130909", "#1c0d0d", "#261212", "#311817", "#3e1f1d", "#4d2825", "#5f332f", "#753f39"],
         wood=WOOD_CHAR, strata=0.06, chunks=9, veins="#7a1414", ore=["#3a0808", "#7a1010", "#c42020", "#ff6050"]),
]


def rock_texture(th, rng, size=64, kind="front"):
    n_chunks = th["chunks"] if kind == "front" else int(th["chunks"] * 1.8)
    f1, f2, _ = voronoi(size, size, n_chunks, rng, sx=1.0, sy=1.25)
    cell = 1 - norm(f1) ** 0.8
    crack = 1 - smoothstep(0.0, 2.2, f2 - f1)
    noise = fbm(size, size, rng, 4, 4, 5)
    fine = fbm(size, size, rng, 16, 16, 2)
    hgt = 0.55 * cell + 0.30 * noise + 0.15 * fine
    if th["strata"]:
        yy = np.arange(size)[:, None] / size
        hgt += th["strata"] * np.sin((yy * 3 + noise * 0.6) * 2 * math.pi)
    hgt = norm(hgt) * (1 - 0.75 * crack)
    shade = lambert(hgt, 7.0)
    t = 0.55 * hgt + 0.45 * shade
    if kind == "back":
        t = t * 0.72
    else:
        t = 0.08 + t * 0.92
    rgb = ramp(th["rock"], np.clip(t, 0, 0.999)).astype(np.int32)
    if th.get("wet"):
        # Wet streaks running down the rock + specular highlights.
        streak = pnoise(size, size, 16, 2, rng)
        rgb = np.where((streak > 0.78)[..., None], (rgb * 0.75).astype(np.int32), rgb)
        spec = (shade > 0.93) & (hgt > 0.6)
        rgb[spec] = np.minimum(rgb[spec] + 45, 255)
    if th.get("glints"):
        g = (rng.random((size, size)) > 0.985) & (hgt > 0.55)
        rgb[g] = hexc("#8b8379")
    if th.get("veins"):
        v = (np.abs(pnoise(size, size, 4, 4, rng) - 0.5) < 0.012) & (crack < 0.5)
        vc = np.array(hexc(th["veins"]))
        rgb[v] = (rgb[v] * 0.72 + vc * 0.28).astype(np.int32)
    return np.clip(rgb, 0, 255), hgt


def floor_top(th, rng, w=64, h=16):
    rock = th["rock"]
    edge = 3 + (pnoise(w, 1, 8, 1, rng)[0] * 3).astype(int)
    rgb = np.zeros((h, w, 3), np.int32)
    alpha = np.zeros((h, w), np.int32)
    base = fbm(w, h, rng, 8, 2, 3)
    t = 0.35 + base * 0.3
    rgb[:] = ramp(rock, t)
    hgt = base * 0.3
    # Pebbles.
    img = Image.new("RGBA", (w, h))
    for _ in range(70):
        x = rng.integers(0, w)
        y = rng.integers(2, 11)
        r = rng.integers(1, 3)
        shade_i = rng.integers(3, len(rock))
        c = tuple(hexc(rock[shade_i])) + (255,)
        ImageDraw.Draw(img).ellipse([x - r, y - r * 0.7, x + r, y + r * 0.7], fill=c)
        for dx in (-w, w):
            ImageDraw.Draw(img).ellipse([x + dx - r, y - r * 0.7, x + dx + r, y + r * 0.7], fill=c)
    peb = np.array(img).astype(np.int32)
    pm = peb[..., 3] > 0
    rgb[pm] = peb[..., :3][pm]
    hgt = hgt + pm * 0.5
    for x in range(w):
        alpha[edge[x]:, x] = 255
        rgb[edge[x], x] = np.minimum(np.array(hexc(rock[-2])), 255)
    fade = np.clip((h - 1 - np.arange(h)) / 5.0, 0, 1)
    alpha = (alpha * fade[:, None]).astype(np.int32)
    return rgb, alpha, hgt


def ceiling_edge(th, rng, w=64, h=24):
    rock = th["rock"]
    length = 4 + pnoise(w, 1, 8, 1, rng)[0] * 5
    for _ in range(3):
        cx = rng.integers(0, w)
        ln = rng.integers(8, h - 2)
        for dx in range(-3, 4):
            x = (cx + dx) % w
            length[x] = max(length[x], ln * (1 - abs(dx) / 4))
    yy = np.arange(h)[:, None]
    mask = yy < length[None, :]
    noise = fbm(w, h, rng, 8, 4, 3)
    t = 0.45 - (yy / h) * 0.25 + noise * 0.3
    rgb = ramp(rock, np.clip(t, 0, 0.999)).astype(np.int32)
    tip = (yy >= length[None, :] - 1) & mask
    rgb[tip] = ramp(rock, np.full((1, 1), 0.15))[0, 0]
    alpha = (mask * 255).astype(np.int32)
    hgt = np.where(mask, 1 - yy / h, 0) + noise * 0.2
    return rgb, alpha, hgt


def rubble(th, rng, w=48, h=32):
    rock = th["rock"]
    f1, f2, cid = voronoi(w, h, 26, rng)
    yy, xx = np.mgrid[0:h, 0:w]
    mound = ((xx - w / 2) / (w / 2)) ** 2 + ((yy - h) / (h * 0.95)) ** 2
    jag = pnoise(w, h, 8, 4, rng) * 0.25
    inside = mound + jag < 1.0
    stone = 1 - norm(f1)
    crack = 1 - smoothstep(0, 1.6, f2 - f1)
    tone = (cid * 0.6180339) % 1.0
    hgt = (stone * 0.7 + (1 - mound) * 0.5) * (1 - 0.8 * crack)
    shade = lambert(hgt, 6.0, wrap=False)
    t = 0.15 + 0.45 * shade + 0.25 * tone + 0.15 * stone
    rgb = ramp(rock, np.clip(t, 0, 0.999)).astype(np.int32)
    alpha = (inside * 255).astype(np.int32)
    # Dark outline.
    edge = inside & ~(np.roll(inside, 1, 0) & np.roll(inside, -1, 0) & np.roll(inside, 1, 1) & np.roll(inside, -1, 1))
    rgb[edge] = hexc(rock[0])
    return rgb, alpha, hgt * inside


def wood(th, rng, w, h, along_x=True, kind="beam"):
    pal = th["wood"]
    if along_x:
        grain = pnoise(w, h, 2, max(h // 2, 2), rng) * 0.6 + pnoise(w, h, 8, h, rng) * 0.4
        across = np.arange(h)[:, None] / (h - 1)
    else:
        grain = pnoise(w, h, max(w // 2, 2), 2, rng) * 0.6 + pnoise(w, h, w, 8, rng) * 0.4
        across = np.arange(w)[None, :] / (w - 1)
    bevel = 1 - (np.abs(across - 0.5) * 2) ** 3
    lines = (np.sin(grain * 40) * 0.5 + 0.5) * 0.25
    t = 0.2 + 0.45 * bevel + lines + grain * 0.15
    rgb = ramp(pal, np.clip(t, 0, 0.999)).astype(np.int32)
    hgt = bevel * 0.7 + lines
    dark = np.array(hexc(pal[0]))
    if along_x:
        rgb[0, :] = dark
        rgb[-1, :] = dark
    else:
        rgb[:, 0] = dark
        rgb[:, -1] = dark
    # Iron bolts.
    steel = np.array(hexc("#8a8f96"))
    if kind == "beam":
        for x in range(8, w, 32):
            for y in (h // 2 - 2, h // 2 + 2):
                rgb[y, x] = steel
                rgb[y, x + 1] = np.array(hexc("#4c5056"))
    elif kind == "post":
        for y in range(10, h, 32):
            rgb[y:y + 3, :] = np.array(hexc("#3a3d42"))
            rgb[y, :] = np.array(hexc("#6d737b"))
    return np.clip(rgb, 0, 255), hgt


def ore_sprite(th, rng, w=24, h=12):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    pal = [tuple(hexc(c)) + (255,) for c in th["ore"]]
    for _ in range(9):
        x = rng.integers(2, w - 3)
        y = rng.integers(2, h - 2)
        s = rng.integers(1, 3)
        d.polygon([(x, y - s - 1), (x + s, y), (x, y + s), (x - s, y)], fill=pal[rng.integers(1, 3)])
        d.point((x, y - s), fill=pal[3])
    return img


# ---------------------------------------------------------------------------
# Shared sprites
# ---------------------------------------------------------------------------

def door_slab(rng, w=14, h=48):
    base = fbm(w, h, rng, 2, 8, 3)
    yy = np.arange(h)[:, None]
    xx = np.arange(w)[None, :]
    hgt = 0.5 + 0.1 * base
    t = 0.45 + 0.2 * base - (xx / w) * 0.12
    steel = ["#16181b", "#202327", "#2b2f34", "#373c42", "#454b52", "#555c64", "#677079", "#7c8690"]
    rgb = ramp(steel, np.clip(t * np.ones((h, w)), 0, 0.999)).astype(np.int32)
    for by in range(5, h - 5, 11):
        rgb[by:by + 3, :] = hexc("#2a2e33")
        rgb[by, :] = hexc("#59616a")
        hgt[by:by + 3, :] += 0.3
        for rx in (2, w - 3):
            rgb[by + 1, rx] = hexc("#a3acb6")
            rgb[by + 2, rx] = hexc("#16181b")
    rust = (pnoise(w, h, 3, 10, rng) > 0.62) & (rng.random((h, w)) > 0.3)
    rgb[rust] = (rgb[rust] * 0.5 + np.array(hexc("#7a3d1a")) * 0.5).astype(np.int32)
    streak = (pnoise(w, h, 6, 1, rng) > 0.7) & (yy > h * 0.3)
    rgb[streak] = (rgb[streak] * 0.7 + np.array(hexc("#5c2c12")) * 0.3).astype(np.int32)
    rgb[:, 0:2] = hexc("#8a939c")
    rgb[:, 0] = hexc("#a9b2bb")
    rgb[:, -1] = hexc("#101214")
    for x in range(w):
        for y in range(h - 5, h):
            rgb[y, x] = hexc("#d8a21e") if ((x + y) // 3) % 2 == 0 else hexc("#1a1612")
    return np.clip(rgb, 0, 255), hgt


def door_frame(w=28, h=58):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], fill=ink("#2a2d31", 255))
    d.rectangle([5, 9, w - 6, h - 1], fill=(0, 0, 0, 0))
    d.rectangle([0, 0, w - 1, 8], fill=ink("#3a3f45", 255))
    for x in range(0, w, 4):
        d.polygon([(x, 8), (x + 2, 8), (x + 4, 3), (x + 2, 3)], fill=ink("#c9951c", 255))
    d.line([(0, 0), (w - 1, 0)], fill=ink("#6b737c", 255))
    for y in range(13, h, 10):
        d.point((2, y), fill=ink("#9aa3ad", 255))
        d.point((w - 3, y), fill=ink("#9aa3ad", 255))
    d.line([(4, 9), (4, h - 1)], fill=ink("#121416", 255))
    d.line([(w - 5, 9), (w - 5, h - 1)], fill=ink("#121416", 255))
    return img


def _lantern_body(d, cx, top):
    """Upright lantern whose hook is at (cx, top)."""
    d.rectangle([cx - 4, top, cx + 4, top + 1], fill=ink("#2a2d31"))
    d.polygon([(cx - 5, top + 3), (cx + 5, top + 3), (cx + 3, top + 1), (cx - 3, top + 1)], fill=ink("#454a51"))
    d.rectangle([cx - 5, top + 4, cx + 5, top + 16], fill=ink("#1c1f22"))
    d.rectangle([cx - 4, top + 5, cx + 4, top + 15], fill=ink("#f0a440"))
    d.rectangle([cx - 3, top + 6, cx + 3, top + 14], fill=ink("#ffc865"))
    d.ellipse([cx - 2, top + 8, cx + 2, top + 14], fill=ink("#ffe7a3"))
    d.ellipse([cx - 1, top + 10, cx + 1, top + 13], fill=ink("#fffbe8"))
    for x in (cx - 2, cx + 2):
        d.line([(x, top + 5), (x, top + 15)], fill=ink("#2a2d31"))
    d.rectangle([cx - 6, top + 16, cx + 6, top + 18], fill=ink("#3a3f45"))
    d.line([(cx - 6, top + 16), (cx + 6, top + 16)], fill=ink("#6b737c"))


def lantern_sheet():
    """4 frames: still, swing right, still, swing left. The lantern stays upright
    and moves along its chain's arc (rotating pixel art garbles it)."""
    sheet = Image.new("RGBA", (128, 64))
    for i, ang in enumerate([0, 11, 0, -11]):
        frame = Image.new("RGBA", (32, 64))
        d = ImageDraw.Draw(frame)
        a = math.radians(ang)
        hook = (16 + math.sin(a) * 30, math.cos(a) * 30)
        n = 30
        for k in range(n + 1):
            x = 16 + (hook[0] - 16) * k / n
            y = hook[1] * k / n
            d.point((round(x), round(y)), fill=ink("#5d636b" if k % 3 else "#2c3035"))
        _lantern_body(d, round(hook[0]), round(hook[1]))
        sheet.paste(frame, (i * 32, 0))
    return sheet


def crawlspace(rng, w=44, h=26):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    hole = np.zeros((h, w, 4), np.uint8)
    yy, xx = np.mgrid[0:h, 0:w]
    inner = (xx >= 6) & (xx < w - 6) & (yy >= 7)
    depth = np.clip(1 - np.minimum(np.minimum(xx - 6, w - 7 - xx), yy - 7) / 6, 0, 1)
    rock = np.array(hexc("#1b1714"))
    col = (rock * depth[..., None] * 0.8).astype(np.uint8)
    hole[inner] = np.dstack([col, np.full((h, w), 255, np.uint8)])[inner]
    img = Image.fromarray(hole, "RGBA")
    d = ImageDraw.Draw(img)
    woodc = [tuple(hexc(c)) + (255,) for c in WOOD]
    for x0 in (1, w - 6):
        d.rectangle([x0, 4, x0 + 4, h - 1], fill=woodc[3])
        d.line([(x0, 4), (x0, h - 1)], fill=woodc[5])
        d.line([(x0 + 4, 4), (x0 + 4, h - 1)], fill=woodc[1])
        for y in range(7, h, 5):
            d.point((x0 + 2, y), fill=woodc[1])
    d.rectangle([0, 1, w - 1, 6], fill=woodc[4])
    d.line([(0, 1), (w - 1, 1)], fill=woodc[6])
    d.line([(0, 6), (w - 1, 6)], fill=woodc[1])
    d.point((3, 3), fill=(150, 150, 150, 255))
    d.point((w - 4, 3), fill=(150, 150, 150, 255))
    # Broken board hanging across a corner.
    d.polygon([(w - 7, 7), (w - 18, 15), (w - 16, 17), (w - 7, 10)], fill=woodc[3])
    d.line([(w - 7, 7), (w - 18, 15)], fill=woodc[5])
    # Cobweb.
    web = (200, 200, 200, 110)
    for i in range(3):
        d.line([(6, 7 + i * 3), (6 + 6 - i * 2, 7)], fill=web)
    d.line([(6, 7), (11, 12)], fill=web)
    return img


def rail(w=64, h=12):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    woodc = [tuple(hexc(c)) + (255,) for c in WOOD]
    for x in range(2, w, 16):
        d.rectangle([x, 6, x + 7, 11], fill=woodc[2])
        d.line([(x, 6), (x + 7, 6)], fill=woodc[4])
    d.rectangle([0, 3, w - 1, 5], fill=ink("#3c4248", 255))
    d.line([(0, 3), (w - 1, 3)], fill=ink("#a8b0b8", 255))
    d.line([(0, 5), (w - 1, 5)], fill=ink("#1c1f22", 255))
    return img


def crate(w=20, h=18):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    wc = [tuple(hexc(c)) + (255,) for c in WOOD]
    d.rectangle([0, 0, w - 1, h - 1], fill=wc[4])
    for y in range(3, h, 5):
        d.line([(0, y), (w - 1, y)], fill=wc[2])
    d.rectangle([0, 0, w - 1, h - 1], outline=wc[1])
    d.rectangle([1, 1, w - 2, 2], fill=wc[5])
    d.line([(2, 2), (w - 3, h - 3)], fill=wc[6], width=2)
    d.line([(2, h - 3), (w - 3, 2)], fill=wc[3], width=2)
    return img


def barrel(w=12, h=16):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    wc = [tuple(hexc(c)) + (255,) for c in WOOD]
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=3, fill=wc[3], outline=wc[0])
    for x in range(2, w - 1, 3):
        d.line([(x, 1), (x, h - 2)], fill=wc[4])
    for y in (3, h - 4):
        d.line([(0, y), (w - 1, y)], fill=ink("#3a3f45", 255))
    d.line([(1, 1), (w - 2, 1)], fill=wc[6])
    return img


def minecart(w=34, h=22):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    d.polygon([(1, 2), (w - 2, 2), (w - 5, 16), (4, 16)], fill=ink("#5c3a26", 255))
    d.polygon([(1, 2), (w - 2, 2), (w - 5, 16), (4, 16)], outline=ink("#24160e", 255))
    d.line([(1, 2), (w - 2, 2)], fill=ink("#9c6a44", 255), width=2)
    for x in range(6, w - 6, 7):
        d.line([(x, 4), (x - 1, 15)], fill=ink("#3b2416", 255))
    d.ellipse([3, 1, w - 4, 6], fill=ink("#2a2a2a", 255))
    for x in (8, w - 10):
        d.ellipse([x - 3, 14, x + 3, 20], fill=ink("#1e2124", 255), outline=ink("#6b737c", 255))
    return img


def bones(w=18, h=8):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    bone = ink("#cfc6b2", 255)
    shade = ink("#8c846f", 255)
    d.line([(1, 6), (10, 5)], fill=bone, width=2)
    d.ellipse([0, 4, 2, 7], fill=bone)
    d.ellipse([9, 3, 11, 6], fill=bone)
    d.ellipse([11, 1, 17, 7], fill=bone)
    d.point((13, 4), fill=ink("#1b1714", 255))
    d.point((15, 4), fill=ink("#1b1714", 255))
    d.line([(12, 7), (16, 7)], fill=shade)
    return img


def crystals(rng, w=18, h=22):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    cols = ["#3b2a8a", "#6a4ff0", "#9d8bff", "#e3dcff", "#3fd6e8"]
    for i in range(5):
        bx = rng.integers(3, w - 3)
        ht = rng.integers(8, h - 1)
        wd = rng.integers(2, 4)
        lean = rng.integers(-3, 4)
        tip = (bx + lean, h - ht)
        c = cols[i % 2 + (1 if i == 2 else 0)]
        d.polygon([(bx - wd, h - 1), (bx + wd, h - 1), tip], fill=ink(c))
        d.line([(bx - wd + 1, h - 2), tip], fill=ink(cols[3]))
    return img


def claws(w=28, h=24):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    for i in range(4):
        x = 4 + i * 6
        d.line([(x, 2), (x + 8, h - 3)], fill=(10, 4, 4, 230), width=2)
        d.line([(x + 1, 2), (x + 9, h - 3)], fill=(120, 60, 55, 140))
    return img


def particle_soft(size=16):
    yy, xx = np.mgrid[0:size, 0:size]
    r = np.sqrt((xx - size / 2 + 0.5) ** 2 + (yy - size / 2 + 0.5) ** 2) / (size / 2)
    a = np.clip(1 - r, 0, 1) ** 1.6 * 255
    rgb = np.full((size, size, 3), 255)
    return rgb, a


# ---------------------------------------------------------------------------
# Bruce
# ---------------------------------------------------------------------------

C = {
    "out": (18, 12, 10, 255),
    "jeans": (58, 78, 108, 255), "jeans_d": (38, 52, 74, 255),
    "boot": (66, 44, 28, 255), "boot_d": (40, 27, 18, 255),
    "jacket": (196, 98, 44, 255), "jacket_d": (138, 64, 28, 255), "jacket_l": (226, 132, 70, 255),
    "stripe": (226, 222, 140, 255),
    "glove": (92, 70, 48, 255),
    "skin": (226, 170, 124, 255), "skin_d": (182, 124, 88, 255),
    "beard": (96, 66, 46, 255),
    "helmet": (232, 184, 58, 255), "helmet_l": (250, 220, 120, 255), "helmet_d": (170, 128, 30, 255),
    "lamp": (255, 250, 220, 255),
    "belt": (40, 30, 24, 255), "buckle": (190, 170, 100, 255),
}


def _pt(p, ang, length):
    a = math.radians(ang)
    return (p[0] + math.sin(a) * length, p[1] + math.cos(a) * length)


def _limb(d, p0, ang, length, width, col):
    p1 = _pt(p0, ang, length)
    d.line([p0, p1], fill=col, width=width)
    r = width / 2 - 0.3
    d.ellipse([p1[0] - r, p1[1] - r, p1[0] + r, p1[1] + r], fill=col)
    return p1


def bruce_frame(pose):
    img = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(img)
    hip = (15 + pose.get("hx", 0), 21 + pose.get("hy", 0))
    lean = pose.get("lean", 0)
    sh = _pt(hip, 180 - lean, 8)          # shoulders above the hips
    neck = _pt(hip, 180 - lean, 9.5)

    def leg(thigh, knee, col, boot):
        k = _limb(d, hip, thigh, 5.2, 3, col)
        f = _limb(d, k, thigh - knee, 5.0, 3, col)
        toe = (f[0] + 2.6, f[1] + 0.2)
        d.line([f, toe], fill=boot, width=2)
        d.point((round(f[0] - 1), round(f[1] + 0.6)), fill=boot)

    def arm(upper, elbow, col):
        e = _limb(d, (sh[0], sh[1] + 1), upper, 4.0, 2, col)
        h = _limb(d, e, upper + elbow, 3.6, 2, col)
        d.ellipse([h[0] - 1.1, h[1] - 1.1, h[0] + 1.1, h[1] + 1.1], fill=C["glove"])

    arm(pose["arm_b"], pose.get("elb_b", 20), C["jacket_d"])
    leg(pose["thigh_b"], pose.get("knee_b", 0), C["jeans_d"], C["boot_d"])
    # Torso (jacket) + reflective stripe + belt.
    d.line([hip, sh], fill=C["jacket"], width=8)
    d.line([_pt(hip, 180 - lean, 1), _pt(hip, 180 - lean, 7)], fill=C["jacket_l"], width=3)
    mid = _pt(hip, 180 - lean, 4.5)
    perp = math.radians(90 - lean)
    a = (mid[0] - math.sin(perp) * 4, mid[1] - math.cos(perp) * 4)
    b = (mid[0] + math.sin(perp) * 4, mid[1] + math.cos(perp) * 4)
    d.line([a, b], fill=C["stripe"], width=1)
    belt = _pt(hip, 180 - lean, 0.5)
    ba = (belt[0] - math.sin(perp) * 4, belt[1] - math.cos(perp) * 4)
    bb = (belt[0] + math.sin(perp) * 4, belt[1] + math.cos(perp) * 4)
    d.line([ba, bb], fill=C["belt"], width=2)
    d.point((round(belt[0] + 1), round(belt[1])), fill=C["buckle"])
    leg(pose["thigh_f"], pose.get("knee_f", 0), C["jeans"], C["boot"])
    # Head.
    hc = _pt(neck, 180 - lean, 3.2 + pose.get("head_dy", 0))
    hx, hy = hc
    d.ellipse([hx - 3.4, hy - 3.0, hx + 3.4, hy + 3.4], fill=C["skin"])
    d.line([(hx - 2.5, hy + 2.6), (hx + 3.0, hy + 2.6)], fill=C["beard"], width=1)
    d.point((round(hx + 3), round(hy + 1.6)), fill=C["beard"])
    d.point((round(hx + 1.6), round(hy + 0.1)), fill=C["out"])        # eye
    d.point((round(hx - 2.4), round(hy + 0.6)), fill=C["skin_d"])     # ear
    # Hard hat with brim and lamp.
    d.chord([hx - 4.2, hy - 6.4, hx + 4.0, hy + 1.6], 180, 360, fill=C["helmet"])
    d.line([(hx - 4.2, hy - 2.0), (hx + 5.4, hy - 2.0)], fill=C["helmet_d"], width=1)
    d.line([(hx - 2.0, hy - 5.6), (hx + 1.0, hy - 5.6)], fill=C["helmet_l"], width=1)
    d.rectangle([hx + 3.0, hy - 4.6, hx + 4.6, hy - 3.0], fill=C["lamp"])
    arm(pose["arm_f"], pose.get("elb_f", 20), C["jacket"])

    # 1px dark outline around the silhouette.
    a = np.array(img)
    solid = a[..., 3] > 0
    p = np.pad(solid, 1)
    grow = solid | p[2:, 1:-1] | p[:-2, 1:-1] | p[1:-1, 2:] | p[1:-1, :-2]
    edge = grow & ~solid
    a[edge] = C["out"]
    return Image.fromarray(a, "RGBA")


def bruce_sheet():
    rows = []
    # idle
    rows.append([dict(thigh_f=6, thigh_b=-6, arm_f=10, arm_b=-8, elb_f=15, elb_b=15, hy=hy, head_dy=hd)
                 for hy, hd in ((0, 0), (0, -0.3), (0.6, 0), (0.6, 0.2))])
    # walk
    walk = []
    for i in range(4):
        s = math.sin(i / 4 * 2 * math.pi)
        walk.append(dict(thigh_f=28 * s, thigh_b=-28 * s, knee_f=max(0, -30 * s) + 6, knee_b=max(0, 30 * s) + 6,
                         arm_f=-24 * s, arm_b=24 * s, elb_f=25, elb_b=25, lean=4, hy=-0.6 * abs(math.cos(i / 4 * 2 * math.pi))))
    rows.append(walk)
    # run
    run = []
    for i in range(6):
        ph = i / 6 * 2 * math.pi
        s = math.sin(ph)
        run.append(dict(thigh_f=45 * s + 10, thigh_b=-45 * s + 10, knee_f=max(0, -70 * s) + 15, knee_b=max(0, 70 * s) + 15,
                        arm_f=-50 * s, arm_b=50 * s, elb_f=80, elb_b=80, lean=14, hy=-1.2 * abs(math.cos(ph)) + 0.4))
    rows.append(run)
    # jump (tucked)
    rows.append([dict(thigh_f=65, thigh_b=40, knee_f=85, knee_b=70, arm_f=125, arm_b=-130, elb_f=30, elb_b=-30, lean=8, hy=-2),
                 dict(thigh_f=55, thigh_b=30, knee_f=75, knee_b=60, arm_f=135, arm_b=-140, elb_f=20, elb_b=-20, lean=6, hy=-2)])
    # crouch
    rows.append([dict(thigh_f=80, thigh_b=60, knee_f=150, knee_b=140, arm_f=40, arm_b=20, elb_f=50, elb_b=60, lean=26, hy=6.5),
                 dict(thigh_f=78, thigh_b=62, knee_f=146, knee_b=142, arm_f=46, arm_b=24, elb_f=50, elb_b=60, lean=28, hy=7)])
    # slide (legs out front, leaning back)
    rows.append([dict(thigh_f=88, thigh_b=82, knee_f=4, knee_b=10, arm_f=-120 + j * 6, arm_b=-95, elb_f=-10, elb_b=-20,
                      lean=-62, hy=6.5, hx=5) for j in range(4)])
    sheet = Image.new("RGBA", (256, 192))
    for r, poses in enumerate(rows):
        for c, p in enumerate(poses):
            sheet.paste(bruce_frame(p), (c * 32, r * 32))
    return sheet


# ---------------------------------------------------------------------------
# Game icon
# ---------------------------------------------------------------------------

def game_icon():
    """32x32 pixel-art icon: Bruce's hard hat, lamp blazing, on a rock badge."""
    s = 32
    rng = np.random.default_rng(99)
    yy, xx = np.mgrid[0:s, 0:s]
    # Rounded-square badge of dark rock.
    r = 6
    cx = np.clip(xx, r, s - 1 - r)
    cy = np.clip(yy, r, s - 1 - r)
    inside = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    rock = THEMES[0]["rock"]
    f1, f2, _ = voronoi(s, s, 9, rng)
    t = 0.12 + 0.22 * (1 - norm(f1)) - 0.1 * (1 - smoothstep(0, 1.5, f2 - f1))
    rgb = ramp(rock, np.clip(t, 0, 0.999)).astype(np.int32)
    # Warm glow behind the hat.
    glow = np.clip(1 - np.sqrt((xx - 16) ** 2 + (yy - 15) ** 2) / 15, 0, 1) ** 1.5
    rgb = np.clip(rgb + (glow[..., None] * np.array([120, 70, 20])).astype(np.int32), 0, 255)
    img = Image.fromarray(np.dstack([rgb.astype(np.uint8), (inside * 255).astype(np.uint8)]), "RGBA")
    d = ImageDraw.Draw(img)
    # Border.
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=r, outline=ink("#7a5634"))
    d.rounded_rectangle([1, 1, s - 2, s - 2], radius=r - 1, outline=ink("#2a1d16"))
    # Hard hat dome, brim, ridge.
    d.chord([6, 7, 26, 29], 180, 360, fill=ink("#e8b83a"))
    d.chord([8, 9, 18, 25], 200, 290, fill=ink("#f8dc7c"))
    d.line([(16, 8), (16, 17)], fill=ink("#c9971f"))
    d.rectangle([3, 18, 28, 20], fill=ink("#d9a62c"))
    d.line([(3, 18), (28, 18)], fill=ink("#f8dc7c"))
    d.line([(3, 21), (28, 21)], fill=ink("#7a5418"))
    d.line([(6, 17), (26, 17)], fill=ink("#a87b1c"))
    # Lamp on the front of the hat.
    d.ellipse([12, 10, 20, 17], fill=ink("#2b2f34"))
    d.ellipse([13, 11, 19, 16], fill=ink("#fff4c4"))
    d.ellipse([14, 12, 17, 14], fill=ink("#ffffff"))
    # Outline the hat.
    a = np.array(img)
    hat = (a[..., 0] > 150) & (a[..., 1] > 100) & (a[..., 2] < 140) & inside
    lamp = (a[..., 0] > 240) & (a[..., 1] > 230)
    solid = hat | lamp
    p = np.pad(solid, 1)
    grow = solid | p[2:, 1:-1] | p[:-2, 1:-1] | p[1:-1, 2:] | p[1:-1, :-2]
    edge = grow & ~solid & inside & (yy > 4) & (yy < 23)
    a[edge] = ink("#120c09")
    # Lamp rays.
    for (x0, y0, x1, y1) in ((16, 9, 16, 4), (11, 11, 8, 7), (21, 11, 24, 7)):
        Image.fromarray(a)
        dd = ImageDraw.Draw(img := Image.fromarray(a, "RGBA"))
        dd.line([(x0, y0), (x1, y1)], fill=ink("#ffe9a0"))
        a = np.array(img)
    return Image.fromarray(a, "RGBA")


def save_icon(icon32):
    big = icon32.resize((256, 256), Image.NEAREST)
    big.save(OUT / "icon.png")
    sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)]
    big.save(OUT / "icon.ico", sizes=sizes)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    for i, th in enumerate(THEMES):
        rng = np.random.default_rng(1000 + i)
        d = OUT / th["key"]
        for kind, size in (("front", 64), ("back", 64)):
            rgb, hgt = rock_texture(th, rng, size, kind)
            save(rgb, d / f"wall_{kind}.png")
            save_n(normal_map(hgt, 6.0), d / f"wall_{kind}_n.png")
        rgb, a, hgt = floor_top(th, rng)
        save(rgb, d / "floor_top.png", a)
        save_n(normal_map(hgt, 4.0, alpha=a.astype(np.uint8)), d / "floor_top_n.png")
        rgb, a, hgt = ceiling_edge(th, rng)
        save(rgb, d / "ceiling_edge.png", a)
        save_n(normal_map(hgt, 4.0, alpha=a.astype(np.uint8)), d / "ceiling_edge_n.png")
        rgb, a, hgt = rubble(th, rng)
        save(rgb, d / "rubble.png", a)
        save_n(normal_map(hgt, 5.0, wrap=False, alpha=a.astype(np.uint8)), d / "rubble_n.png")
        for name, w, h, ax in (("beam", 64, 12, True), ("post", 12, 64, False), ("plank", 32, 8, True)):
            rgb, hgt = wood(th, rng, w, h, ax, name)
            save(rgb, d / f"{name}.png")
            save_n(normal_map(hgt, 3.0), d / f"{name}_n.png")
        ore_sprite(th, rng).save(d / "ore.png")
        print("theme", th["key"], "done")

    rng = np.random.default_rng(7)
    shared = OUT / "shared"
    rgb, hgt = door_slab(rng)
    save(rgb, shared / "door.png")
    save_n(normal_map(hgt, 4.0, wrap=False), shared / "door_n.png")
    door_frame().save(shared / "door_frame.png")
    lantern_sheet().save(shared / "lantern.png")
    crawlspace(rng).save(shared / "crawlspace.png")
    rail().save(shared / "rail.png")
    crate().save(shared / "crate.png")
    barrel().save(shared / "barrel.png")
    minecart().save(shared / "minecart.png")
    bones().save(shared / "bones.png")
    crystals(rng).save(shared / "crystals.png")
    claws().save(shared / "claws.png")
    rgb, a = particle_soft()
    save(rgb, shared / "soft.png", a)
    bruce_sheet().save(shared / "bruce.png")
    save_icon(game_icon())
    print("shared sprites done ->", OUT)


if __name__ == "__main__":
    main()
