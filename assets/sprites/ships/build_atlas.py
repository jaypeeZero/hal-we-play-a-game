"""
Pack the five ship PNGs into a sprite sheet with a JSON atlas describing
each region. Layout: simple shelf-pack, biggest first.

Atlas JSON format:
{
  "image": "ships_atlas.png",
  "frames": {
    "<ship_name>": {"x": int, "y": int, "w": int, "h": int, "anchor": [x, y]}
  }
}
The "anchor" is the ship's origin (rotation center) inside the frame, in
pixels. For top-down ships, this is the center of mass — placed at the
visual centroid of the hull silhouette.
"""

import os
import json
from PIL import Image
import numpy as np

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
SHIPS_DIR = os.path.join(OUT_DIR, "ships")
ATLAS_PATH = os.path.join(SHIPS_DIR, "ships_atlas.png")
ATLAS_JSON = os.path.join(SHIPS_DIR, "ships_atlas.json")

# Order: largest first for tighter packing
SHIPS = ["capital", "corvette", "heavy_fighter", "torpedo_boat", "fighter"]
PADDING = 4  # transparent gutter around each frame

def alpha_centroid(img):
    """Return (x, y) centroid of non-zero alpha pixels — the visual center
    of mass, used as the rotation anchor."""
    arr = np.asarray(img)
    a = arr[..., 3].astype(np.float32)
    total = a.sum()
    if total < 1:
        return img.width // 2, img.height // 2
    ys, xs = np.indices(a.shape)
    cx = (xs * a).sum() / total
    cy = (ys * a).sum() / total
    return int(round(cx)), int(round(cy))

def shelf_pack(sizes, max_w):
    """Returns positions [(x, y), ...] and (atlas_w, atlas_h)."""
    positions = []
    x = 0
    y = 0
    shelf_h = 0
    atlas_w = 0
    for w, h in sizes:
        if x + w > max_w:
            # New shelf
            x = 0
            y += shelf_h + PADDING
            shelf_h = 0
        positions.append((x, y))
        atlas_w = max(atlas_w, x + w)
        shelf_h = max(shelf_h, h)
        x += w + PADDING
    atlas_h = y + shelf_h
    return positions, (atlas_w, atlas_h)

def main():
    images = {name: Image.open(os.path.join(SHIPS_DIR, f"{name}.png")).convert("RGBA")
              for name in SHIPS}

    # Capital is tall; let it occupy its own column.
    sizes = [(images[n].width + PADDING * 2, images[n].height + PADDING * 2)
             for n in SHIPS]

    # Pick max width = capital width + corvette width + padding
    max_w = images["capital"].width + images["corvette"].width + PADDING * 6

    positions, (atlas_w, atlas_h) = shelf_pack(sizes, max_w)

    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))
    frames = {}
    for name, (x, y), (w, h) in zip(SHIPS, positions, sizes):
        img = images[name]
        atlas.paste(img, (x + PADDING, y + PADDING), img)
        ax, ay = alpha_centroid(img)
        frames[name] = {
            "x": x + PADDING,
            "y": y + PADDING,
            "w": img.width,
            "h": img.height,
            "anchor": [ax, ay],
        }

    atlas.save(ATLAS_PATH)
    with open(ATLAS_JSON, "w") as f:
        json.dump({
            "image": "ships_atlas.png",
            "frames": frames,
            "notes": "Sprites are grayscale; multiply by faction color to tint. Anchor is the rotation center.",
        }, f, indent=2)

    print(f"Atlas: {atlas_w}x{atlas_h} -> {ATLAS_PATH}")
    print(f"JSON:  {ATLAS_JSON}")
    for name, frame in frames.items():
        print(f"  {name}: x={frame['x']:4d} y={frame['y']:4d} "
              f"{frame['w']:4d}x{frame['h']:4d} anchor={frame['anchor']}")

if __name__ == "__main__":
    main()
