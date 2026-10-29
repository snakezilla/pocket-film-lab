"""Build synthetic test photos (no personal images). Run: python3 tools/make_fixtures.py"""
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "tests" / "fixtures"
OUT.mkdir(parents=True, exist_ok=True)

# 4032x3024 landscape as stored. Red block top-left, blue block bottom-right,
# bright lamp in the middle (for halation), grey ramp along the bottom.
w, h = 4032, 3024
img = Image.new("RGB", (w, h), (90, 110, 130))
d = ImageDraw.Draw(img)
for x in range(0, w, 8):
    v = int(255 * x / w)
    d.rectangle([x, h - 600, x + 8, h], fill=(v, v, v))
d.rectangle([0, 0, 600, 600], fill=(220, 30, 30))
d.rectangle([w - 600, h - 1200, w, h - 600], fill=(30, 40, 220))
d.ellipse([w // 2 - 150, h // 2 - 150, w // 2 + 150, h // 2 + 150], fill=(255, 255, 255))
d.rectangle([800, 300, 1400, 900], fill=(224, 172, 140))  # skin-ish
img.save(OUT / "rotated.jpg", quality=92)
# Mark as "rotate 90 CW to display" and add GPS + camera tags that must not survive export.
subprocess.run(
    ["exiftool", "-q", "-overwrite_original", "-Orientation#=6", "-Make=TestCam", "-Model=Fixture",
     "-GPSLatitude=43.6", "-GPSLatitudeRef=N", "-GPSLongitude=79.4", "-GPSLongitudeRef=W",
     str(OUT / "rotated.jpg")],
    check=True,
)

Image.new("RGB", (640, 480), (128, 128, 128)).save(OUT / "small.png")
(OUT / "camera.dng").write_bytes(b"II*\x00" + b"\x00" * 1024)
(OUT / "broken.jpg").write_bytes(b"\xff\xd8\xff\xe0 not really a jpeg" + b"\x00" * 512)
(OUT / "notes.txt").write_text("not an image")
subprocess.run(["sips", "-s", "format", "heic", str(OUT / "small.png"), "--out", str(OUT / "small.heic")],
               check=True, capture_output=True)
print("fixtures in", OUT)
