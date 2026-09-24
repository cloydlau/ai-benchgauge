#!/usr/bin/env python3
"""Geometry check: re-rasterize exported SVGs (subset) and diff alpha vs the Pillow render."""
import math, os, re, sys
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw
import logo_lib as L
import build_logo as B
from PIL import ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NS = "{http://www.w3.org/2000/svg}"


def parse_transform(t):
    sc, tx, ty = 1.0, 0.0, 0.0
    m = re.search(r"translate\(([-\d.]+)[ ,]([-\d.]+)\)", t or "")
    if m:
        tx, ty = float(m.group(1)), float(m.group(2))
    m = re.search(r"scale\(([-\d.]+)\)", t or "")
    if m:
        sc = float(m.group(1))
    return sc, tx, ty


def flatten_path(d):
    """Return list of subpaths; each a list of points. Arcs are sampled."""
    toks = re.findall(r"[MLAZ]|-?\d*\.?\d+(?:e-?\d+)?", d)
    pts, cur, sub = [], None, []
    i = 0
    while i < len(toks):
        c = toks[i]
        if c == "M":
            if sub:
                pts.append(sub)
            sub = [(float(toks[i + 1]), float(toks[i + 2]))]
            i += 3
        elif c == "L":
            sub.append((float(toks[i + 1]), float(toks[i + 2])))
            i += 3
        elif c == "A":
            rx, ry, rot, laf, sf, x, y = (float(v) for v in toks[i + 1:i + 8])
            x0, y0 = sub[-1]
            sub.extend(arc_points(x0, y0, rx, ry, rot, int(laf), int(sf), x, y))
            i += 8
        elif c == "Z":
            sub.append(sub[0])
            i += 1
        else:
            i += 1
    if sub:
        pts.append(sub)
    return pts


def arc_points(x0, y0, rx, ry, rot, laf, sf, x1, y1, steps=96):
    rot = math.radians(rot)
    dx, dy = (x0 - x1) / 2, (y0 - y1) / 2
    xr = dx * math.cos(rot) + dy * math.sin(rot)
    yr = -dx * math.sin(rot) + dy * math.cos(rot)
    lam = (xr / rx) ** 2 + (yr / ry) ** 2
    if lam > 1:
        rx *= math.sqrt(lam)
        ry *= math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * yr * yr - ry * ry * xr * xr
    den = rx * rx * yr * yr + ry * ry * xr * xr
    coef = math.sqrt(max(num, 0) / den) * (1 if laf != sf else -1)
    cxr, cyr = coef * rx * yr / ry, -coef * ry * xr / rx
    cx = cxr * math.cos(rot) - cyr * math.sin(rot) + (x0 + x1) / 2
    cy = cxr * math.sin(rot) + cyr * math.cos(rot) + (y0 + y1) / 2
    ang = lambda ux, uy: math.atan2(uy / ry, ux / rx)
    a0 = ang(xr - cxr, yr - cyr)
    a1 = ang(-xr - cxr, -yr - cyr)
    da = a1 - a0
    if sf == 0 and da > 0:
        da -= 2 * math.pi
    if sf == 1 and da < 0:
        da += 2 * math.pi
    out = []
    for k in range(1, steps + 1):
        a = a0 + da * k / steps
        px = rx * math.cos(a)
        py = ry * math.sin(a)
        out.append((px * math.cos(rot) - py * math.sin(rot) + cx,
                    px * math.sin(rot) + py * math.cos(rot) + cy))
    return out


def stroke_polyline(pts, w):
    """Outline polygon (butt caps) for a polyline stroke."""
    left, right = [], []
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy) or 1
        ox, oy = -dy / ln * w / 2, dx / ln * w / 2
        left += [(x0 + ox, y0 + oy), (x1 + ox, y1 + oy)]
        right += [(x0 - ox, y0 - oy), (x1 - ox, y1 - oy)]
    return left + right[::-1]


def render_svg_mask(path, size, ss=3):
    tree = ET.parse(path)
    root = tree.getroot()
    vb = [float(v) for v in root.get("viewBox").split()]
    S = size * ss
    k = S / vb[2]
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)

    def walk(el, sc, tx, ty):
        tsc, ttx, tty = parse_transform(el.get("transform"))
        sc2 = sc * tsc
        tx2 = tx + sc * ttx
        ty2 = ty + sc * tty
        for ch in el:
            tag = ch.tag.replace(NS, "")
            if tag == "g":
                walk(ch, sc2, tx2, ty2)
                continue
            P = lambda x, y: ((x * sc2 + tx2) * k, (y * sc2 + ty2) * k)
            W = lambda v: v * sc2 * k
            if tag == "path":
                subs = flatten_path(ch.get("d"))
                sw = ch.get("stroke-width")
                if sw and ch.get("fill") == "none":
                    for sub in subs:
                        poly = stroke_polyline([P(*p) for p in sub], W(float(sw)))
                        d.polygon(poly, fill=255)
                else:
                    for sub in subs:
                        d.polygon([P(*p) for p in sub], fill=255)
            elif tag == "line":
                p1 = P(float(ch.get("x1")), float(ch.get("y1")))
                p2 = P(float(ch.get("x2")), float(ch.get("y2")))
                w = W(float(ch.get("stroke-width")))
                if ch.get("stroke-linecap") == "round":
                    L.capsule(d, p1, p2, w, 255)
                else:
                    d.polygon(stroke_polyline([p1, p2], w), fill=255)
            elif tag == "circle":
                c = P(float(ch.get("cx")), float(ch.get("cy")))
                r = W(float(ch.get("r")))
                d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=255)
            elif tag == "rect":
                x, y = P(float(ch.get("x")), float(ch.get("y")))
                w, h = W(float(ch.get("width"))), W(float(ch.get("height")))
                rx = W(float(ch.get("rx") or 0))
                if ch.get("fill", "none") == "none" and ch.get("stroke"):
                    sw = W(float(ch.get("stroke-width")))
                    d.rounded_rectangle([x + sw / 2, y + sw / 2, x + w - sw / 2, y + h - sw / 2],
                                        radius=max(rx - sw / 2, 1), outline=255, width=int(round(sw)))
                else:
                    d.rounded_rectangle([x, y, x + w, y + h], radius=rx, fill=255)
            elif tag == "text":
                pass
    walk(root, 1.0, 0.0, 0.0)
    return mask.resize((size, size), Image.LANCZOS).point(lambda x: 255 if x > 24 else 0)


