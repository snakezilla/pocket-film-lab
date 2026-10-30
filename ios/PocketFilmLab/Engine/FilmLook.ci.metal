#include <CoreImage/CoreImage.h>

extern "C" {
namespace coreimage {

// Scene-linear -> film look in one pass.
// 1. Log2 shaper: s = (log2(x / midGrey) - logMin) / (logMax - logMin), clamped 0..1.
//    Must match tools/make_raw_lut.py.
// 2. Trilinear lookup in a size^3 float cube stored as a 2D image, size wide and
//    size*size tall: row = g + b * size, column = r. Done here rather than with
//    CIColorCube because CIColorCube quantised the cube to 8 bits in testing,
//    which crushed the bottom five stops to 0.
float4 filmLook(sampler src, sampler cube, float size, float midGrey, float logMin, float logMax) {
    float4 s = src.sample(src.coord());
    float3 x = max(s.rgb, float3(1.0e-10));
    float3 v = clamp((log2(x / midGrey) - logMin) / (logMax - logMin), 0.0, 1.0);
    float3 p = v * (size - 1.0);
    float b0 = floor(p.b);
    float b1 = min(b0 + 1.0, size - 1.0);
    float fb = p.b - b0;
    float2 rg = float2(p.r + 0.5, p.g + 0.5);
    float4 c0 = cube.sample(cube.transform(float2(rg.x, rg.y + b0 * size)));
    float4 c1 = cube.sample(cube.transform(float2(rg.x, rg.y + b1 * size)));
    return float4(mix(c0.rgb, c1.rgb, fb), s.a);
}

}
}
