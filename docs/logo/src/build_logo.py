#!/usr/bin/env python3
"""Render AI BenchGauge logo previews (PNG) from the shared geometry in logo_lib."""
import math, os, sys
from PIL import Image, ImageDraw
import logo_lib as L

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEW = os.path.join(HERE, "..", "..", "..", "work", "app-logo", "preview")
os.makedirs(PREVIEW, exist_ok=True)

CANVAS_UNITS = 1024.0
BODY = dict(x=100.0, y=100.0, w=824.0)      # macOS icon body inside a 1024 canvas
BODY_R_RATIO = 0.225
MARK_BOX_W = 566.0                           # mark width in canvas units (icon layout)


def fit(bbox, target_w, cx, cy, S):
    """Return (scale, ox, oy) mapping mark-space coords to S-pixel canvas coords."""
    x0, y0, x1, y1 = bbox
    bw, bh = x1 - x0, y1 - y0
    sc = (target_w / bw) * (S / CANVAS_UNITS)
    ox = cx * S / CANVAS_UNITS - sc * (x0 + bw / 2)
    oy = cy * S / CANVAS_UNITS - sc * (y0 + bh / 2)
    return sc, ox, oy


class T:
    def __init__(self, sc, ox, oy):
        self.sc, self.ox, self.oy = sc, ox, oy

    def p(self, x, y):
        return (x * self.sc + self.ox, y * self.sc + self.oy)

    def d(self, v):
        return v * self.sc


CAPS = "butt"
MONO = False


def draw_mark_masks(S, tf):
    """Return (accent_mask, white_mask) L-mode images for the mark at S pixels."""
    acc = Image.new("L", (S, S), 0)
    accd = Image.new("L", (S, S), 0)
    wht = Image.new("L", (S, S), 0)
    da, dd, dw = ImageDraw.Draw(acc), ImageDraw.Draw(accd), ImageDraw.Draw(wht)

    d = L.DIAL
    da = dw if MONO else da
    c = tf.p(d["cx"], d["cy"])
    r = tf.d(d["r"])
    w = tf.d(d["w"])
    # Pillow draws arc strokes inside the bbox, so inflate by w/2 to centre on r.
    bbox = [c[0] - r - w / 2, c[1] - r - w / 2, c[0] + r + w / 2, c[1] + r + w / 2]
    da.arc(bbox, start=d["a0"] % 360, end=d["a1"] % 360, fill=255, width=int(round(w)))
    if CAPS == "round":
        for ang in (d["a0"] % 360, d["a1"] % 360):
            p = tf.p(*L.polar(d["cx"], d["cy"], d["r"], ang))
            da.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=255)

    pv = L.PIVOT
    pc = tf.p(pv["cx"], pv["cy"])
    pr = tf.d(pv["r"])
    (da if not MONO else dw).ellipse([pc[0] - pr, pc[1] - pr, pc[0] + pr, pc[1] + pr], fill=255)

    for b in L.BARS:
        tgt = dw if MONO else (dd if b["layer"] == "accent" else dw)
        (x0, y0), (x1, y1) = tf.p(b["x"], b["top"]), tf.p(b["x"] + b["w"], L.BASELINE)
        r = tf.d(L.BAR_R)
        tgt.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=b["alpha"])
        tgt.rectangle([x0, y1 - r, x1, y1], fill=b["alpha"])   # flat bottom

    ax = getattr(L, "AXIS", None)
    if ax and not MONO:
        (x0, y0), (x1, y1) = tf.p(ax["x0"], ax["y"]), tf.p(ax["x1"], ax["y"] + ax["h"])
        dw.rounded_rectangle([x0, y0, x1, y1], radius=(y1 - y0) / 2, fill=ax["alpha"])

    if getattr(L, "TICKS", None) and not MONO:
        d = L.DIAL
        inner = d["r"] - d["w"] / 2 - 16
        for ang in L.TICKS:
            p1 = tf.p(*L.polar(d["cx"], d["cy"], inner, ang))
            p2 = tf.p(*L.polar(d["cx"], d["cy"], inner - L.TICK_LEN, ang))
            L.capsule(dw, p1, p2, tf.d(L.TICK_W), 120)

    n = L.NEEDLE
    tail = tf.p(*L.needle_points()[0])
    tip = tf.p(*L.needle_points()[1])
    L.capsule(dw, tail, tip, tf.d(n["w"]), 255)

    if L.SPARK:
        cx, cy, sr = L.SPARK
        p = tf.p(cx, cy)
        rr = tf.d(sr)
        pts = []
        for i in range(64):
            t = i / 64 * 2 * math.pi
            rad = rr * (0.28 + 0.72 * abs(math.cos(2 * t)) ** 6)
            pts.append((p[0] + rad * math.cos(t), p[1] + rad * math.sin(t)))
        dw.polygon(pts, fill=255)
    return acc, accd, wht


