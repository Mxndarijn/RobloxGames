# habitat_theme_reef: ocean-reef theme for the habitat pad (Chomp, Octo, Catfish, Captain Goo, Kraken, Queen Jelly,
# Klawdius, Abyss). Props on the back and sides of the rim only (the frame mesh supplies the ring): a tall pink
# branch coral at the back, an orange branch coral and a tube-coral cluster on the back corners, green seaweed
# strands on the sides, sand mounds with a scallop shell and a starfish toward the front sides, rising bubbles.
# The front arc stays clear.
import math, random
from mathutils import Matrix, Vector
from lib import *
from models._habitat_overlay import *
from models._habitat_theme_bits import *
from models._habitat import place
from models._phoenix_pad import lathe

PINK, PINK_HI = rgb(255, 112, 160), rgb(255, 186, 214)
ORANGE, ORANGE_HI = rgb(255, 140, 60), rgb(255, 204, 120)
CORAL_RED = rgb(250, 96, 92)
SAND, SAND_D = rgb(246, 222, 164), rgb(222, 190, 128)
WEED, WEED_D = rgb(120, 226, 120), rgb(78, 184, 110)
SHELL, SHELL_D = rgb(255, 228, 214), rgb(246, 170, 160)
BUBBLE = rgb(200, 240, 255)
parts = []


def coral(name, base, ang, branches, lo, hi, r0=0.13):
    """Branch coral: tapered tubes from base, each [(dx_tangent, dz)...] relative to base, rounded tip blobs.
    dx is along the rim tangent, so the coral fans out sideways (seen from the front)."""
    a = math.radians(ang)
    tg = Vector((-math.sin(a), math.cos(a), 0))
    out = Vector((math.cos(a), math.sin(a), 0))
    objs = []
    for i, pts in enumerate(branches):
        P = [Vector(base) + tg * dx + out * dr + Vector((0, 0, dz)) for dx, dr, dz in pts]
        rad = [r0 * (1 - 0.3 * j / (len(P) - 1)) for j in range(len(P))]
        t = tube(f"{name}B{i}", P, rad, None, segs=5)
        gradient(t, lo, mix(lo, hi, 0.6))
        objs.append(t)
        tip = blob(f"{name}T{i}", rad[-1] * 1.3, P[-1], None, seed=i, subdiv=1, jitter=0.05)
        objs.append(paint_faces(tip, lambda c, n: hi))
    return objs


def sand(name, ang, w, h, seed, dr=0.0, dt=0.0):
    a = math.radians(ang)
    s = blob(name, 0.5, (0, 0, 0), None, seed=seed, subdiv=2, squash=(0.95, w, h), jitter=0.06, lumps=0.1)
    s.data.transform(Matrix.Translation(at(ang, dr=dr, dt=dt)) @ Matrix.Rotation(a, 4, "Z"))
    s.data.update()
    stand(s, -0.02)
    return paint_faces(s, lambda c, n: SAND if n.z > 0.4 else SAND_D)


def seaweed(name, base, ang, h, phase, lean):
    """One flat wavy strand (a tube squashed along the radial direction so its face shows from the front)."""
    a = math.radians(ang)
    tg = Vector((-math.sin(a), math.cos(a), 0))
    P, R = [], []
    n = 7
    for j in range(n):
        t = j / (n - 1)
        P.append(Vector(base) + tg * (0.13 * math.sin(t * 7 + phase) + lean * t) + Vector((0, 0, h * t)))
        R.append(0.17 * (1 - 0.55 * t) + 0.03)
    s = tube(name, P, R, None, segs=5)
    # flatten across the radial direction (a ribbon, face toward the slime and the walkway)
    out = Vector((math.cos(a), math.sin(a), 0))
    for v in s.data.vertices:
        d = (v.co - Vector(base)).dot(out)
        v.co -= out * d * 0.55
    gradient(s, WEED_D, WEED)
    return s


