"""Generate scene-linear-in 3D LUTs for the native RAW engine (ios/).

Input:  scene-linear Rec.709 (Core Image's working space), log2-encoded by the
        shaper below so the cube spends its samples evenly per stop.
Output: display-linear Rec.709 (Core Image converts to sRGB on render).

Film model: Spectral Film LUT 0.18.0 (MIT, Jan Lohse), negative stock printed
onto Kodak 2383. These are datasheet simulations, not Chromagraph or Yedlin
transforms.

Files: ios/PocketFilmLab/Resources/LUTs/<id>.cube.bin  float32 LE, size^3 * 4
       (RGBA, red index fastest, the layout CIColorCube expects)
       ios/PocketFilmLab/Resources/LUTs/<id>.json      metadata + grey ramp

Usage: tools/.venv/bin/python tools/make_raw_lut.py [look-id ...]  (default: all)
"""

import json
import sys
from pathlib import Path

import colour
import numpy as np
from spectral_film_lut.film_spectral import FilmSpectral
from spectral_film_lut.negative_film.kodak_5207 import KODAK_5207
from spectral_film_lut.negative_film.kodak_5219 import KODAK_5219
from spectral_film_lut.negative_film.kodak_portra_400 import KODAK_PORTRA_400
from spectral_film_lut.print_film.kodak_2383 import KODAK_2383
from spectral_film_lut.utils import film_conversion

SIZE = 65
OUT = Path(__file__).resolve().parent.parent / "ios" / "PocketFilmLab" / "Resources" / "LUTs"

# Shaper: s = (log2(x / 0.18) - LOG_MIN) / (LOG_MAX - LOG_MIN), clamped to 0..1.
# Must match FilmShaper in ios/PocketFilmLab/Engine/FilmLUT.swift.
MID_GREY = 0.18
LOG_MIN = -10.0  # 0.18 * 2^-10  = 0.000176
LOG_MAX = 6.5    # 0.18 * 2^6.5  = 16.3

# Mid grey (0.18 scene-linear) lands on this display-linear value.
# 0.18 is "no tonal change at mid grey". Judged, not measured; phase 2 tunes it.
TARGET_MID_OUT = 0.18

LOOKS = {
    "vision3-250d-2383": {
        "label": "Daylight",
        "negative": KODAK_5207,
        "print": KODAK_2383,
    },
    "vision3-500t-2383": {
        "label": "Lamplight",
        "negative": KODAK_5219,
        "print": KODAK_2383,
    },
    "portra400-2383": {
        "label": "Portrait",
        "negative": KODAK_PORTRA_400,
        "print": KODAK_2383,
    },
}

REC709 = colour.RGB_COLOURSPACES["ITU-R BT.709"]

# First tuning pass against references/LOOK-TRAITS.md (phase 2).
# Measured there: reference chroma is ~0.55-0.65x a stock render at equal L*, and
# highlight chroma (L* 70-90) is ~0.5x midtone chroma (L* 40-60).
# Applied as a chroma scale around the pixel's own luminance in display-linear, so
# greys are untouched (tests keep them neutral). The curve shape is judged; the
# targets it is fitted to are measured. See chroma_report() output.
CHROMA_MID = 1.0       # midtones: the film model alone already lands at ~0.6x plain chroma (report)
CHROMA_HIGH = 0.8      # trims highlight chroma toward the measured high/mid ratio of ~0.5
CHROMA_HIGH_Y = 0.6    # ~L* 82
# Black floor. Measured in LOOK-TRAITS: p0.5 of reference outputs sits at sRGB code
# 4-6; the film model alone floors at code 2. A neutral flare-like offset in
# display-linear: out' = BLACK_LIFT + out * (1 - BLACK_LIFT). With the film floor (~0.0006) the
# black lands at ~0.0016, code 5.
BLACK_LIFT = 0.001
CHROMA_SHADOW_Y = 0.01 # below this the scale eases back toward 1 (film already desaturates)

