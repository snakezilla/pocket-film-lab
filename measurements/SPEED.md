# Render speed (headless browsers on this Mac)

Generated 2026-10-29T23:20:36.073Z. Input: 4032x3024 JPEG -> preview 960x1280, export 1800x2400. All effects at defaults. Times are the worker render only (not decode/encode).

| Browser | Preview ms | Export ms (3 runs) |
|---|---|---|
| Chromium (Mac) | 352 | 1136, 1242, 1251 |
| Playwright WebKit (Mac) | 176 | 449, 564, 416 |

Not measured: physical iPhone Safari.
