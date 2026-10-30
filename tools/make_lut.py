"""Generate sRGB-in / sRGB-out 3D LUTs from Spectral Film LUT (MIT, Jan Lohse).

The LUTs simulate a film negative printed onto a print stock, from digitised
datasheet curves. They are NOT Chromagraph or Yedlin transforms.

Output: public/luts/<id>.bin  (uint16 LE, size^3 * 3, red index fastest)
        tools/lut-meta/<id>.json (metadata + measured grey ramp; not shipped in the app)

Usage: tools/.venv/bin/python tools/make_lut.py
"""

import json
import sys
from pathlib import Path

import colour
import numpy as np
from spectral_film_lut.film_spectral import FilmSpectral
from spectral_film_lut.negative_film.kodak_5219 import KODAK_5219
from spectral_film_lut.negative_film.kodak_portra_400 import KODAK_PORTRA_400
from spectral_film_lut.print_film.kodak_2383 import KODAK_2383
from spectral_film_lut.print_film.kodak_portra_endura import KODAK_PORTRA_ENDURA
from spectral_film_lut.utils import film_conversion

SIZE = 33
OUT = Path(__file__).resolve().parent.parent / "public" / "luts"
# Stock names stay out of the shipped app (App Store guideline 5.2.1).
META_OUT = Path(__file__).resolve().parent / "lut-meta"

LOOKS = {
    "print": {
        "label": "Lamplight",
        "negative": KODAK_5219,
        "print": KODAK_2383,
        "kelvin": 5600,
    },
    "portra": {
        "label": "Portrait",
        "negative": KODAK_PORTRA_400,
        "print": KODAK_PORTRA_ENDURA,
        "kelvin": 5600,
    },
}

MID_GREY_SRGB = 0.4614  # 0.18 linear, sRGB encoded

# Input is an already tone-mapped phone JPEG, so running the full film curve
# on it tones the image twice (crushed shadows, grey whites). We keep the film's
# cross-channel colour response but rebuild the neutral axis: each channel is
# mapped so that greys stay grey and follow a curve halfway between the film
# print curve (stretched to the display range) and identity.
FILM_TONE_WEIGHT = 0.5
BLACK_OUT = 0.02
WHITE_OUT = 0.975


def convert(rgb, neg, prt, kelvin, exp_comp):
    return film_conversion(
        rgb,
        neg,
        prt,
        input_colorspace=colour.RGB_COLOURSPACES["sRGB"],
        exp_kelvin=kelvin,
        exp_comp=exp_comp,
        output_gamut="Rec. 709",
        gamma_func="sRGB",
        white_clip=True,
    )


def find_exposure(neg, prt, kelvin):
    """Pick exposure so input mid grey lands near output mid grey."""
    grey = np.full((1, 1, 3), MID_GREY_SRGB, dtype=np.float32)
    best = (1e9, 0.0)
    for ev in np.arange(-2.0, 2.01, 0.125):
        out = convert(grey, neg, prt, kelvin, float(ev))
        err = abs(float(np.mean(out)) - MID_GREY_SRGB)
        best = min(best, (err, float(ev)))
    return best[1]


def neutral_axis_fix(table, neg, prt, kelvin, ev):
    """Remap each channel so the grey axis is neutral and display-ranged."""
    xs = np.linspace(0, 1, 257, dtype=np.float32)
    ramp = np.repeat(xs[:, None, None], 3, axis=2).reshape(257, 1, 3)
    out = convert(ramp, neg, prt, kelvin, ev).reshape(257, 3)
    lum = out.mean(axis=1)
    film = (lum - lum[0]) / (lum[-1] - lum[0])
    target = FILM_TONE_WEIGHT * film + (1 - FILM_TONE_WEIGHT) * xs
    target = BLACK_OUT + (WHITE_OUT - BLACK_OUT) * target
    fixed = np.empty_like(table)
    for c in range(3):
        mono = np.maximum.accumulate(out[:, c])  # interp needs increasing x
        grey_in = np.interp(table[..., c], mono, xs)
        fixed[..., c] = np.interp(grey_in, xs, target)
    return fixed, target


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    axis = np.linspace(0.0, 1.0, SIZE, dtype=np.float32)
    # Grid indexed [b][g][r] so that red varies fastest in the flat array.
    b, g, r = np.meshgrid(axis, axis, axis, indexing="ij")
    grid = np.stack([r, g, b], axis=-1)

    for look_id, look in LOOKS.items():
        neg = FilmSpectral(look["negative"])
        neg.set_color_checker()
        prt = FilmSpectral(look["print"])
        prt.set_color_checker(negative=neg)
        ev = find_exposure(neg, prt, look["kelvin"])
        table = convert(grid, neg, prt, look["kelvin"], ev)
        table = np.nan_to_num(table, nan=0.0)
        table, target = neutral_axis_fix(table, neg, prt, look["kelvin"], ev)
        table = np.clip(table, 0.0, 1.0)
        data = np.round(table.reshape(-1, 3) * 65535).astype("<u2")
        (OUT / f"{look_id}.bin").write_bytes(data.tobytes())

        ramp_in = np.linspace(0, 1, 17, dtype=np.float32)
        ramp = np.repeat(ramp_in[:, None, None], 3, axis=2).reshape(17, 1, 3)
        film_out = convert(ramp, neg, prt, look["kelvin"], ev).reshape(17, 3)
        idx = np.round(ramp_in * (SIZE - 1)).astype(int)
        lut_out = table[idx, idx, idx]
        meta = {
            "id": look_id,
            "label": look["label"],
            "size": SIZE,
            "negative": look["negative"].name,
            "print": look["print"].name,
            "exposureCompensationEv": ev,
            "source": "spectral-film-lut 0.18.0 (MIT, Jan Lohse)",
            "greyRampIn": [round(float(v), 4) for v in ramp_in],
            "filmToneWeight": FILM_TONE_WEIGHT,
            "greyRampFilmRaw": [[round(float(c), 4) for c in r] for r in film_out],
            "greyRampLut": [[round(float(c), 4) for c in r] for r in lut_out],
        }
        META_OUT.mkdir(parents=True, exist_ok=True)
        (META_OUT / f"{look_id}.json").write_text(json.dumps(meta, indent=1))
        print(look_id, "ev", ev, "bytes", data.nbytes, file=sys.stderr)


if __name__ == "__main__":
    main()
