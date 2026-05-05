"""
Generate top-down painted-illustrated ship sprites for Space Battle.

Constraints:
- Hull pixels are STRICTLY grayscale (R==G==B) so the engine can multiplicative-tint by faction color.
- Engine plumes / muzzle glows are slightly desaturated warm white so they tint cleanly too.
- Transparent background; ship points up (-Y), matching hull JSON convention.
- Painted feel: gradient body shading, rim light, panel lines, hard highlights, soft AO.
"""

import math
import os
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
SHIPS_DIR = os.path.join(OUT_DIR, "ships")
os.makedirs(SHIPS_DIR, exist_ok=True)

# ---------- helpers ----------

def gray(v, a=255):
    """Grayscale color (R==G==B), so multiplicative tint stays neutral."""
    v = max(0, min(255, int(v)))
    return (v, v, v, a)

def warm_white(v, a=255):
    """Slightly desaturated warm-white for engine plumes; still tints cleanly."""
    v = max(0, min(255, int(v)))
    return (v, max(0, v - 6), max(0, v - 14), a)  # subtle warm bias

def lerp(a, b, t):
    return a + (b - a) * t

def blit(dst, src, pos=(0, 0)):
    dst.alpha_composite(src, pos)

def soft_blur(img, r):
    return img.filter(ImageFilter.GaussianBlur(radius=r))


# ---------- core painting primitives ----------

