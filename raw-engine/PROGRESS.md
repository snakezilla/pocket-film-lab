# RAW engine progress

Read this first in every phase. Plan: `PLAN.md`. Test files: `TEST-RAWS.md`. Reference images: `../references/SOURCES.md`.

## Phase 1 (2026-10-29, 22:00–22:40): decode + first film look. DONE

Done:
- `raw-engine/PLAN.md`: the architecture (Core Image pipeline, the web UI bridge design for phase 2, the phase list).
- `tools/make_raw_lut.py`: a scene-linear-in 65³ float cube, from Spectral Film LUT (MIT). It simulates Kodak Vision3 250D 5207 printed on Kodak 2383, with the log2 shaper running from 0.18·2^-10 to 0.18·2^6.5. Greys are forced neutral on the axis, and off-axis colour keeps the film's response.
- Native engine in `ios/PocketFilmLab/Engine/`:
  - `RawDecoder`: CIRAWFilter with boost 0, local tone map 0, and contrast, sharpness and detail at 0. It uses the as-shot white balance and baseline exposure, and drops metadata.
  - `FilmLook.ci.metal`: shaper plus trilinear cube lookup in a single kernel.
  - `FilmEngine`: preview path with reduced-scale decode, or full size.
  - `FilmExporter`: writes JPEG or HEIC in sRGB with no source metadata.
- `ios/PocketFilmLabTests`: 10 tests on the iPhone 17 Pro simulator, all passing (`xcodebuild test … -scheme PocketFilmLab`).
- `tools/fetch_test_raws.sh` + `TEST-RAWS.md`: 3 CC0 DNGs from raw.pixls.us (iPhone 12 Pro ProRAW, iPhone XS Bayer, Leica Q2 47 MP), sha256-checked and gitignored.
- `references/SOURCES.md`: about 17 public Chromagraph sources. 11 images are in `references/local/` (gitignored). Only one before/after pair exists, and it is small (press_mezha_photo1, 1312×875).
- The web tests are still green: `npm test` 33/33, `npm run test:e2e` 12/12.

Measured (simulator, iPhone 17 Pro, iOS 27 SDK):
- Decode is scene-linear: +1 EV gives ×1.99999 (median over 25 849 unclipped pixels, iPhone XS DNG).
- Grey axis through the film look (scene-linear in → display-linear out, sRGB 8-bit code):

  | stop | in | out | sRGB |
  |---|---|---|---|
  | −8 | 0.0007 | 0.00058 | 2 |
  | −4 | 0.0113 | 0.00137 | 5 |
  | −2 | 0.045 | 0.0152 | 33 |
  | −1 | 0.09 | 0.0600 | 69 |
  | 0 | 0.18 | 0.1768 | 117 |
  | +1 | 0.36 | 0.3602 | 162 |
  | +2 | 0.72 | 0.5560 | 197 |
  | +3 | 1.44 | 0.7146 | 220 |
  | +4 | 2.88 | 0.8186 | 233 |
  | +5 | 5.76 | 0.8739 | 240 |
  | +6 | 11.52 | 0.9054 | 244 |

  Black floor is code 2. The shoulder rolls off smoothly, and +6 stops still sits under white (244). The GPU result matches the Python film model within 1%. Greys stay neutral within 1% per channel.
- Exported file vs in-memory render, every pixel (1600 px long edge, quality 1.0). JPEG: mean |Δ| 0.64–0.76 codes. HEIC: mean |Δ| 0.42–0.54 codes. Fewer than 0.06% of channels are more than 8 codes off; those are chroma-subsampling edges. Neither export has GPS, camera model or capture date, and the source file's bytes are unchanged.
- 47 MP full-size HEIC export (Leica Q2, output 8368×5584 after the DNG default crop): peak footprint +192 to +227 MB over start, about 4.8 s. This is simulator only, so phone numbers will differ.
- iPhone 12 Pro ProRAW as-shot WB read: 5201 K, tint +6.4.

