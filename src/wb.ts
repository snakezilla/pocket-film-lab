/** White-balance slider ranges for RAW photos. Pure, so they are unit tested. */

export interface SliderRange {
  readonly min: number
  readonly max: number
  readonly step: number
}

/** The usual white-balance slider ranges. */
export const WB_TEMP_RANGE: SliderRange = { min: 2000, max: 12000, step: 50 }
export const WB_TINT_RANGE: SliderRange = { min: -100, max: 100, step: 1 }
/** What the native side accepts (RawBridge.settings clamps to these). */
export const WB_TEMP_LIMITS = { min: 1800, max: 50_000 } as const
export const WB_TINT_LIMITS = { min: -150, max: 150 } as const

/**
 * Slider bounds widened (on the step grid) to include `value`. A file shot under odd
 * light can have an as-shot white balance outside the usual range; a range input
 * would silently clamp it, so "as shot" would not really be as shot. Never widens past
 * `limits`, the values the native side accepts.
 */
export function rangeIncluding(
  value: number,
  range: SliderRange,
  limits: { readonly min: number; readonly max: number },
): SliderRange {
  if (!Number.isFinite(value)) return range
  return {
    min: Math.max(limits.min, Math.min(range.min, Math.floor(value / range.step) * range.step)),
    max: Math.min(limits.max, Math.max(range.max, Math.ceil(value / range.step) * range.step)),
    step: range.step,
  }
}