def render_svg_mark_mask(path, size, ss=3):
    """Same as render_svg_mask but only the transformed mark <g>."""
    tree = ET.parse(path)
    root = tree.getroot()
    vb = [float(x) for x in root.get("viewBox").split()]
    S = size * ss
    k = S / vb[2]
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    import types
    src = render_svg_mask

    def walk(el, sc, tx, ty):
        tsc, ttx, tty = parse_transform(el.get("transform"))
        sc2, tx2, ty2 = sc * tsc, tx + sc * ttx, ty + sc * tty
        for ch in el:
            tag = ch.tag.replace(NS, "")
            if tag == "g":
                walk(ch, sc2, tx2, ty2)
                continue
            P = lambda x, y: ((x * sc2 + tx2) * k, (y * sc2 + ty2) * k)
            W = lambda val: val * sc2 * k
            if tag == "path":
                subs = flatten_path(ch.get("d"))
                sw = ch.get("stroke-width")
                if sw and ch.get("fill") == "none":
                    for sub in subs:
                        d.polygon(stroke_polyline([P(*p) for p in sub], W(float(sw))), fill=255)
                else:
                    for sub in subs:
                        d.polygon([P(*p) for p in sub], fill=255)
            elif tag == "line":
                p1 = P(float(ch.get("x1")), float(ch.get("y1")))
                p2 = P(float(ch.get("x2")), float(ch.get("y2")))
                w = W(float(ch.get("stroke-width")))
                if ch.get("stroke-linecap") == "round":
                    L.capsule(d, p1, p2, w, 255)
                else:
                    d.polygon(stroke_polyline([p1, p2], w), fill=255)
            elif tag == "circle":
                c = P(float(ch.get("cx")), float(ch.get("cy")))
                r = W(float(ch.get("r")))
                d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=255)
    for el in root:
        if el.tag == NS + "g" and el.get("transform"):
            walk(el, 1.0, 0.0, 0.0)
    return mask.resize((size, size), Image.LANCZOS).point(lambda x: 255 if x > 24 else 0)


def alpha_of(img):
    return img.getchannel("A").point(lambda v: 255 if v > 24 else 0)


def diff(a, b):
    pa, pb = a.load(), b.load()
    bad = 0
    for y in range(a.size[1]):
        for x in range(a.size[0]):
            if pa[x, y] != pb[x, y]:
                bad += 1
    return bad / (a.size[0] * a.size[1])


if __name__ == "__main__":
    B.apply_variant("v5")
    size = 512
    # icon: padded body + mark
    direct = B.compose(size, ss=3)
    svg = render_svg_mask(os.path.join(OUT, "ai-benchgauge-icon.svg"), size)
    from PIL import ImageDraw as _ID
    S = size * 3
    tf = B.T(*B.fit(L.mark_bbox(), B.MARK_BOX_W, 512, 512, S))
    acc, accd, wht = B.draw_mark_masks(S, tf)
    union = ImageChops.lighter(ImageChops.lighter(acc, accd), wht).resize((size, size), Image.LANCZOS).point(lambda x: 255 if x > 24 else 0)
    for name, mw in (("ai-benchgauge-icon.svg", B.MARK_BOX_W), ("ai-benchgauge-mark.svg", 660.0)):
        tfu = B.T(*B.fit(L.mark_bbox(), mw, 512, 512, S))
        u1, u2, u3 = B.draw_mark_masks(S, tfu)
        un = ImageChops.lighter(ImageChops.lighter(u1, u2), u3).resize((size, size), Image.LANCZOS).point(lambda x: 255 if x > 24 else 0)
        sm = render_svg_mark_mask(os.path.join(OUT, name), size)
        print(name, "mark diff:", round(diff(un, sm), 5))
    S2 = size * 3
    saved = (L.DIAL, L.BARS, L.BASELINE, L.NEEDLE, L.PIVOT, L.AXIS)
    L.DIAL, L.BARS, L.BASELINE, L.NEEDLE, L.PIVOT = (B.TEMPLATE[k] for k in ("dial", "bars", "baseline", "needle", "pivot"))
    L.AXIS = None
    try:
        tf2 = B.T(*B.fit(L.mark_bbox(), 1024 * 20 / 24, 512, 512, S2))
        macc, maccd, mwht = B.draw_mark_masks(S2, tf2)
        munion = ImageChops.lighter(ImageChops.lighter(macc, maccd), mwht).resize((size, size), Image.LANCZOS).point(lambda x: 255 if x > 24 else 0)
        smt = render_svg_mark_mask(os.path.join(OUT, "ai-benchgauge-menubar-template.svg"), size)
        print("menubar mark diff:", round(diff(munion, smt), 5))
    finally:
        L.DIAL, L.BARS, L.BASELINE, L.NEEDLE, L.PIVOT, L.AXIS = saved