Bugs found and fixed:
- CIColorCube stored the float cube at 8-bit precision, which put stops −8…−4 at 0. It was replaced with a custom trilinear lookup in the Metal kernel.
- `CIImage(bitmapData:)` puts row 0 at the top, so the cube image is now flipped explicitly.

Judged, not measured: mid grey maps to 0.18 out (no tonal change at mid grey). The 250D stock was chosen as the daylight default.

Not done / blockers:
- Not wired into the app UI yet. The engine runs only in tests (phase 2).
- No device run: `xcrun devicectl list devices` shows "AE's iPhone 13 Pro" as unavailable, and only an iPad 9 is available. Simulator only, unverified on a phone.
- No real 48 MP iPhone ProRAW sample. The Leica Q2 47 MP file stands in.
- Building needs the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`), which was installed tonight.

## Phase 2 (2026-10-29, 22:40–23:10): three looks, texture, bridge, first tuning pass. DONE

Done:
- **Three looks** on linear data, all into Kodak 2383: Vision3 250D (5207), Vision3 500T (5219), Portra 400. `tools/make_raw_lut.py [look-id …]` builds them (about 12 s for all three). Each look's JSON records its grade and a chroma report.
- **First tuning pass** in the cube, against `references/LOOK-TRAITS.md` (new this phase; script `tools/measure_refs.py`):
  - Black lift `BLACK_LIFT = 0.001`. The floor is now at code 5–6; it was 2. Target 4–6, measured.
  - Highlight chroma scale 0.8 above display Y 0.6. High/mid chroma comes out at 0.51 / 0.50 / 0.40; the target is about 0.5, measured. Midtone chroma is left to the film model.
  - Greys stay neutral. The full table of where we stand against each trait is at the end of LOOK-TRAITS.md.
- **Texture** (`Engine/FilmTexture.swift` + `FilmTexture.ci.metal`):
  - Halation in scene-linear before the cube. Light more than 2.5 stops over mid grey (soft knee) is blurred twice (sigma 0.42% and 1.2% of the long edge), tinted red-orange (1, 0.32, 0.06), with gain 0.25. The film's shoulder then compresses it.
  - Grain in print density after the cube. D = −log10(y). The swing follows a squared gamma bell that peaks at D ≈ 0.8, is 0 on paper white and fades in deep blacks. It mixes two noise scales, 65% mono and 35% per dye layer. The cell is 1/3000 of the long edge, so preview and export match at print size. Below one pixel per cell, the swing shrinks with the cell size (averaging).
- **Controls through the web UI** (the brief's preferred route):
  - `Bridge/RawBridge.swift` adds the `raw` message handler. It imports through PHPicker (the RAW representation only) or Files (`UTType.rawImage`), copying the file to our own temp folder so the original is only read.
  - Renders run on a serial queue; stale requests are dropped.
  - The reduced-size linear decode is cached per white balance (`Bridge/RawSession.swift`). Exposure is applied as a linear gain, so slider moves don't re-decode.
  - Previews are served as `app://local/__raw/pN.jpg` (`PreviewStore`), with no base64.
  - Hold-to-compare shows the plain decode.
  - HEIC/JPEG full-size export goes to the share sheet. The temp file is removed afterwards. No metadata; each export gets a fresh grain seed.
  - Web: `src/native.ts` (client) and `src/rawmode.ts`. `main.ts` shows "Open RAW" and "RAW from Files" only when the bridge exists, plus native look buttons, white balance and tint sliders (as-shot by default), and Save JPEG / Save HEIC. The JPEG/PNG path is unchanged, and the browser build doesn't show the RAW controls.
