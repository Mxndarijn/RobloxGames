# Gl1tch (Secret): a CORRUPTED slime. Its body is sliced into horizontal bands shoved sideways like
# a broken video frame, with cyan/magenta RGB-split fringes peeking out of the slices, one band
# colour-inverted, the tip dropped to a flat-shaded low LOD, a black/magenta "missing texture"
# checker on its side and voxel cubes breaking off the top. The face is sliced with the body and
# doubled in cyan + magenta; one eye is a loading spinner, the other a pixel eye.
from models._slimepool import *

LIME, LIME_D, LIME_L = hexc("b6ff2a"), hexc("5fc61a"), hexc("eaffb0")
CYAN, MAGENTA = hexc("19f0ff"), hexc("ff1fd2")
INV, INV_D = hexc("7a2bff"), hexc("4a14b8")   # the colour-inverted band
VOID = rgb(14, 10, 22)

PROFILE = [(0, 1.15), (0.15, 1.42), (0.5, 1.55), (1.1, 1.48), (1.8, 1.18), (2.4, 0.72), (2.8, 0.22), (2.92, 0)]
_m = Body(PROFILE, register_surface=False, name="Master", segs=8)
radius = _m.radius
H = _m.H
bpy.data.objects.remove(_m.obj)

#        z0    z1    shift  kind
SLICES = [(0.0, 0.55, 0.0, "lime"),
          (0.58, 0.82, -0.26, "inv"),
          (0.85, 1.3, 0.1, "lime"),
          (1.33, 1.62, 0.32, "lime"),
          (1.65, 2.0, -0.14, "lime"),
          (2.03, 2.26, 0.2, "lime"),
          (2.29, H, -0.26, "lod")]
FRINGE = {2: 0.87, 3: 0.89, 5: 0.86, 0: 0.9}


TINT = {2: (hexc("fff23a"), 0.35), 4: (hexc("3affb0"), 0.3)}  # per-band colour drift


def lime_paint(a, z, p):
    c = mix(LIME_D, LIME, smoothstep(0.0, 1.0, z))
    return mix(c, LIME_L, 0.6 * smoothstep(1.6, 2.6, z))


def inv_paint(a, z, p):
    return mix(INV_D, INV, 0.5 + 0.5 * math.sin(a * 3))


def make_slice(name, z0, z1, shift, paint=None, color=None, segs=32, scale=1.0, tip=False, register_it=True, shade=1.0,
               sectors=None):
    n = max(2, int((z1 - z0) / 0.1) + 1)
    prof = [(z0 + (z1 - z0) * k / (n - 1), radius(z0 + (z1 - z0) * k / (n - 1)) * scale) for k in range(n)]
    if tip:
        prof[-1] = (z1, 0.0)
    bd = Body(prof, paint=paint, color=color or LIME, segs=segs, sub=1, name=name, register_surface=False,
              shade=shade, gloss=0.5, sectors=sectors)
    bd.obj.data.transform(Matrix.Translation((shift, 0, 0)))
    if register_it:
        register(bd.obj, name)
    return bd.obj


parts = []
names = []
for i, (z0, z1, sh, kind) in enumerate(SLICES):
    nm = "Body" if i == 0 else f"Slice{i}"
    names.append(nm)
    if kind == "lod":
        o = make_slice(nm, z0, z1, sh, paint=lime_paint, segs=7, tip=True)
        keep(o, False)
    elif kind == "inv":
        o = make_slice(nm, z0, z1, sh, paint=inv_paint)
    else:
        # RGB split: the slice's far-left edge bleeds cyan, its far-right edge magenta (a shifted
        # 3D copy showed over half the slice from every angle, so the split is painted per face)
        lim = FRINGE.get(i)
        sec = (lambda a, z, lim=lim: CYAN if math.sin(a) < -lim else (MAGENTA if math.sin(a) > lim else None)) if lim else None
        tint = TINT.get(i)
        pf = (lambda a, z, p, t=tint: mix(lime_paint(a, z, p), t[0], t[1])) if tint else lime_paint
        o = make_slice(nm, z0, z1, sh, paint=pf, sectors=sec)
    parts.append(o)


