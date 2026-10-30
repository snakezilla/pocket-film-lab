# RAW engine: final report (phases 1–4 + landing pass)

Measured on the iPhone 17 Pro **simulator** (iOS 26.5 runtime, Xcode 27.0 / SDK 27.0, Mac GPU). **No phone was used in any phase**: nothing here is verified on an iPhone.

**Final run, after all landing-pass fixes, at revision `02b8fa7`:** iOS **50/50**, web `npm test` **45/45**, `npm run test:e2e` **12/12**, with no failures or skips. **Regression pass at `a7b0102`** (open/clear/compare races, all reproduced, then fixed): iOS **51/51**, web **49/49**, e2e **12/12**. See the end of `artifacts/SUMMARY.md`. Commands, test names and the artifacts are in [`artifacts/SUMMARY.md`](artifacts/SUMMARY.md).

## Landing pass (2026-10-30)

- **WebView boundary** (`WebSecurity.swift`, `SecurityTests` 6):
  - Both bridges answer only the bundled page's main frame (app://local). Tested negatively: another origin, and a same-origin iframe, both get "Untrusted sender".
  - Navigation: app://local loads. A tapped https link opens in Safari. http, file, javascript, data, other app:// hosts and scripted redirects are refused.
  - The scheme handler serves only `local`, and only files inside `dist/`. `..`, encoded `..` and symlinks out of the folder are refused.
  - The Web Inspector is enabled in DEBUG builds only.
- **Lifecycle** (`LifecycleTests` 8 + 4 web unit tests):
  - New `clear` command. Close and new-file both bump an epoch. A render or export that finishes for an older file is dropped (`stale`) and never shown or shared; a stale export is deleted.
  - The temp copy is removed on the render queue after the work already queued for it. Previews are dropped. LUT loading moved onto the render queue, so the engine cache is touched from one queue only.
  - Tested: slow render then clear, slow render then new file, rapid sliders, export after clear, a cancelled picker (the current file stays open), a failed import, and an image extent that doesn't start at 0,0.
- **JPEG/PNG share**: the old share bridge now shares the page's encoded file (same bytes, safe name, extension taken from the bytes), not a re-encoded UIImage.
- **Neutral baseline**:
  - The shipped cubes are neutral on the grey axis again (`WARM_IN_CUBE = False`). The cream highlights became an optional `warmth` setting, default 0, with a Warm highlights slider.
  - Strict neutral grey tests are back at every stop, plus a test that warmth only touches highlights.
  - The pale-sky trim is off.
- **Corrections**:
  - Removed the claim that the simulator footprint proves the export fits a 6 GB phone.
  - "No public 48 MP ProRAW" became "none obtained or tested here".
  - Phase 2's iOS count is 18/18 full plus a 6/6 subset, not 19/19.


## Fidelity summary (honest)

What the engine is: Apple's `CIRAWFilter` decodes DNG/ProRAW to scene-linear light with every Apple look switched off. A 65³ float cube then simulates a Kodak negative (Vision3 250D, Vision3 500T or Portra 400) printed on Kodak 2383, generated from Spectral Film LUT (MIT). A small grade on top was tuned by measuring public Chromagraph sample photos. Grain and halation are our own. It is not Chromagraph and copies nothing from it.

How close it is to the Chromagraph feel, trait by trait. "Measured" means compared with numbers from the reference photos (`references/LOOK-TRAITS.md`). "Judged" means set by eye.

| Trait | Status | Evidence |
|---|---|---|
| Lifted, soft blacks (floor ~code 5) | close | measured: floor 5–6 vs reference median ~5 |
| Long highlight shoulder (+6 stops still under white) | close | measured: +6 stops = 248/245/226; references 209–251 without sun |
| Warm, cream near-whites | **optional, off by default** | the default print is neutral. The `warmth` setting at 1 gives b\* about +9 from +3 stops, close to the references (+8.3 to +10.6). Those reference numbers are rendered scene distributions, not a calibrated transform |
| Saturation falling with brightness | roughly | measured: high/mid chroma 0.53–0.72 vs reference 0.47–0.50, a bit too saturated in the brights |
| Pale skies lose their blue | not applied | a phase-4 trim was turned back off in the landing pass (owner direction: scene quantiles are not a calibrated transform) |
| Warm mid-tones keep or gain colour | partly | the film model does this; not tuned separately |
| Shadow density (toe) | roughly | direction measured, amount judged (toe lift ×1.12) |
| Grain: fine, strongest in mid-tones, none in white | close | measured std 4.0 / 2.6 / 2.1 codes at mid / code 197 / code 70; reference ~4 / 3 / 1.5 |
| Halation: subtle red-orange glow | unverified | judged only; no reference has clipped light sources to measure |
| Skin hue | unverified | judged "natural warm tan"; no reference has a skin patch big and clean enough to measure |

