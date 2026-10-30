"""Draw the app icon: one frame of warm negative film with a halated sun.

Original artwork, made only from shapes and gradients in this file.
Run: tools/.venv/bin/python tools/make_icon.py [output.png]
Default output: ios/PocketFilmLab/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024x1024, no alpha).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "ios/PocketFilmLab/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZE = 1024
SS = 4  # supersampling factor for clean edges
S = SIZE * SS


def lerp(a, b, t):
    return a + (b - a) * t


def vertical_gradient(top, bottom):
    t = np.linspace(0, 1, S, dtype=np.float32)[:, None, None]
    col = lerp(np.array(top, np.float32), np.array(bottom, np.float32), t)
    return np.broadcast_to(col, (S, S, 3)).copy()


def radial(cx, cy, radius):
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    return np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / radius


def mask_from(draw_fn):
    m = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(m))
    return np.asarray(m, np.float32)[..., None] / 255.0


def composite(base, color, mask):
    return base * (1 - mask) + np.asarray(color, np.float32) * mask


def build():
    # Background: deep warm brown, a touch lighter at the top.
    img = vertical_gradient((46, 32, 26), (18, 12, 10))

    # The film frame: a warm print-stock window, slightly landscape, centred.
    fx0, fx1 = 0.17 * S, 0.83 * S
    fy0, fy1 = 0.30 * S, 0.70 * S
    radius = 0.045 * S

    # Strip edges with sprocket holes, above and below the frame (the film base, orange mask).
    base_col = (150, 78, 38)
    sy0, sy1 = 0.205 * S, 0.795 * S
    strip = mask_from(lambda d: d.rounded_rectangle([0.09 * S, sy0, 0.91 * S, sy1], radius=0.06 * S, fill=255))
    img = composite(img, base_col, strip * 0.92)

    holes = 5
    hw, hh = 0.072 * S, 0.045 * S
    xs = np.linspace(0.20 * S, 0.80 * S, holes)

    def draw_holes(d):
        for x in xs:
            for yc in (0.2525 * S, 0.7475 * S):
                d.rounded_rectangle([x - hw / 2, yc - hh / 2, x + hw / 2, yc + hh / 2], radius=0.012 * S, fill=255)

    img = composite(img, (24, 16, 13), mask_from(draw_holes))

    # Inside the frame: a dusk sky, amber at the horizon to plum at the top.
    frame = mask_from(lambda d: d.rounded_rectangle([fx0, fy0, fx1, fy1], radius=radius, fill=255))
    t = np.clip((np.mgrid[0:S, 0:1][0].astype(np.float32) - fy0) / (fy1 - fy0), 0, 1)[..., None]
    sky = np.where(
        t < 0.62,
        lerp(np.array((92, 44, 52), np.float32), np.array((236, 132, 62), np.float32), (t / 0.62) ** 1.4),
        lerp(np.array((236, 132, 62), np.float32), np.array((252, 196, 120), np.float32), (t - 0.62) / 0.38),
    )
    sky = np.broadcast_to(sky, (S, S, 3))
    img = img * (1 - frame) + sky * frame

    # The sun: cream core with a red-orange halation ring, clipped to the frame.
    cx, cy, r = 0.5 * S, 0.565 * S, 0.085 * S
    d = radial(cx, cy, r)
    halo = np.exp(-np.maximum(d - 1, 0) * 1.15)[..., None] * 0.9
    img = img * (1 - halo * frame) + np.array((255, 104, 48), np.float32) * halo * frame
    core = np.clip((1.04 - d) / 0.06, 0, 1)[..., None]
    img = img * (1 - core * frame) + np.array((255, 244, 222), np.float32) * core * frame

    # Horizon: a dark band across the lower frame, like land at dusk.
    land = mask_from(lambda dr: dr.rectangle([0, 0.625 * S, S, S], fill=255)) * frame
    land_col = lerp(np.array((70, 30, 24), np.float32), np.array((40, 18, 16), np.float32), np.clip((np.mgrid[0:S, 0:1][0] / S - 0.625) / 0.08, 0, 1)[..., None])
    img = img * (1 - land) + np.broadcast_to(land_col, (S, S, 3)) * land

    # A soft inner shadow on the frame edge, for depth.
    edge = Image.fromarray((frame[..., 0] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.012 * S))
    inner = (1 - np.asarray(edge, np.float32)[..., None] / 255.0) * frame * 0.55
    img = img * (1 - inner)

    # Very light film grain over everything, fixed seed so the icon is reproducible.
    rng = np.random.default_rng(250)
    grain = rng.normal(0, 1, (SIZE, SIZE)).astype(np.float32)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS)
    arr = np.asarray(out, np.float32) + grain[..., None] * 3.0
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    build().save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
