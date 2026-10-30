# Look traits measured from the reference images

Measured on 2026-10-29 from the public sample photos listed in `references/SOURCES.md`. The copies in `references/local/` are gitignored and are not reproduced here. Re-run the measurements with:

```
tools/.venv/bin/python -I tools/measure_refs.py [--crops /tmp/somewhere]
```

The script prints JSON. The crop boxes for the UI screenshots are hard-coded in `SOURCES` at the top of the script.

## Images used

| Label | File (in `references/local/`) | Crop | Weight |
|---|---|---|---|
| ig_portrait | instagram_steveyedlin_..._2880x2880.jpg | full | high (2880 px, low-key portrait) |
| x_dusk | x_rianjohnson_..._2880x2160.jpg | full | high (2880 px, dusk, lamps; the only usable grain source) |
| mezha1_after | press_mezha_photo1.jpg, right half | x 662-1312, y 70-875 (below the label) | high for relative tone/colour (it is the only before/after pair), low for absolutes |
| mezha1_before_iphone | press_mezha_photo1.jpg, left half | x 0-650, y 70-875 | baseline only. This is the stock iPhone render, not the reference look |
| mezha2_forest | press_mezha_photo2.jpg, right panel | x 662-1312 | medium. Probably reference output, but not confirmed |
| mezha2_ship | press_mezha_photo2.jpg, left panel | x 0-650 | low. Its sky is far more saturated than in any other sample, so this may not be the reference look |
| as_ipad_seascape / as_iphone_seascape | App Store viewer screenshots | photo area only | medium for tone and tint. The image is scaled and composited into a UI mockup |
| as_ipad_fruit / as_iphone_fruit | App Store editor screenshots | photo area, below the info overlay | medium for colour. Same photo twice; the two results agree to within 1-2 units |

Split check: `press_mezha_photo1` is a before/after pair. The left half is labelled "iPhone 17 Camera app" and the right half carries the app label. The split is at x = 656. I cropped both halves below the label bar.

## 1. Black level and lift

Luminance Y is computed from linear sRGB (Rec.709 weights) and then re-encoded to an 8-bit sRGB code.

| Image | p0.5 code (lin) | p1 code (lin) | p5 code | min channel p0.5 (R,G,B) | Source |
|---|---|---|---|---|---|
| ig_portrait | 0.0 (0.0000) | 0.0 (0.0000) | 0.0 | 0,0,0 | measured |
| x_dusk | 3.0 (0.0009) | 4.1 (0.0012) | 8.4 | 0,3,0 | measured |
| mezha1_after | 6.4 (0.0019) | 8.4 (0.0025) | 14.6 | 9,1,0 | measured |
| mezha1_before_iphone (baseline) | 2.1 (0.0007) | 3.6 (0.0011) | 18.8 | 5,0,0 | measured |
| mezha2_forest | 2.9 (0.0009) | 4.0 (0.0012) | 8.0 | 0,3,0 | measured |
| as_*_fruit | 5.9-6.1 (0.0018) | 7.2-7.4 | 14.3-14.6 | 8-9,0,0 | measured |
| as_ipad_seascape | 11.9 (0.0036) | 14.8 | 24.7 | 3,13,20 | measured |
| as_iphone_seascape | 18.7 (0.0064) | 20.8 | 35.7 | 9,20,26 | measured (smaller copy of the same photo) |

Reading:
- **Measured:** the floor is only slightly raised in most frames (p0.5 at 3-6 codes). The low-key portrait crushes fully to 0: 77% of its pixels have L* < 10, and its median is code 2. So the look does not enforce a fixed lifted black. It allows true black.
- **Measured (pair):** compared with the iPhone render, the very bottom is lifted (p1: 3.6 → 8.4), but everything from p5 upward is darker (p5: 18.8 → 14.6, p25: 46.7 → 25.5). This is a dense, contrasty toe with only a small lift at the very bottom.
- **Measured:** the seascape is the exception. Its floor sits at 12-19 codes, and the lift is blue (min channel R 3, G 13, B 20). That looks like a cool, lifted black in that grade, or flare from the backlit scene.
- **Judged by eye:** the blacks look dense and inky rather than milky. There is no obvious faded-film look.

## 2. Whites and highlight roll-off

