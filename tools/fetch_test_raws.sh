#!/usr/bin/env bash
# Downloads the CC0 test DNGs from raw.pixls.us into ios/TestData/ (gitignored)
# and checks their sha256. Licences and sources: raw-engine/TEST-RAWS.md
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/ios/TestData"
mkdir -p "$DIR"
fetch() {
  local name="$1" id="$2" path="$3" sha="$4"
  local target="$DIR/$name"
  if [ ! -f "$target" ]; then
    curl -fsSL -o "$target.part" "https://raw.pixls.us/getfile.php/$id/nice/$path"
    mv "$target.part" "$target"
  fi
  echo "$sha  $target" | shasum -a 256 -c -
}
fetch iphone12pro-proraw.dng 4264 "Apple%20-%20iPhone%2012%20Pro%20-%208bit%20(4:3).DNG" e91e77a4533ed7cce551d83330676ea5c47dd5e55fb38adda7819366afdbdfc2
fetch iphonexs-bayer.dng 3372 "Apple%20-%20iPhone%20XS%20-%2016bit%20(4:3).dng" 50bc64ee8cfbbfb6c0531e29ab428ff985506a16fe2d1d2e74656f21b54505f6
fetch leicaq2-47mp.dng 3204 "Leica%20-%20Q2%20-%2014bit%2014bit%20uncompressed%20(3:2).DNG" a71f98405e9e9c1e4ac0f2d2e6c52d65daae3234fc0a9f6eed2a84ee4ce794ad
