import { describe, expect, it } from 'vitest'
import { WB_TEMP_LIMITS, WB_TEMP_RANGE, WB_TINT_LIMITS, WB_TINT_RANGE, rangeIncluding, wbValue } from '../../src/rawmode'

describe('white balance slider range', () => {
  it('keeps the usual range for ordinary as-shot values', () => {
    expect(rangeIncluding(5201, WB_TEMP_RANGE, WB_TEMP_LIMITS)).toEqual(WB_TEMP_RANGE)
    expect(rangeIncluding(6.4, WB_TINT_RANGE, WB_TINT_LIMITS)).toEqual(WB_TINT_RANGE)
  })

  it('widens on the step grid so odd light is not clamped', () => {
    expect(rangeIncluding(1890, WB_TEMP_RANGE, WB_TEMP_LIMITS)).toEqual({ min: 1850, max: 12000, step: 50 })
    expect(rangeIncluding(14_020, WB_TEMP_RANGE, WB_TEMP_LIMITS)).toEqual({ min: 2000, max: 14_050, step: 50 })
    expect(rangeIncluding(-121.5, WB_TINT_RANGE, WB_TINT_LIMITS)).toEqual({ min: -122, max: 100, step: 1 })
  })

  it('ignores values that are not numbers', () => {
    expect(rangeIncluding(Number.NaN, WB_TEMP_RANGE, WB_TEMP_LIMITS)).toEqual(WB_TEMP_RANGE)
  })

  it('never widens past what the native side accepts', () => {
    expect(rangeIncluding(1790, WB_TEMP_RANGE, WB_TEMP_LIMITS).min).toBe(1800)
    expect(rangeIncluding(60_000, WB_TEMP_RANGE, WB_TEMP_LIMITS).max).toBe(50_000)
    expect(rangeIncluding(-170, WB_TINT_RANGE, WB_TINT_LIMITS).min).toBe(-150)
  })
})

describe('white balance value sent to the engine', () => {
  it('sends the exact as-shot value until the slider is moved', () => {
    expect(wbValue(5200, 5201.4, false)).toBe(5201.4)
    expect(wbValue(5600, 5201.4, true)).toBe(5600)
    expect(wbValue(5200, undefined, false)).toBe(5200)
    expect(wbValue(5200, Number.NaN, false)).toBe(5200)
  })
})
