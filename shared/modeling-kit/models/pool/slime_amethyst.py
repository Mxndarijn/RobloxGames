# Amethyst (Mythic): crystal golem. Faceted gem body with amethyst clusters bursting from the
# crown and shoulders, glowing eyes in dark sockets, a calm stony little smile.
from models._slimepool import *

V_D, V, V_L = hexc("26094f"), hexc("5420b8"), hexc("8a5cf0")
CR_D, CR_M, CR_L = hexc("9a40ff"), hexc("de8cff"), hexc("fff2ff")
GLOW = hexc("6ff6ff")


def gemstone(name, base, direction, length, rad, segs=6):
    """local crystal: deep violet root -> vivid violet -> pink-white tip, facets alternate softly"""
    d = Vector(direction).normalized()
    B = Vector(base)

    def col(p, n):
        t = min(1.0, max(0.0, (p - B).dot(d) / length))
        return mix(CR_D, CR_M, t / 0.6) if t < 0.6 else mix(CR_M, CR_L, (t - 0.6) / 0.4)
    o = lathe(name, [(0, rad * 0.85), (length * 0.7, rad), (length, 0)], col, pos=base, axis=d, segs=segs, smooth=False)
    bm = bmesh.new(); bm.from_mesh(o.data)
    c = bm.loops.layers.color["Col"]
    for i, f in enumerate(bm.faces):
        for lp in f.loops:
            lp[c] = mix(lp[c], WHITE, 0.3) if i % 3 == 0 else (shade(lp[c], 0.85) if i % 3 == 1 else lp[c])
    bm.to_mesh(o.data); bm.free()
    return o
SEGS = 14


def sectors(a, z):
    """gem facets: alternate light/dark per facet, darker foot, lighter crown"""
    i = int(round((a + math.pi) / (math.tau / SEGS)))
    base = mix(V_D, V, smoothstep(0.0, 1.7, z))
    base = mix(base, V_L, 0.3 * smoothstep(1.8, 2.9, z))
    return mix(base, V_L, 0.14) if i % 2 else base


b = Body([(0, 1.25), (0.25, 1.5), (0.9, 1.62), (1.6, 1.5), (2.2, 1.12), (2.65, 0.55), (2.8, 0)],
         sub=1, segs=SEGS, sectors=sectors, gloss=0.5)
keep(b.obj, False)  # flat facets: cut-gem body
parts = [b.obj]


def out_dir(yaw, up):
    a = math.radians(yaw)
    return Vector((math.sin(a), -math.cos(a), up)).normalized()


def cluster(tag, yaw, z, specs, sink=0.05):
    """specs: [(dyaw, up, length, rad)] crystals rooted just inside the body surface at (yaw, z)"""
    out = []
    for k, (dy, up, L, r) in enumerate(specs):
        p = b.point(math.radians(yaw + dy * 0.4), z, -sink)
        out.append(gemstone(f"Cr{tag}{k}", p, out_dir(yaw + dy, up), L, r * 1.2))
    return out


# crown cluster: a tall centre spire + a fan around it, leaning back a little
crown = [((0, 0.25, 2.55), (0, 0.18, 1), 1.55, 0.36), ((-0.42, 0.2, 2.45), (-0.55, 0.15, 1), 1.05, 0.27),
         ((0.45, 0.25, 2.45), (0.6, 0.25, 1), 1.15, 0.28), ((0.05, 0.62, 2.35), (0.1, 0.8, 1), 0.95, 0.25),
         ((-0.2, -0.2, 2.5), (-0.2, -0.45, 1), 0.7, 0.2), ((0.28, -0.15, 2.5), (0.35, -0.4, 1), 0.55, 0.17)]
for k, (p, d, L, r) in enumerate(crown):
    parts.append(gemstone(f"Crown{k}", p, d, L * 1.35, r * 1.45))
# glowing veins (cracks of crystal light) running down the stone body
VEIN = hexc("ff7ae6")
for k, (yaw, z0, z1, amp) in enumerate([(135, 0.4, 1.9, 0.1), (-140, 0.35, 1.8, 0.1), (200, 0.6, 1.6, 0.09)]):
    pts = zigzag(z0, z1, 0, amp, 4, 0.11)
    parts.append(decal(f"Vein{k}", [(v, u) for u, v in pts], VEIN, frame_at(yaw, 0), off=0.01, th=0.015, on=["Body"]))
# shoulder clusters (asymmetric: big on the left, small on the right), and one on the back
parts += cluster("L", 95, 1.75, [(0, 0.7, 1.35, 0.32), (-22, 0.3, 0.9, 0.24), (24, 1.3, 0.85, 0.22)])
parts += cluster("R", -100, 1.35, [(0, 0.55, 0.95, 0.26), (24, 1.1, 0.65, 0.19)])
parts += cluster("B", 165, 1.2, [(0, 0.5, 1.1, 0.28), (-28, 0.9, 0.8, 0.22), (28, 0.2, 0.7, 0.2)])
# loose crystals on the ground
for k, (x, y, d, L, r) in enumerate([(-1.75, -0.55, (-0.5, -0.2, 1), 0.55, 0.16), (-1.95, -0.1, (-0.8, 0.1, 1), 0.38, 0.12),
                                     (1.65, -0.85, (0.4, -0.5, 1), 0.42, 0.13)]):
    parts.append(gemstone(f"Ground{k}", (x, y, -0.05), d, L * 1.3, r * 1.3))

# face: dark sockets with glowing eyes
f = Face(b, eye_u=0.52, eye_v=1.55, mouth_v=1.05)
for sd in (-1, 1):
    f.d(f"Socket{sd}", oval(sd * 0.55, 1.55, 0.68, 0.74, n=18), hexc("12042a"), off=0.012)
    f.d(f"Glow{sd}", oval(sd * 0.55, 1.53, 0.46, 0.54, n=16), GLOW, off=0.03, th=0.012)
    f.d(f"GlowC{sd}", oval(sd * 0.55, 1.53, 0.22, 0.28, n=12), WHITE, off=0.045, th=0.01)
    f.d(f"Spark{sd}", star(sd * 0.55 - 0.1, 1.68, 0.09, 0.035, n=4), WHITE, off=0.06, th=0.01)
f.mouth("smile", w=1.1, v=1.0, color=hexc("12042a"))
f.cheeks(color=hexc("ff9ee8"))
parts += f.parts
ship("slime_amethyst", parts)