def scallop(name, pos, ang, size=0.42):
    """Fan shell standing up, ribbed: a half disc of wedges with alternating shade, a small hinge block."""
    import bmesh
    bm = bmesh.new()
    cl = bm.loops.layers.color.new("Col")
    n = 9
    c0, c1 = bm.verts.new((0, -0.04, 0)), bm.verts.new((0, 0.06, 0))
    rim0 = [bm.verts.new((size * math.cos(math.pi * k / n), -0.08 * (1 if k % 2 else 0.4), size * math.sin(math.pi * k / n) + 0.02)) for k in range(n + 1)]
    rim1 = [bm.verts.new((v.co.x * 0.92, 0.07, v.co.z * 0.92)) for v in rim0]
    for k in range(n):
        for f, c in ((bm.faces.new((c0, rim0[k + 1], rim0[k])), SHELL if k % 2 else SHELL_D),
                     (bm.faces.new((c1, rim1[k], rim1[k + 1])), SHELL_D),
                     (bm.faces.new((rim0[k], rim0[k + 1], rim1[k + 1], rim1[k])), SHELL_D)):
            for lp in f.loops:
                lp[cl] = c
    for f, c in ((bm.faces.new((c0, rim0[0], rim1[0], c1)), SHELL_D), (bm.faces.new((c1, rim1[n], rim0[n], c0)), SHELL_D)):
        for lp in f.loops:
            lp[cl] = c
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    from lib.shapes import obj_from_bm
    o = obj_from_bm(name, bm)
    # face the centre (and so the walkway across the pad), lean back a little
    o.data.transform(Matrix.Translation(pos) @ Matrix.Rotation(math.radians(ang + 90), 4, "Z") @ Matrix.Rotation(math.radians(-25), 4, "X"))
    o.data.update()
    return o


# --- back: tall pink branch coral on a sand mound ---
bx, by, _ = at(90)
parts.append(sand("SandBack", 90, 1.75, 0.34, 1))  # > RIGID: bends round the rim, its own part (the coral keeps its size)
parts += coral("Pink", (bx, by, 0.1), 90, [
    [(0, 0, 0), (0.02, 0, 0.7), (-0.05, 0, 1.3), (0.0, 0, 2.15)],
    [(0, 0, 0.5), (-0.28, 0, 0.9), (-0.42, 0, 1.45), (-0.4, 0, 1.85)],
    [(0, 0, 0.75), (0.3, 0, 1.1), (0.45, 0, 1.6)],
    [(-0.05, 0, 1.25), (-0.2, 0.05, 1.7), (-0.18, 0.05, 2.0)],
    [(0.3, 0, 1.12), (0.18, 0.0, 1.55), (0.22, 0.0, 1.95)],
], PINK, PINK_HI, r0=0.21)

# --- back corners: orange branch coral (right), tube corals (left) ---
ox, oy, _ = at(50)
parts += coral("Orange", (ox, oy, 0), 50, [
    [(0, 0, 0), (0.05, 0, 0.6), (0.0, 0, 1.25)],
    [(0, 0, 0.3), (-0.3, 0, 0.7), (-0.35, 0, 1.05)],
    [(0, 0, 0.4), (0.33, 0, 0.75), (0.4, 0, 1.15)],
    [(0.05, 0, 0.6), (0.2, 0, 0.95), (0.15, 0, 1.4)],
], ORANGE, ORANGE_HI, r0=0.18)
tx, ty, _ = at(130)
for k, (dt, dr, h, r) in enumerate(((0.0, 0.0, 1.3, 0.17), (-0.32, 0.1, 0.95, 0.15), (0.3, 0.05, 0.75, 0.14), (-0.08, -0.25, 0.55, 0.12))):
    a = math.radians(130)
    x, y = tx - math.sin(a) * dt + math.cos(a) * dr, ty + math.cos(a) * dt + math.sin(a) * dr
    PROF = [(0, 0), (r * 0.9, 0), (r, h * 0.5), (r * 1.25, h - 0.05), (r * 1.3, h), (r * 0.85, h), (r * 0.8, h - 0.12), (0, h - 0.12)]
    parts.append(lathe(f"Tube{k}", PROF, segs=7, pos=(x, y, 0),
                       color_fn=lambda i, kk, z, h=h: (rgb(200, 60, 80) if i >= 5 else (PINK_HI if i >= 3 else mix(shade(CORAL_RED, 0.95), PINK, z / h)))))

