import { describe, expect, it } from 'vitest'
import { stripJpegMetadata } from '../../src/jpeg'

const seg = (marker: number, body: number[]) => [0xff, marker, (body.length + 2) >> 8, (body.length + 2) & 0xff, ...body]

describe('stripJpegMetadata', () => {
  it('drops APP1/APP13/COM, keeps JFIF, ICC, tables and scan data', () => {
    const jpeg = Uint8Array.from([
      0xff, 0xd8,
      ...seg(0xe0, [74, 70, 73, 70, 0]), // JFIF
      ...seg(0xe1, [69, 120, 105, 102, 0, 0, 1, 2]), // Exif
      ...seg(0xe2, [73, 67, 67]), // ICC
      ...seg(0xed, [80, 104, 111]), // Photoshop/IPTC
      ...seg(0xfe, [104, 105]), // comment
      ...seg(0xdb, [0, 1, 2]), // quant table
      0xff, 0xda, 0, 2, 9, 9, 9, 0xff, 0xd9,
    ])
    const out = Array.from(stripJpegMetadata(jpeg))
    expect(out).toEqual([
      0xff, 0xd8,
      ...seg(0xe0, [74, 70, 73, 70, 0]),
      ...seg(0xe2, [73, 67, 67]),
      ...seg(0xdb, [0, 1, 2]),
      0xff, 0xda, 0, 2, 9, 9, 9, 0xff, 0xd9,
    ])
  })
  it('rejects non-JPEG and truncated input', () => {
    expect(() => stripJpegMetadata(Uint8Array.from([1, 2, 3]))).toThrow()
    expect(() => stripJpegMetadata(Uint8Array.from([0xff, 0xd8, 0xff, 0xe1, 0x10, 0x00]))).toThrow()
  })
})