def render_tile(S, body, glows=True, rim=True):
    """body: dict(x,y,w) in canvas units."""
    bx = body["x"] * S / CANVAS_UNITS
    by = body["y"] * S / CANVAS_UNITS
    bw = body["w"] * S / CANVAS_UNITS
    rad = bw * BODY_R_RATIO
    box = [bx, by, bx + bw, by + bw]

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=rad, fill=255)

    tile = L.linear_gradient((S, S), L.TILE_STOPS, 135).convert("RGBA")
    if glows:
        g1 = L.radial_glow((S, S), (bx + bw * 0.92, by + bw * 0.06), bw * 0.62, "#7f8eff", 62)
        g2 = L.radial_glow((S, S), (bx + bw * 0.04, by + bw * 0.98), bw * 0.66, "#4fd6c0", 46)
        tile = Image.alpha_composite(tile, g1)
        tile = Image.alpha_composite(tile, g2)

    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    base = Image.composite(tile, base, mask)
    if rim:
        rim_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(rim_layer).rounded_rectangle(
            [box[0] + 1, box[1] + 1, box[2] - 1, box[3] - 1],
            radius=max(rad - 1, 1), outline=L.RIM, width=max(2, int(round(S / 512 * 2))))
        base = Image.alpha_composite(base, rim_layer)
    return base, mask


def compose(size, ss=3, body=BODY, mark_w=MARK_BOX_W, mark_c=(512.0, 512.0),
            tile=True, bg=None):
    S = size * ss
    tf = T(*fit(L.mark_bbox(), mark_w, mark_c[0], mark_c[1], S))
    if tile:
        base, mask = render_tile(S, body)
    else:
        base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        mask = Image.new("L", (S, S), 255)
    acc, accd, wht = draw_mark_masks(S, tf)
    x0, y0, x1, y1 = L.mark_bbox()
    gx0 = x0 * tf.sc + tf.ox
    gx1 = x1 * tf.sc + tf.ox
    accent = L.linear_gradient((S, S), L.ACCENT_STOPS, 8).crop((0, 0, S, S)).convert("RGBA")
    ink_rgb = (0, 0, 0) if MONO else L.hex2rgb(L.INK)
    ink = Image.new("RGBA", (S, S), ink_rgb + (255,))
    base = Image.composite(accent, base, acc)
    base = Image.composite(accent, base, accd)
    base = Image.composite(ink, base, wht)
    out = base.resize((size, size), Image.LANCZOS)
    if bg:
        canvas = Image.new("RGBA", (size, size), L.hex2rgb(bg) + (255,))
        canvas.alpha_composite(out)
        out = canvas
    return out


def sheet(name, images, labels=None, pad=28, bg="#eef1f8"):
    widths = [im.size[0] for im in images]
    heights = [im.size[1] for im in images]
    W = sum(widths) + pad * (len(images) + 1)
    H = max(heights) + pad * 2
    out = Image.new("RGBA", (W, H), L.hex2rgb(bg) + (255,))
    x = pad
    for im in images:
        out.alpha_composite(im, (x, pad))
        x += im.size[0] + pad
    out.save(os.path.join(PREVIEW, name))
    print("wrote", name, out.size)


