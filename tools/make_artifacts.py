"""Builds measurements/artifacts/ from one ArtifactTests run (ios/TestData/artifacts/<stamp>/).
CC0-derived and synthetic images only. Usage: tools/.venv/bin/python tools/make_artifacts.py <run dir> <out dir>"""
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

run, out = Path(sys.argv[1]), Path(sys.argv[2])
if out.exists():
    sys.exit(f"{out} exists; pick a new folder")
out.mkdir(parents=True)
LOOKS = ["vision3-250d-2383", "vision3-500t-2383", "portra400-2383"]


def label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, img.width, 22], fill=(0, 0, 0))
    d.text((6, 5), text, fill=(255, 255, 255))
    return img


# Shipping exports, unchanged bytes, plus a viewable PNG of the HEIC (1600 px).
for ext in ("jpg", "heic"):
    shutil.copy(run / f"shipping-iphonexs-250d.{ext}", out / f"shipping-iphonexs-250d.{ext}")
subprocess.run(["sips", "-s", "format", "png", "-Z", "1600", str(run / "shipping-iphonexs-250d.heic"),
                "--out", str(out / "shipping-iphonexs-250d-heic-preview.png")], check=True, capture_output=True)

# Grey ramp: one row per look x warmth.
rows = [(f"{look}  warmth {w}", Image.open(run / f"ramp-{look}-warmth{w}.png").convert("RGB")) for look in LOOKS for w in (0, 1)]
w = rows[0][1].width
sheet = Image.new("RGB", (w, len(rows) * 86 + 22), (40, 40, 40))
label(sheet, "scene-linear grey stops -8 ... +6 (left to right), 64 px each")
for i, (name, img) in enumerate(rows):
    tile = Image.new("RGB", (w, 86), (40, 40, 40))
    tile.paste(img, (0, 22))
    sheet.paste(label(tile, name), (0, 22 + i * 86))
sheet.save(out / "grey-ramp-neutral-vs-warm.png")

# Look sheets: plain + 3 looks, neutral row and warm row.
for base in ("iphone12pro-proraw", "iphonexs-bayer"):
    plain = Image.open(run / f"look-{base}-plain.jpg").convert("RGB")
    tw, th = plain.size
    grid = Image.new("RGB", (tw * 4, th * 2), (20, 20, 20))
    for r, warm in enumerate((0, 1)):
        grid.paste(label(plain.copy(), "plain linear decode (no look)"), (0, r * th))
        for c, look in enumerate(LOOKS):
            img = Image.open(run / f"look-{base}-{look}-warmth{warm}.jpg").convert("RGB")
            grid.paste(label(img, f"{look}  warmth {warm}  grain .35 halation .3"), ((c + 1) * tw, r * th))
    grid.save(out / f"look-sheet-{base}-neutral-vs-warm.jpg", quality=88)

shutil.copy(run / "app-raw-preview-2.png", out / "app-raw-preview-simulator.png")
print("\n".join(sorted(p.name for p in out.iterdir())))
