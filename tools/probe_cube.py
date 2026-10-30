"""Probe patches through two RAW film cubes (old vs new). Usage:
  git show HEAD~1:ios/PocketFilmLab/Resources/LUTs/vision3-250d-2383.cube.bin > /tmp/old.bin
  tools/.venv/bin/python tools/probe_cube.py /tmp/old.bin ios/PocketFilmLab/Resources/LUTs/vision3-250d-2383.cube.bin
"""
import sys, numpy as np, colour
N=65; MID=0.18; LMIN=-10; LMAX=6.5
def load(p): return np.fromfile(p, dtype=np.float32).reshape(N, N, N, 4)[..., :3]  # [b][g][r]
def look(cube, x):
    v = np.clip((np.log2(np.maximum(x, 1e-10)/MID) - LMIN)/(LMAX-LMIN), 0, 1) * (N-1)
    i0 = np.floor(v).astype(int); i1 = np.minimum(i0+1, N-1); f = v - i0
    out = 0
    for br in (0,1):
        for bg in (0,1):
            for bb in (0,1):
                ir = i1[0] if br else i0[0]; ig = i1[1] if bg else i0[1]; ib = i1[2] if bb else i0[2]
                w = (f[0] if br else 1-f[0])*(f[1] if bg else 1-f[1])*(f[2] if bb else 1-f[2])
                out = out + w*cube[ib, ig, ir]
    return out
old, new = load(sys.argv[1]), load(sys.argv[2])
print("patch (scene-linear)            | old L* C* h      | new L* C* h      | C* ratio")
for name, rgb in [("mid blue sky", (0.15,0.22,0.45)), ("light blue sky", (0.22,0.32,0.62)), ("hazy blue", (0.3,0.4,0.65)), ("pale daylight sky", (0.42,0.55,0.80)), ("bright pale sky", (0.9,1.1,1.5)), ("deep blue sky", (0.05,0.09,0.20)), ("dusk blue", (0.02,0.03,0.08)), ("skin", (0.40,0.25,0.17)), ("foliage", (0.06,0.10,0.03))]:
    res=[]
    for c in (old,new):
        y = look(c, np.array(rgb))
        lab = colour.XYZ_to_Lab(colour.RGB_to_XYZ(y, colour.RGB_COLOURSPACES['ITU-R BT.709'], apply_cctf_decoding=False))
        res.append((lab[0], np.hypot(lab[1],lab[2]), np.degrees(np.arctan2(lab[2],lab[1]))%360))
    print(f"{name:18s} {str(rgb):16s}| {res[0][0]:5.1f} {res[0][1]:5.1f} {res[0][2]:4.0f} | {res[1][0]:5.1f} {res[1][1]:5.1f} {res[1][2]:4.0f} | {res[1][1]/max(res[0][1],1e-6):.2f}")
