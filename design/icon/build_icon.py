"""Builds the Seal app icon from the generated source image (source/b3-seed5.png, made with FLUX.1-schnell,
Apache-2.0; no photograph is used). Flattens it onto a locked palette, adds the bark rays, and writes the three
appearances iOS expects. Run from this folder with a Python that has numpy, scipy and Pillow:
    ~/.agents/venv/bin/python build_icon.py
Outputs: seal-icon-1024.png (light), seal-icon-1024-dark.png, seal-icon-1024-tinted.png
"""
import math
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

SRC = "source/b3-seed5.png"
SS = 2; N = 1024 * SS
a = np.asarray(Image.open(SRC).convert("RGB"))

# source colours (sampled), then each is mapped onto just TWO families: teal and cream, each with shadow tones
pts = {"bg": (30, 300), "cream": (320, 160), "cream_shadow": (230, 440), "cheek": (292, 313),
       "tongue": (385, 372), "mouth": (392, 325), "ink": (300, 255), "shine": (277, 241)}
src = {k: tuple(int(v) for v in a[y, x]) for k, (x, y) in pts.items()}
names = list(src); P = np.array([src[k] for k in names], np.float32)
FINAL = {  # teal family / cream family
    "bg": "#1F998B", "mouth": "#0E5A56", "ink": "#0E5A56",
    "cream": "#FBE8C1", "shine": "#FBE8C1", "cream_shadow": "#EFC587", "cheek": "#EFC587", "tongue": "#0E5A56",
}
hexrgb = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
col = {k: hexrgb(v) for k, v in FINAL.items()}
col_global = col
lab = ((a[:, :, None, :].astype(np.float32) - P[None, None]) ** 2).sum(-1).argmin(-1)
bg_i = names.index("bg")
_ink, _cream = names.index("ink"), names.index("cream")
_cc, _n = ndi.label(lab == _ink)
_sz = ndi.sum(lab == _ink, _cc, range(1, _n + 1))
lab[np.isin(_cc, [i + 1 for i, v in enumerate(_sz) if v < 350])] = _cream