# ---------------------------------------------------------------- sliced face decals
def clip_v(poly, lo, hi):
    def clip(pts, keep_fn, inter):
        out = []
        for k in range(len(pts)):
            a, b = pts[k - 1], pts[k]
            ia, ib = keep_fn(a), keep_fn(b)
            if ib:
                if not ia:
                    out.append(inter(a, b))
                out.append(b)
            elif ia:
                out.append(inter(a, b))
        return out

    def at(v):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (v - a[1]) / (b[1] - a[1]), v)
    p = clip(poly, lambda q: q[1] >= lo, at(lo))
    if len(p) < 3:
        return []
    p = clip(p, lambda q: q[1] <= hi, at(hi))
    return p if len(p) >= 3 else []


def gdecal(name, poly, color, off=0.015, th=0.02, du=0.0):
    """front decal cut along the slices; each piece moves with its slice."""
    out = []
    for i, (z0, z1, sh, kind) in enumerate(SLICES):
        piece = clip_v(poly, z0 + 0.015, z1 - 0.015)
        if not piece:
            continue
        piece = [(u + sh + du, v) for u, v in piece]
        out.append(decal(f"{name}_{i}", piece, color, FRONT, off=off, th=th, on=[names[i]], step=0.1))
    return out


def pixel_poly(cells, cu, cv, px):
    """union outline of a set of grid cells is fiddly; return one square per cell instead."""
    return [rect(cu + x * px, cv + y * px, px * 1.02, px * 1.02) for x, y in cells]


EV, EU, MV = 1.6, 0.5, 1.08
face = []
# RGB ghost copies of the whole face first (under the ink)
for c, du, off in ((CYAN, -0.075, 0.012), (MAGENTA, 0.075, 0.013)):
    face += gdecal(f"GhostEyeL{c[0]:.1f}", oval(-EU, EV, 0.6, 0.6, n=16), c, off=off, th=0.006, du=du)
    face += gdecal(f"GhostEyeR{c[0]:.1f}", rect(EU, EV, 0.5, 0.5), c, off=off, th=0.006, du=du)
    face += gdecal(f"GhostMouth{c[0]:.1f}", half_oval(0, MV + 0.1, 0.7, 0.3, n=12), c, off=off, th=0.006, du=du)
# loading-spinner eye
face += gdecal("EyeL", oval(-EU, EV, 0.6, 0.6, n=18), VOID, off=0.022)
for k in range(8):
    a = math.radians(90 - k * 45)
    g = 1.0 - k / 8
    face += gdecal(f"Spin{k}", oval(-EU + math.cos(a) * 0.19, EV + math.sin(a) * 0.19, 0.1, 0.1, n=8),
                   mix(rgb(60, 70, 90), WHITE, g) if k else CYAN, off=0.045, th=0.008)
# pixel eye: chunky square with a pixel catchlight
face += gdecal("EyeR", rect(EU, EV, 0.5, 0.5), VOID, off=0.022)
face += gdecal("EyePx", rect(EU - 0.11, EV + 0.11, 0.14, 0.14), WHITE, off=0.045, th=0.008)
face += gdecal("EyePx2", rect(EU + 0.1, EV - 0.1, 0.06, 0.06), WHITE, off=0.045, th=0.008)
# pixel grin: stair-stepped, with two square teeth
P = 0.07
grin = [(-0.35, MV + 0.12), (0.35, MV + 0.12), (0.35, MV + 0.12 - P), (0.28, MV + 0.12 - P), (0.28, MV + 0.12 - 2 * P),
        (0.14, MV + 0.12 - 2 * P), (0.14, MV + 0.12 - 3 * P), (-0.14, MV + 0.12 - 3 * P), (-0.14, MV + 0.12 - 2 * P),
        (-0.28, MV + 0.12 - 2 * P), (-0.28, MV + 0.12 - P), (-0.35, MV + 0.12 - P)]
