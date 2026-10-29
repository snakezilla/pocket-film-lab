/**
 * Remove metadata segments from a JPEG: APP1 (EXIF/XMP), APP3-APP15
 * (Photoshop/IPTC etc.) and COM. Keeps APP0 (JFIF) and APP2 (ICC profile),
 * and everything from the first SOS on is copied unchanged.
 */
export function stripJpegMetadata(input: Uint8Array): Uint8Array {
  if (input[0] !== 0xff || input[1] !== 0xd8) throw new Error('Not a JPEG')
  const keep: Uint8Array[] = [input.subarray(0, 2)]
  let i = 2
  while (i + 4 <= input.length) {
    if (input[i] !== 0xff) throw new Error('Malformed JPEG segment')
    const marker = input[i + 1]
    if (marker === 0xda) {
      keep.push(input.subarray(i)) // start of scan: rest is image data
      return concat(keep)
    }
    const length = (input[i + 2] << 8) | input[i + 3]
    const end = i + 2 + length
    if (length < 2 || end > input.length) throw new Error('Malformed JPEG segment length')
    const isApp = marker >= 0xe0 && marker <= 0xef
    const drop = (isApp && marker !== 0xe0 && marker !== 0xe2) || marker === 0xfe
    if (!drop) keep.push(input.subarray(i, end))
    i = end
  }
  throw new Error('JPEG has no image data')
}

function concat(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0))
  let o = 0
  for (const p of parts) {
    out.set(p, o)
    o += p.length
  }
  return out
}
