# RAW engine plan

Goal: develop iPhone ProRAW / DNG into a film look with our own engine, getting as close as we legally can to the feel of Chromagraph Camera. We never extract, decompile or copy anything from the Chromagraph app, and we never call our output "Chromagraph". We tune by measuring public sample photos (`references/SOURCES.md`).

## Pipeline (native, Core Image, all on the GPU in tiles)

```
DNG / ProRAW file (read only)
  │  CIRAWFilter: as-shot WB (or user WB), baseline exposure + user exposure,
  │  boost 0, local tone map 0, contrast/sharpness/detail 0, metadata dropped
  ▼
scene-linear Rec.709, half float (CIContext working space: extended linear sRGB, RGBAh)
  │  [phase 3] halation: highlights > threshold, blurred, tinted red-orange, added in linear light
  ▼
FilmShaper.ci.metal: s = (log2(x/0.18) + 10) / 16.5, clamp 0..1  (0.000176 … 16.3 linear)
  ▼
CIColorCube 65³ float: negative stock → print (Kodak 2383) → display-linear Rec.709
  │  greys forced neutral on the axis, film colour response kept off-axis
  │  strength: dissolve with the plain linear decode
  ▼
  │  [phase 3] grain: per-pixel, sized and weighted by print density, in display space
  ▼
CIContext render → sRGB 8-bit: preview (long edge ≤ 1280–2048, decoded at reduced scale)
                              export (full size, JPEG/HEIC, no source metadata)
```

Why a log-shaped 3D cube rather than a Metal reimplementation of the film model: Spectral Film LUT (MIT) does the spectral negative → print simulation offline in Python; a 65³ float cube reproduces it to within interpolation error and costs one texture lookup per pixel. A 1D log shaper before the cube spreads the samples evenly per stop, which is what scene-linear input needs. The cube's output is display-linear so Core Image's colour management stays correct.

Why not LibRaw/WebAssembly: memory (README "RAW: feasibility"), and CIRAWFilter is Apple's own ProRAW decoder, which understands the ProRAW tags and profile.

## Files

| Path | Role |
|---|---|
| `tools/make_raw_lut.py` | Generates `ios/PocketFilmLab/Resources/LUTs/<look>.cube.bin` + `.json` (shaper, grey ramp) |
| `tools/fetch_test_raws.sh` | Downloads the CC0 test DNGs into `ios/TestData/` (gitignored), checks sha256 |
| `ios/PocketFilmLab/Engine/RawDecoder.swift` | CIRAWFilter setup, reduced-scale decode, as-shot WB |
| `ios/PocketFilmLab/Engine/FilmShaper.ci.metal`, `FilmShaperKernel.swift` | Log shaper kernel |
| `ios/PocketFilmLab/Engine/FilmLUT.swift` | Loads and validates the cube |
| `ios/PocketFilmLab/Engine/FilmEngine.swift` | Settings → CIImage graph, preview vs full size |
| `ios/PocketFilmLab/Engine/FilmExporter.swift` | JPEG/HEIC writer, sRGB, metadata-free |
| `ios/PocketFilmLabTests/` | Simulator tests on synthetic patches and the sample DNGs |

## UI and bridge (phase 2)

Keep the web UI as the control surface. The WKWebView already has a native `share` bridge; add a `raw` message handler:

- JS `pickRaw()` → native PHPicker (`UTType.rawImage`, ProRAW is a DNG) or document picker. Native keeps the file URL, the web UI never sees the RAW bytes.
- JS `setSettings({look, strength, exposure, wbTemp, wbTint, grain, halation})` → native renders a preview (long edge = screen pixels, ≤ 2048) and returns it to the page as a JPEG blob URL via the `app://` scheme handler (`app://local/preview/<n>.jpg`), so no base64 round trip. Debounce on the native side; drop stale renders.
- Hold-to-compare: native also serves the decode with strength 0 (or the embedded preview) once per file.
- JS `exportRaw({format})` → native renders full size, writes to a temp file, presents the share sheet (Save Image puts it in Photos). Temp file removed after.
- JPEG/PNG keep the existing web path untouched.

If the bridge round trip is too slow for slider drags (> ~120 ms), fall back to native SwiftUI controls over a native `MTKView`/`UIImageView` preview.

## Phases

1. **(this)** Architecture, CIRAWFilter decode, one look (Vision3 250D → 2383), simulator tests incl. exported-file pixel check and 47 MP memory, `references/SOURCES.md`.
2. Bridge + web UI driving the native engine; PHPicker/Files RAW import; preview loop; HEIC/JPEG share export; looks 500T → 2383 and Portra 400 → 2383 (or Endura, decided by measurement); white balance controls.
3. Texture: density-weighted grain (multi-scale, per-layer), halation (red-orange, threshold + wide blur in linear light), optional softness and gate weave (off by default). Measure the reference traits into `references/LOOK-TRAITS.md`.
4. Tune the default look against LOOK-TRAITS (black lift, roll-off, saturation vs brightness, hue shifts, grain), mark measured vs judged numbers, speed/memory pass, device install if a phone is paired.

## Risks

- Simulator GPU/memory differ from a phone. All memory numbers are simulator-only until a device is paired.
- Public Chromagraph samples are recompressed web images with no grey cards: tone and hue are estimates, grain is weak evidence.
- ProRAW decodes in CIRAWFilter may still include Apple's semantic processing baked into the linear data; we can't remove that, only avoid adding more.
