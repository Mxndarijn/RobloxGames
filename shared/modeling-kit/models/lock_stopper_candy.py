# Lock stopper style "Candy": jar 1's door as a giant wrapped peppermint (pink and cream swirl) in a crimped wrapper
# frill, a red padlock seal on the opening side. Same box as goo_jar_stopper (models/_lock_stopper.py).
from models._lock_stopper import *

PINK = PALETTE["ranch_pink"]
CREAM = PALETTE["ranch_cream"]
METAL = PALETTE["ranch_metal"]
PINK_D = mix(PINK, PALETTE["ranch_roof"], 0.25)

BODY_R = 3.9
segs = 32

# the sweet: a domed peppermint lens with a swirl of 8 pink stripes, cream in the middle
def sweet_col(r, a, i, j):
    if i < 0:
        return CREAM
    stripe = ((j % 8) < 4)
    base = PINK if stripe else CREAM
    return shade(base, 0.93 + 0.07 * (1 - r / BODY_R))


parts = [plug("Sweet", [0.7, 1.5, 2.3, 3.0, 3.5, BODY_R], segs,
              lambda r: 0.8 + 0.3 * (1 - (r / BODY_R) ** 2), sweet_col,
              twist=lambda r: 0.55 * r, back_y=-0.05, back_col=mix(PINK, CREAM, 0.35))]


# the wrapper frill round it: a pleated cellophane-paper ring out to the door's radius, alternating pleats
def frill():
    import bmesh as _bm
    bm = _bm.new()
    n = 56
    rin, rout = BODY_R - 0.3, R
    rows = []
    for j in range(n):
        a = j / n * math.tau
        out = rout * (1.0 + 0.008 * (1 if j % 2 else -1))
        dy = 0.62 if j % 2 else 0.42
        pts = [(rin, -dy - 0.1), (out, -dy), (out, 0.0), (rin, 0.0)]
        rows.append([bm.verts.new((r * math.cos(a), y, CZ + r * math.sin(a))) for r, y in pts])
    for j in range(n):
        A, B = rows[j], rows[(j + 1) % n]
        col = mix(PINK, CREAM, 0.55) if (j // 2) % 2 else CREAM
        for s in range(4):
            f = bm.faces.new((A[s], B[s], B[(s + 1) % 4], A[(s + 1) % 4]))
            set_col(bm, f, shade(col, 1.0 if s == 0 else 0.86))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm("Frill", bm)


parts.append(frill())
parts += hinges(METAL, t=0.55)
parts += padlock("Lock", 2.6, -0.98, CZ - 0.25, s=1.45)

ship("lock_stopper_candy", fit_to_classic(parts))
