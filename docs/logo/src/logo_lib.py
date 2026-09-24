#!/usr/bin/env python3
"""Shared geometry + palette for the AI BenchGauge logo (SVG and PNG from one source)."""
import math
from PIL import Image, ImageDraw

# ---------------------------------------------------------------- palette
def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

TILE_STOPS = [(0.0, "#0d1734"), (0.52, "#182451"), (1.0, "#2b4686")]
ACCENT_STOPS = [(0.0, "#74e2cd"), (0.52, "#7fd3e8"), (1.0, "#8ba9ff")]
INK = "#f7faff"
BAR_DIM = 118          # 0-255 alpha for the "second board" bar
BAR_LEAD = 246         # 0-255 alpha for the leading bar
RIM = (255, 255, 255, 40)

# ---------------------------------------------------------------- mark geometry
# All numbers live in a 1024x1024 "mark space".
DIAL = dict(cx=512, cy=418, r=238, w=52, a0=152, a1=388)   # screen degrees, gap at bottom
BASELINE = 672
BARS = [
    dict(x=384, w=92, top=546, alpha=160, layer="accent"),  # left board
    dict(x=536, w=92, top=486, alpha=246, layer="white"),   # right board
]
BAR_R = 28
AXIS = dict(x0=348, x1=676, y=694, h=14, alpha=88)   # the "bench" baseline, None to disable
TICKS = [198, 270, 342]          # screen angles of small gauge ticks, None to disable
TICK_LEN = 26
TICK_W = 14
NEEDLE = dict(cx=512, cy=418, ang=60.0, up=168, down=12, w=28)  # ang = math degrees CCW from +x
PIVOT = dict(cx=512, cy=418, r=32)
SPARK = None            # optional (cx, cy, r) four-point sparkle


def polar(cx, cy, r, deg_screen):
    a = math.radians(deg_screen)
    return (cx + r * math.cos(a), cy + r * math.sin(a))


def needle_points():
    n = NEEDLE
    a = math.radians(-n["ang"])          # screen angle for a math angle
    dx, dy = math.cos(a), math.sin(a)
    tip = (n["cx"] + n["up"] * dx, n["cy"] + n["up"] * dy)
    tail = (n["cx"] - n["down"] * dx, n["cy"] - n["down"] * dy)
    return tail, tip


def arc_endpoints():
    d = DIAL
    return polar(d["cx"], d["cy"], d["r"], d["a0"] % 360), polar(d["cx"], d["cy"], d["r"], d["a1"] % 360)


def mark_bbox():
    d = DIAL
    outer = d["r"] + d["w"] / 2
    x0 = d["cx"] - outer
    x1 = d["cx"] + outer
    y0 = d["cy"] - outer
    y1 = max(BASELINE, d["cy"] + outer * math.sin(math.radians(d["a0"] % 360)))
    ax = globals().get("AXIS")
    if ax:
        y1 = max(y1, ax["y"] + ax["h"])
        x0 = min(x0, ax["x0"])
        x1 = max(x1, ax["x1"])
    return (x0, y0, x1, y1)

# ---------------------------------------------------------------- pillow helpers
def _sample_stops(stops, t):
    t = max(0.0, min(1.0, t))
    for i in range(len(stops) - 1):
        t0, c0 = stops[i]
        t1, c1 = stops[i + 1]
        if t <= t1 or i == len(stops) - 2:
            f = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            f = max(0.0, min(1.0, f))
            a, b = hex2rgb(c0), hex2rgb(c1)
            return tuple(int(a[k] + (b[k] - a[k]) * f) for k in range(3))
    return hex2rgb(stops[-1][1])


def linear_gradient(size, stops, angle_deg=135, grid=160):
    a = math.radians(angle_deg)
    dx, dy = math.cos(a), math.sin(a)
    span = 0.5 * (abs(dx) + abs(dy))
    small = Image.new("RGB", (grid, grid))
    px = small.load()
    for j in range(grid):
        for i in range(grid):
            u = ((i / (grid - 1)) - 0.5) * dx + ((j / (grid - 1)) - 0.5) * dy
            px[i, j] = _sample_stops(stops, 0.5 + u / (2 * span))
    return small.resize(size, Image.BICUBIC)


def radial_glow(size, center, radius, color, peak, grid=200, power=1.7):
    """RGBA layer: soft radial blob. center/radius are in canvas pixel units."""
    W, H = size
    cx, cy = center
    small = Image.new("RGBA", (grid, grid), (0, 0, 0, 0))
    px = small.load()
    rgb = hex2rgb(color)
    for j in range(grid):
        y = (j / (grid - 1)) * H
        for i in range(grid):
            x = (i / (grid - 1)) * W
            d = math.hypot(x - cx, y - cy) / radius
            if d >= 1:
                continue
            px[i, j] = rgb + (int(peak * (1 - d) ** power),)
    return small.resize(size, Image.BILINEAR)


def capsule(d, p1, p2, w, fill):
    r = w / 2
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    L = math.hypot(dx, dy) or 1
    ox, oy = -dy / L * r, dx / L * r
    d.polygon([(p1[0] + ox, p1[1] + oy), (p2[0] + ox, p2[1] + oy),
               (p2[0] - ox, p2[1] - oy), (p1[0] - ox, p1[1] - oy)], fill=fill)
    for p in (p1, p2):
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def rounded_rect_xy(xy, radius):
    x, y, w, h = xy
    return [x, y, x + w, y + h], radius
