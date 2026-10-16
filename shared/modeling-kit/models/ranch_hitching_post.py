# ranch_hitching_post: chunky two-post hitching rail (Slime Ranch), ~7 wide x ~4 tall.
# Two beveled posts on plinth feet with knob tops, one fat round rail across them (along X so the
# front view shows it full length), two pewter tie rings hanging from the rail, a rope coil
# looped over the rail, and a small wood water bucket with goo water at the right post's foot.
# cylinder() pos = base; rot= in DEGREES.
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_metal"], PALETTE["ranch_plaza"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
BUTTER, PATH = PALETTE["ranch_butter"], PALETTE["ranch_path"]

WOOD_LO = mix(WOOD_D, WOOD, 0.55)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO = mix(METAL, CREAM, 0.2)
METAL_HI = mix(METAL, CREAM, 0.55)
ROPE_LO, ROPE_HI = mix(BUTTER, WOOD, 0.35), mix(BUTTER, CREAM, 0.3)
parts = []


def pbox(name, size, pos, bot, top, bev=0.08, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


def torus(name, R, r, M, bot, top, segs=12, rsegs=6):
    """closed torus in its local XZ plane (ring hangs like a door knocker), placed by matrix M."""
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = i * math.tau / segs
        c, s = math.cos(a), math.sin(a)
        ring = []
        for k in range(rsegs):
            b = k * math.tau / rsegs
            rr = R + r * math.cos(b)
            ring.append(bm.verts.new(M @ Vector((c * rr, r * math.sin(b), s * rr))))
        rings.append(ring)
    for i in range(segs):
        a, b = rings[i], rings[(i + 1) % segs]
        for k in range(rsegs):
            bm.faces.new((a[k], a[(k + 1) % rsegs], b[(k + 1) % rsegs], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, bot)
    gradient(o, bot, top)
    return o


# --- posts ---
PX = 2.9
PH = 3.9
for s in (-1, 1):
    tilt = s * 1.5
    parts.append(pbox(f"Plinth{s}", (1.5, 1.5, 0.4), (s * PX, 0, 0.2), WOOD_D, WOOD_LO, bev=0.12))
    parts.append(pbox(f"Post{s}", (0.95, 0.95, PH), (s * PX, 0, 0.4 + PH / 2 - 0.05), mix(WOOD_LO, WOOD, 0.5), WOOD_HI, bev=0.14,
                      rot=(0, tilt, 0)))
    parts.append(pbox(f"PostBand{s}", (1.08, 1.08, 0.22), (s * PX, 0, PH - 0.35), mix(ROOF_D, ROOF, 0.5), ROOF, bev=0.05))
    knob = blob(f"Knob{s}", 0.62, (s * PX, 0, PH + 0.45), WOOD_HI, seed=s + 5, subdiv=2, squash=(1, 1, 0.75), jitter=0.0)
    gradient(knob, WOOD, WOOD_HI)
    parts.append(knob)

# --- rail: fat round log across the posts, a little sag-free tilt for the hand-made feel ---
RZ = PH - 0.9
RAIL_L = 2 * PX + 1.4
rail = cylinder("Rail", 0.34, RAIL_L, (-RAIL_L / 2, 0, RZ), WOOD, segs=10, rot=(0, 90, 0))
gradient(rail, WOOD_LO, WOOD_HI)
parts.append(rail)
for s in (-1, 1):  # end caps (lighter cut ends)
    parts.append(cylinder(f"RailEnd{s}", 0.3, 0.06, (s * (RAIL_L / 2), 0, RZ), mix(PATH, WOOD, 0.35), segs=10,
                          rot=(0, 90 * s, 0)))
# lower brace rail
parts.append(pbox("LowRail", (2 * PX, 0.5, 0.45), (0, 0.05, 1.15), WOOD_LO, WOOD, bev=0.1))

# --- tie rings hanging from the rail on the front (-Y) side ---
for i, x in enumerate((-1.3, 1.1)):
    parts.append(pbox(f"Staple{i}", (0.3, 0.3, 0.3), (x, -0.3, RZ - 0.12), METAL, METAL_HI, bev=0.04))
    M = Matrix.Translation((x, -0.42, RZ - 0.72)) @ Matrix.Rotation(math.radians(8 * (i * 2 - 1)), 4, "Y")
    parts.append(torus(f"Ring{i}", 0.48, 0.12, M, METAL_LO, METAL_HI))

# --- rope coil looped over the rail near the left post ---
for k in range(3):
    M = Matrix.Translation((-2.05 + k * 0.3, 0, RZ - 0.32 - k * 0.06)) @ Matrix.Rotation(math.radians(90), 4, "Z")
    parts.append(torus(f"Rope{k}", 0.66 - k * 0.05, 0.15, M, ROPE_LO, ROPE_HI, segs=12, rsegs=6))
# --- water bucket with goo water at the right post foot (front) ---
BX, BY = 1.6, -1.25
BR, BH = 0.65, 1.0
bucket = cylinder("Bucket", BR, BH, (BX, BY, 0), WOOD, segs=10, r_top=BR + 0.12)
bm = bmesh.new()
bm.from_mesh(bucket.data)
top = [f for f in bm.faces if f.normal.z > 0.9]
r = bmesh.ops.inset_region(bm, faces=top, thickness=0.12)
bmesh.ops.translate(bm, vec=(0, 0, -0.1), verts=list({v for f in top for v in f.verts}))
bm.normal_update()
layer = bm.loops.layers.color.get("Col")
for f in bm.faces:
    c = f.calc_center_median()
    if f in top:
        col = mix(GOO, GOO_HI, 0.4)
    else:
        col = mix(WOOD_LO, WOOD_HI, max(0.0, min(1.0, c.z / BH)))
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
bm.to_mesh(bucket.data)
bm.free()
parts.append(bucket)
for i, t in enumerate((0.22, 0.75)):
    rr = BR + 0.12 * t + 0.05
    hoop = cylinder(f"BucketHoop{i}", rr, 0.14, (BX, BY, t * BH - 0.07), METAL, segs=10)
    gradient(hoop, METAL_LO, METAL_HI)
    parts.append(hoop)
# small goo splash puddle by the bucket
pud = metaball_mesh("Splash", [Ball((BX - 0.75, BY - 0.55, 0.02), (1.0, 0.6, 0.07)),
                               Ball((BX - 1.2, BY - 0.3, 0.02), (0.4, 0.35, 0.05))], resolution=0.1, tris=120, clamp_z=0.02)
parts.append(paint_goo(pud, lambda co, n: mix(GOO, GOO_HI, 0.35)))

finish("ranch_hitching_post", parts)
