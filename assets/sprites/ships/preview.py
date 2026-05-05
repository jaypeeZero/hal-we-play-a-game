"""
Preview compositions:
  preview_lineup.png  — all five ships at uniform display height to compare style
  preview_scale.png   — ships at relative in-game scale on a dark space background
  preview_tints.png   — fighter rendered in 4 faction tints to verify grayscale tints cleanly
"""

import os
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
SHIPS_DIR = os.path.join(OUT_DIR, "ships")
PREVIEW_DIR = os.path.join(OUT_DIR, "previews")
os.makedirs(PREVIEW_DIR, exist_ok=True)

SHIPS = ["fighter", "heavy_fighter", "torpedo_boat", "corvette", "capital"]
HULL_LENGTH = {  # from hull JSONs (Y span)
    "fighter": 31,
    "heavy_fighter": 42,
    "torpedo_boat": 36,
    "corvette": 216,
    "capital": 648,
}

# Faction tint colors (multiply with grayscale)
TINTS = {
    "neutral": (255, 255, 255),
    "player_blue": (110, 180, 255),
    "enemy_red": (255, 110, 110),
    "pirate_amber": (255, 180, 80),
}

def starfield(w, h, density=0.0008, seed=42):
    rng = np.random.default_rng(seed)
    bg = Image.new("RGBA", (w, h), (8, 10, 18, 255))
    # Add some nebula wash
    nb = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    nd = ImageDraw.Draw(nb)
    for _ in range(8):
        cx = rng.integers(0, w); cy = rng.integers(0, h)
        r = rng.integers(80, 200)
        col = (rng.integers(20, 50), rng.integers(15, 40), rng.integers(40, 80), 70)
        nd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
    nb = nb.filter(ImageFilter.GaussianBlur(60))
    bg.alpha_composite(nb)
    # Stars
    n_stars = int(w * h * density)
    sd = ImageDraw.Draw(bg)
    for _ in range(n_stars):
        x = rng.integers(0, w); y = rng.integers(0, h)
        b = rng.integers(140, 255)
        sd.point((x, y), fill=(b, b, b, 255))
    # A few brighter stars with diffraction
    for _ in range(n_stars // 80):
        x = rng.integers(0, w); y = rng.integers(0, h)
        b = rng.integers(200, 255)
        sd.ellipse((x - 1, y - 1, x + 1, y + 1), fill=(b, b, b, 255))
    return bg

def tint(img, color):
    """Multiplicative tint of a grayscale RGBA sprite."""
    arr = np.array(img).astype(np.float32)
    r, g, b = color
    arr[..., 0] = arr[..., 0] * (r / 255.0)
    arr[..., 1] = arr[..., 1] * (g / 255.0)
    arr[..., 2] = arr[..., 2] * (b / 255.0)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

def label(draw, text, xy, color=(220, 220, 220, 255), size=18):
    # PIL default font
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", size)
    except Exception:
        font = ImageFont.load_default()
    draw.text(xy, text, fill=color, font=font)

def preview_lineup():
    """Each ship resized to the same display height (180px) for style comparison."""
    target_h = 180
    pad = 30
    imgs = []
    for n in SHIPS:
        img = Image.open(os.path.join(SHIPS_DIR, f"{n}.png")).convert("RGBA")
        scale = target_h / img.height
        img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
        imgs.append((n, img))
    total_w = sum(i[1].width for i in imgs) + pad * (len(imgs) + 1)
    total_h = target_h + 80
    canvas = starfield(total_w, total_h)
    d = ImageDraw.Draw(canvas)
    x = pad
    for n, img in imgs:
        y = (total_h - img.height) // 2 - 10
        canvas.alpha_composite(img, (x, y))
        label(d, n, (x, y + img.height + 6), size=14)
        x += img.width + pad
    canvas.save(os.path.join(PREVIEW_DIR, "preview_lineup.png"))
    print(f"  lineup: {total_w}x{total_h}")

def preview_scale():
    """Ships at relative in-game scale on a star background."""
    # 1 hull-unit -> px factor. Capital is 648 units, biggest. Render capital at 480px tall.
    target_capital_h = 480
    px_per_unit = target_capital_h / HULL_LENGTH["capital"]
    pad = 40
    imgs = []
    for n in SHIPS:
        img = Image.open(os.path.join(SHIPS_DIR, f"{n}.png")).convert("RGBA")
        target_h = HULL_LENGTH[n] * px_per_unit
        scale = target_h / img.height
        img = img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))),
                         Image.LANCZOS)
        imgs.append((n, img))
    total_w = sum(i[1].width for i in imgs) + pad * (len(imgs) + 1)
    total_h = max(i[1].height for i in imgs) + 80
    canvas = starfield(total_w, total_h)
    d = ImageDraw.Draw(canvas)
    x = pad
    for n, img in imgs:
        y = (total_h - img.height) // 2 - 10
        canvas.alpha_composite(img, (x, y))
        label(d, f"{n}  ({HULL_LENGTH[n]}u)", (x, total_h - 30), size=14)
        x += img.width + pad
    canvas.save(os.path.join(PREVIEW_DIR, "preview_scale.png"))
    print(f"  scale: {total_w}x{total_h}")

def preview_tints():
    """One ship rendered with several faction tints to verify the grayscale base tints cleanly."""
    src = Image.open(os.path.join(SHIPS_DIR, "fighter.png")).convert("RGBA")
    src2 = Image.open(os.path.join(SHIPS_DIR, "heavy_fighter.png")).convert("RGBA")
    src3 = Image.open(os.path.join(SHIPS_DIR, "corvette.png")).convert("RGBA")
    target_h = 220
    rows = [("fighter", src), ("heavy_fighter", src2), ("corvette", src3)]
    pad = 24
    cols = list(TINTS.items())

    def fit(img):
        scale = target_h / img.height
        return img.resize((int(img.width * scale), target_h), Image.LANCZOS)

    rows = [(n, fit(img)) for n, img in rows]
    col_w = max(img.width for _, img in rows) + pad * 2
    row_h = target_h + 50
    total_w = col_w * len(cols) + pad
    total_h = row_h * len(rows) + 50
    canvas = starfield(total_w, total_h)
    d = ImageDraw.Draw(canvas)
    # Headers
    for ci, (tn, _) in enumerate(cols):
        label(d, tn, (pad + ci * col_w + 6, 10), size=16)
    for ri, (rn, img) in enumerate(rows):
        for ci, (tn, color) in enumerate(cols):
            tinted = tint(img, color)
            x = pad + ci * col_w + (col_w - img.width) // 2 - pad // 2
            y = 50 + ri * row_h + (row_h - target_h) // 2
            canvas.alpha_composite(tinted, (x, y))
        label(d, rn, (10, 50 + ri * row_h + target_h // 2), size=14)
    canvas.save(os.path.join(PREVIEW_DIR, "preview_tints.png"))
    print(f"  tints: {total_w}x{total_h}")

if __name__ == "__main__":
    preview_lineup()
    preview_scale()
    preview_tints()
