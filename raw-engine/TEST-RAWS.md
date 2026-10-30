# Test RAW files

All three come from raw.pixls.us, whose per-file licence column marks each as **CC0 1.0 (public domain dedication)**: https://creativecommons.org/publicdomain/zero/1.0/. They are checked on 2026-10-29 through `https://raw.pixls.us/json/getrepository.php?set=all`. `tools/fetch_test_raws.sh` downloads them into `ios/TestData/` (gitignored, so they are not committed) and checks their sha256.

| Local name | Camera / mode | Size | Licence | Source | sha256 |
|---|---|---|---|---|---|
| `iphone12pro-proraw.dng` | Apple iPhone 12 Pro, ProRAW (Linear Raw, 12-bit, Apple Embedded Color Profile) | 4032×3024 | CC0 | https://raw.pixls.us/getfile.php/4264/nice/Apple%20-%20iPhone%2012%20Pro%20-%208bit%20(4:3).DNG | e91e77a4…dfc2 |
| `iphonexs-bayer.dng` | Apple iPhone XS, Bayer DNG (ProCamera app, 16-bit) | 4032×3024 | CC0 | https://raw.pixls.us/getfile.php/3372/nice/Apple%20-%20iPhone%20XS%20-%2016bit%20(4:3).dng | 50bc64ee…05f6 |
| `leicaq2-47mp.dng` | Leica Q2, Bayer DNG, 14-bit | 8424×5632 (47.4 MP) | CC0 | https://raw.pixls.us/getfile.php/3204/nice/Leica%20-%20Q2%20-%2014bit%2014bit%20uncompressed%20(3:2).DNG | a71f9840…94ad |

raw.pixls.us has no 48 MP iPhone ProRAW sample. The Leica Q2 file stands in for the 48 MP memory test (same pixel count class, 87 MB file). A real 48 MP ProRAW should be tested once the owner shoots one.
