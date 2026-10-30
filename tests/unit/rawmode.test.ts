import { describe, expect, it } from 'vitest'
import { WB_TEMP_RANGE, WB_TINT_RANGE, rangeIncluding } from '../../src/rawmode'

describe('white balance slider range', () => {
  it('keeps the usual range for ordinary as-shot values', () => {
    expect(rangeIncluding(5201, WB_TEMP_RANGE)).toEqual(WB_TEMP_RANGE)
    expect(rangeIncluding(6.4, WB_TINT_RANGE)).toEqual(WB_TINT_RANGE)
  })

  it('widens on the step grid so odd light is not clamped', () => {
    expect(rangeIncluding(1890, WB_TEMP_RANGE)).toEqual({ min: 1850, max: 12000, step: 50 })
    expect(rangeIncluding(14_020, WB_TEMP_RANGE)).toEqual({ min: 2000, max: 14_050, step: 50 })
    expect(rangeIncluding(-121.5, WB_TINT_RANGE)).toEqual({ min: -122, max: 100, step: 1 })
  })

  it('ignores values that are not numbers', () => {
    expect(rangeIncluding(Number.NaN, WB_TEMP_RANGE)).toEqual(WB_TEMP_RANGE)
  })
})
