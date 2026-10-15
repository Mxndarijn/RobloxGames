# ranch_wagon: small farm handcart (Slime Ranch), ~8 studs long plaza/path decor.
# Warm wood bed + side rails, pewter axle/hubs, two chunky wheels, pull handles.
# Soft hay in the bed + a small goo drip on the rim (blob, not stuck tubes).
# Target under ~2000 tris. Long axis X; pull handles toward -X.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM = PALETTE["ranch_cream"]
METAL = PALETTE["ranch_metal"]
PLAZA = PALETTE["ranch_plaza"]
BUTTER = PALETTE["ranch_butter"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]

WOOD_LO = mix(WOOD_D, WOOD, 0.55)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO = mix(METAL, WOOD_D, 0.2)
PLAZA_LO = mix(PLAZA, WOOD, 0.2)
HAY_LO = mix(BUTTER, WOOD, 0.12)
HAY_HI = mix(BUTTER, CREAM, 0.28)
GOO_LO = shade(GOO, 0.85)
parts = []


def pbox(name, size, pos, bot, top, bev=0.1, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


def wheel_disc(name, r, thick, centre, color, segs=12):
    """Disc in the XZ plane (axle along Y). cylinder rot=(90,0,0) grows toward -Y;
    place base at centre.y + thick/2 so the disc is centred on centre."""
    y_base = centre[1] + thick / 2
    # cylinder stands on pos.z; after rot X=90, local Z→-Y, so height runs -Y from base.
    # The "standing" base was at local z=0; after rot the circle lies in XZ at y=y_base,
    # extending to y=y_base-thick. Centre z of the circle = pos.z + r (because standing
    # cylinder base at pos.z, mid-height of... wait: standing cylinder base at pos.z,
    # top at pos.z+h, AXIS along Z. After rot(90,0,0): axis along -Y, the circle that
    # was in XY at each z is now in XZ. The base circle centre is at (pos.x, pos.y, pos.z)
    # — NO: standing cylinder: base circle centred at (pos.x, pos.y, pos.z) in XY plane.
    # After Euler X=90 about origin of the mesh before _place... actually _place applies
    # rot after the standing construction, so verts at (x,y,z_local) → rotated then +pos.
    # Standing: verts around (0,0) in xy, z from 0..h, then translate by pos, then... 
    # Looking at shapes.py: create at origin standing, translate z by h/2 (so z=0..h becomes
    # centred?), wait: create_cone depth=h centred at origin (z=-h/2..h/2), then translate
    # +h/2 so z=0..h, THEN _place(pos, rot).
    # So before place: cylinder from z=0 to z=h, axis Z, base at z=0.
    # _place: rotate then translate by pos.
    # rot=(90,0,0): (x,y,z) → (x, -z, y) roughly (Rx90: y'=-z, z'=y).
    # So base z=0 → y'=0, top z=h → y'=-h. Circle that was in XY at z becomes in XZ at y'.
    # Base circle centre ends at pos after translate, with local (0,0,0)→pos.
    # Wheel centre should be at `centre`; base at y = centre.y + thick/2, and we need
    # the circle centre z = centre.z. Before rot, circle centre is at (0,0,0) for base
    # (=pos after place). After Rx90, base centre (0,0,0) stays; points (r,0,0) stay.
    # A point on base circle (r,0,0) → (r,0,0); (0,r,0) → (0,0,r). So base circle is in XZ!
    # Perfect. Axis goes to -Y. So pos = (centre.x, centre.y + thick/2, centre.z).
    o = cylinder(name, r, thick, (centre[0], centre[1] + thick / 2, centre[2]), color, segs=segs, rot=(90, 0, 0))
    return o


# --- footprint: ~8 long (X) x ~4.2 wide (Y) x ~3.6 tall ---
L, W = 7.6, 3.8
BED_Z = 1.55
FLOOR_T = 0.42
RAIL_H = 1.15
Z_AXLE = 1.05  # = WR so tire sits on z=0

# floor core + plaza deck planks (cream banned on big surfaces)
parts.append(pbox("Floor", (L - 0.3, W - 0.35, FLOOR_T), (0, 0, BED_Z - FLOOR_T / 2),
                  WOOD_LO, WOOD, bev=0.1))
n_plank = 5
for k in range(n_plank):
    x = -L / 2 + 0.55 + k * (L - 0.7) / (n_plank - 1)
    c = PLAZA if k % 2 == 0 else mix(PLAZA, WOOD, 0.15)
    parts.append(pbox(f"Deck{k}", (1.15, W - 0.55, 0.14), (x, 0, BED_Z + 0.05),
                      mix(PLAZA_LO, c, 0.5), c, bev=0))

# side rails
for sy in (-1, 1):
    y = sy * (W / 2 - 0.18)
    parts.append(pbox(f"RailLo{sy}", (L - 0.9, 0.38, 0.55), (0, y, BED_Z + 0.35),
                      WOOD_LO, WOOD, bev=0.08))
    parts.append(pbox(f"RailHi{sy}", (L - 1.1, 0.32, 0.5), (0.05 * sy, y, BED_Z + 0.85),
                      WOOD, WOOD_HI, bev=0.08))
    for sx in (-1, 1):
        parts.append(pbox(f"Post{sx}{sy}", (0.42, 0.42, RAIL_H + 0.15),
                          (sx * (L / 2 - 0.45), y, BED_Z + (RAIL_H + 0.15) / 2),
                          WOOD_LO, WOOD, bev=0.1))

# front (+ cream trim) and rear boards
parts.append(pbox("Front", (0.4, W - 0.5, RAIL_H + 0.25),
                  (-L / 2 + 0.25, 0, BED_Z + (RAIL_H + 0.25) / 2),
                  WOOD_LO, WOOD_HI, bev=0.12))
parts.append(pbox("FrontTrim", (0.18, W - 0.9, 0.28),
                  (-L / 2 + 0.42, 0, BED_Z + RAIL_H + 0.05),
                  mix(CREAM, WOOD, 0.25), CREAM, bev=0.06))
parts.append(pbox("Rear", (0.38, W - 0.6, RAIL_H * 0.75),
                  (L / 2 - 0.3, 0, BED_Z + (RAIL_H * 0.75) / 2),
                  WOOD_LO, WOOD, bev=0.1))

# undercarriage
parts.append(pbox("BeamX", (L - 1.2, 0.5, 0.45), (0, 0, BED_Z - FLOOR_T - 0.25),
                  WOOD_LO, WOOD, bev=0.08))
for sy in (-1, 1):
    parts.append(pbox(f"BeamY{sy}", (0.55, W - 0.8, 0.45),
                      (0.1 * sy, sy * 0.9, BED_Z - FLOOR_T - 0.25),
                      WOOD_LO, WOOD, bev=0.08))

# pewter axle along Y
# rot=(90,0,0) grows toward -Y: base at +len/2 so the axle is centred on y=0
axle_len = W + 1.4
parts.append(cylinder("Axle", 0.14, axle_len, (0, axle_len / 2, Z_AXLE), METAL, segs=8, rot=(90, 0, 0)))
gradient(parts[-1], METAL_LO, METAL)

# wheels
WR, WT = 1.05, 0.42
for sy in (-1, 1):
    y = sy * (W / 2 + 0.55)
    centre = (0.0, y, Z_AXLE)
    tire = wheel_disc(f"Wheel{sy}", WR, WT, centre, WOOD_D, segs=12)
    bm = bmesh.new()
    bm.from_mesh(tire.data)
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        n = f.normal
        if abs(n.y) > 0.7:
            col = mix(PLAZA, WOOD, 0.25)
        else:
            c = f.calc_center_median()
            t = max(0.0, min(1.0, (c.z - (Z_AXLE - WR)) / (2 * WR)))
            col = mix(WOOD_LO, WOOD_HI, t)
        for lp in f.loops:
            lp[layer] = (*col[:3], 1.0)
    bm.to_mesh(tire.data)
    bm.free()
    parts.append(tire)
    # hub
    hub = wheel_disc(f"Hub{sy}", 0.32, WT + 0.14, centre, METAL, segs=8)
    gradient(hub, METAL_LO, METAL)
    parts.append(hub)
    # pewter tread band (slightly larger radius, thinner)
    rim = wheel_disc(f"Rim{sy}", WR + 0.05, 0.22, (0.0, y, Z_AXLE), METAL, segs=12)
    gradient(rim, METAL_LO, METAL)
    parts.append(rim)
    # 4 chunky spokes
    for i in range(4):
        ang = i * math.pi / 2 + 0.25
        parts.append(pbox(f"Spoke{sy}{i}", (0.85, 0.16, 0.2),
                          (math.cos(ang) * 0.5, y, Z_AXLE + math.sin(ang) * 0.5),
                          WOOD_LO, WOOD, bev=0, rot=(0, 0, math.degrees(ang))))

# pull handles toward -X
for sy in (-1, 1):
    parts.append(pbox(f"Shaft{sy}", (2.0, 0.28, 0.28),
                      (-L / 2 - 0.85, sy * 0.7, BED_Z + 0.55),
                      WOOD_LO, WOOD, bev=0.08, rot=(0, -8, 0)))
parts.append(pbox("Crossbar", (0.28, 1.7, 0.28),
                  (-L / 2 - 1.75, 0, BED_Z + 0.85),
                  WOOD_LO, WOOD_HI, bev=0.08))
for sy in (-1, 1):
    parts.append(cylinder(f"Bolt{sy}", 0.12, 0.35,
                          (-L / 2 + 0.1, sy * 0.7 - 0.175, BED_Z + 0.55),
                          METAL, segs=6, rot=(90, 0, 0)))
    gradient(parts[-1], METAL_LO, METAL)

# hay in bed (top only)
parts.append(blob("Hay1", 0.85, (-0.8, 0.15, BED_Z + 0.7), HAY_HI, subdiv=2,
                  squash=(1.8, 1.2, 0.65), jitter=0.1, seed=4))
parts.append(blob("Hay2", 0.7, (0.9, -0.2, BED_Z + 0.65), HAY_LO, subdiv=2,
                  squash=(1.5, 1.1, 0.55), jitter=0.1, seed=9))
parts.append(blob("Hay3", 0.55, (0.1, 0.5, BED_Z + 0.9), HAY_HI, subdiv=2,
                  squash=(1.2, 1.0, 0.5), jitter=0.08, seed=2))
for o in parts[-3:]:
    gradient(o, HAY_LO, HAY_HI)

# soft goo drip on rear-right rail (blob, not tube)
parts.append(blob("GooDrip", 0.28, (L / 2 - 1.2, W / 2 - 0.15, BED_Z + RAIL_H - 0.15),
                  GOO, subdiv=1, squash=(1.1, 0.7, 1.4), jitter=0.08, seed=6))
gradient(parts[-1], GOO_LO, GOO_HI)
parts.append(blob("GooHi", 0.12, (L / 2 - 1.15, W / 2 - 0.2, BED_Z + RAIL_H + 0.05),
                  GOO_HI, subdiv=1, squash=(1, 1, 0.8), jitter=0.05, seed=1))

finish("ranch_wagon", parts)
