# Venus (Legendary, Garden): venus flytrap slime. Lime goo with a big open flytrap on its head:
# two cupped leaf jaws (green outside, red inside) fringed with pale bristle teeth, a rosette of
# trap leaves round the foot, and a hungry face (sly eyes, toothy grin, a drool drop).
from models._slimepool import *

G_D, G, G_L = hexc("50c44a"), hexc("7ee24c"), hexc("c2f45c")
TRAP_D, TRAP, TRAP_L = hexc("62c43c"), hexc("94e040"), hexc("ccf05a")
VEIN = hexc("4cb444")
BELLY = hexc("d6fa8a")
RED_D, RED, RED_L = hexc("d42a3a"), hexc("ff4a4a"), hexc("ff8a6a")
RIM = hexc("d8f468")
CIL, CIL_T = hexc("e8f8a0"), hexc("fffbe0")
IRIS = hexc("ffd23a")
DROOL = hexc("c8ff9a")


def paint(a, z, p):
    c = mix(G_D, G, smoothstep(0.0, 1.3, z))
    c = mix(c, G_L, 0.55 * smoothstep(1.7, 2.8, z))
    # pale belly low on the front (the face sits above it)
    bl = smoothstep(0.75, 0.35, abs(a)) * smoothstep(0.95, 0.55, z) * smoothstep(0.05, 0.3, z)
    return mix(c, BELLY, 0.7 * bl)


b = Body([(0, 1.08), (0.14, 1.36), (0.5, 1.5), (1.1, 1.47), (1.8, 1.26), (2.35, 0.92), (2.7, 0.48), (2.82, 0)],
         paint=paint, segs=32, sub=2)
parts = [b.obj]
H = b.H


# ---- trap lobe: a cupped half-disc pillow, built flat at the origin (x along the hinge, y out,
# +z = inner side), painted, bent, then moved into place
def lobe_poly(L, W, n=14):
    pts = []
    for k in range(n + 1):
        a = math.pi * k / n
        pts.append((math.cos(a) * L / 2, W * math.sin(a) ** 0.7))
    return pts


def bend(p, L, W, curl, cup):
    """curl the lobe tip inwards (+z) and cup it across the hinge"""
    y = max(0.0, p.y) / W
    x = p.x / (L / 2)
    return Vector((p.x, p.y, p.z + curl * y * y + cup * x * x * (0.3 + y)))


def lobe(tag, L, W, origin, X, Y, curl=0.35, cup=0.18, th=0.16, n_cil=13, cil_len=0.42, red=(RED_D, RED, RED_L), green=(TRAP_D, TRAP, TRAP_L), name="Ear"):
    X, Y = Vector(X).normalized(), Vector(Y).normalized()
    N = X.cross(Y).normalized()
    M = Matrix((X, Y, N)).transposed()
    O = Vector(origin)

    def xf(p):
        return O + M @ bend(Vector(p), L, W, curl, cup)

    def col(p, n):
        rr = math.sqrt((p.x / (L / 2)) ** 2 + (max(p.y, 0) / W) ** 2)
        if p.z > 0.01:  # inner face: deep red middle -> warm rim -> lime lip
            c = mix(red[0], red[1], smoothstep(0.1, 0.6, rr))
            c = mix(c, red[2], smoothstep(0.6, 0.85, rr))
            return mix(c, RIM, smoothstep(0.86, 0.97, rr))
        c = mix(green[0], green[1], smoothstep(0.0, 0.5, p.y / W))
        return mix(c, green[2], smoothstep(0.5, 1.0, p.y / W))

    o = puffy_slab(f"{name}{tag}", lobe_poly(L, W), th, (0, 0, 0), (1, 0, 0), (0, 1, 0), col, rows=3)
    for v in o.data.vertices:
        v.co = xf(v.co)
    o.data.update()
    out = [o]
    vp = [xf(Vector((0, W * t, -th / 2 - 0.035))) for t in (0.05, 0.4, 0.75)]
    out.append(horn(f"{name}Vein{tag}", [tuple(q) for q in vp], [0.07 * th / 0.16, 0.05 * th / 0.16, 0.02], VEIN, green[1], segs=5))
    # bristle teeth round the rim, pointing out and curling in
    for k in range(n_cil):
        a = math.pi * (0.06 + 0.88 * k / (n_cil - 1))
        rim = Vector((math.cos(a) * L / 2, W * math.sin(a) ** 0.7, 0))
        d = Vector((math.cos(a) * 0.55, math.sin(a), 0)).normalized()
        ln = cil_len * (0.75 + 0.25 * math.sin(a))
        p0 = xf(rim - d * 0.06)
        p1 = xf(rim + d * ln * 0.55 + Vector((0, 0, 0.05)))
        p2 = xf(rim + d * ln + Vector((0, 0, 0.16)))
        out.append(horn(f"{name}Cil{tag}{k}", [tuple(p0), tuple(p1), tuple(p2)], [0.05, 0.035, 0.012], CIL, CIL_T, segs=4, smooth=False))
    return out


