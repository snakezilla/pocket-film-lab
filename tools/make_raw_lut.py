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

Usage: tools/.venv/bin/python tools/make_raw_lut.py
"""

import json
import sys
from pathlib import Path

import colour
import numpy as np
from spectral_film_lut.film_spectral import FilmSpectral
from spectral_film_lut.negative_film.kodak_5207 import KODAK_5207
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
        "label": "250D Print",
        "negative": KODAK_5207,
        "print": KODAK_2383,
    },
}

REC709 = colour.RGB_COLOURSPACES["ITU-R BT.709"]


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


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    axis = np.linspace(0.0, 1.0, SIZE)
    b, g, r = np.meshgrid(axis, axis, axis, indexing="ij")  # red fastest when flat
    grid = shaper_decode(np.stack([r, g, b], axis=-1))

    for look_id, look in LOOKS.items():
        neg = FilmSpectral(look["negative"])
        neg.set_color_checker()
        prt = FilmSpectral(look["print"])
        prt.set_color_checker(negative=neg)
        ev = find_exposure(neg, prt)
        table = convert(grid.reshape(-1, 1, 3), neg, prt, ev).reshape(grid.shape)
        table = np.clip(neutral_axis_fix(table, neg, prt, ev), 0.0, 1.0)

        rgba = np.concatenate([table, np.ones(table.shape[:-1] + (1,))], axis=-1)
        (OUT / f"{look_id}.cube.bin").write_bytes(rgba.astype("<f4").tobytes())

        stops = np.arange(-8, 7)
        ramp_lin = MID_GREY * np.exp2(stops.astype(float))
        # Exact film-model output at each stop (not the nearest cube node), for tests.
        exact = convert(grey(ramp_lin), neg, prt, ev).reshape(-1, 1, 1, 3)
        exact = np.clip(neutral_axis_fix(exact, neg, prt, ev), 0.0, 1.0).reshape(-1, 3)
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
            "greyRampOutLinear": [[round(float(c), 6) for c in row] for row in exact],
        }
        (OUT / f"{look_id}.json").write_text(json.dumps(meta, indent=1))
        print(look_id, "ev", ev, "bytes", rgba.nbytes, file=sys.stderr)
        for st, row in zip(stops, meta["greyRampOutLinear"]):
            print(f"  {st:+d} stops -> {row}", file=sys.stderr)


if __name__ == "__main__":
    main()