GAP = 56
def build(ROT, heading, head_target_px, out, r_side=370, zoom=2.0, shadow=True):
    global lab
                                   # turn the pup so the face looks toward the top-right corner
    head_c = (312, 296); f = zoom * SS
    head_target = (head_target_px[0] * SS, head_target_px[1] * SS)
    ox = int(head_target[0] - head_c[0] * f); oy = int(head_target[1] - head_c[1] * f)
    W = int(640 * f)
    stack = np.zeros((len(names), N, N), np.float32)
    for k in range(len(names)):
        m = Image.fromarray(((lab == k) * 255).astype(np.uint8)).rotate(ROT, resample=Image.BICUBIC, center=head_c)
        m = m.resize((W, W), Image.BICUBIC)
        c = Image.new("L", (N, N), 0); c.paste(m, (ox, oy))
        stack[k] = ndi.gaussian_filter(np.asarray(c, np.float32) / 255, 2.6 * SS)
    cov = Image.new("L", (N, N), 0); cov.paste(Image.new("L", (W, W), 255), (ox, oy))
    stack[bg_i] += (1 - np.asarray(cov, np.float32) / 255) * 2
    # rotating leaves empty corners in the source; treat "no colour at all" as background too
    stack[bg_i] += (stack.sum(0) < 0.15) * 1.0
    out_lab = stack.argmax(0)
    for _nm in ("ink", "mouth", "tongue"):
        _k = names.index(_nm); _cc, _n = ndi.label(out_lab == _k)
        _sz = ndi.sum(out_lab == _k, _cc, range(1, _n + 1))
        out_lab[np.isin(_cc, [i + 1 for i, v in enumerate(_sz) if v < 4500])] = names.index("cream")
    seal = out_lab != bg_i
    _disk = lambda r: np.fromfunction(lambda y, x: (x - r) ** 2 + (y - r) ** 2 <= r ** 2, (2 * r + 1, 2 * r + 1))
    _open = ndi.binary_opening(seal, structure=_disk(7 * SS))
    out_lab[seal & ~_open] = bg_i; seal = _open

    def rot_pt(px, py):                    # same convention as PIL's counter-clockwise rotate, then to canvas
        dx, dy = px - head_c[0], py - head_c[1]; t = math.radians(ROT)
        return (head_target[0] + (dx * math.cos(t) + dy * math.sin(t)) * f, head_target[1] + (-dx * math.sin(t) + dy * math.cos(t)) * f)
    mx, my = rot_pt(392, 342)

    col = dict(col_global)
    if not shadow: col["cream_shadow"] = col["cream"]
    base = np.zeros((N, N, 3), np.uint8); base[:] = col["bg"]
    im = Image.fromarray(base); dr = ImageDraw.Draw(im)
    # three straight bark lines fanning toward the top-right, centred on where the mouth points
    # start each ray just outside the head edge in its own direction, so none is hidden behind the head
    hc = head_target; Rh = 198 * f
    hc = head_target; Rh = 198 * f
    # corner-safe region: inside the icon's rounded square, inset so no ray ever touches an edge or corner
    inset, rad = 46, 229
    def inside(px, py):
        x, y = px / SS, py / SS
        cx_ = min(max(x, inset + rad), 1024 - inset - rad); cy_ = min(max(y, inset + rad), 1024 - inset - rad)
        return (x - cx_) ** 2 + (y - cy_) ** 2 <= rad ** 2 and inset <= x <= 1024 - inset and inset <= y <= 1024 - inset
    for ang, length in ((heading - 26, 175), (heading, 235), (heading + 26, 150)):
        t = math.radians(ang); w = 38 * SS; dx, dy = math.cos(t), math.sin(t)
        ux, uy = mx - hc[0], my - hc[1]
        bq = ux * dx + uy * dy; cq = ux * ux + uy * uy - Rh * Rh
        t_edge = -bq + math.sqrt(max(bq * bq - cq, 0))
        r0 = t_edge + GAP * SS; r1 = r0 + length * SS
        while r1 > r0 + 60 * SS and not (inside(mx + r1 * dx, my + r1 * dy) and inside(mx + (r1 + 19 * SS) * dx, my + (r1 + 19 * SS) * dy)):
            r1 -= 4 * SS                                   # shorten until clear of the corners and edges
        p0 = (mx + r0 * dx, my + r0 * dy); p1 = (mx + r1 * dx, my + r1 * dy)
        dr.line([p0, p1], fill=col["cream"], width=int(w))
        for p in (p0, p1): dr.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=col["cream"])
    arr = np.asarray(im).copy()
    disk = lambda r: np.fromfunction(lambda y, x: (x - r) ** 2 + (y - r) ** 2 <= r ** 2, (2 * r + 1, 2 * r + 1))
    arr[ndi.binary_dilation(seal, structure=disk(16 * SS))] = col["bg"]
    for k, nm in enumerate(names):
        if k != bg_i: arr[(out_lab == k) & seal] = col[nm]
    sh_i, cr_i, sn_i = names.index("cream_shadow"), names.index("cream"), names.index("shine")
    cream_m = (out_lab == cr_i) | (out_lab == sn_i)
    band = (out_lab == sh_i) & ndi.binary_dilation(cream_m, structure=disk(15 * SS))
    band = ndi.gaussian_filter(band.astype(np.float32), 3 * SS) > 0.5
    # clean tongue: smooth cream ellipse, only where the mouth is
    pts_t = [rot_pt(392 + 27 * math.cos(math.radians(a_)), 366 + 13 * math.sin(math.radians(a_))) for a_ in range(0, 360, 4)]
    tmask = Image.new("L", (N, N), 0); ImageDraw.Draw(tmask).polygon(pts_t, fill=255)
    mouth_region = (out_lab == names.index("mouth")) | (out_lab == names.index("tongue"))
    inner = ndi.binary_erosion(mouth_region, structure=np.fromfunction(lambda y, x: (x - 12) ** 2 + (y - 12) ** 2 <= 144, (25, 25)))   # keeps a dark rim around the tongue
    arr[(np.asarray(tmask) > 0) & inner] = col["cream_shadow"]
    imf = Image.fromarray(arr); dw = ImageDraw.Draw(imf)
    def whisker(p0, p1):
        q0, q1 = rot_pt(*p0), rot_pt(*p1); w = 12 * SS
        dw.line([q0, q1], fill=col["ink"], width=int(w))
        for q in (q0, q1): dw.ellipse((q[0] - w / 2, q[1] - w / 2, q[0] + w / 2, q[1] + w / 2), fill=col["ink"])
    for end in ((262, 296), (256, 314), (262, 332)): whisker((328, 312), end)
    Image.fromarray(np.asarray(imf)).resize((1024, 1024), Image.LANCZOS).save(out)



def render(shadow, out, ht=(410, 545), zoom=1.8):
    build(18, -26, ht, out, zoom=zoom, shadow=shadow)

def with_palette(overrides, out):
    saved = dict(col_global)
    col_global.update({k: hexrgb(v) for k, v in overrides.items()})
    try:
        render(True, out, ht=(410, 545), zoom=1.8)
    finally:
        col_global.clear(); col_global.update(saved)

if __name__ == "__main__":
    with_palette({}, "seal-icon-1024.png")                                    # light (the approved look)
    with_palette({"bg": "#0F3F3C"}, "seal-icon-1024-dark.png")                # dark appearance: deeper teal background
    gray = {"bg": "#151515", "cream": "#F2F2F2", "shine": "#F2F2F2", "cream_shadow": "#B8B8B8", "cheek": "#B8B8B8",
            "tongue": "#4A4A4A", "mouth": "#2B2B2B", "ink": "#2B2B2B"}
    with_palette(gray, "seal-icon-1024-tinted.png")                           # tinted appearance: grayscale, iOS applies the tint
    print("ok")