# Second tuning pass (phase 3), against the two before/after pairs in LOOK-TRAITS.md.
# Warm highlights. Measured: near-neutral highlights sit at b* +8 to +11, a* -1 to -3 in 8 of
# 9 reference outputs, and both pairs shift them by +10 b* or more. Gains on display-linear
# RGB at constant luminance, about b* +8 / a* -1.5 at full strength. The ramp position is
# measured (the tint is already strong at L* 76); the smoothstep shape is judged.
# Greys below HIGHLIGHT_WARM_Y0 (about +1 stop) stay neutral.
HIGHLIGHT_WARM = (1.037, 1.0051, 0.84)  # R, G, B gains at full strength (G keeps Y)
# The cube is neutral (owner direction 2026-10-30: neutral baseline, warmth optional and
# reversible). The warm gains above are applied at runtime by the `warmth` setting
# (FilmLook.ci.metal warmHighlights, same gains and ramp), default 0.
WARM_IN_CUBE = False
HIGHLIGHT_WARM_Y0 = 0.36                # display Y, L* 66
HIGHLIGHT_WARM_Y1 = 0.64                # display Y, L* 84
# Toe. Measured direction: both pairs keep the very bottom lifted but are ~21-25 codes darker
# at p25 than the phone render; ours is ~31 darker than our plain render, so slightly too
# dense. The size (+0.16 stop at code ~32) is a weak estimate: exposure is unknown in both.
# Pale blue skies lose chroma (LOOK-TRAITS tuning pass 2): the cakesauce pair measured
# x0.68 on a daylight sky, mezha1 lost all of it. We take the gentler pair, rounded:
# x0.7 on hues 200-290 deg (Lab), ramping in from display Y 0.2 to 0.45 (L* ~52-73),
# so dusk and deep blues (darker) keep their colour. Amount measured, ramp judged.
BLUE_HIGH_CHROMA = 1.0   # OFF (owner direction 2026-10-30: scene quantiles are not a calibrated transform); was 0.7
BLUE_HUE = (200.0, 290.0)   # Lab hue, degrees; edges fade over 15 deg
BLUE_Y = (0.2, 0.45)

TOE_LIFT = 1.12        # gain on display Y at TOE_PEAK_Y
TOE_PEAK_Y = 0.015     # sRGB code ~32
TOE_LOW_Y, TOE_HIGH_Y = 0.004, 0.08  # the gain eases back to 1 at these (log-space smoothstep)


def shaper_decode(s):
    return MID_GREY * np.exp2(LOG_MIN + s * (LOG_MAX - LOG_MIN))


def convert(linear_rgb, neg, prt, exp_comp):
    """Scene-linear Rec.709 -> display-linear Rec.709 through negative + print."""
    xyz = colour.RGB_to_XYZ(
        linear_rgb, REC709, apply_cctf_decoding=False
    )
    out = film_conversion(
        xyz.astype(np.float32),
        neg,
        prt,
        input_colorspace=None,  # XYZ
        exp_kelvin=6500,  # CIRAWFilter has already white balanced to D65
        exp_comp=exp_comp,
        output_gamut="Rec. 709",
        gamma_func="sRGB",
        white_clip=True,
    )
    out = np.nan_to_num(np.asarray(out, dtype=np.float64), nan=0.0)
    return srgb_decode(out)


def srgb_decode(v):
    v = np.clip(v, 0.0, 1.0)
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def grey(values):
    v = np.asarray(values, dtype=np.float64)
    return np.repeat(v[:, None, None], 3, axis=2).reshape(len(v), 1, 3)


def find_exposure(neg, prt):
    best = (1e9, 0.0)
    for ev in np.arange(-3.0, 3.01, 0.125):
        out = convert(grey([MID_GREY]), neg, prt, float(ev))
        err = abs(float(np.mean(out)) - TARGET_MID_OUT)
        best = min(best, (err, float(ev)))
    return best[1]


