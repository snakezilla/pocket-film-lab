# Test run evidence

Run 2026-10-30T01:31:02Z on macOS 26.7, Node v22.15.0. Headless Chromium and Playwright WebKit (iPhone 13 viewport) on this Mac. NOT a physical iPhone.

## npm run build
```
✓ 14 modules transformed.
rendering chunks...
computing gzip size...
dist/index.html                  3.82 kB │ gzip: 1.49 kB
dist/assets/worker-DNsRqdzH.js   4.63 kB
dist/assets/index-DFOx_MJw.css   2.14 kB │ gzip: 0.94 kB
dist/assets/index-DNx3Qi6r.js   10.96 kB │ gzip: 4.61 kB
✓ built in 111ms
```

## npm test
```
 RUN  v3.2.7 /Users/ahsan/Projects/pocket-film-lab

 ✓ tests/unit/jpeg.test.ts (2 tests) 4ms
 ✓ tests/unit/files.test.ts (7 tests) 7ms
 ✓ tests/unit/lut.test.ts (9 tests) 8ms
 ✓ tests/unit/color.test.ts (4 tests) 23ms
 ✓ tests/unit/blur.test.ts (2 tests) 26ms
 ✓ tests/unit/film.test.ts (9 tests) 123ms

 Test Files  6 passed (6)
      Tests  33 passed (33)
   Start at  21:31:04
   Duration  532ms (transform 291ms, setup 0ms, collect 456ms, tests 191ms, environment 1ms, prepare 450ms)

```

## npm run test:e2e
```

  ✓   1 [chromium] › tests/e2e/app.spec.ts:62:1 › opens a rotated JPEG, renders film pixels, compares, exports a clean JPEG (3.5s)
  ✓   2 [chromium] › tests/e2e/app.spec.ts:128:1 › re-importing the same file works and replaces the photo (520ms)
  ✓   3 [chromium] › tests/e2e/app.spec.ts:140:1 › export can be cancelled (314ms)
  ✓   4 [chromium] › tests/e2e/app.spec.ts:154:1 › rejects RAW, broken and unsupported files with clear errors (87ms)
  ✓   5 [chromium] › tests/e2e/app.spec.ts:165:1 › HEIC: decodes or fails with a HEIC-specific message (79ms)
  ✓   6 [chromium] › tests/e2e/app.spec.ts:173:1 › share path hands a JPEG file to navigator.share (1.5s)

  ✓   7 [webkit-iphone] › tests/e2e/app.spec.ts:62:1 › opens a rotated JPEG, renders film pixels, compares, exports a clean JPEG (3.2s)
  ✓   8 [webkit-iphone] › tests/e2e/app.spec.ts:128:1 › re-importing the same file works and replaces the photo (806ms)
  ✓   9 [webkit-iphone] › tests/e2e/app.spec.ts:140:1 › export can be cancelled (486ms)
  ✓  10 [webkit-iphone] › tests/e2e/app.spec.ts:154:1 › rejects RAW, broken and unsupported files with clear errors (205ms)
  ✓  11 [webkit-iphone] › tests/e2e/app.spec.ts:165:1 › HEIC: decodes or fails with a HEIC-specific message (289ms)
  ✓  12 [webkit-iphone] › tests/e2e/app.spec.ts:173:1 › share path hands a JPEG file to navigator.share (466ms)

  12 passed (13.7s)
```
