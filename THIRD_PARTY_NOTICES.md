# Third-party notices

## Spectral Film LUT 0.18.0 (used offline to generate public/luts/*.bin)

https://github.com/JanLohse/spectral_film_lut

```
MIT License

Copyright (c) 2026 Jan Lohse

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The LUTs are derived output of that software, which uses film datasheet data digitised by its author. Film stock names are used only to describe the source data; this app is not affiliated with Kodak.

## Tetrahedral interpolation

src/engine/lut.ts implements standard tetrahedral interpolation, written for this project. The scheme matches the MIT reference https://github.com/calvinsilly/Tetrahedral-Interpolation (no code copied).

## Raw2Film

https://github.com/JanLohse/raw2film (MIT). Studied for pipeline order and halation colour weights (red 1.0 / green 0.4 / blue 0). No code copied.
