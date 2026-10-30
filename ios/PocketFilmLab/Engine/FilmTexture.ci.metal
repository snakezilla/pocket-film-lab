#include <CoreImage/CoreImage.h>

extern "C" {
namespace coreimage {

// Halation source, in scene-linear light. Only the part of each pixel above
// `threshold` (soft knee one stop wide) feeds the glow, so mid tones stay clean.
float4 halationSource(sample_t s, float threshold) {
    float y = dot(s.rgb, float3(0.2126, 0.7152, 0.0722));
    float over = max(y - threshold, 0.0);
    float knee = over * over / (over + threshold);
    float k = y > 0.0 ? knee / y : 0.0;
    return float4(s.rgb * k, 1.0);
}

// Adds the blurred glow back in scene-linear light, tinted red-orange: light that
// went through the emulsion, bounced off the base and re-exposed mostly the red
// (bottom) layer, some green, almost no blue.
float4 halationAdd(sample_t s, sample_t glow, float amount, float3 tint) {
    float g = dot(glow.rgb, float3(0.2126, 0.7152, 0.0722));
    return float4(s.rgb + tint * (g * amount), s.a);
}

// Grain in print density. y is display-linear (the print as seen); D = -log10(y).
// Grain strength follows a bell over density: none on paper white (no dye),
// a peak a little above mid grey (D ~ 0.8) and less in the deep blacks and highlights.
// n is zero-mean noise per channel: shared luminance noise plus some per-layer noise.
float4 filmGrain(sample_t s, sample_t fine, sample_t coarse, float amount, float chroma) {
    float3 y = max(s.rgb, float3(1.0e-4));
    float3 d = -log10(y);
    float3 b = d / 0.8;
    // Squared gamma bell: drops faster toward white than a plain one (LOOK-TRAITS: ~3 codes
    // above code 200 vs ~4 at midtones, fading to 0 in crushed blacks).
    float3 bell = b * b * exp(2.0 * (1.0 - b));
    float3 nf = fine.rgb - 0.5;
    float3 nc = coarse.rgb - 0.5;
    float monoF = fine.a - 0.5;
    float monoC = coarse.a - 0.5;
    float3 n = mix(float3(monoF), nf, chroma) * 0.7 + mix(float3(monoC), nc, chroma) * 0.5;
    float3 dn = d + amount * bell * n;
    return float4(pow(float3(10.0), -dn), s.a);
}

}
}
