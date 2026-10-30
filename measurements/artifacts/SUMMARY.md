# Inspection artifacts (landing pass, 2026-10-30)

Source revision: **`02b8fa7`** (code). The renders come from that revision's own full test run (`ArtifactTests`, run `2026-10-30T043035Z`) and were copied here by `tools/make_artifacts.py`. Every image is made from the CC0 sample DNGs in `raw-engine/TEST-RAWS.md` (raw.pixls.us, iPhone XS Bayer and iPhone 12 Pro ProRAW) or from synthetic grey patches. There are no reference images, private photos or picker contents.

| File | What it is |
|---|---|
| `shipping-iphonexs-250d.jpg` | The real export path (`RawSession.export`, full size 4032×3024, quality 0.95) at the UI defaults: 250D look, strength 1, as-shot WB, grain 0.35, halation 0.3, softness 0, warmth 0 |
| `shipping-iphonexs-250d.heic` | Same render, HEIC |
| `shipping-iphonexs-250d-heic-preview.png` | The HEIC converted to PNG at 1600 px by `sips`, for viewers without HEIC |
| `grey-ramp-neutral-vs-warm.png` | Synthetic scene-linear greys at −8…+6 stops through each look, warmth 0 (the default) and warmth 1 |
| `look-sheet-iphone12pro-proraw-neutral-vs-warm.jpg` | ProRAW (portrait, Orientation 6): plain linear decode, then the 3 looks. Top row warmth 0, bottom row warmth 1 |
| `look-sheet-iphonexs-bayer-neutral-vs-warm.jpg` | The same for the Bayer DNG |
| `app-raw-preview-simulator.png` | The app on the iPhone 17 Pro simulator showing the native 250D render of the CC0 ProRAW, with the native controls |

How the screenshot was made: a DEBUG-only launch argument (`-PFLDebugOpenRaw <path>`) opens a file in place of the picker, and is compiled out of release builds. So **the Photos/Files pickers and the share sheet are not shown and are not tested**. Everything after the picker (adopt the copy → `startSession` → render → page) is the real code path.

Export metadata (ImageIO, and checked again with exiftool on these files):
- JPEG keys: `ColorModel, DPIHeight, DPIWidth, Depth, PixelHeight, PixelWidth, ProfileName, {Exif}, {JFIF}, {TIFF}`.
- HEIC keys: `ColorModel, Depth, HasAlpha, Headroom, Orientation, PixelHeight, PixelWidth, PrimaryImage, ProfileName, {Exif}, {TIFF}`.
- No GPS, make, model or capture date in either file.

What to look at: at warmth 0 the ramp is neutral at every stop, and warmth 1 turns only the patches above about +1 stop cream. The bottom 5–6 stops all sit within a few codes of black (the 2383 print toe plus the small black lift). That is a trait of the current look; it was not tuned in this pass.

## Final test run (after all fixes, revision `02b8fa7`)

Simulator iPhone 17 Pro (iOS 26.5 runtime), Xcode 27.0, iphonesimulator SDK 27.0, on this Mac.

| Suite | Command | Result |
|---|---|---|
| iOS | `cd ios && xcodebuild test -project PocketFilmLab.xcodeproj -scheme PocketFilmLab -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` | **50/50 passed**, 0 failed, 0 skipped |
| Web unit | `npm test` | **45/45 passed** (8 files) |
| Web e2e | `npm run test:e2e` (Chromium + WebKit iPhone viewport) | **12/12 passed** |

iOS tests by suite: ArtifactTests 1, BridgeTests 2, EdgeCaseTests 6, ExportPrivacyTests 5, FilmLookTests 6, LifecycleTests 8, LookSheetTests 1, RawPipelineTests 6, SecurityTests 6, SpeedMemoryTests 3, TextureTests 6.

Numbers from that run (simulator only): 47 MP preview path +33 MB, slider median 15 ms; 47 MP full-size HEIC export with grain and halation +256 MB, 4.9 s; bridge drag median 21 ms; export vs in-memory render mean |Δ| 0.42–0.76 codes.

**Not verified:** anything on a physical iPhone (speed, memory limit, Photos/Files pickers, share sheet, saving to Photos), the per-look fidelity against Chromagraph, and halation and skin against references.

## Regression pass (2026-10-30, revision `a7b0102`)

The owner's four race hypotheses were checked with deferred-callback tests. **All four reproduced** against `8db7214`, and a fifth turned up on the same path. All five are fixed:

1. `clear()` while a picker was open: a late pick opened a session, replied with file info and left a temp copy. Fix: clear answers the pending open as cancelled and bumps an open token. Late or old picker results are dropped and their copy removed, and the copy is no longer adopted on a background thread. Test: `LifecycleTests.testClearWhilePickerPendingIgnoresTheLatePick`.
2. JS `RawMode.open()` resolving after `close()` reactivated the page. Fix: a call-time epoch guard. Test: "close while an open is pending".
3. A new file opened while the old render was busy: the new file's queued render never ran. Fix: a stale result is dropped but the queue still drains. Test: "new file while the old render is busy".
4. A compare render finishing after `invalidateCompare()` was shown and cached. Fix: a compare epoch. Test: "a compare render that finishes after invalidateCompare is discarded".
5. A native `{stale: true}` open reply was read as a RAW file in `native.ts`. Fix: treated as no file. Test: "treats a stale open … as no file".

Each new test failed before its fix (4 web tests on the old `src/`, the native one before the RawBridge change) and passes after.

Final run at `a7b0102` (same simulator, Xcode and commands as above): iOS **51/51** (+1, LifecycleTests 9), web unit **49/49** (+4), e2e **12/12**. No failures, no skips. Web unit tests ran with `--maxWorkers=1` because two unrelated CPU-heavy jobs were running on this Mac: in a parallel run one existing pixel test hit vitest's 5 s timeout. No timeouts were changed. The rendered artifacts above are unchanged; this pass touched only open/clear/compare bookkeeping.