The biggest limits on fidelity:
1. **No matched test.** No reference photo has a grey card or colour checker, all are recompressed web images, and only two before/after pairs exist (one small, one not pixel-aligned). Every comparison is about distributions, not patches. A real calibration needs the owner to shoot the same scene in Chromagraph and in the iPhone Camera (ProRAW) from a tripod, ideally with a colour checker.
2. **The base differs.** Chromagraph's own decode and its tone mapping of iPhone ProRAW are unknown. Ours uses Apple's decoder with its rendering off. ProRAW files may still carry some of Apple's processing in the linear data; we can't remove that.
3. **One look was tuned.** The grade is shared by all three stocks, so 500T and Portra inherit the 250D tuning. Only 250D was compared with the references.

## Phase 4: edge cases

`ios/PocketFilmLabTests/EdgeCaseTests.swift` (new):

| Case | Result | Test |
|---|---|---|
| ProRAW stored landscape with Orientation 6 | decode, preview and full-size export all come out portrait (4032×3024 → 3024×4032); export orientation tag 1 | `testRotatedProRAWIsUprightEverywhere` |
| Bayer DNG with Orientation 8 (copy with only that tag changed) | equals the unrotated decode turned 90° counter-clockwise: mean \|Δ\| **0.00 codes** after the film look. The fast WB preview keeps the rotation | `testOrientationTagRotatesPixels` |
| White balance at the bridge's corners (1800 K and 50 000 K, tint ±150), ProRAW and Bayer, with grain and halation on | every pixel finite and in range, through both the true decode and the fitted WB matrix. The colour moves the right way (B/R 0.11–0.53 at 50 000 K, 3.5 to 1×10⁵ at 1800 K) | `testExtremeWhiteBalanceStaysFiniteAndInRange` |
| Bad WB values from the page (negative, 1e9, a string, NaN) | clamped to 1800–50 000 K and tint ±150, or as-shot | `testOddWhiteBalanceValuesFromThePageAreClamped` |
| As-shot WB outside the web sliders (2000–12 000 K, tint ±100) | **bug fixed**: the range input used to clamp it (and snap it to the 50 K step), so "as shot" was not really as shot. The sliders now widen to include the file's value, up to the native limits, and the exact as-shot value is sent until a slider is moved | `tests/unit/rawmode.test.ts` |
| Bayer vs ProRAW linearity | +1 EV gives ×2.0 on both (median over 28 657 and 25 849 px) | `testBayerAndProRAWAreBothSceneLinear` |
| Apple rendering options | ProRAW supports local tone map, contrast, sharpness and detail; the Bayer DNG has no local tone map. All are held at 0 where supported | `testRenderingOptionsAreOffOnBothFileTypes` |

Finding: at 1800 K with tint −150 the red channel goes to about zero and some values go negative (out of gamut). The film kernel clamps them before the log shaper, so the output stays finite. That corner is extreme; the UI sliders don't reach it unless the file's own as-shot value is out there.

## Phase 4: other changes