| Image | p99 code | p99.5 code | max Y code | area Y > 245 | area any channel ≥ 250 | top histogram, Y codes 225-260 in 5-code bins (% of pixels) | Source |
|---|---|---|---|---|---|---|---|
| ig_portrait | 174.9 | 179.8 | 237.3 | 0% | 0% | all 0 | measured |
| x_dusk | 209.8 | 220.7 | 243.5 | 0% | 0.007% | 0.09, 0.11, 0.19, 0, 0, 0, 0 | measured |
| mezha1_after | 225.8 | 229.8 | 250.9 | 0.007% | 0.36% | 0.67, 0.31, 0.13, 0.04, 0.01, 0, 0 | measured |
| mezha1_before_iphone (baseline) | 250.9 | 252.7 | 255.0 | **2.54%** | **13.9%** | 0.87, 1.16, 1.30, 1.34, 1.29, 1.25, 0 | measured |
| mezha2_forest (sun in frame) | 229.6 | 238.5 | 254.4 | 0.20% | 1.42% | 0.28, 0.27, 0.27, 0.22, 0.17, 0.03, 0 | measured |
| as_ipad_seascape (sun rays) | 224.2 | 229.4 | 234.8 | 0% | 0% | 0.43, 0.46, 0, 0, 0, 0, 0 | measured |
| as_*_fruit | 203.4-204.4 | 205.6-206.6 | 231-235 | 0% | 0% | ~0 | measured |

Reading:
- **Measured:** the reference renders almost never reach code 255. Across the five confirmed outputs, the maximum Y is 231-251 and p99.5 is 206-230. The histogram falls away well before 245. That is a soft shoulder, not a hard clip.
- **Measured (pair):** the same sky goes from 2.5% of pixels above Y 245 (iPhone) to 0.007% (reference). The quantile map is p90 212.7 → 190.4, p95 235.6 → 207.5, p99 250.9 → 225.8 and p99.5 252.7 → 229.8. Highlights are pulled down by about 22-28 codes and spread out instead of piling up at 255.
- **Measured:** even the backlit seascape with sun rays tops out at 235. When the sun itself is in frame (forest), there is a small specular core at 250-254, about 0.2% of the area.
- **Judged by eye:** the clouds in the seascape keep their texture right up to the sun rays. Highlights look creamy, not white.
- **Not inferable:** the codes at +3 and +5 stops above mid grey. There is no grey card and the exposure is unknown, so I give the shoulder shape instead (see Targets).

## 3. Saturation vs brightness

Mean CIELAB C* in L* bins. Empty cells mean fewer than 200 pixels in the bin.

| Image | L 0-10 | 10-20 | 20-30 | 30-40 | 40-50 | 50-60 | 60-70 | 70-80 | 80-90 | 90-100 | C(L70-90) / C(L40-60) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ig_portrait | 0.7 | 16.1 | 24.3 | 30.5 | 33.8 | 33.9 | 33.4 | 28.7 | 19.6 | — | 0.71 |
| x_dusk | 5.0 | 16.9 | 22.7 | 23.8 | 22.6 | 20.8 | 16.0 | 14.9 | 20.2 | 10.3 | 0.81 |
| mezha1_after | 10.8 | 20.7 | 25.8 | 24.7 | 24.9 | 19.8 | 10.7 | 9.8 | 11.0 | 10.1 | 0.47 |
| mezha1_before_iphone | 11.9 | 29.9 | 40.0 | 46.1 | 44.9 | 40.8 | 30.3 | 25.7 | 19.8 | 6.1 | 0.53 |
| mezha2_forest | 5.5 | 14.3 | 18.3 | 22.5 | 25.9 | 28.8 | 31.5 | 29.6 | 21.4 | 13.7 | 0.93 |
| as_ipad_fruit | 8.0 | 30.2 | 47.7 | 57.6 | 52.5 | 42.7 | 37.4 | 25.7 | 17.6 | — | 0.45 |
| as_ipad_seascape | 7.0 | 5.5 | 4.1 | 7.2 | 13.1 | 20.6 | 22.3 | 23.3 | 18.4 | 12.5 | 1.24 (warm clouds) |

Pair, per L* bin (reference / iPhone): L20-30 0.64, L30-40 0.54, L40-50 0.55, L50-60 0.49, L70-80 0.38, L80-90 0.56. The overall mean C* drops from 31.7 to 16.4, a ratio of 0.52.

Reading:
- **Measured:** chroma peaks in the lower midtones (L* 30-60) and falls in the highlights. In the scenes that are not dominated by a warm sky, highlight chroma is 0.45-0.8× midtone chroma. Shadows below L* 10 carry almost no chroma (0.7-11).
- **Measured (pair):** the reference is about 0.5-0.65× as saturated as the stock iPhone render at the same L*. The biggest drop is in the bright end (L70-80, 0.38×). The sky loses nearly all its chroma: no pixel passes the sky mask (C* ≥ 6, hue 200-290°) in the reference half.
- **Judged by eye:** strong primaries are still rich (the fruit reaches C* 57 at L* 30-40). The look reads as dense colour that thins out in the highlights, not as a global desaturation.