def neutral_axis_fix(table, neg, prt, ev):
    """Remap each channel so scene greys come out neutral.

    The print's own luminance curve is kept (mean of the three channels); only
    the per-channel imbalance on the grey axis is removed. Off-axis colours keep
    the film's cross-channel response.
    """
    s = np.linspace(0, 1, 513)
    out = convert(grey(shaper_decode(s)), neg, prt, ev).reshape(-1, 3)
    target = out.mean(axis=1)
    fixed = np.empty_like(table)
    for c in range(3):
        mono = np.maximum.accumulate(out[:, c]) + np.arange(len(s)) * 1e-9
        pos = np.interp(table[..., c], mono, s)
        fixed[..., c] = np.interp(pos, s, target)
    return fixed


def luminance(rgb):
    return rgb @ np.array([0.2126, 0.7152, 0.0722])


def chroma_scale(y):
    t = np.clip((np.log2(np.maximum(y, 1e-6)) - np.log2(0.18)) / (np.log2(CHROMA_HIGH_Y) - np.log2(0.18)), 0, 1)
    t = t * t * (3 - 2 * t)
    k = CHROMA_MID + (CHROMA_HIGH - CHROMA_MID) * t
    shadow = np.clip(y / CHROMA_SHADOW_Y, 0, 1)
    return 1 + (k - 1) * shadow