- **WB fitter pre-warm.** After the first preview, the bridge builds the white-balance fitter on the render queue. First WB change: **231–353 ms cold → 78–93 ms pre-warmed** (`SpeedMemoryTests.testPrewarmedFirstWhiteBalanceChange`).
- **Softness** (optional, off by default, scene-linear before halation): a blur with sigma 0.07% of the long edge, mixed in at up to 60%. On 4 px detail it lowers contrast to 40% at the slider maximum, with mean and neutrality unchanged (`TextureTests.testSoftnessIsGentleAndOffByDefault`). Size and mix are judged by eye. **Gate weave was not built**: on a single still it reduces to a sub-pixel shift you cannot see.
- **Superseded in the landing pass: the trim is off (`BLUE_HIGH_CHROMA` 1.0).** For the record, the phase-4 version was **Pale-sky chroma** (`BLUE_HIGH_CHROMA` 0.7 in `tools/make_raw_lut.py`, Lab hue 200–290°, ramping in from display Y 0.2 to 0.45). Probe through the 250D cube, old → new (`tools/probe_cube.py`):

  | Patch (scene-linear) | L\* | C\* before → after |
  |---|---|---|
  | deep blue sky (0.05, 0.09, 0.20) | 31.6 | 19.8 → 19.8 |
  | mid blue sky (0.15, 0.22, 0.45) | 56.6 | 14.6 → 14.2 |
  | light blue sky (0.22, 0.32, 0.62) | 65.3 | 11.0 → 9.1 |
  | hazy blue (0.30, 0.40, 0.65) | 69.8 | 6.7 → 4.8 |
  | skin, foliage | — | unchanged |

  Greys are unchanged. On the ProRAW lake frame (sky at L\* 56) the sky goes from C\* 10.1 to 9.9, as intended for a mid-dark sky. The amount is the gentler of the two measured pairs; the ramp is judged.

## Final numbers (phase 4 run)

| What | Result |
|---|---|
| 47 MP open / first preview / slider median / WB change / preview peak | 104 ms / 477 ms / 14 ms / 381 ms / +34 MB |
| 47 MP full-size HEIC export, plain / with grain and halation | +158 MB, 3.5 s / +208 MB, 4.9 s |
| Bridge round trip (page → render → JPEG in page), drag median | 21 ms (native 14 ms) |
| WB change via matrix vs re-decode | 94–115 ms vs 294–349 ms; mean error 0.01–0.69 codes |
| Export vs in-memory render, mean \|Δ\| | 0.42–0.77 codes |
| Export metadata | allow-listed keys only; no make, GPS, MakerApple or capture date |

## Remaining gaps (for the owner)

1. **Device.** Install and run on an iPhone: `devicectl` listed "AE's iPhone 13 Pro" as unavailable in every phase. Speed, memory (the 47 MP export peak of ~+210 MB is the number to watch), the Photos picker, the share sheet and HEIC saving to Photos are unverified on a phone.
2. **A real 48 MP iPhone ProRAW.** None was obtained or tested here. The Leica Q2 47 MP Bayer DNG is only a size proxy.
3. **Matched calibration shots** (see the fidelity limits above): the single most useful next step for fidelity.
4. **Halation and skin** need reference evidence: a Chromagraph shot with a bare bulb or the sun in frame, and a portrait.
5. **Per-stock tuning.** 500T and Portra share the 250D grade.
6. **Picker click-through.** The PHPicker and Files UI can't be automated here; a human has to try Open RAW and RAW from Files once.

---

# Phase 3 detail (kept for the record)

Measured on 2026-10-29 on the iPhone 17 Pro **simulator** (iOS 27 SDK, Mac GPU). No phone was available, so none of these numbers are from a phone; expect a phone to be slower. Re-run with:

```
cd ios && xcodebuild test -project PocketFilmLab.xcodeproj -scheme PocketFilmLab -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Each number below is printed by a test (`MEMORY`, `LARGE`, `WB`, `BRIDGE`, `EXPORT`, `PRIVACY` lines). The test files are the CC0 DNGs in `raw-engine/TEST-RAWS.md`. No 48 MP iPhone ProRAW was obtained or tested here *(corrected 2026-10-30: an earlier version said none is public, which was not established by a scoped search)*. The 47 MP Leica Q2 DNG (8424×5632, 8368×5584 after crop) is only a size proxy: it is a Bayer DNG, not ProRAW.

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
- Full-size export peaks at +160 to +220 MB. The 8-bit output bitmap alone is 187 MB (8368×5584×4), so Core Image is already tiling everything else. *(Corrected 2026-10-30.)* This does **not** show the export fits a phone's app memory limit: the limit (jetsam) depends on the device, the OS and what else is in memory, and there has been no phone run. It is a simulator footprint only. The phase-2 and phase-3 numbers come from different runs on the same machine. The spread between runs is about ±40 MB and ±1 s, so read the change as "no regression", not as a gain.

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

*Superseded in the landing pass (2026-10-30): the shipped cubes are neutral on the grey axis again. The warm column below is what the optional `warmth` setting at 1 gives.*

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