VARIANTS = {
    "v1": dict(caps="butt", axis=True),
    "v2": dict(caps="butt", axis=False),
    "v3": dict(caps="round", axis=False),
    "v4": dict(caps="butt", axis=False, dial=dict(cx=512, cy=420, r=240, w=52, a0=158, a1=382),
               bars=[dict(x=384, w=100, top=520, alpha=160, layer="accent"),
                     dict(x=528, w=100, top=462, alpha=246, layer="white")],
               baseline=680, needle=dict(cx=512, cy=420, ang=62.0, up=170, down=12, w=26),
               pivot=dict(cx=512, cy=420, r=30)),
    "v5": dict(caps="butt", axis=False, dial=dict(cx=512, cy=428, r=238, w=52, a0=158, a1=382),
               bars=[dict(x=384, w=100, top=512, alpha=160, layer="accent"),
                     dict(x=528, w=100, top=452, alpha=246, layer="white")],
               baseline=664, needle=dict(cx=512, cy=428, ang=62.0, up=176, down=12, w=24),
               pivot=dict(cx=512, cy=428, r=30)),
}


def apply_variant(name):
    global CAPS
    v = VARIANTS[name]
    CAPS = v["caps"]
    L.AXIS = dict(x0=356, x1=668, y=700, h=14, alpha=76) if v["axis"] else None
    if v.get("dial"):
        L.DIAL = v["dial"]
    if v.get("bars"):
        L.BARS = v["bars"]
    if v.get("baseline"):
        L.BASELINE = v["baseline"]
    if v.get("needle"):
        L.NEEDLE = v["needle"]
    if v.get("pivot"):
        L.PIVOT = v["pivot"]


TEMPLATE = dict(
    dial=dict(cx=512, cy=430, r=250, w=78, a0=158, a1=382),
    bars=[dict(x=352, w=124, top=520, alpha=255, layer="white"),
          dict(x=548, w=124, top=436, alpha=255, layer="white")],
    baseline=684,
    needle=dict(cx=512, cy=430, ang=62.0, up=172, down=14, w=66),
    pivot=dict(cx=512, cy=430, r=58),
)


def render_mono(size, ss=8):
    global MONO
    saved = (L.DIAL, L.BARS, L.BASELINE, L.NEEDLE, L.PIVOT, L.AXIS)
    MONO = True
    L.DIAL, L.BARS, L.BASELINE, L.NEEDLE, L.PIVOT = (TEMPLATE[k] for k in
        ("dial", "bars", "baseline", "needle", "pivot"))
    L.AXIS = None
    try:
        return compose(size, ss=ss, tile=False, mark_w=1024 * 20 / 24, mark_c=(512, 512))
    finally:
        MONO = False
        L.DIAL, L.BARS, L.BASELINE, L.NEEDLE, L.PIVOT, L.AXIS = saved


def menubar_strip(name):
    """Fake menu bar: light strip with the template icon + fake items."""
    h = 66
    icons = [render_mono(s, ss=10 if s <= 24 else 6) for s in (18, 22, 28)]
    W = 620
    bar = Image.new("RGBA", (W, h), (246, 247, 250, 255))
    d = ImageDraw.Draw(bar)
    d.rectangle([0, h - 1, W, h], fill=(214, 218, 228, 255))
    x = 24
    for im in icons:
        bar.alpha_composite(im, (x, (h - im.size[1]) // 2 - 1))
        x += im.size[0] + 34
    d.rounded_rectangle([x, 20, x + 90, 46], radius=6, fill=(228, 231, 238, 255))
    d.rounded_rectangle([x + 106, 20, x + 150, 46], radius=6, fill=(228, 231, 238, 255))
    bar.save(os.path.join(PREVIEW, name))
    print("wrote", name)


if __name__ == "__main__":
    variant = sys.argv[1] if len(sys.argv) > 1 else "v1"
    apply_variant(variant)
    icon = compose(512, ss=3)
    icon.save(os.path.join(PREVIEW, f"icon-{variant}-512.png"))
    sizes = [compose(s, ss=6 if s <= 64 else 4) for s in (128, 64, 48, 32, 22, 16)]
    sheet(f"legibility-{variant}.png", [icon] + sizes)
    light = compose(512, ss=3, bg="#ffffff")
    dark = compose(512, ss=3, bg="#10131c")
    sheet(f"backdrop-{variant}.png", [light, dark], bg="#dfe4ee")
    menubar_strip(f"menubar-{variant}.png")
    print(variant, "mark bbox", L.mark_bbox())
