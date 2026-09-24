#!/usr/bin/env python3
"""Export final AI BenchGauge logo assets (SVG + PNG + icns) into docs/logo."""
import math, os, shutil, subprocess, sys
from PIL import Image, ImageDraw, ImageFont
import logo_lib as L
import build_logo as B

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.abspath(os.path.join(OUT, "..", ".."))
os.makedirs(OUT, exist_ok=True)

B.apply_variant("v5")
INK = L.INK
FONT_STACK = ("-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', "
              "'Helvetica Neue', 'PingFang SC', Arial, sans-serif")


def f2(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


# ------------------------------------------------------------------ svg pieces
def svg_bar(b, baseline):
    x, w, top, r = b["x"], b["w"], b["top"], L.BAR_R
    y1 = baseline
    return (f'<path d="M{f2(x)} {f2(y1)} L{f2(x)} {f2(top + r)} '
            f'A{f2(r)} {f2(r)} 0 0 1 {f2(x + r)} {f2(top)} '
            f'L{f2(x + w - r)} {f2(top)} A{f2(r)} {f2(r)} 0 0 1 {f2(x + w)} {f2(top + r)} '
            f'L{f2(x + w)} {f2(y1)} Z"')


def svg_mark_group(scale, tx, ty, mono=False):
    d, n, pv = L.DIAL, L.NEEDLE, L.PIVOT
    p0, p1 = L.polar(d["cx"], d["cy"], d["r"], d["a0"] % 360), L.polar(d["cx"], d["cy"], d["r"], d["a1"] % 360)
    sweep = (d["a1"] - d["a0"]) % 360
    large = 1 if sweep > 180 else 0
    accent = "#000000" if mono else "url(#accent)"
    ink = "#000000" if mono else INK
    out = [f'<g transform="translate({f2(tx)} {f2(ty)}) scale({scale:.6f})">']
    out.append(f'<path d="M{f2(p0[0])} {f2(p0[1])} A{f2(d["r"])} {f2(d["r"])} 0 {large} 1 '
               f'{f2(p1[0])} {f2(p1[1])}" fill="none" stroke="{accent}" '
               f'stroke-width="{f2(d["w"])}" stroke-linecap="butt"/>')
    if not mono:
        inner = d["r"] - d["w"] / 2 - 16
        for ang in L.TICKS:
            a = L.polar(d["cx"], d["cy"], inner, ang)
            b = L.polar(d["cx"], d["cy"], inner - L.TICK_LEN, ang)
            out.append(f'<line x1="{f2(a[0])}" y1="{f2(a[1])}" x2="{f2(b[0])}" y2="{f2(b[1])}" '
                       f'stroke="{ink}" stroke-width="{f2(L.TICK_W)}" stroke-linecap="round" opacity="0.47"/>')
    tail, tip = L.needle_points()
    out.append(f'<line x1="{f2(tail[0])}" y1="{f2(tail[1])}" x2="{f2(tip[0])}" y2="{f2(tip[1])}" '
               f'stroke="{ink}" stroke-width="{f2(n["w"])}" stroke-linecap="round"/>')
    out.append(f'<circle cx="{f2(pv["cx"])}" cy="{f2(pv["cy"])}" r="{f2(pv["r"])}" fill="{accent}"/>')
    for b in L.BARS:
        fill = "#000000" if mono else (accent if b["layer"] == "accent" else ink)
        op = "" if mono else (f' opacity="{b["alpha"] / 255:.3f}"' if b["layer"] == "accent" else "")
        out.append(svg_bar(b, L.BASELINE) + f' fill="{fill}"{op}/>')
    out.append("</g>")
    return "\n    ".join(out)


def svg_defs(accent_x0, accent_x1):
    return f"""  <defs>
    <linearGradient id="tile" x1="1" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{L.TILE_STOPS[0][1]}"/>
      <stop offset="0.52" stop-color="{L.TILE_STOPS[1][1]}"/>
      <stop offset="1" stop-color="{L.TILE_STOPS[2][1]}"/>
    </linearGradient>
    <linearGradient id="accent" gradientUnits="userSpaceOnUse" x1="{f2(accent_x0)}" y1="414" x2="{f2(accent_x1)}" y2="414">
      <stop offset="0" stop-color="{L.ACCENT_STOPS[0][1]}"/>
      <stop offset="0.52" stop-color="{L.ACCENT_STOPS[1][1]}"/>
      <stop offset="1" stop-color="{L.ACCENT_STOPS[2][1]}"/>
    </linearGradient>
    <radialGradient id="glowA" gradientUnits="userSpaceOnUse" cx="GLAX" cy="GLAY" r="GLAR">
      <stop offset="0" stop-color="#7f8eff" stop-opacity="0.243"/>
      <stop offset="0.35" stop-color="#7f8eff" stop-opacity="0.124"/>
      <stop offset="0.7" stop-color="#7f8eff" stop-opacity="0.038"/>
      <stop offset="1" stop-color="#7f8eff" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glowB" gradientUnits="userSpaceOnUse" cx="GLBX" cy="GLBY" r="GLBR">
      <stop offset="0" stop-color="#4fd6c0" stop-opacity="0.18"/>
      <stop offset="0.35" stop-color="#4fd6c0" stop-opacity="0.092"/>
      <stop offset="0.7" stop-color="#4fd6c0" stop-opacity="0.028"/>
      <stop offset="1" stop-color="#4fd6c0" stop-opacity="0"/>
    </radialGradient>
  </defs>"""


def fit_units(target_w, cx, cy):
    x0, y0, x1, y1 = L.mark_bbox()
    sc = target_w / (x1 - x0)
    tx = cx - sc * (x0 + x1) / 2
    ty = cy - sc * (y0 + y1) / 2
    return sc, tx, ty


def svg_tile_doc(size, body_x, body_w, mark_w, name):
    r = body_w * 0.225
    sc, tx, ty = fit_units(mark_w, body_x + body_w / 2, body_x + body_w / 2)
    glax = body_x + body_w * 0.92
    glay = body_x + body_w * 0.06
    glar = body_w * 0.62
    glbx = body_x + body_w * 0.04
    glby = body_x + body_w * 0.98
    glbr = body_w * 0.66
    defs = (svg_defs(L.mark_bbox()[0], L.mark_bbox()[2])
            .replace("GLAX", f2(glax)).replace("GLAY", f2(glay)).replace("GLAR", f2(glar))
            .replace("GLBX", f2(glbx)).replace("GLBY", f2(glby)).replace("GLBR", f2(glbr)))
    body = f'<rect x="{f2(body_x)}" y="{f2(body_x)}" width="{f2(body_w)}" height="{f2(body_w)}" rx="{f2(r)}"'
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 1024 1024" role="img" aria-label="AI BenchGauge logo">
{defs}
  {body} fill="url(#tile)"/>
  <g clip-path="none">
    <rect x="{f2(body_x)}" y="{f2(body_x)}" width="{f2(body_w)}" height="{f2(body_w)}" rx="{f2(r)}" fill="url(#glowA)"/>
    <rect x="{f2(body_x)}" y="{f2(body_x)}" width="{f2(body_w)}" height="{f2(body_w)}" rx="{f2(r)}" fill="url(#glowB)"/>
  </g>
  {body} fill="none" stroke="#ffffff" stroke-opacity="0.157" stroke-width="3"/>
    {svg_mark_group(sc, tx, ty)}
</svg>
"""
    path = os.path.join(OUT, name)
    open(path, "w").write(svg)
    print("wrote", os.path.relpath(path, REPO))
    return sc, tx, ty


def svg_menubar():
    saved = (L.DIAL, L.BARS, L.BASELINE, L.NEEDLE, L.PIVOT, L.AXIS, L.TICKS)
    L.DIAL, L.BARS, L.BASELINE, L.NEEDLE, L.PIVOT = (B.TEMPLATE[k] for k in
        ("dial", "bars", "baseline", "needle", "pivot"))
    L.AXIS = None
    try:
        x0, y0, x1, y1 = L.mark_bbox()
        sc = 20.0 / (x1 - x0)
        tx = 12 - sc * (x0 + x1) / 2
        ty = 12 - sc * (y0 + y1) / 2
        svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" role="img" aria-label="AI BenchGauge menu bar icon (template)">
    {svg_mark_group(sc, tx, ty, mono=True)}
</svg>
"""
        path = os.path.join(OUT, "ai-benchgauge-menubar-template.svg")
        open(path, "w").write(svg)
        print("wrote", os.path.relpath(path, REPO))
    finally:
        L.DIAL, L.BARS, L.BASELINE, L.NEEDLE, L.PIVOT, L.AXIS, L.TICKS = saved


TAGLINE = "Two leaderboards and your quotas, in the menu bar."
HELV = "/System/Library/Fonts/HelveticaNeue.ttc"


def lockup_metrics():
    fb = ImageFont.truetype(HELV, 68, index=1)
    fr = ImageFont.truetype(HELV, 27, index=0)
    tw = fb.getlength("AI BenchGauge")
    gw = fr.getlength(TAGLINE)
    width = int(234 + max(tw, gw) * 1.06 + 24)
    return width, fb, fr


def svg_lockup():
    width, _, _ = lockup_metrics()
    sc, tx, ty = fit_units(130, 100, 100)
    defs = (svg_defs(L.mark_bbox()[0], L.mark_bbox()[2])
            .replace("GLAX", "184").replace("GLAY", "12").replace("GLAR", "124")
            .replace("GLBX", "8").replace("GLBY", "196").replace("GLBR", "132"))
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="200" viewBox="0 0 {width} 200" role="img" aria-label="AI BenchGauge — {TAGLINE}">
{defs}
  <rect x="0" y="0" width="200" height="200" rx="45" fill="url(#tile)"/>
  <rect x="0" y="0" width="200" height="200" rx="45" fill="url(#glowA)"/>
  <rect x="0" y="0" width="200" height="200" rx="45" fill="url(#glowB)"/>
  <rect x="0.75" y="0.75" width="198.5" height="198.5" rx="44.3" fill="none" stroke="#ffffff" stroke-opacity="0.157" stroke-width="1.5"/>
    {svg_mark_group(sc, tx, ty)}
  <text x="234" y="110" font-family="{FONT_STACK}" font-size="68" font-weight="700" letter-spacing="-1.5" fill="#17224b">AI BenchGauge</text>
  <text x="236" y="154" font-family="{FONT_STACK}" font-size="27" fill="#5c6b8f">{TAGLINE}</text>
</svg>
"""
    path = os.path.join(OUT, "ai-benchgauge-lockup.svg")
    open(path, "w").write(svg)
    print("wrote", os.path.relpath(path, REPO))


# ------------------------------------------------------------------ png + icns
def pngs():
    icon = B.compose(1024, ss=3)
    icon.save(os.path.join(OUT, "ai-benchgauge-icon-1024.png"))
    icon.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "ai-benchgauge-icon-512.png"))
    mark = B.compose(512, ss=4, body=dict(x=0, y=0, w=1024), mark_w=660)
    mark.save(os.path.join(OUT, "ai-benchgauge-mark-512.png"))
    B.render_mono(22, ss=10).save(os.path.join(OUT, "ai-benchgauge-menubar-22.png"))
    B.render_mono(44, ss=8).save(os.path.join(OUT, "ai-benchgauge-menubar-22@2x.png"))
    print("wrote pngs")
    return icon


def lockup_png():
    tile = B.compose(200, ss=4, body=dict(x=0, y=0, w=1024), mark_w=660)
    W, fb, fr = lockup_metrics()
    H = 200
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(tile, (0, 0))
    d = ImageDraw.Draw(out)
    d.text((234, 110), "AI BenchGauge", font=fb, fill=(23, 34, 75, 255), anchor="ls")
    d.text((236, 154), TAGLINE, font=fr, fill=(92, 107, 143, 255), anchor="ls")
    out.save(os.path.join(OUT, "ai-benchgauge-lockup.png"))
    print("wrote lockup png")


ICNS_TYPES = [("icp4", 16), ("ic11", 32), ("ic12", 64), ("ic07", 128),
              ("ic13", 256), ("ic14", 512), ("ic10", 1024)]


def icns(icon):
    """Write an .icns container directly (iconutil is unavailable in the sandbox)."""
    import io, struct
    body = b""
    for ostype, size in ICNS_TYPES:
        buf = io.BytesIO()
        icon.resize((size, size), Image.LANCZOS).save(buf, format="PNG")
        data = buf.getvalue()
        body += ostype.encode() + struct.pack(">I", len(data) + 8) + data
    dst = os.path.join(OUT, "AI-BenchGauge.icns")
    with open(dst, "wb") as fh:
        fh.write(b"icns" + struct.pack(">I", len(body) + 8) + body)
    print("wrote", os.path.relpath(dst, REPO), os.path.getsize(dst), "bytes")


def presentation():
    lock = Image.open(os.path.join(OUT, "ai-benchgauge-lockup.png"))
    icon_l = B.compose(300, ss=4, bg="#f6f8fc")
    icon_d = B.compose(300, ss=4, bg="#0d1119")
    mark = B.compose(300, ss=4, body=dict(x=0, y=0, w=1024), mark_w=660, bg="#f6f8fc")
    sizes = [B.compose(sz, ss=6 if sz <= 64 else 4) for sz in (128, 64, 32, 22, 16)]
    h = 66
    icons = [B.render_mono(sz, ss=10 if sz <= 24 else 6) for sz in (18, 22, 28)]
    bar = Image.new("RGBA", (620, h), (246, 247, 250, 255))
    d = ImageDraw.Draw(bar)
    d.rectangle([0, h - 1, 620, h], fill=(214, 218, 228, 255))
    x = 24
    for im in icons:
        bar.alpha_composite(im, (x, (h - im.size[1]) // 2 - 1))
        x += im.size[0] + 34
    d.rounded_rectangle([x, 20, x + 90, 46], radius=6, fill=(228, 231, 238, 255))
    d.rounded_rectangle([x + 106, 20, x + 150, 46], radius=6, fill=(228, 231, 238, 255))
    PAD = 36
    W = max(lock.size[0], 300 * 3 + PAD * 4, 620) + PAD * 2
    H = PAD * 5 + lock.size[1] + 300 + h + 128
    sheet = Image.new("RGBA", (W, H), (238, 241, 247, 255))
    y = PAD
    sheet.alpha_composite(lock, (PAD, y)); y += lock.size[1] + PAD
    for i, im in enumerate((icon_l, icon_d, mark)):
        sheet.alpha_composite(im, (PAD + i * (300 + PAD), y))
    y += 300 + PAD
    sheet.alpha_composite(bar, (PAD, y)); y += h + PAD
    x = PAD
    for im in sizes:
        sheet.alpha_composite(im, (x, y)); x += im.size[0] + PAD
    sheet.save(os.path.join(OUT, "preview.png"))
    print("wrote docs/logo/preview.png")


if __name__ == "__main__":
    svg_tile_doc(1024, 100, 824, 566, "ai-benchgauge-icon.svg")
    svg_tile_doc(1024, 0, 1024, 660, "ai-benchgauge-mark.svg")
    svg_menubar()
    svg_lockup()
    icon = pngs()
    lockup_png()
    icns(icon)
    presentation()