# ---- the big trap on the head: hinge across the back of the crown, the mouth opens to the front:
# the lower jaw lies forward over the crown, the upper jaw stands up and back so its red inside
# faces the viewer
HC = Vector((0, 0.6, H - 0.32))
LOW, UP = math.radians(12), math.radians(70)  # jaw angles above the horizontal (pointing forward)
for tag, ang, nm in (("Low", LOW, "Jaw"), ("Up", UP, "Ear")):
    Y = Vector((0, -math.cos(ang), math.sin(ang)))  # out of the hinge, forward/up
    X = (1, 0, 0) if tag == "Up" else (-1, 0, 0)  # +N (inner side) faces the other jaw
    parts += lobe(tag, 2.5 if tag == "Up" else 2.3, 1.8 if tag == "Up" else 1.5, HC, X, Y, curl=0.3, cup=0.2, name=nm, n_cil=15 if tag == "Up" else 11)
parts.append(horn("Midrib", [(-1.0, 0.62, H - 0.42), (0, 0.72, H - 0.26), (1.0, 0.62, H - 0.42)], [0.12, 0.17, 0.12], TRAP_D, TRAP, segs=6))

# ---- two small traps on leaf stalks at the sides, mouths open outwards
for sd in (-1, 1):
    a = math.radians(sd * 82)
    root = b.point(a, 1.15, -0.15)
    tip = root + Vector((sd * 0.45, -0.15, 0.6))
    parts.append(horn(f"Stalk{sd}", [tuple(root), tuple(root + Vector((sd * 0.35, -0.05, 0.15))), tuple(tip)], [0.13, 0.1, 0.08], TRAP_D, TRAP, segs=6))
    out = Vector((sd * 0.8, -0.7, 0.45)).normalized()  # mouth direction
    hinge = Vector((0, 0, 1)).cross(out).normalized()
    for j, ang in ((0, 0.5), (1, -0.5)):
        Yv = (out * math.cos(ang) + out.cross(hinge) * math.sin(ang)).normalized()
        Xv = hinge if j == 0 else -hinge
        parts += lobe(f"S{sd}{j}", 1.1, 0.78, tip, Xv, Yv, curl=0.15, cup=0.1, th=0.1, n_cil=7, cil_len=0.22, name="Ear")

# ---- face: hungry and cheeky
f = Face(b, eye_v=1.5, eye_u=0.5, mouth_v=1.0, s=1.1)
f.eyes("sly", w=0.5, h=0.62, iris=IRIS)
f.mouth("shark", w=0.9)
f.d("Drool", [(0.3, 0.97), (0.36, 0.97), (0.37, 0.8), (0.4, 0.7), (0.36, 0.64), (0.31, 0.66), (0.3, 0.75)], DROOL, off=0.03, th=0.015)
parts += f.parts
ship("slime_venus", parts)