## 4. Hue shifts and tint

Shadow and highlight tint: mean a\*/b\* of the darkest and brightest 10% of near-neutral pixels (C* < 12).

| Image | shadow a*, b* (mean L*) | highlight a*, b* (mean L*) | Source |
|---|---|---|---|
| ig_portrait | 0.0, 0.0 (0.2) | +1.2, +1.4 (6.0, still dark) | measured. Not informative because the neutral pixels are the black background |
| x_dusk | -0.3, +0.5 (1.4) | -4.6, +2.2 (80) | measured |
| mezha1_after | +3.0, +0.8 (2.9) | +1.7, **+8.8** (86) | measured |
| mezha1_before_iphone | +3.3, +0.6 (1.1) | -1.5, -1.5 (98.5) | measured baseline |
| mezha2_forest | -1.3, +0.5 (1.6) | -3.5, +6.1 (46) | measured |
| as_ipad_seascape | -1.6, **-6.8** (6.4) | -1.7, **+7.7** (53) | measured |
| as_iphone_seascape | -1.9, -6.5 (10) | -1.9, +7.9 (55) | measured |
| as_*_fruit | +1.4, +0.4 (1.6) | +4.1, +5.5 (33) | measured |

Hue masks (CIELAB hue angle h, mean over the mask; masks are simple hue/chroma/L* gates defined in `HUE_MASKS` in the script):

| Region | Mask | Reference value | iPhone baseline | Source |
|---|---|---|---|---|
| Skin (portrait) | h 20-70°, C* ≥ 12, L* 25-85 | h 58.4°, C* 34, L* 53 | — | measured (the face fills most of the mask) |
| Red maple leaves | h 350-40°, C* ≥ 30 | h 35.7°, C* 36.5, L* 24 | h 33.6°, C* 46, L* 30 | measured (pair) |
| Pomegranates (red) | same | h 34.8°, C* 52, L* 34-36 | — | measured |
| Dusk sky | h 200-290°, C* ≥ 6 | h 254°, C* 18, L* 40 | — | measured |
| Daytime sky | same | none (C* < 6 after the look) | h 273°, C* 22.5, L* 83 | measured (pair) |
| Seascape sky patches | same | h 230°, C* 8-9 | — | measured (cyan-blue, low chroma) |
| Foliage / green fruit | h 95-170°, C* ≥ 8 | forest h 133° C* 19; green fruit h 123-126° C* 49-54; dusk palms h 100° C* 26 | — | measured; the mask also catches yellow-green |

Reading:
- **Measured:** highlights are warm. The brightest near-neutral pixels sit at b* +5 to +9 in four of the five scenes with real highlights. In the pair, the shift is about +10 b* compared with the iPhone render (-1.5 → +8.8). a* is close to neutral or slightly green (-4.6 to +1.7), so the tint is yellow/cream, not orange.
- **Measured:** shadows are mostly neutral (|b*| < 1). The seascape is the exception, with clearly cool/blue shadows (b* -6.5 to -6.8) that move to warm highlights. That is a classic split tone in that frame.
- **Measured (pair):** reds move about 2° toward orange and lose about 20% chroma. A blue daytime sky collapses toward a cyan-grey with almost no chroma.
- **Judged by eye:** skin is a natural warm tan, neither pink nor orange. Dusk blue stays a deep, slightly cyan blue.

## 5. Grain

Method: Y code minus a Gaussian blur (σ = 1.5 px), measured in 32×32 patches whose gradient is in the lowest quartile. The table gives the median patch std for each luminance band. The autocorrelation comes from up to 400 flat midtone patches.

| Image | 0-30 | 30-80 | 80-140 | 140-200 | 200-255 | ACF lag 1 / 2 (x and y) | half-width | Source |
|---|---|---|---|---|---|---|---|---|
| x_dusk (2880 px wide) | 1.6 codes | 3.4 | **4.7** | 4.3 | 3.1 | 0.19 / -0.16 | 0.62 px = 0.00022 × width | measured |
| ig_portrait | 0.0 (the flat area is pure black) | — | — | — | — | — | — | measured. Grain is fully clipped in crushed blacks |
| Other images | — | — | — | — | — | — | — | not measured (≤ 1312 px, or scaled UI mockups) |