def smoothstep(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def toe_gain(y):
    """Gain bump on display Y: 1 outside TOE_LOW_Y..TOE_HIGH_Y, TOE_LIFT at TOE_PEAK_Y."""
    ly = np.log2(np.maximum(y, 1e-6))
    up = smoothstep(ly, np.log2(TOE_LOW_Y), np.log2(TOE_PEAK_Y))
    down = 1 - smoothstep(ly, np.log2(TOE_PEAK_Y), np.log2(TOE_HIGH_Y))
    return 1 + (TOE_LIFT - 1) * np.minimum(up, down)


def warm_gains(y):
    w = smoothstep(y, HIGHLIGHT_WARM_Y0, HIGHLIGHT_WARM_Y1)[..., None]
    return 1 + (np.array(HIGHLIGHT_WARM) - 1) * w


def sky_scale(table, y):
    """Chroma scale for pale blues: BLUE_HIGH_CHROMA inside the hue band and above BLUE_Y."""
    xyz = colour.RGB_to_XYZ(np.clip(table, 0, None), REC709, apply_cctf_decoding=False)
    lab = colour.XYZ_to_Lab(xyz)
    h = np.degrees(np.arctan2(lab[..., 2], lab[..., 1])) % 360
    lo, hi = BLUE_HUE
    w_hue = smoothstep(h, lo - 15, lo) * (1 - smoothstep(h, hi, hi + 15))
    w = w_hue * smoothstep(y, *BLUE_Y)
    return 1 + (BLUE_HIGH_CHROMA - 1) * w


def grade(table):
    y = luminance(table)[..., None]
    k = chroma_scale(y[..., 0]) * sky_scale(table, y[..., 0])
    graded = np.clip(y + (table - y) * k[..., None], 0, 1)
    warm = warm_gains(y[..., 0]) if WARM_IN_CUBE else 1.0
    graded = np.clip(graded * toe_gain(y[..., 0])[..., None] * warm, 0, 1)
    return BLACK_LIFT + graded * (1 - BLACK_LIFT)


def lab_chroma(display_linear):
    xyz = colour.RGB_to_XYZ(display_linear, REC709, apply_cctf_decoding=False)
    lab = colour.XYZ_to_Lab(xyz)
    return lab[..., 0], np.hypot(lab[..., 1], lab[..., 2])


def chroma_report(look_id, neg, prt, ev, graded):
    """Our chroma vs the plain (clipped) linear render, per L* band, on random scene colours."""
    rng = np.random.default_rng(1)
    scene = MID_GREY * np.exp2(rng.uniform(-4, 3, (4000, 1))) * rng.dirichlet([2, 2, 2], 4000) * 3
    film = convert(scene.reshape(-1, 1, 3), neg, prt, ev).reshape(-1, 3)
    if graded:
        film = grade(film)
    l_ref, c_ref = lab_chroma(np.clip(scene, 0, 1))
    l_out, c_out = lab_chroma(film)
    bands = {"L20-40": (20, 40), "L40-60": (40, 60), "L70-90": (70, 90)}
    out = {}
    for name, (lo, hi) in bands.items():
        m = (l_out >= lo) & (l_out < hi) & (c_ref > 5)
        out[name] = {"vsPlain": round(float(np.median(c_out[m] / c_ref[m])), 3), "chroma": round(float(np.median(c_out[m])), 1)}
    out["highOverMid"] = round(out["L70-90"]["chroma"] / max(out["L40-60"]["chroma"], 1e-6), 3)
    print(look_id, "graded" if graded else "raw film", out, file=sys.stderr)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    axis = np.linspace(0.0, 1.0, SIZE)
    b, g, r = np.meshgrid(axis, axis, axis, indexing="ij")  # red fastest when flat
    grid = shaper_decode(np.stack([r, g, b], axis=-1))

    only = set(sys.argv[1:])
    for look_id, look in LOOKS.items():
        if only and look_id not in only:
            continue
        neg = FilmSpectral(look["negative"])
        neg.set_color_checker()
        prt = FilmSpectral(look["print"])
        prt.set_color_checker(negative=neg)
        ev = find_exposure(neg, prt)
        table = convert(grid.reshape(-1, 1, 3), neg, prt, ev).reshape(grid.shape)
        table = np.clip(neutral_axis_fix(table, neg, prt, ev), 0.0, 1.0)
        chroma_report(look_id, neg, prt, ev, graded=False)
        table = grade(table)
        report = chroma_report(look_id, neg, prt, ev, graded=True)

        rgba = np.concatenate([table, np.ones(table.shape[:-1] + (1,))], axis=-1)
        (OUT / f"{look_id}.cube.bin").write_bytes(rgba.astype("<f4").tobytes())

        stops = np.arange(-8, 7)
        ramp_lin = MID_GREY * np.exp2(stops.astype(float))
        # Exact film-model output at each stop (not the nearest cube node), for tests.
        exact = convert(grey(ramp_lin), neg, prt, ev).reshape(-1, 1, 1, 3)
        exact = grade(np.clip(neutral_axis_fix(exact, neg, prt, ev), 0.0, 1.0)).reshape(-1, 3)
        meta = {
            "id": look_id,
            "label": look["label"],
            "size": SIZE,
            "negative": look["negative"].name,
            "print": look["print"].name,
            "shaper": {"midGrey": MID_GREY, "logMin": LOG_MIN, "logMax": LOG_MAX},
            "exposureCompensationEv": ev,
            "targetMidOut": TARGET_MID_OUT,
            "source": "spectral-film-lut 0.18.0 (MIT, Jan Lohse)",
            "greyRampStops": [int(x) for x in stops],
            "grade": {"blackLift": BLACK_LIFT, "chromaMid": CHROMA_MID, "chromaHigh": CHROMA_HIGH, "chromaHighY": CHROMA_HIGH_Y,
                      "blueHighChroma": BLUE_HIGH_CHROMA, "blueHue": list(BLUE_HUE), "blueY": list(BLUE_Y),
                      "toeLift": TOE_LIFT, "toePeakY": TOE_PEAK_Y, "warmInCube": WARM_IN_CUBE, "highlightWarm": list(HIGHLIGHT_WARM),
                      "highlightWarmY": [HIGHLIGHT_WARM_Y0, HIGHLIGHT_WARM_Y1]},
            "chromaReport": report,
            "greyRampOutLinear": [[round(float(c), 6) for c in row] for row in exact],
        }
        (OUT / f"{look_id}.json").write_text(json.dumps(meta, indent=1))
        print(look_id, "ev", ev, "bytes", rgba.nbytes, file=sys.stderr)
        for st, row in zip(stops, meta["greyRampOutLinear"]):
            print(f"  {st:+d} stops -> {row}", file=sys.stderr)


if __name__ == "__main__":
    main()
