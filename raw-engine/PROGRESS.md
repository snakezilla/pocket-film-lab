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
- Tests: iOS 19/19 on the iPhone 17 Pro simulator.
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

## Next: phase 3
1. Tuning pass 2: decide on 1 and 2 above, compare the LookSheet renders with the reference images side by side, and make halation a little redder (R−B ≈ 2×(R−G); now 1.5).
2. Optional softness and gate weave (off by default), as the brief asks.
3. Preview WB as a matrix on the cached decode, if WB drags are slow.
4. A device install if a phone is paired. Then measure bridge latency and memory on the phone.