- Tests: *(corrected 2026-10-30)* the evidence is one full iOS run at **18/18**, then a **6/6** subset run after the halation test fix. No complete 19/19 run happened in phase 2. The halation failure and its fix are as recorded at the time.
  - New: `TextureTests` (all looks neutral on greys; looks differ on skin; grain density weighting and scaling; halation colour and locality), `BridgeTests` (settings clamping; a real WKWebView round trip), `LookSheetTests` (writes renders to `ios/TestData/renders/<timestamp>/`, gitignored), and a 47 MP export with texture.
  - Web: `npm test` 35/35 (new `native.test.ts`), `npm run test:e2e` 12/12.

Measured (simulator):
- **Bridge latency** (postMessage → render → JPEG over app:// → decoded in the page, 1206 px preview, ProRAW sample): slider moves have a median of 34–36 ms and a max of 38–75 ms (native about 25 ms). The first render after opening a file, or after a WB change, re-decodes the RAW and takes 590–815 ms. That is well under the 120 ms limit, so the web UI stays as the control surface. These are Mac GPU numbers; a phone will be slower.
- Grain at the UI default 0.35, 3000 px: std 4.0 codes at mid grey, 2.6 at code 197, 2.1 at code 70, 0.3 at code 16, 0 at code 7. Target from the references: 4 / 3 / 1.5.
- Halation next to a 40× spot: R +0.093, G +0.045, B +0.021 (linear). Far away there is no change at all.
- 47 MP full-size HEIC: +153 MB and 5.6 s plain; **+254 MB and 7.5 s with grain and halation**.
- Black floor codes: 5.2 (250D), 5.4 (500T), 6.2 (Portra).

Judged by eye, not measured: halation tint, gain and two-blur shape; the grain bell shape and the 65/35 mono/chroma split; the highlight chroma curve shape; RAW UI defaults (grain 0.35, halation 0.3). On the ProRAW lake sample all three looks read as film prints. 250D and 500T are close on daylight greys (500T is a bit cooler and more contrasty in colour). Portra is warmer on skin-like colours and softer in the sky. The shadow toe is dense; see the open decisions below.

Not done / blockers:
- **No device run.** `devicectl` lists "AE's iPhone 13 Pro" as unavailable; only the iPad 9 is available. Simulator only, unverified on a phone.
- The RAW import UI (PHPicker/Files → `open`) has not been clicked through by a human. The bridge is tested from `startSession` onwards in a real WKWebView, but the picker itself can't be automated here.
- A white balance change re-decodes at preview size (about 0.6–0.8 s on the simulator). This is fine for a slider release, but sluggish while dragging. If it is a problem on a phone, apply WB as a linear matrix on the cached decode for preview and do the true re-decode only on export.

Open decisions for the owner:
1. **Warm highlights.** The references warm near-white highlights to cream (b* +6 to +9, measured). We keep greys neutral because the brief's tests require it. Option: warm only above about +2.5 stops, and loosen the neutrality test there.
2. **Shadow density.** Our toe is denser than the references suggest (p25 −31 codes vs our plain render; the references show −20 vs an iPhone render, a different base). A gentle toe lift is the next tuning knob.

## Phase 3 (2026-10-29, 23:20–00:10): speed, memory, export privacy, JPEG/PNG fallback, tuning pass 2. DONE

All measured comparisons are in `measurements/RAW-REPORT.md`.

Done:
- **Fast white-balance preview** (`Engine/WhiteBalanceMatrix.swift`, used by `RawSession`). A WB change keeps the cached preview decode and applies a 3×3 matrix. The matrix is fitted by least squares between two 160 px decodes, with one CIRAWFilter kept alive. This was phase-2 next step 3. Export still decodes at the chosen WB. `RawSession(fastWhiteBalance: false)` gives the old behaviour.
- **JPEG/PNG/HEIC fallback** (`Bridge/FallbackImage.swift`):
  - Open RAW (Photos) takes the RAW version if there is one; otherwise it takes the photo's own JPEG/PNG/HEIC. The Files picker also accepts JPEG/PNG/HEIC.
  - Anything that is not RAW goes to the page's existing JPEG/PNG path. The bridge reply is `{fallback: {url, name}}`, served over `app://local/__raw/`.
  - JPEG/PNG are passed through byte for byte. HEIC becomes an upright JPEG with no metadata.
  - Web side: `native.ts` `open()` now returns `{raw}` | `{photo}` | null, and `main.ts` feeds `{photo}` into `onFile`.
- **Export privacy** (`ExportPrivacyTests`): an allow-list of metadata keys, orientation 1, and a byte search for the camera make, GPS, MakerApple and DateTimeOriginal, on full-size exports with texture on.
- **Speed and memory on a 47 MP file** (`SpeedMemoryTests.testLargeFilePreviewPath`): open, first preview, slider moves, a WB change and peak memory on the preview path.
- **Tuning pass 2** (`tools/make_raw_lut.py`, `references/LOOK-TRAITS.md` "Tuning pass 2", `tools/measure_refs.py`):
  - New references: the cakesauce before/after pair on X, the dmcgco interior and 3 Newsshooter images. These are the ones the assistant account posted on issue #7; copies are in `references/local/`, which is gitignored. The AppleInsider pair still returns 403.
  - *(Superseded in the landing pass: the cube is neutral again, and warmth is an optional setting, default 0.)* Warm highlights are now on: greys at +3 to +6 stops sit at b\* +8.7 to +9.4, a\* about −2. Reference: b\* +8.3 to +10.6 in 8 of 9 outputs, and both pairs shift by at least +10. This settles open decision 1.
  - Small toe lift (×1.12 at code ~32; stop −2 goes 34 → 36). This settles open decision 2. The direction is measured, the size is not.
  - The grey-neutral tests now require neutral greys up to +1 stop. Above that they require a warm but bounded tint: R ≥ G ≥ B, B/G > 0.8, R/G < 1.05 (`assertGreyOrWarmHighlight`).
- Tests: iOS **26/26** on the iPhone 17 Pro simulator. Web `npm test` **36/36**, `npm run test:e2e` **12/12**.

Measured (simulator):
- **WB change:** 100–120 ms with the matrix vs 300–355 ms re-decoding (about 3×). The first change costs 220–240 ms because it sets up the fitter. Preview error against a true decode: mean 0.01–0.69 codes.
- **47 MP preview path:** open 102–108 ms, first preview 546–765 ms, slider median 14–25 ms, WB change 384–397 ms, peak **+34 MB**.
- **47 MP full-size HEIC:** +162 MB / 5.1 s plain; +217 MB / 5.5 s with grain and halation. That is no regression; runs vary by about ±40 MB.
- **Bridge round trip:** drag median 22 ms (native 14 ms).
- **Export vs render:** mean |Δ| 0.42–0.77 codes.

Not done / blockers:
- **No device run.** Same as phases 1 and 2: simulator only, unverified on a phone.
- The picker → fallback path has not been clicked through by a human. It is unit-tested from `FallbackImage` and `startSession` onwards.
- Halation tint is unchanged, because no reference has clipped sources. Blue-sky desaturation was proposed but not applied (the two pairs disagree).
- No real 48 MP iPhone ProRAW yet.

## Phase 4 (2026-10-29 23:40 – 2026-10-30 00:10): edge cases, polish, final docs. DONE

The final report, with the honest fidelity summary and remaining gaps, is at the top of `measurements/RAW-REPORT.md`.

Done:
- **Edge cases** (`EdgeCaseTests`, 6 new tests):
  - Rotated photos: the ProRAW sample is stored with Orientation 6. Its decode, preview and full-size export are all portrait, with orientation tag 1.
  - A Bayer copy with Orientation 8 (`tools/fetch_test_raws.sh` makes it with exiftool) equals the plain decode rotated, at 0.00 codes mean difference.
  - Extreme white balance (1800/50 000 K, tint ±150) stays finite and in range on both file types, through the true decode and the WB matrix, with texture on.
  - Bayer and ProRAW are both scene-linear (+1 EV → ×2.0). The Apple rendering options are held at 0 on both (the Bayer DNG has no local tone map).
- **Bug fixed:** the web WB sliders (2000–12 000 K, tint ±100) silently clamped an as-shot value outside that range. They now widen to include it (`rangeIncluding` in `src/rawmode.ts`, plus a unit test).
- **WB fitter pre-warm** after the first preview. The first WB change went from 231–353 ms to 78–93 ms (phase-3 next step 3).
- **Softness** (optional, off by default): a native setting, a bridge key and a RAW-only slider. **Gate weave was not built**: on a still it is only a sub-pixel shift.
- *(Turned back off in the landing pass.)* **Pale-sky chroma trim** (`BLUE_HIGH_CHROMA` 0.7). Light and hazy blues go to ×0.72–0.83 chroma, while deep blues, skin and foliage are unchanged (`tools/probe_cube.py`). This settles phase-3 next step 1. The amount is the gentler measured pair; the ramp is judged.
- **Code review fixes** (independent reviewer agent): a pre-warm that fails is no longer retried on every render, and it is skipped when a newer render or another file is waiting. The page sends the exact as-shot WB until a slider is moved, because a range input snaps 5201 K to 5200 K. Widened slider ranges stop at the native limits. A junk-input test could never fail; it is fixed. A timing assertion was replaced by a state check. A missing fixture now skips with a hint instead of failing in confusing ways.
- **Docs:** a README "RAW mode (iOS app only)" section, the THIRD_PARTY_NOTICES stock list, the derived fixture in TEST-RAWS.md, and the final RAW-REPORT.md.
- **Final test pass:** iOS **34/34** on the iPhone 17 Pro simulator, web `npm test` **41/41**, `npm run test:e2e` **12/12**.

Measured (simulator): see RAW-REPORT "Final numbers". 47 MP preview path +34 MB, export +208 MB / 4.9 s with texture, slider median 14 ms, bridge drag median 21 ms.

Not done / blockers:
- **No device run, in any phase.** `xcrun devicectl list devices` at 23:40 again showed "AE's iPhone 13 Pro" as unavailable; only the iPad 9 is available. iPhone apps do run on iPads in compatibility mode, but the brief scopes device testing to an iPhone, and signing for the iPad could register it in the developer account, so I left it alone. It is an option for the owner (an A10 with 2 GB RAM would be a harsh memory test). Simulator only, unverified on a phone.
- The PHPicker / Files picker has still not been clicked through by a human.
- Halation and skin are unverified against references (there is no usable evidence).

## Landing pass (2026-10-30 00:20–00:40): owner review items. DONE, simulator only

What was done, and the evidence, is at the top of `measurements/RAW-REPORT.md`; the artifacts are in `measurements/artifacts/` (see its SUMMARY.md). The final full run at `02b8fa7`: iOS 50/50, web 45/45, e2e 12/12.

Still not verified: phone, Photos/Files pickers (the screenshot uses a DEBUG-only launch argument instead of a picker), the share sheet and saving to Photos, per-look fidelity, halation and skin. No device was installed or signed, per the owner's direction.

## Regression pass (2026-10-30 ~01:30): open/clear races. DONE
All four owner hypotheses reproduced with deferred-callback tests, plus a fifth (a stale open reply was read as a file). All are fixed. Final run at `a7b0102`: iOS 51/51, web 49/49, e2e 12/12. Details at the end of `measurements/artifacts/SUMMARY.md`.

## After phase 4 (for the owner)
1. Pair the iPhone, then `xcrun devicectl device install app --device <id> <path to .app>`, and re-run the speed and memory numbers on the phone.
2. Shoot matched calibration pairs (Chromagraph vs iPhone ProRAW, tripod, colour checker); that is the next big fidelity step.
3. A 48 MP iPhone ProRAW for the memory test (none was obtained or tested here), and a Chromagraph shot with a light source in frame (halation) and a portrait (skin).
4. Per-stock tuning for 500T and Portra.
