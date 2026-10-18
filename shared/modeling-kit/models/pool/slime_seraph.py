# Seraph (Mythic): pearly angel goo with gold accents, a glowing halo, two layered feathered wings,
# a soft top curl and a serene sleepy smile.
from models._slimepool import *

PEARL, PINK, BLUE, LAV = hexc("fbf6ff"), hexc("ffd6ec"), hexc("cfe6ff"), hexc("e6d6ff")
FEATH, FEATH_D = hexc("ffffff"), hexc("dcdcf4")
HALO, HALO_L = hexc("ffd24a"), hexc("fff6b8")


def paint(a, z, p):
    c = mix(LAV, PEARL, smoothstep(0.0, 1.6, z))
    n1 = noise.noise(Vector((p.x * 0.9, p.y * 0.9, p.z * 0.9 + 7.0)))
    n2 = noise.noise(Vector((p.x * 0.8 + 3.1, p.y * 0.8, p.z * 0.8)))
    c = mix(c, PINK, 0.45 * smoothstep(0.05, 0.45, n1))
    c = mix(c, BLUE, 0.45 * smoothstep(0.1, 0.5, n2))
    return c


H = 3.05
b = Body([(0, 1.02), (0.12, 1.3), (0.5, 1.46), (1.1, 1.44), (1.8, 1.22), (2.45, 0.84), (2.85, 0.4), (H, 0)],
         paint=paint, segs=36, sub=2, bands=[(0.14, 0.26, GOLD)], lean=lambda z: 0.12 * max(0.0, (z - 2.3) / 0.75) ** 2)
parts = [b.obj]

# ---- halo: gold ring + pale glow ring, floating and tilted a touch
HC = Vector((0, 0.22, H + 0.62))
HN = Vector((0, 0.28, 1))
parts.append(torus("Halo", 0.72, 0.085, tuple(HC), tuple(HN), lambda p, n: mix(HALO, HALO_L, 0.5 + 0.5 * n.z), segs=32, rsegs=6))
parts.append(torus("HaloGlow", 0.9, 0.035, tuple(HC), tuple(HN), mix(HALO_L, WHITE, 0.4), segs=32, rsegs=4))


# ---- wings: layered feathers fanned in a plane behind each side
def feather_poly(L, w, n=5):
    """soft feather: narrow quill end, widest at ~60 %, round tip."""
    top = []
    for k in range(n + 1):
        t = k / n
        x = t * L
        if t < 0.7:
            y = w / 2 * (0.45 + 0.55 * math.sin(math.pi / 2 * t / 0.7))
        else:
            q = (t - 0.7) / 0.3
            y = w / 2 * math.sqrt(max(0.0, 1 - q * q))
        top.append((x, y))
    bot = [(x, -y) for x, y in reversed(top[1:-1])]
    return top + bot


def wing(sd):
    out = []
    root = b.point(math.radians(sd * 115), 1.7, -0.15)
    e_out = Vector((sd * 0.95, 0.32, 0)).normalized()
    e_up = Vector((0, 0.18, 1)).normalized()
    N = e_out.cross(e_up).normalized()

    def dirv(deg):
        th = math.radians(deg)
        return e_out * math.cos(th) + e_up * math.sin(th)
    arm = dirv(48)
    n = 7
    # primaries hang off the rising wing arm, pointing down-out, longest at the tip
    for i in range(n):
        t = i / (n - 1)
        o = root + arm * (0.1 + 0.88 * t) + N * (0.03 * i * sd)
        d = dirv(-70 + 95 * t)
        L = 0.7 + 0.68 * t ** 0.8
        y = d.cross(N).normalized()
        col = along(FEATH_D, mix(FEATH, HALO_L, 0.75), o, o + d * L, power=1.8)
        out.append(puffy_slab(f"WingPrim{sd}{i}", feather_poly(L, 0.5), 0.1, tuple(o), tuple(d), tuple(y), col, rows=2))
    # coverts: short round feathers along the arm, in front of the primaries
    for i in range(5):
        t = i / 4
        o = root + arm * (0.05 + 0.8 * t) - N * (0.12 * sd) + N * (0.025 * i * sd)
        d = dirv(-45 + 85 * t)
        L = 0.55 + 0.25 * t
        y = d.cross(N).normalized()
        out.append(puffy_slab(f"WingCov{sd}{i}", feather_poly(L, 0.5), 0.12, tuple(o), tuple(d), tuple(y), along(FEATH_D, FEATH, o, o + d * L), rows=2))
    # leading edge: a soft round arm tube along the top
    arm_pts = [tuple(root + arm * (1.0 * k / 4) + e_up * 0.06 * math.sin(k / 4 * math.pi) - N * 0.06 * sd) for k in range(5)]
    out.append(horn(f"WingArm{sd}", arm_pts, [0.2, 0.18, 0.15, 0.12, 0.09], FEATH, FEATH, segs=8))
    return out


parts += wing(1) + wing(-1)

# ---- serene face: closed sleepy eyes with long lashes, soft smile, blush, gold forehead gem
f = Face(b, eye_v=1.62, eye_u=0.5, mouth_v=1.2)
for sd in (-1, 1):
    u, v = sd * 0.5, 1.6
    f.d(f"Eye{sd}", arc(u, v + 0.07, 0.19, 200, 340, 0.075, n=10), INK)
    for j, (aa, ln) in enumerate(((215 if sd < 0 else 325, 0.12), (235 if sd < 0 else 305, 0.1))):
        r = math.radians(aa)
        x0, y0 = u + math.cos(r) * 0.19, v + 0.07 + math.sin(r) * 0.19
        f.d(f"Lash{sd}{j}", rect(x0 + math.cos(r) * 0.05, y0 + math.sin(r) * 0.05, 0.035, ln, r + math.pi / 2), INK)
f.mouth("smile", w=1.15)
f.cheeks(color=hexc("ffa6c8"), w=0.32, h=0.15)
parts += f.parts
parts.append(gem("Forehead", tuple(b.point(0, 2.2, 0.03)), 0.12, hexc("6ad8ff"), axis=(0, -1, 0.25), h=0.13, segs=6))
parts.append(decal("GemSet", star(0, 2.2, 0.24, 0.1, n=4), GOLD, FRONT, off=0.015, th=0.02, on=["Body"]))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_seraph", parts)