Reading:
- **Measured, weak evidence:** grain is clearly present at about 3.5-4.7 codes std in the midtones of a 2880 px image. It peaks in the midtones and is lower in the shadows and highlights. In black areas crushed to 0, the grain is gone too, so grain is added before the black clip or is scaled down near black.
- **Measured, weak evidence:** the residual is nearly white. Lag-1 correlation is 0.19 with a negative lobe at lag 2, so the measurable structure is about 1 px at 2880 px. A blur this small removes coarser grain, and JPEG plus web resizing reshape the fine structure, so treat the size as a lower bound.
- **Judged by eye (lamp crop of x_dusk at 100%):** the grain is visible, fine, and slightly clumpy, with a little colour noise in the dark wall areas.
- The App Store editor screenshot shows grain amplitude 1.25 and size 1.00, so the default amplitude may be lower than in that sample. Its relation to the samples above is unknown.

## 6. Halation

Method: mask pixels with any channel ≥ 250 (or Y ≥ 225/235 for the dusk lamps), then compare mean R-G and R-B in rings 0-3, 3-8, 8-16, 16-32 and 32-64 px outside the mask against a baseline more than 96 px away.

| Image | Ring 0-3 px R-G / R-B | 3-8 | 8-16 | 16-32 | Baseline | Source |
|---|---|---|---|---|---|---|
| mezha2_forest (sun) | +46 / +83 | +39 / +76 | +24 / +61 | +9 / +40 | -13 / +1 | measured |
| mezha2_ship (sunlit white tower) | +50 / +123 | +49 / +90 | +28 / +42 | +10 / +11 | -21 / -59 | measured (low weight) |
| x_dusk (lamps, Y ≥ 235) | +11 / +36 | +21 / +84 | +35 / +121 | +43 / +129 | n/a | measured |
| mezha1_before_iphone (sky gaps) | +4 / -7 | +39 / +36 | +60 / +61 | +72 / +75 | +62 / +67 | measured baseline (no halation expected) |
| mezha1_after, ig_portrait, App Store crops | — | — | — | — | — | not enough clipped pixels to test |

Reading:
- **Measured:** around the sun in the forest frame, a warm orange fringe (R > G > B) decays over about 16-32 px, which is 2.5-5% of the 650 px panel width. Away from the highlight, the pixels are neutral or green.
- **Confounded:** around the dusk lamps, the ring gets more orange with distance from the hot core. The core itself is desaturated toward cream (241, 230, 205). That is consistent with a tungsten wash on the wall plus highlight desaturation. It does not prove halation.
- **Judged by eye:** I saw no distinct red rim around the lamps in the 100% crop. The warm glow around the sun in the forest frame looks like a mix of lens flare and a soft orange bloom.
- **Conclusion:** halation is probably present but subtle. Its colour is warm orange-red, not a saturated red line. These images cannot separate it from the scene illuminant and from flare.

## Caveats

- Every image is a web re-encode (Instagram, X, Mezha/AppleInsider, App Store CDN). JPEG quantisation smooths the grain and can shift the lowest and highest codes by a few units.
- There is no grey card or chart, and the exposure is unknown. Absolute tone positions such as "mid grey lands at code N" cannot be measured, only distributions.
- There is only one before/after pair, it is about 650 px per half, and it was re-compressed. The "iPhone" side is Apple's processed render, not a neutral scene reference.
- The App Store photos are scaled down and composited into UI. Their absolute floor may include display-mockup treatment. The iPad and iPhone copies of the seascape disagree on the floor (12 vs 19 codes).
- The hue masks are crude gates. "Skin" also catches orange and brown objects (for example the pomegranates). The sky mask needs C* ≥ 6, so very desaturated skies drop out of it.
- mezha2 is not confirmed as reference output, and the ship panel looks stylistically different, so it carries little weight.

## Targets for our engine

These are sRGB 8-bit codes for a normally exposed scene with mid grey placed normally. They are tuning targets, not a match.

