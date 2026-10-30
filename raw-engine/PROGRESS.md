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

## Next: phase 2
1. Add a `raw` message handler to the WebView bridge: RAW import via PHPicker (`UTType.rawImage`) and Files, settings in, preview JPEG served from `app://local/preview/…`, and full-size export through the share sheet (HEIC/JPEG). See PLAN.md "UI and bridge".
2. Web UI: when the native bridge is present, accept DNG and route it to the bridge. Add WB temp/tint sliders. Leave the JPEG/PNG path unchanged.
3. Add looks 500T → 2383 and Portra 400 → 2383/Endura to `make_raw_lut.py` (add the ids to the LOOKS dict).
4. Measure bridge latency for slider drags. If it is over ~120 ms, use native controls.
