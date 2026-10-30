import { describe, expect, it } from 'vitest'
import { DEFAULT_ADJUSTMENTS, formatTint, formatValue, toRawSettings, toRecipe, webLookFor } from '../../src/settings'

describe('one set of adjustments for both engines', () => {
  it('RAW keeps each photo’s as-shot white balance until a WB slider moves', () => {
    const raw = toRawSettings({ ...DEFAULT_ADJUSTMENTS, look: 'vision3-500t-2383' })
    expect(raw).not.toHaveProperty('wbTemp')
    expect(raw).not.toHaveProperty('wbTint')
    expect(raw).toMatchObject({ look: 'vision3-500t-2383', grain: 0.35, halation: 0.3 })
    expect(toRawSettings({ ...DEFAULT_ADJUSTMENTS, wbTemp: 4800, wbTint: -3 })).toMatchObject({ wbTemp: 4800, wbTint: -3 })
  })

  it('the web engine gets a recipe in its own range', () => {
    expect(toRecipe({ ...DEFAULT_ADJUSTMENTS, exposure: 3.5, halation: 0.6 })).toEqual({ strength: 1, exposure: 2, grain: 0.35, halo: 0.6 })
  })

  it('maps native looks to the closest web look', () => {
    expect(webLookFor('portra400-2383').id).toBe('portra')
    expect(webLookFor('vision3-250d-2383').id).toBe('print')
    expect(webLookFor('print').id).toBe('print')
    expect(webLookFor('portra').id).toBe('portra')
  })

  it('formats values for the sliders', () => {
    expect(formatValue('exposure', 0)).toBe('0.0 EV')
    expect(formatValue('exposure', 0.5)).toBe('+0.5 EV')
    expect(formatValue('exposure', -1.2)).toBe('−1.2 EV')
    expect(formatValue('grain', 0.35)).toBe('35%')
    expect(formatTint(-4)).toBe('−4')
    expect(formatTint(0)).toBe('0')
  })
})