def make_layer(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def build_hull_mask(w, h, polygon):
    """Anti-aliased polygon mask (super-sampled)."""
    SS = 4
    big = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(big)
    poly_ss = [(x * SS, y * SS) for (x, y) in polygon]
    d.polygon(poly_ss, fill=255)
    return big.resize((w, h), Image.LANCZOS)

def paint_body(w, h, mask, base=110, light=210, shadow=55, light_dir=(-0.5, -0.7)):
    """Apply gradient lighting to a masked silhouette and return RGBA layer."""
    arr_mask = np.asarray(mask, dtype=np.float32) / 255.0  # H, W

    ys, xs = np.indices((h, w))
    # Normalize
    nx = (xs - w / 2) / (w / 2)
    ny = (ys - h / 2) / (h / 2)

    # Light dot-product (top-left light): components are flipped because image y goes down.
    lx, ly = light_dir
    # Distance-to-edge of mask drives "roundness" of the volumetric shading.
    # Quick proxy: gaussian blurred mask gives soft falloff = pseudo-thickness.
    soft = np.asarray(mask.filter(ImageFilter.GaussianBlur(radius=max(2, w // 18))),
                      dtype=np.float32) / 255.0
    thickness = np.clip(soft, 0.0, 1.0)

    # Base shading: dark at edges (low thickness) → mid in middle. Then add directional light.
    body = base * thickness + shadow * (1 - thickness)
    # Directional component: project a normal that bulges from center
    nl = (-nx) * lx + (-ny) * ly  # higher where lit
    nl = np.clip(nl, -1.0, 1.0)
    body = body + (light - base) * np.clip(nl, 0.0, 1.0) * (0.3 + 0.7 * thickness)
    body = np.clip(body, 0, 255)

    rgb = np.stack([body, body, body], axis=-1).astype(np.uint8)
    alpha = (arr_mask * 255).astype(np.uint8)
    out = np.dstack([rgb, alpha])
    return Image.fromarray(out, "RGBA")

def add_rim_light(layer, mask, intensity=70, light_dir=(-0.5, -0.7)):
    """Bright rim where ship faces the light source."""
    w, h = layer.size
    # Edge of mask
    eroded = mask.filter(ImageFilter.MinFilter(3))
    edge = Image.eval(mask, lambda v: v)
    # rim = mask - eroded
    arr_m = np.asarray(mask, dtype=np.int16)
    arr_e = np.asarray(eroded, dtype=np.int16)
    rim = np.clip(arr_m - arr_e, 0, 255).astype(np.uint8)
    rim_img = Image.fromarray(rim, "L").filter(ImageFilter.GaussianBlur(radius=1))

    ys, xs = np.indices((h, w))
    nx = (xs - w / 2) / (w / 2)
    ny = (ys - h / 2) / (h / 2)
    lx, ly = light_dir
    facing = np.clip((-nx) * lx + (-ny) * ly, 0.0, 1.0)
    rim_arr = np.asarray(rim_img, dtype=np.float32) / 255.0
    val = (intensity * facing * rim_arr).astype(np.uint8)
    rgba = np.dstack([255 * np.ones_like(val), 255 * np.ones_like(val), 255 * np.ones_like(val), val])
    rim_layer = Image.fromarray(rgba.astype(np.uint8), "RGBA")
    layer.alpha_composite(rim_layer)

def add_inner_shadow(layer, mask, depth=80):
    """Soft AO inside the silhouette near edges."""
    w, h = layer.size
    blurred = mask.filter(ImageFilter.GaussianBlur(radius=max(2, w // 25)))
    arr_m = np.asarray(mask, dtype=np.float32) / 255.0
    arr_b = np.asarray(blurred, dtype=np.float32) / 255.0
    shadow = np.clip(arr_m - arr_b, 0.0, 1.0) * 0  # zero out
    # Actually we want darker INSIDE near edges; use (1 - blurred) * mask
    inner = arr_m * (1.0 - arr_b)
    val = np.clip(inner * depth, 0, 255).astype(np.uint8)
    rgba = np.dstack([np.zeros_like(val), np.zeros_like(val), np.zeros_like(val), val])
    layer.alpha_composite(Image.fromarray(rgba, "RGBA"))

def stroke_panel_lines(layer, mask, lines, width=1, color=35, alpha=180):
    """Draw dark panel lines clipped to the mask."""
    w, h = layer.size
    pl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(pl)
    for line in lines:
        d.line(line, fill=(color, color, color, alpha), width=width)
    # Clip to mask
    arr_pl = np.array(pl)
    arr_m = np.asarray(mask, dtype=np.uint8)
    arr_pl[..., 3] = (arr_pl[..., 3].astype(np.uint16) * arr_m // 255).astype(np.uint8)
    pl = Image.fromarray(arr_pl, "RGBA")
    pl = pl.filter(ImageFilter.GaussianBlur(0.5))
    layer.alpha_composite(pl)

def add_canopy(layer, mask, cx, cy, rx, ry, dark=40, highlight=210):
    """A reflective gray cockpit / bridge dome."""
    w, h = layer.size
    cp = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(cp)
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=gray(dark, 240))
    # specular crescent
    sp = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sp)
    sd.ellipse((cx - rx * 0.7, cy - ry * 0.85, cx + rx * 0.2, cy - ry * 0.1),
               fill=gray(highlight, 230))
    sp = soft_blur(sp, max(1, rx // 4))
    cp.alpha_composite(sp)
    # Clip to mask
    arr_cp = np.array(cp)
    arr_m = np.asarray(mask, dtype=np.uint8)
    arr_cp[..., 3] = (arr_cp[..., 3].astype(np.uint16) * arr_m // 255).astype(np.uint8)
    layer.alpha_composite(Image.fromarray(arr_cp, "RGBA"))

def add_engine_glow(layer, x, y, r_inner, r_outer, core=240, halo=200):
    """Hot warm-white plume at engine bell. Slight warm bias still tints OK."""
    w, h = layer.size
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((x - r_outer, y - r_outer, x + r_outer, y + r_outer),
               fill=warm_white(halo, 90))
    glow = soft_blur(glow, r_outer * 0.5)
    # Hot core (no blur)
    core_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(core_layer)
    cd.ellipse((x - r_inner, y - r_inner, x + r_inner, y + r_inner),
               fill=warm_white(core, 230))
    core_layer = soft_blur(core_layer, max(0.5, r_inner * 0.25))
    glow.alpha_composite(core_layer)
    layer.alpha_composite(glow)

def add_engine_bell(layer, mask, x, y, r, depth=20):
    """Dark engine bell - circular dark patch on rear hull."""
    w, h = layer.size
    bell = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bell)
    bd.ellipse((x - r, y - r, x + r, y + r), fill=gray(depth, 255))
    # subtle inner ring
    bd.ellipse((x - r + 1, y - r + 1, x + r - 1, y + r - 1), outline=gray(depth + 25, 255), width=1)
    # Clip
    arr_b = np.array(bell)
    arr_m = np.asarray(mask, dtype=np.uint8)
    arr_b[..., 3] = (arr_b[..., 3].astype(np.uint16) * arr_m // 255).astype(np.uint8)
    layer.alpha_composite(Image.fromarray(arr_b, "RGBA"))

def add_hardpoint(layer, mask, x, y, w_, h_, color=70):
    """Small dark rectangle (weapon mount / panel)."""
    w, h = layer.size
    hp = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(hp)
    d.rounded_rectangle((x - w_ / 2, y - h_ / 2, x + w_ / 2, y + h_ / 2),
                        radius=max(1, min(w_, h_) / 4),
                        fill=gray(color, 220))
    arr = np.array(hp)
    arr_m = np.asarray(mask, dtype=np.uint8)
    arr[..., 3] = (arr[..., 3].astype(np.uint16) * arr_m // 255).astype(np.uint8)
    layer.alpha_composite(Image.fromarray(arr, "RGBA"))

def add_running_light(layer, x, y, r=2, brightness=240):
    """Tiny bright pinpoint, neutral so it tints with the ship."""
    w, h = layer.size
    rl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(rl)
    d.ellipse((x - r * 2, y - r * 2, x + r * 2, y + r * 2),
              fill=gray(brightness, 70))
    rl = soft_blur(rl, r)
    d2 = ImageDraw.Draw(rl)
    d2.ellipse((x - r, y - r, x + r, y + r), fill=gray(brightness, 255))
    layer.alpha_composite(rl)


# ---------- ship designs ----------
# All ships point up. Center of canvas = ship origin.
# Hull polygon coords in IMAGE space (top-left origin).

def design_fighter(scale=4):
    """Sleek interceptor: 96 x 240 (24 x 60 hull units * 4)."""
    W, H = 96, 240
    cx, cy = W // 2, H // 2

    # Silhouette: long nose, swept-back trailing edge with two small wings
    poly = [
        (cx, 16),                  # nose
        (cx + 6, 60),              # forward edge L
        (cx + 14, 110),            # mid wing point
        (cx + 38, 168),            # wingtip R
        (cx + 30, 188),            # rear wing notch
        (cx + 14, 196),            # engine block edge R
        (cx + 12, 212),            # engine corner R
        (cx - 12, 212),
        (cx - 14, 196),
        (cx - 30, 188),
        (cx - 38, 168),
        (cx - 14, 110),
        (cx - 6, 60),
    ]
    mask = build_hull_mask(W, H, poly)
    layer = paint_body(W, H, mask, base=120, light=215, shadow=55)
    add_inner_shadow(layer, mask, depth=70)
    add_rim_light(layer, mask, intensity=85)

    # Spine line down the middle and wing seams
    panel_lines = [
        [(cx, 22), (cx, 200)],
        [(cx - 6, 60), (cx - 14, 110)],
        [(cx + 6, 60), (cx + 14, 110)],
        [(cx - 14, 110), (cx - 30, 188)],
        [(cx + 14, 110), (cx + 30, 188)],
        [(cx - 14, 196), (cx + 14, 196)],
    ]
    stroke_panel_lines(layer, mask, panel_lines, width=1, color=30, alpha=200)

    # Canopy (slightly forward)
    add_canopy(layer, mask, cx, 96, rx=7, ry=14, dark=40, highlight=210)

    # Wing hardpoints
    add_hardpoint(layer, mask, cx - 22, 150, 4, 10, color=60)
    add_hardpoint(layer, mask, cx + 22, 150, 4, 10, color=60)

    # Engine bells + glow (twin)
    add_engine_bell(layer, mask, cx - 7, 208, r=4, depth=25)
    add_engine_bell(layer, mask, cx + 7, 208, r=4, depth=25)
    add_engine_glow(layer, cx - 7, 218, r_inner=4, r_outer=14)
    add_engine_glow(layer, cx + 7, 218, r_inner=4, r_outer=14)

    # Running light at nose
    add_running_light(layer, cx, 22, r=2, brightness=235)

    return layer


def design_heavy_fighter(scale=4):
    """Stockier brawler: 128 x 256."""
    W, H = 128, 256
    cx, cy = W // 2, H // 2

    poly = [
        (cx, 18),
        (cx + 10, 50),
        (cx + 22, 90),
        (cx + 50, 140),
        (cx + 56, 180),
        (cx + 44, 200),
        (cx + 26, 210),
        (cx + 22, 230),
        (cx - 22, 230),
        (cx - 26, 210),
        (cx - 44, 200),
        (cx - 56, 180),
        (cx - 50, 140),
        (cx - 22, 90),
        (cx - 10, 50),
    ]
    mask = build_hull_mask(W, H, poly)
    layer = paint_body(W, H, mask, base=115, light=210, shadow=50)
    add_inner_shadow(layer, mask, depth=80)
    add_rim_light(layer, mask, intensity=80)

    panel_lines = [
        [(cx, 24), (cx, 220)],
        [(cx - 22, 90), (cx - 50, 140)],
        [(cx + 22, 90), (cx + 50, 140)],
        [(cx - 22, 90), (cx + 22, 90)],
        [(cx - 22, 230), (cx + 22, 230)],
        [(cx - 50, 140), (cx - 56, 180)],
        [(cx + 50, 140), (cx + 56, 180)],
    ]
    stroke_panel_lines(layer, mask, panel_lines, width=1, color=28, alpha=200)

    # Twin canopy
    add_canopy(layer, mask, cx - 9, 100, rx=7, ry=12, dark=38, highlight=205)
    add_canopy(layer, mask, cx + 9, 100, rx=7, ry=12, dark=38, highlight=205)

    # Wing hardpoints (heavy: two per wing)
    add_hardpoint(layer, mask, cx - 38, 155, 5, 14, color=55)
    add_hardpoint(layer, mask, cx + 38, 155, 5, 14, color=55)
    add_hardpoint(layer, mask, cx - 46, 178, 4, 10, color=55)
    add_hardpoint(layer, mask, cx + 46, 178, 4, 10, color=55)

    # Four engines
    for ex in (cx - 14, cx - 4, cx + 4, cx + 14):
        add_engine_bell(layer, mask, ex, 226, r=4, depth=22)
        add_engine_glow(layer, ex, 236, r_inner=4, r_outer=14)

    add_running_light(layer, cx, 24, r=2, brightness=230)
    return layer


def design_torpedo_boat(scale=4):
    """Bulky midsection with bay door: 112 x 224."""
    W, H = 112, 224
    cx = W // 2

    poly = [
        (cx, 18),
        (cx + 8, 38),
        (cx + 20, 64),
        (cx + 38, 110),
        (cx + 42, 156),
        (cx + 34, 184),
        (cx + 18, 200),
        (cx - 18, 200),
        (cx - 34, 184),
        (cx - 42, 156),
        (cx - 38, 110),
        (cx - 20, 64),
        (cx - 8, 38),
    ]
    mask = build_hull_mask(W, H, poly)
    layer = paint_body(W, H, mask, base=108, light=200, shadow=48)
    add_inner_shadow(layer, mask, depth=85)
    add_rim_light(layer, mask, intensity=70)

    panel_lines = [
        [(cx, 24), (cx, 196)],
        [(cx - 22, 90), (cx + 22, 90)],     # forward bay door seam
        [(cx - 24, 145), (cx + 24, 145)],   # rear bay door seam
        [(cx - 22, 90), (cx - 24, 145)],
        [(cx + 22, 90), (cx + 24, 145)],
        [(cx - 38, 110), (cx - 42, 156)],
        [(cx + 38, 110), (cx + 42, 156)],
    ]
    stroke_panel_lines(layer, mask, panel_lines, width=1, color=26, alpha=210)

    # Forward canopy (smaller, higher up)
    add_canopy(layer, mask, cx, 60, rx=6, ry=10, dark=42, highlight=200)

    # Torpedo bay (darker rectangular recess in middle)
    add_hardpoint(layer, mask, cx, 118, 30, 36, color=42)
    # Inner bay detailing - two darker tubes
    add_hardpoint(layer, mask, cx - 7, 118, 6, 26, color=22)
    add_hardpoint(layer, mask, cx + 7, 118, 6, 26, color=22)

    # Side hardpoints
    add_hardpoint(layer, mask, cx - 32, 168, 5, 12, color=55)
    add_hardpoint(layer, mask, cx + 32, 168, 5, 12, color=55)

    # Twin large engines
    add_engine_bell(layer, mask, cx - 10, 196, r=6, depth=22)
    add_engine_bell(layer, mask, cx + 10, 196, r=6, depth=22)
    add_engine_glow(layer, cx - 10, 208, r_inner=5, r_outer=18)
    add_engine_glow(layer, cx + 10, 208, r_inner=5, r_outer=18)

    add_running_light(layer, cx, 24, r=2, brightness=225)
    return layer


def design_corvette(scale=2):
    """Hammerhead front, narrow body, flared engine block: 256 x 640.
    Hull is 81w x 216h units; we render at ~3x. """
    W, H = 256, 640
    cx = W // 2

    # Coordinates derived from corvette_hull.json (translated to image space):
    #   nose y=-108  → y=20
    #   neck y=-36  → y=216
    #   neck y=+36  → y=288
    #   rear y=+108 → y=504
    # Width: front 76 (-31.5..+31.5 → 64..192? scale*3 = 96..160), neck ±18 ~54, rear ±40.5 ~120
    # Use scale = 3 * coord
    s = 3
    OY = 320  # vertical center of ship in canvas

    poly = [
        (cx, 20),                                     # nose
        (cx + 25.2 * s, 70),                          # bow shoulder R
        (cx + 31.5 * s, 130),                         # widest R (head)
        (cx + 18 * s, 175),                           # head/neck transition
        (cx + 18 * s, 460),                           # narrow body R
        (cx + 40.5 * s, 620),                         # engine flare R
        (cx - 40.5 * s, 620),                         # engine flare L
        (cx - 18 * s, 460),                           # narrow body L
        (cx - 18 * s, 175),
        (cx - 31.5 * s, 130),
        (cx - 25.2 * s, 70),
    ]
    mask = build_hull_mask(W, H, poly)
    layer = paint_body(W, H, mask, base=110, light=205, shadow=52)
    add_inner_shadow(layer, mask, depth=85)
    add_rim_light(layer, mask, intensity=75)

    panel_lines = [
        [(cx, 30), (cx, 600)],                       # spine
        [(cx - 18 * s, 175), (cx + 18 * s, 175)],   # head/body seam
        [(cx - 18 * s, 460), (cx + 18 * s, 460)],   # body/engine seam
        [(cx - 25, 100), (cx + 25, 100)],            # bow detail
        [(cx - 25, 145), (cx + 25, 145)],
        [(cx - 12, 220), (cx + 12, 220)],
        [(cx - 12, 280), (cx + 12, 280)],
        [(cx - 12, 340), (cx + 12, 340)],
        [(cx - 12, 400), (cx + 12, 400)],
        [(cx - 30 * s, 550), (cx + 30 * s, 550)],   # engine block
    ]
    stroke_panel_lines(layer, mask, panel_lines, width=2, color=25, alpha=210)

    # Bridge tower (raised superstructure, top-down = a brighter elongated dome)
    bridge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bridge)
    bd.rounded_rectangle((cx - 14, 280, cx + 14, 360), radius=8, fill=gray(150, 230))
    bridge = soft_blur(bridge, 1.5)
    add_canopy(bridge, mask, cx, 312, rx=8, ry=22, dark=45, highlight=215)
    arr = np.array(bridge)
    arr_m = np.asarray(mask, dtype=np.uint8)
    arr[..., 3] = (arr[..., 3].astype(np.uint16) * arr_m // 255).astype(np.uint8)
    layer.alpha_composite(Image.fromarray(arr, "RGBA"))

    # Hammerhead turrets (two on the head)
    add_hardpoint(layer, mask, cx - 50, 100, 14, 14, color=55)
    add_hardpoint(layer, mask, cx + 50, 100, 14, 14, color=55)
    # Small turrets along spine
    for ty in (220, 400):
        add_hardpoint(layer, mask, cx - 22, ty, 10, 10, color=60)
        add_hardpoint(layer, mask, cx + 22, ty, 10, 10, color=60)

    # Engine block — three bells
    for ex_off, r in ((-60, 12), (0, 16), (60, 12)):
        add_engine_bell(layer, mask, cx + ex_off, 600, r=r, depth=20)
        add_engine_glow(layer, cx + ex_off, 624, r_inner=r * 0.7, r_outer=r * 2.2)

    add_running_light(layer, cx, 28, r=3, brightness=235)
    add_running_light(layer, cx - 31 * s, 130, r=2, brightness=215)
    add_running_light(layer, cx + 31 * s, 130, r=2, brightness=215)
    return layer


def design_capital(scale=2):
    """Star Destroyer wedge: 384 x 960.
    Hull 270w x 648h; render at ~1.4x. """
    W, H = 384, 960
    cx = W // 2

    # Convert hull units to image coords. vertical: nose y=-540 → y=40, mid y=-270 → y=380, rear y=108 → y=920
    # widths: nose 0, mid ±27 (image scale s_w * 27), rear ±135 (s_w * 135)
    # Use s = 1.3 (so widest = 175.5px each side) → fits in 384 with margin.
    s = 1.3
    poly = [
        (cx, 40),                              # nose
        (cx + 27 * s, 380),                    # mid shoulder R
        (cx + 81 * s, 650),                    # back/mid R
        (cx + 135 * s, 920),                   # rear R
        (cx - 135 * s, 920),                   # rear L
        (cx - 81 * s, 650),
        (cx - 27 * s, 380),
    ]
    mask = build_hull_mask(W, H, poly)
    layer = paint_body(W, H, mask, base=115, light=215, shadow=50)
    add_inner_shadow(layer, mask, depth=90)
    add_rim_light(layer, mask, intensity=80)

    # Heavy paneling
    panel_lines = [
        [(cx, 50), (cx, 905)],                                  # spine
        [(cx - 27 * s, 380), (cx + 27 * s, 380)],              # forward shoulder seam
        [(cx - 81 * s, 650), (cx + 81 * s, 650)],              # mid/aft seam
        # Diagonal panel breaks fanning out
        [(cx - 14, 100), (cx - 60, 350)],
        [(cx + 14, 100), (cx + 60, 350)],
        [(cx - 30, 200), (cx - 100, 500)],
        [(cx + 30, 200), (cx + 100, 500)],
        # Lateral panels
        [(cx - 50 * s, 480), (cx + 50 * s, 480)],
        [(cx - 70 * s, 580), (cx + 70 * s, 580)],
        [(cx - 100 * s, 750), (cx + 100 * s, 750)],
        [(cx - 120 * s, 850), (cx + 120 * s, 850)],
    ]
    stroke_panel_lines(layer, mask, panel_lines, width=2, color=22, alpha=220)

    # Bridge tower at rear (raised, painted brighter)
    bt = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    btd = ImageDraw.Draw(bt)
    btd.rounded_rectangle((cx - 26, 720, cx + 26, 820), radius=10, fill=gray(155, 240))
    btd.rounded_rectangle((cx - 18, 740, cx + 18, 805), radius=6, fill=gray(180, 255))
    # twin command sensors
    btd.ellipse((cx - 22, 740, cx - 12, 750), fill=gray(80, 255))
    btd.ellipse((cx + 12, 740, cx + 22, 750), fill=gray(80, 255))
    bt = soft_blur(bt, 1.0)
    arr = np.array(bt)
    arr_m = np.asarray(mask, dtype=np.uint8)
    arr[..., 3] = (arr[..., 3].astype(np.uint16) * arr_m // 255).astype(np.uint8)
    layer.alpha_composite(Image.fromarray(arr, "RGBA"))

    # Gun batteries (two rows along the flanks)
    for y in (450, 540, 630, 720):
        for off in (-1, 1):
            distance = 0.55 + (y - 380) / 1100  # widen toward rear
            x = cx + off * (27 * s + (135 * s - 27 * s) * distance)
            add_hardpoint(layer, mask, x - off * 14, y, 10, 14, color=55)
            # turret barrel hint
            add_hardpoint(layer, mask, x - off * 14, y - 6, 3, 8, color=35)

    # Forward heavy spine batteries
    add_hardpoint(layer, mask, cx, 250, 14, 22, color=55)
    add_hardpoint(layer, mask, cx, 320, 14, 22, color=55)

    # Engine bank: 4 engines along the rear
    engine_y = 905
    for ex_off, r in ((-90, 18), (-30, 22), (30, 22), (90, 18)):
        add_engine_bell(layer, mask, cx + ex_off, engine_y, r=r, depth=18)
        add_engine_glow(layer, cx + ex_off, engine_y + 30, r_inner=r * 0.6, r_outer=r * 2.5)

    # Running lights along the edges
    for y in (200, 350, 500, 650, 800):
        for off in (-1, 1):
            distance = 0.4 + (y - 40) / 920
            x = cx + off * (27 * s * (1 - distance) + 135 * s * distance) * 0.92
            add_running_light(layer, x, y, r=1, brightness=210)
    add_running_light(layer, cx, 50, r=3, brightness=245)
    return layer


# ---------- main ----------

def save_with_trim(img, path):
    # Trim to non-empty bbox + small padding
    bbox = img.getbbox()
    if bbox:
        pad = 4
        l, t, r, b = bbox
        l = max(0, l - pad); t = max(0, t - pad)
        r = min(img.width, r + pad); b = min(img.height, b + pad)
        img = img.crop((l, t, r, b))
    img.save(path)
    return img.size

def main():
    designs = {
        "fighter": design_fighter,
        "heavy_fighter": design_heavy_fighter,
        "torpedo_boat": design_torpedo_boat,
        "corvette": design_corvette,
        "capital": design_capital,
    }
    sizes = {}
    for name, fn in designs.items():
        img = fn()
        path = os.path.join(SHIPS_DIR, f"{name}.png")
        size = save_with_trim(img, path)
        sizes[name] = size
        print(f"  {name}: {size[0]}x{size[1]} -> {path}")
    # Atlas summary
    with open(os.path.join(SHIPS_DIR, "_sizes.json"), "w") as f:
        json.dump(sizes, f, indent=2)

if __name__ == "__main__":
    main()
