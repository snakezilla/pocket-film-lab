"""Measure look traits of local reference photos (references/local/, gitignored).

Reads image paths only; writes nothing into the repo. Prints a JSON report.

Usage:
    tools/.venv/bin/python -I tools/measure_refs.py [--refdir references/local] [--crops /tmp/lt]

Measurements per image (photo area only; UI screenshots are cropped):
  tone       : 0.5/1/50/99/99.5/max percentiles of luminance (sRGB code + linear),
               area above code 245/250, histogram of the top 30 codes
  chroma     : mean CIELAB C* in 10 L* bins
  tint       : mean a*/b* of darkest / brightest 10% of near-neutral pixels (C* < 12)
  hues       : mean hue angle / chroma inside simple hue masks (skin, sky, foliage)
  grain      : high-pass residual std in flat patches per luminance band,
               autocorrelation half-width of the residual (px and fraction of width)
  halation   : R-G and R-B code differences in rings just outside clipped regions
  pair       : for the before/after pair, quantile tone mapping and chroma ratio
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

# (file, crop box (x0, y0, x1, y1) or None, label, use_for_grain)
SOURCES = [
    ("instagram_steveyedlin_DfCaSRqG_Sz_carousel_2880x2880.jpg", None, "ig_portrait", True),
    ("x_rianjohnson_2115436068774543534_sample_2880x2160.jpg", None, "x_dusk", True),
    ("press_mezha_photo1.jpg", (662, 70, 1312, 875), "mezha1_after", False),
    ("press_mezha_photo1.jpg", (0, 70, 650, 875), "mezha1_before_iphone", False),
    ("press_mezha_photo2.jpg", (0, 0, 650, 875), "mezha2_ship", False),
    ("press_mezha_photo2.jpg", (662, 0, 1312, 875), "mezha2_forest", False),
    ("appstore_ipad_viewer_2064x2752.png", (340, 1010, 1720, 2560), "as_ipad_seascape", False),
    ("appstore_ipad_editor_2064x2752.png", (340, 900, 1720, 2150), "as_ipad_fruit", False),
    ("appstore_iphone_editor_1179x2556.png", (260, 990, 950, 1760), "as_iphone_fruit", False),
    ("appstore_iphone_viewer_1179x2556.png", (225, 1150, 955, 1930), "as_iphone_seascape", False),
    # Phase 3 additions (issue #7 assistant comments). The app's exports carry a 1 px dark border.
    ("x_cakesauce_2115693910458781996_chromagraph_2048x1422.jpg", (2, 2, 2046, 1418), "cake_after", False),
    ("x_cakesauce_2115694195583451349_original_2048x1536.jpg", None, "cake_before_original", False),
    ("x_dmcgco_2115886480962847174_chromagraph_1536x2048.jpg", (2, 2, 1532, 2044), "dmcg_interior", False),
    ("newsshooter_IMG_6668-740x948.webp", (2, 2, 736, 944), "ns_beach", False),
    ("newsshooter_IMG_6670-740x529.webp", (2, 2, 736, 525), "ns_harbour", False),
    ("newsshooter_IMG_6671-740x418.webp", (2, 2, 736, 414), "ns_building", False),
]
REFERENCE_LABELS = {"mezha1_before_iphone", "cake_before_original"}  # not reference-look output

# Same-scene pairs with different framing: compare sky and land separately.
# Row bands are fractions of the image height (horizon at ~0.40 in the output, ~0.49 in the original).
REGION_PAIRS = {
    "pair_cake": ("cake_before_original", "cake_after",
                  {"sky": ((0.0, 0.45), (0.0, 0.36)), "land": ((0.58, 1.0), (0.50, 1.0))}),
}

L_BINS = np.arange(0, 101, 10)
HUE_MASKS = {  # (hue lo, hue hi, C* min, L* lo, L* hi) in CIELAB degrees
    "skin": (20.0, 70.0, 12.0, 25.0, 85.0),
    "sky": (200.0, 290.0, 6.0, 20.0, 95.0),
    "foliage": (95.0, 170.0, 8.0, 10.0, 90.0),
    "red": (350.0, 40.0, 30.0, 10.0, 80.0),
}


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_code(y):
    y = np.clip(y, 0.0, 1.0)
    v = np.where(y <= 0.0031308, 12.92 * y, 1.055 * y ** (1 / 2.4) - 0.055)
    return 255.0 * v


def rgb_to_lab(lin):
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = lin @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    lab_l = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([lab_l, a, b], axis=-1)


def load(path, box):
    im = Image.open(path).convert("RGB")
    if box:
        im = im.crop(box)
    return np.asarray(im).astype(np.float64)


def tone_stats(codes, lin_y, ycode):
    pct = [0.5, 1, 5, 50, 95, 99, 99.5, 100]
    out = {f"p{p}": {"code": round(float(np.percentile(ycode, p)), 1),
                     "lin": round(float(np.percentile(lin_y, p)), 5)} for p in pct}
    mx = codes.max(axis=-1)
    out["area_Y_gt245_pct"] = round(100 * float((ycode > 245).mean()), 3)
    out["area_anych_ge250_pct"] = round(100 * float((mx >= 250).mean()), 3)
    out["area_anych_eq255_pct"] = round(100 * float((mx >= 254.5).mean()), 3)
    out["min_channel_p0.5"] = [round(float(np.percentile(codes[..., i], 0.5)), 1) for i in range(3)]
    hist, _ = np.histogram(ycode, bins=np.arange(225, 261, 5))
    out["top_hist_225_260_step5_pct"] = [round(100 * h / ycode.size, 3) for h in hist]
    return out


def chroma_by_l(lab):
    c = np.hypot(lab[..., 1], lab[..., 2])
    res = []
    for lo, hi in zip(L_BINS[:-1], L_BINS[1:]):
        m = (lab[..., 0] >= lo) & (lab[..., 0] < hi)
        frac = float(m.mean())
        res.append({"L": f"{lo}-{hi}", "frac_pct": round(100 * frac, 2),
                    "C": round(float(c[m].mean()), 2) if m.sum() > 200 else None})
    return res


def tint(lab):
    c = np.hypot(lab[..., 1], lab[..., 2])
    neutral = c < 12
    if neutral.sum() < 1000:
        return None
    lv = lab[..., 0][neutral]
    lo, hi = np.percentile(lv, [10, 90])
    out = {}
    for name, sel in (("shadow", lv <= lo), ("highlight", lv >= hi)):
        a = lab[..., 1][neutral][sel]
        b = lab[..., 2][neutral][sel]
        out[name] = {"L_mean": round(float(lv[sel].mean()), 1),
                     "a": round(float(a.mean()), 2), "b": round(float(b.mean()), 2)}
    out["neutral_frac_pct"] = round(100 * float(neutral.mean()), 1)
    return out


def hues(lab):
    c = np.hypot(lab[..., 1], lab[..., 2])
    h = np.degrees(np.arctan2(lab[..., 2], lab[..., 1])) % 360
    out = {}
    for name, (h0, h1, cmin, l0, l1) in HUE_MASKS.items():
        hm = (h >= h0) & (h < h1) if h0 < h1 else (h >= h0) | (h < h1)
        m = hm & (c >= cmin) & (lab[..., 0] >= l0) & (lab[..., 0] <= l1)
        frac = float(m.mean())
        if frac < 0.01:
            continue
        ang = np.degrees(np.arctan2(lab[..., 2][m].mean(), lab[..., 1][m].mean())) % 360
        out[name] = {"frac_pct": round(100 * frac, 1), "hue": round(float(ang), 1),
                     "C": round(float(c[m].mean()), 1), "L": round(float(lab[..., 0][m].mean()), 1)}
    return out


def grain(ycode, patch=32):
    blur = ndimage.gaussian_filter(ycode, 1.5)
    resid = ycode - blur
    grad = ndimage.gaussian_gradient_magnitude(ycode, 3.0)
    hh, ww = (ycode.shape[0] // patch) * patch, (ycode.shape[1] // patch) * patch

    def tiles(a):
        return a[:hh, :ww].reshape(hh // patch, patch, ww // patch, patch).swapaxes(1, 2)

    r_t, g_t, y_t = tiles(resid), tiles(grad), tiles(ycode)
    gmean = g_t.mean(axis=(2, 3))
    flat = gmean < np.percentile(gmean, 25)
    ymean = y_t.mean(axis=(2, 3))
    rstd = r_t.std(axis=(2, 3))
    bands = {}
    for lo, hi in ((0, 30), (30, 80), (80, 140), (140, 200), (200, 256)):
        m = flat & (ymean >= lo) & (ymean < hi) & (ymean.max() > 0)
        if m.sum() >= 10:
            bands[f"{lo}-{hi}"] = {"n": int(m.sum()), "std_code": round(float(np.median(rstd[m])), 3)}
    # autocorrelation of residual in flat mid patches
    sel = flat & (ymean > 30) & (ymean < 220)
    acf_x = acf_y = None
    if sel.sum() >= 10:
        acc = np.zeros((patch, patch))
        for t in r_t[sel][:400]:
            t = t - t.mean()
            f = np.fft.fft2(t)
            acc += np.real(np.fft.ifft2(f * np.conj(f)))
        acc /= acc[0, 0]
        acf_x = [round(float(v), 3) for v in acc[0, :5]]
        acf_y = [round(float(v), 3) for v in acc[:5, 0]]
    hw = None
    if acf_x:
        row = np.array(acf_x)
        below = np.where(row < 0.5)[0]
        if below.size:
            i = below[0]
            hw = round(float(i - 1 + (row[i - 1] - 0.5) / (row[i - 1] - row[i])), 2)
    return {"bands": bands, "acf_x_lag0_4": acf_x, "acf_y_lag0_4": acf_y,
            "acf_halfwidth_px": hw,
            "halfwidth_frac_width": round(hw / ycode.shape[1], 6) if hw else None,
            "flat_patches": int(flat.sum())}


def halation(codes):
    mx = codes.max(axis=-1)
    clip = mx >= 250
    clip = ndimage.binary_opening(clip, iterations=1)
    if clip.sum() < 50:
        return {"clipped_px": int(clip.sum()), "note": "too few clipped pixels"}
    out = {"clipped_px": int(clip.sum())}
    prev = clip
    for r in (3, 8, 16, 32, 64):
        d = ndimage.binary_dilation(clip, iterations=r)
        ring = d & ~prev
        prev = d
        if ring.sum() < 50:
            continue
        px = codes[ring]
        out[f"ring_to_{r}px"] = {"n": int(ring.sum()),
                                 "RGB": [round(float(v), 1) for v in px.mean(axis=0)],
                                 "R-G": round(float((px[:, 0] - px[:, 1]).mean()), 1),
                                 "R-B": round(float((px[:, 0] - px[:, 2]).mean()), 1)}
    far = ~ndimage.binary_dilation(clip, iterations=96)
    px = codes[far]
    out["far_baseline"] = {"R-G": round(float((px[:, 0] - px[:, 1]).mean()), 1),
                           "R-B": round(float((px[:, 0] - px[:, 2]).mean()), 1)}
    return out


def region_rows(codes, band):
    h = codes.shape[0]
    return codes[int(band[0] * h):int(band[1] * h)]


def region_stats(codes):
    lin = srgb_to_linear(codes / 255)
    lab = rgb_to_lab(lin)
    c = np.hypot(lab[..., 1], lab[..., 2])
    ang = np.degrees(np.arctan2(lab[..., 2].mean(), lab[..., 1].mean())) % 360
    return {"L": round(float(lab[..., 0].mean()), 1), "a": round(float(lab[..., 1].mean()), 2),
            "b": round(float(lab[..., 2].mean()), 2), "C": round(float(c.mean()), 1),
            "hue": round(float(ang), 1),
            "RGB_mean": [round(float(v), 1) for v in codes.reshape(-1, 3).mean(axis=0)]}


def pair_compare(before, after):
    yb = linear_to_code(srgb_to_linear(before / 255) @ np.array([0.2126, 0.7152, 0.0722]))
    ya = linear_to_code(srgb_to_linear(after / 255) @ np.array([0.2126, 0.7152, 0.0722]))
    qs = [1, 5, 10, 25, 50, 75, 90, 95, 99, 99.5]
    lb = rgb_to_lab(srgb_to_linear(before / 255))
    la = rgb_to_lab(srgb_to_linear(after / 255))
    cb = np.hypot(lb[..., 1], lb[..., 2]).mean()
    ca = np.hypot(la[..., 1], la[..., 2]).mean()
    return {"quantile_map_before_to_after_code": [
        {"q": q, "before": round(float(np.percentile(yb, q)), 1),
         "after": round(float(np.percentile(ya, q)), 1)} for q in qs],
        "mean_C_before": round(float(cb), 2), "mean_C_after": round(float(ca), 2),
        "chroma_ratio_after_over_before": round(float(ca / cb), 3)}


def measure(path, box, use_grain, crop_dir):
    codes = load(path, box)
    lin = srgb_to_linear(codes / 255)
    lin_y = lin @ np.array([0.2126, 0.7152, 0.0722])
    ycode = linear_to_code(lin_y)
    lab = rgb_to_lab(lin)
    if crop_dir:
        im = Image.fromarray(codes.astype(np.uint8))
        im.thumbnail((320, 320))
        im.save(os.path.join(crop_dir, os.path.basename(path) + f"_{box}.png".replace(" ", "")))
    res = {"size": [codes.shape[1], codes.shape[0]],
           "tone": tone_stats(codes, lin_y, ycode),
           "chroma_by_L": chroma_by_l(lab), "tint": tint(lab), "hues": hues(lab),
           "halation": halation(codes)}
    if use_grain:
        res["grain"] = grain(ycode)
    return res, codes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refdir", default=os.path.join(os.path.dirname(__file__), "..", "references", "local"))
    ap.add_argument("--crops", default=None, help="optional dir for small crop previews (outside repo)")
    args = ap.parse_args()
    if args.crops:
        os.makedirs(args.crops, exist_ok=True)
    report, cache = {}, {}
    for fname, box, label, use_grain in SOURCES:
        path = os.path.join(args.refdir, fname)
        if not os.path.exists(path):
            print(f"missing: {path}", file=sys.stderr)
            continue
        res, codes = measure(path, box, use_grain, args.crops)
        res["is_reference_look"] = label not in REFERENCE_LABELS
        report[label] = res
        cache[label] = codes
    if "mezha1_after" in cache and "mezha1_before_iphone" in cache:
        report["pair_mezha1"] = pair_compare(cache["mezha1_before_iphone"], cache["mezha1_after"])
    for name, (before, after, regions) in REGION_PAIRS.items():
        if before not in cache or after not in cache:
            continue
        res = pair_compare(cache[before], cache[after])
        for region, (band_b, band_a) in regions.items():
            rb, ra = region_rows(cache[before], band_b), region_rows(cache[after], band_a)
            res[region] = {"before": region_stats(rb), "after": region_stats(ra),
                           "pair": pair_compare(rb, ra)}
        report[name] = res
    json.dump(report, sys.stdout, indent=1)


if __name__ == "__main__":
    main()