face += gdecal("Mouth", grin, VOID, off=0.022)
face += gdecal("Tooth1", rect(-0.1, MV + 0.12 - P / 2 - 0.005, 0.08, P * 0.8), WHITE, off=0.045, th=0.008)
face += gdecal("Tooth2", rect(0.1, MV + 0.12 - P / 2 - 0.005, 0.08, P * 0.8), WHITE, off=0.045, th=0.008)
parts += face

# ---------------------------------------------------------------- missing-texture checker (hero side)
for gx in range(4):
    for gy in range(4):
        fr = frame_at(-82, 0.0)
        u, v = -0.27 + gx * 0.18, 0.95 + gy * 0.18
        c = MAGENTA if (gx + gy) % 2 == 0 else VOID
        try:
            parts.append(decal(f"Chk{gx}{gy}", rect(u, v, 0.18, 0.18), c, fr, off=0.016, th=0.012,
                               on=names, step=0.09))
        except ValueError:
            pass

# ---------------------------------------------------------------- voxels breaking off the top
VOX = [((-0.35, 0.05, 2.98), 0.3, LIME), ((0.12, -0.1, 3.35), 0.24, MAGENTA), ((-0.6, 0.2, 3.55), 0.18, CYAN),
       ((0.3, 0.15, 3.0), 0.15, LIME_L), ((0.15, -0.05, 3.7), 0.1, LIME), ((-0.2, -0.2, 3.95), 0.08, VOID),
       ((0.55, -0.1, 3.4), 0.09, CYAN), ((-0.9, 0.0, 2.75), 0.12, MAGENTA), ((0.9, 0.1, 2.6), 0.1, LIME),
       ((-0.05, 0.1, 4.2), 0.06, MAGENTA)]
for j, (p, s, c) in enumerate(VOX):
    parts.append(box(f"Vox{j}", (s, s, s), p, c))

# pixel smears: horizontal streaks dragged out of the slices (pixel-sort glitch)
def slice_shift(z):
    for z0, z1, sh, _ in SLICES:
        if z0 <= z <= z1 + 0.03:
            return sh
    return 0.0


SMEAR = [(-1, 1.47, 0.9, 0.16, -0.1, LIME), (1, 1.07, 1.0, 0.18, -0.05, LIME_D), (-1, 0.7, 0.75, 0.14, 0.05, INV),
         (1, 2.2, 0.6, 0.12, 0.0, MAGENTA), (-1, 1.85, 0.5, 0.1, -0.15, CYAN)]
for j, (sd, z, L, h, y, c) in enumerate(SMEAR):
    r = radius(z)
    x = r * 0.8
    for k, (fl, fh) in enumerate(((0.5, 1.0), (0.3, 0.62), (0.2, 0.34))):  # pixel trail: steps thin out
        ln = L * fl
        parts.append(box(f"Smear{j}{k}", (ln + (r * 0.2 if k == 0 else 0), 0.42 - k * 0.08, h * fh),
                         (sd * (x + ln / 2 + (r * 0.1 if k == 0 else 0)) + slice_shift(z), y, z - (h - h * fh) * 0.5 * (1 if j % 2 else -1)),
                         c if k < 2 else mix(c, WHITE, 0.45)))
        x += ln + (r * 0.2 if k == 0 else 0) + 0.04

# a mouse cursor stuck hovering over it (white arrow, black rim)
CUR = [(0, 0), (0, -0.62), (0.15, -0.48), (0.26, -0.72), (0.36, -0.67), (0.25, -0.44), (0.45, -0.44)]
cx = Vector((0.85, -0.55, 0)).normalized()
cpos = Vector((1.25, -0.35, 2.75))
parts.append(slab("Cursor", CUR, 0.06, cpos, cx, (0, 0, 1), WHITE))
rim = [(x * 1.0, y) for x, y in CUR]
cen = (0.15, -0.4)
rim = [(cen[0] + (x - cen[0]) * 1.22, cen[1] + (y - cen[1]) * 1.16) for x, y in CUR]
nrm = cx.cross(Vector((0, 0, 1)))
parts.append(slab("CursorRim", rim, 0.06, cpos - nrm * 0.05 - cx * 0.01, cx, (0, 0, 1), VOID))

ship("slime_glitch", parts)