| Trait | Target | Basis |
|---|---|---|
| Black floor | **code 4-6** at p0.5 in normal scenes (linear ≈ 0.0012-0.0018). Allow true 0 in deep low-key shadows. Below code ~20 the toe is dense: shadows end up darker than an iPhone render from p5 upward (about -4 codes at p5, -20 at p25) | measured (pair + 4 outputs) |
| Shoulder / whites | Soft shoulder with a **ceiling of about 235-240** for anything short of a specular source. p99.5 of a bright scene lands around **225-230**. Less than 0.05% of area above code 245. Only point sources (the sun) reach 250-254. Codes at +3 and +5 stops above mid grey cannot be measured. Shape implied by the pair: input codes 213/236/251/253 map to 190/208/226/230 | measured |
| Saturation | Overall chroma about **0.55-0.65×** a stock iPhone render at equal L*. Highlight/midtone chroma ratio **C(L70-90)/C(L40-60) ≈ 0.5** (range 0.45-0.8). Near-black chroma close to 0. Saturated primaries can still reach C* 50-57 in the lower midtones | measured |
| Shadow tint | Neutral to slightly cool: **b\* 0 to -3** (the seascape reaches -6.5), a* within ±1.5 | measured, mixed evidence |
| Highlight tint | Warm cream: **b\* +6 to +9**, a* -2 to +2 (yellow, not orange) on near-white highlights. In the pair, the shift is about +10 b* compared with the iPhone render | measured |
| Hue notes | Reds drift about 2° toward orange and lose about 20% chroma. A daylight blue sky goes to a low-chroma cyan-grey (h about 230°, C* < 10). Skin h about 58°, C* about 34 | measured (crude masks) |
| Grain amount | Luminance std of about **4 codes at midtones** (3.5-4.7, peaking around code 80-200), about 1.5 codes near black, about 3 above code 200. Fade grain to 0 in crushed blacks | measured, weak (one 2880 px JPEG) |
| Grain size | Fine. Residual autocorrelation half-width about **0.0002-0.0004 × image width** (about 1 px at 2880 px). Treat this as a lower bound, since a slightly clumpy look reads as natural | measured, weak |
| Halation | **Yes, subtle.** A warm orange-red glow (R > G > B, R-B about 2× R-G) around the brightest sources, decaying over about **3-5% of image width**. No saturated red ring. Highlight cores desaturate to cream | partly measured, confounded by flare and the illuminant |

## Phase 2 tuning pass: where our engine stands

Our numbers come from `tools/make_raw_lut.py` (its chroma report, which uses random scene colours against the plain clipped linear render) and the iOS simulator tests (`TextureTests`, the `LookSheetTests` renders of the two iPhone sample DNGs). Grain is measured at the UI default, 0.35, on a 3000 px render.

| Trait | Target | Ours now (250D / 500T / Portra) | Status | How we got there |
|---|---|---|---|---|
| Black floor | code 4-6 | 5.2 / 5.4 / 6.2 (−8 stops) | on target | `BLACK_LIFT = 0.001`, a neutral display-linear offset. The value is measured; the offset form is judged |
| Shoulder | ceiling ~235-240 short of specular | +4 stops → 233, +5 → 240, +6 → 244 (250D) | on target | the film model's own shoulder, unchanged |
| Highlight/mid chroma | ≈ 0.5 | 0.51 / 0.50 / 0.40 | on target (Portra a little low) | highlight chroma scale of 0.8 above display Y 0.6. The curve shape is judged |
| Midtone chroma | 0.55-0.65× an iPhone render | 0.61 / 0.58 / 0.66× the *plain* linear render | probably close | the film model, untouched. The comparison base differs: an iPhone render is more saturated than plain, so we may be slightly more saturated than the references |
| Grain, midtones | ~4 codes std | 4.0 codes | on target | density bell, squared, `grainDensitySigma 0.55` |
| Grain, > code 200 | ~3 | 2.6 | on target | same bell |
| Grain, near black | ~1.5, fading to 0 | 0.3 at code 16, 0 at code 7 | lower than target | judged acceptable ("fade to 0 in crushed blacks") |
| Grain size | 0.0002-0.0004 × width | cell 1/3000 of the long edge (0.00033) | on target | measured |
| Halation | subtle, R>G>B, R−B ≈ 2×(R−G), decays over 3-5% of width | R−B 0.073, R−G 0.049 (ratio 1.5) near a 40× spot; sigma 1.2% of the long edge | close; could be a little redder | tint (1, 0.32, 0.06) and gain 0.25 are judged |
| Highlight tint | warm cream, b* +6 to +9 | neutral (greys held neutral by design and by test) | **not done** | an open decision, see PROGRESS.md |
| Shadow tint | 0 to −3 b* | neutral | close enough | — |
| Shadow density | p25 about −20 codes vs an iPhone render | p25 −31 vs our *plain* render (ProRAW sample) | possibly too dense | not tuned yet. Our plain render is not an iPhone render, so this comparison is weak |