# --- brain corals between the back corals: round, grooved, peach and lilac-pink ---
BRAIN = [(72, rgb(255, 170, 120), rgb(226, 120, 96)), (108, rgb(250, 150, 200), rgb(214, 96, 150))]
for k, (ang, hi, lo) in enumerate(BRAIN):
    x, y, _ = at(ang, dr=0.05)
    b = blob(f"Brain{k}", 0.42, (x, y, 0), None, seed=50 + k, subdiv=2, squash=(1.0, 1.0, 0.8), jitter=0.04)
    stand(b, -0.04)
    parts.append(paint_faces(b, lambda c, n, hi=hi, lo=lo, x=x, y=y: hi if math.sin((c.x - x) * 14 + (c.z * 9)) * math.cos((c.y - y) * 12) > -0.1 else lo))

# --- sides: seaweed strands on a sand mound ---
for side in (1, -1):
    ang = 18 if side == 1 else 162
    parts.append(sand(f"SandSide{side}", ang, 1.7, 0.3, 10 + side))
    for k, (dt, h, ph, lean) in enumerate(((-0.32, 1.6, 0.0, -0.1), (0.0, 2.05, 1.8, 0.05), (0.3, 1.35, 3.1, 0.15))):
        a = math.radians(ang)
        x, y, _ = at(ang, dt=dt * side)
        parts.append(seaweed(f"Weed{side}{k}", (x, y, 0.05), ang, h, ph, lean * side))

# --- front sides: sand mounds with a scallop shell (right) and a starfish (left), small pebble shells ---
parts.append(sand("SandFR", -22, 1.0, 0.3, 20))
sx, sy, _ = at(-22, dr=0.05)
parts.append(scallop("Scallop", (sx, sy, 0.1), -22, 0.5))
parts.append(sand("SandFL", 202, 1.0, 0.3, 21))
fx, fy, _ = at(202, dr=0.05)
star = star_slab("Starfish", 0.46, 0.19, 0.14, (0, 0, 0), ORANGE, rim=CORAL_RED)
star.data.transform(Matrix.Translation((fx, fy, 0.32)) @ Matrix.Rotation(math.radians(202 + 90), 4, "Z") @ Matrix.Rotation(math.radians(-35), 4, "X"))
star.data.update()
parts.append(star)
for k, ang in enumerate((-36, 216)):
    x, y, _ = at(ang, dr=0.12)
    parts.append(paint_faces(blob(f"Pebble{k}", 0.12, (x, y, 0.06), None, seed=30 + k, subdiv=1, squash=(1.2, 1.0, 0.6)),
                             lambda c, n: SHELL_D if k else SHELL))

# --- bubbles rising from the corals ---
for k, (ang, z, r) in enumerate(((84, 2.45, 0.09), (97, 2.68, 0.07), (56, 1.7, 0.08), (45, 1.95, 0.06), (135, 1.6, 0.08), (20, 2.15, 0.07))):
    x, y, _ = at(ang, dr=-0.05)
    parts.append(paint_faces(blob(f"Bubble{k}", r, (x, y, z), None, seed=40 + k, subdiv=1, jitter=0.0),
                             lambda c, n: rgb(255, 255, 255) if n.z > 0.5 else BUBBLE))

theme_finish("habitat_theme_reef", parts)
