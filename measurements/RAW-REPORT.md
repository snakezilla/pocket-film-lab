# RAW engine: measured comparisons (phase 3)

Measured on 2026-10-29 on the iPhone 17 Pro **simulator** (iOS 27 SDK, Mac GPU). No phone was available, so none of these numbers are from a phone; expect a phone to be slower. Re-run with:

```
cd ios && xcodebuild test -project PocketFilmLab.xcodeproj -scheme PocketFilmLab -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Each number below is printed by a test (`MEMORY`, `LARGE`, `WB`, `BRIDGE`, `EXPORT`, `PRIVACY` lines). The test files are the CC0 DNGs in `raw-engine/TEST-RAWS.md`. There is no public 48 MP iPhone ProRAW, so the 47 MP Leica Q2 DNG (8424×5632, 8368×5584 after crop) stands in for it.

## 1. Memory and speed on a 47 MP file

| Path | Phase 2 | Phase 3 | Test |
|---|---|---|---|
| Open (read size and as-shot WB) | — | 102–108 ms | `SpeedMemoryTests.testLargeFilePreviewPath` |
| First preview, 1600 px (reduced decode + film + grain + halation) | — | 546–765 ms | same |
| Slider move on the cached decode (exposure, look, grain…) | — | median 14–25 ms, max 15–58 ms | same |
| White balance change, 47 MP | re-decode | 384–397 ms, including the one-off fitter setup | same |
| Preview path peak memory | — | **+34 MB** over start | same |
| Full-size HEIC export, plain | +153 MB, 5.6 s | +162 MB, 5.1 s | `RawPipelineTests` |
| Full-size HEIC export, grain 0.35 + halation 0.3 | +254 MB, 7.5 s | +217 MB, 5.5 s | same |

Reading:
- The preview path never decodes at full size. CIRAWFilter's `scaleFactor` decodes straight to about 1600 px, so a 47 MP file costs about 34 MB while editing.
- Full-size export peaks at +160 to +220 MB. The 8-bit output bitmap alone is 187 MB (8368×5584×4), so Core Image is already tiling everything else. On a 6 GB phone this is well inside the app's memory limit. No change was needed this phase. The phase-2 and phase-3 numbers come from different runs on the same machine. The spread between runs is about ±40 MB and ±1 s, so read the change as "no regression", not as a gain.

## 2. White balance preview: matrix instead of re-decode

New in phase 3 (`Engine/WhiteBalanceMatrix.swift`). A WB change keeps the cached preview decode and applies a 3×3 matrix. The matrix is fitted by least squares between two 160 px decodes, with one CIRAWFilter kept alive. Export still does a true decode at the chosen WB.

Preview at 1600 px, ProRAW (iPhone 12 Pro) and Bayer (iPhone XS) DNGs. The error compares the film render at 800 px from the matrix path against a true decode at the new WB.

| File | WB change | Matrix | Re-decode | Mean error | Channels > 6 codes off |
|---|---|---|---|---|---|
| ProRAW | −1200 K (first change, includes fitter setup) | 240 ms | 350 ms | 0.69 codes | 0.035% |
| ProRAW | +1500 K, tint +10 | 102 ms | 354 ms | 0.28 | 0% |
| ProRAW | +600 K, tint −15 | 110 ms | 352 ms | 0.20 | 0% |
| Bayer | −1200 K (first) | 222 ms | 302 ms | 0.05 | 0.015% |
| Bayer | +1500 K, tint +10 | 121 ms | 313 ms | 0.02 | 0% |
| Bayer | +600 K, tint −15 | 114 ms | 310 ms | 0.01 | 0% |

Reading: after the first change, a WB step is about **3× faster** (100–120 ms vs 300–355 ms), and the preview is within 1 code of the true decode on average. Most of the cost of a decode is CIRAWFilter parsing the file; keeping the filter alive is what made this fast. The first try, which made a new filter per change, was no faster than a re-decode (465–673 ms).

## 3. Export: pixels and metadata

| File | Format | Size | Mean \|Δ\| vs in-memory render | Max | Channels > 8 codes off |
|---|---|---|---|---|---|
| ProRAW | JPEG | 1200×1600 | 0.77 codes | 25 | 0.058% |
| ProRAW | HEIC | 1200×1600 | 0.55 | 14 | 0.006% |
| Bayer | JPEG | 1600×1200 | 0.64 | 23 | 0.038% |
| Bayer | HEIC | 1600×1200 | 0.42 | 17 | 0.007% |

The large single-channel differences sit at hard colour edges, where both formats subsample chroma.

Metadata (`ExportPrivacyTests.testExportsCarryNoSourceMetadata`, full-size exports with grain and halation on). The test is stricter than in phase 2: it now uses an allow-list.
- JPEG keys: `ColorModel, DPIHeight, DPIWidth, Depth, PixelHeight, PixelWidth, ProfileName, {Exif}, {JFIF}, {TIFF}`.
- HEIC keys: `ColorModel, Depth, HasAlpha, Headroom, Orientation, PixelHeight, PixelWidth, PrimaryImage, ProfileName, {Exif}, {TIFF}`.
- `{Exif}` holds only pixel size, colour space and the encoder's fixed defaults (ExifVersion, FlashPixVersion, ComponentsConfiguration, SceneCaptureType). `{TIFF}` holds only orientation, resolution and HEIC tile size.
- Orientation is 1 (upright pixels).
- A byte search of every exported file finds no camera make (`Apple`), no `GPS`, no `MakerApple` and no `DateTimeOriginal`. The source DNGs carry a make, so the test would catch a leak.
- The source file is byte-for-byte unchanged (`RawPipelineTests`).

## 4. JPEG/PNG fallback

Both "Open RAW" (Photos) and "RAW from Files" now accept a photo that is not RAW. It is sent to the existing web JPEG/PNG path instead of failing with an error (`Bridge/FallbackImage.swift`).
- JPEG and PNG are passed through byte for byte (test). The web path re-encodes on export and keeps no metadata, as before.
- HEIC, and anything else Core Image reads, becomes an upright JPEG with no metadata. Test: a 120×60 HEIC with EXIF orientation 6 and GPS becomes a 60×120 JPEG with no GPS and orientation 1. Not every web view decodes HEIC, which is why it is converted.
- An unreadable file fails with a clear message (test).
- The browser build is unchanged: `npm test` 36/36 (new: open result, RAW vs fallback), `npm run test:e2e` 12/12.
- Not covered: the PHPicker and Files UI can't be automated here, so a human still has to click through the path from the picker to `startSession`.

## 5. Tuning pass 2: grey axis, before and after

Changes in `tools/make_raw_lut.py`, from the two before/after pairs (mezha1, and cakesauce on X, posted by the assistant account). The evidence is in `references/LOOK-TRAITS.md`, under "Tuning pass 2".
- **Warm highlights** (`HIGHLIGHT_WARM`): near-whites go to b\* about +9 and a\* about −2, ramping in from display Y 0.36 (+1 stop) to Y 0.64. Measured target: b\* +8 to +11 in 8 of 9 reference outputs, with both pairs shifting by +10 or more.
- **Toe lift** (`TOE_LIFT` ×1.12 at display Y 0.015): only the direction is measured, and the amount is deliberately small.
- Kept: `BLACK_LIFT`, `CHROMA_HIGH` (the references confirm them), the shoulder and the halation tint.

250D look, scene grey → sRGB code (R,G,B). From the LUT generator's exact ramp; the GPU matches it within 1% (`FilmLookTests`).

| stop | phase 2 | phase 3 | phase 3 L\*, a\*, b\* |
|---|---|---|---|
| −8 | 5,5,5 | 5,5,5 | 1.4, 0, 0 |
| −4 | 8,8,8 | 8,8,8 | 2.1, 0, 0 |
| −2 | 34,34,34 | 36,36,36 | 14.4, 0, 0 |
| −1 | 70,70,70 | 70,70,70 | 29.8, 0, 0 |
| 0 | 117,117,117 | 117,117,117 | 49.1, 0, 0 |
| +1 | 162,162,162 | 162,162,162 | 66.6, 0, 0 |
| +2 | 197,197,197 | 199,197,185 | 79.4, −1.3, +6.2 |
| +3 | 220,220,220 | 224,220,204 | 87.7, −1.8, +8.7 |
| +4 | 234,234,234 | 237,234,216 | 92.5, −1.9, +9.1 |
| +5 | 240,240,240 | 244,241,222 | 94.9, −2.0, +9.3 |
| +6 | 244,244,244 | 248,245,226 | 96.2, −2.0, +9.4 |

500T and Portra follow the same pattern. At +6 stops they reach b\* +9.4/+9.5, and their top codes are 249/251.

Against the references (measured, distribution only; exposure is unknown in every reference, so absolute codes are indicative):

| Trait | References | Ours, phase 3 | Status |
|---|---|---|---|
| Near-white highlight tint b\* | +8.3 to +10.6 (8 of 9 outputs) | +8.7 to +9.4 from +3 stops up | on target (measured) |
| Near-white highlight tint a\* | −4.6 to +1.7 | −1.8 to −2.0 | on target |
| Max code with no sun in frame | 209–251 | +6 stops: 248 (R), 245 (G) | on target |
| Black floor p0.5 | median about code 5 | 5–6 | on target (unchanged) |
| Highlight/mid chroma | 0.47–0.50 (pairs) | 0.53–0.72 by the generator's report (now includes the cream tint) | slightly high; judged acceptable because the cream itself is chroma |
| Greys at or below +1 stop | neutral | neutral within 1% | test |

Judged, not measured: the smoothstep shapes of the warm ramp and the toe; leaving the halation tint at (1, 0.32, 0.06). The phase-2 note asked for R−B ≈ 2×(R−G), which needs more green, i.e. more orange, not redder. There is no new halation evidence (no reference has clipped sources), so I left it alone.

Not changed, and why: blue-sky desaturation (`BLUE_HIGH_CHROMA`, proposed at ×0.6 for hues 200–290°). The two pairs disagree on the amount (×0.68 vs about ×0), and the warm highlight shift already pulls pale skies toward neutral. Revisit it with a LookSheet side-by-side.
