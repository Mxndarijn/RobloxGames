"""Export a base design layout (models/_<id>_layout.py) to the game as Luau data.

    python tools/export_base_shape.py factory <steal-a-slime game dir>

Writes <game>/src/visuals/shared/BaseShapeData/<Name>.luau: the base's pads, floor-1 spots, every collidable or
contract part per floor (with the "shown only while top / covered" variant the game's BaseFloors flips), the drop
exit, the containment box and the ramps (for tests/BaseShapes.spec). The kit layout stays the design source; rerun
this after changing it and commit the Luau file.

Axes: the kit layout is plot-local with x right, y = plot z (y < 0 = the door side), z up. The game's plot-local
frame is x right, y up, z = kit y. Kit boxes are rotated by Blender XYZ Euler angles; each part's Roblox axes are
X = kit local x, Y = kit local z (up), Z = X cross Y, exported as Roblox orientation degrees (Y, X, Z order).
"""
import importlib
import math
import os
import sys

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, KIT)

# Contract parts the game keeps on every plot (moved, never rebuilt) or leaves where the jar has them.
KEPT_MOVED = {"MergeVat", "LockButton", "LockBarrier", "Bridge"}
KEPT_STILL = {"Base", "PlotFloor", "HomeZone", "LockSign", "Sign"}
# The swinging door's collider comes from the jar's door, moved to the base's doorway (BaseShapes), not from the layout.
FROM_JAR = {"OpenDoorCollider"}

ROLE_LOOK = {  # greybox look per role until the meshes land: colour (sRGB) and material
    "wall": ((209, 104, 85), "Brick"),
    "floor": ((206, 196, 178), "Concrete"),
    "core wall": ((176, 128, 88), "WoodPlanks"),
    "ramp": ((110, 226, 170), "SmoothPlastic"),
    "roof": ((150, 160, 176), "DiamondPlate"),
    "yard silo": ((168, 176, 188), "Metal"),
    "goo belt (collides: 1.2 tall)": ((70, 70, 84), "Rubber"),
}


def load(layout, floors):
    os.environ["LAYOUT_FLOORS"] = str(floors)
    mod = importlib.import_module(f"models.{layout}")
    return importlib.reload(mod)


def rot_kit(rx, ry, rz):
    """Blender XYZ Euler (degrees) -> 3x3 matrix (rows), R = Rz @ Ry @ Rx."""
    a, b, c = (math.radians(v) for v in (rx, ry, rz))
    Rx = [[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]]
    Ry = [[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]]
    Rz = [[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]]
    return mul(Rz, mul(Ry, Rx))


def mul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def col(M, j):
    return [M[0][j], M[1][j], M[2][j]]


def kit_to_plot(v):
    return [v[0], v[2], v[1]]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def orientation(X, Y, Z):
    """Roblox orientation (degrees) of a CFrame whose columns are X, Y, Z (fromOrientation = Ry * Rx * Rz)."""
    M = [[X[0], Y[0], Z[0]], [X[1], Y[1], Z[1]], [X[2], Y[2], Z[2]]]
    rx = math.asin(max(-1.0, min(1.0, -M[1][2])))
    ry = math.atan2(M[0][2], M[2][2])
    rz = math.atan2(M[1][0], M[1][1])
    deg = [math.degrees(v) for v in (rx, ry, rz)]
    # check: rebuild and compare
    a, b, c = (math.radians(v) for v in deg)
    Ry = [[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]]
    Rx = [[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]]
    Rz = [[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]]
    R = mul(Ry, mul(Rx, Rz))
    err = max(abs(R[i][j] - M[i][j]) for i in range(3) for j in range(3))
    assert err < 1e-6, f"orientation round trip failed ({err})"
    return [round(v, 3) + 0.0 for v in deg]


def part_frame(c):
    """(shape, size, pos, rot) in the game's plot-local frame for a kit collider dict."""
    x, y, z = c["pos"]
    sx, sy, sz = c["size"]
    R = rot_kit(*c.get("rot", (0, 0, 0)))
    ex, ey, ez = (kit_to_plot(col(R, j)) for j in range(3))
    pos = [round(x, 4), round(z, 4), round(y, 4)]
    if c["kind"] == "box":
        if c["name"] == "DropHatch":
            # the hatch's local +Z must point out of the building (BaseFloors puts DropPromptAt at local -Z inside)
            if abs(sx) < abs(sy):
                out = 1 if x > 0 else -1
                X, Y, Z = [0, 0, -out], [0, 1, 0], [out, 0, 0]
                return "Block", [sy, sz, sx], pos, orientation(X, Y, Z)
            out = 1 if y > 0 else -1
            X, Y, Z = [out, 0, 0], [0, 1, 0], [0, 0, out]
            return "Block", [sx, sz, sy], pos, orientation(X, Y, Z)
        X, Y = ex, ez
        Z = cross(X, Y)
        return "Block", [sx, sz, sy], pos, orientation(X, Y, Z)
    if c["kind"] == "cyl":
        # Roblox cylinders run along X: X = the kit cylinder's axis (local z), Y = its local x
        X, Y = ez, ex
        Z = cross(X, Y)
        return "Cylinder", [sz, sx, sx], pos, orientation(X, Y, Z)
    return "Ball", [sx, sx, sx], pos, [0.0, 0.0, 0.0]


def key(c):
    return (c["name"], tuple(round(v, 3) for v in c["pos"]), tuple(round(v, 3) for v in c["size"]),
            tuple(round(v, 3) for v in c.get("rot", (0, 0, 0))))


def lua(v, ind=""):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        r = round(float(v), 4)
        return str(int(r)) if r == int(r) else repr(r)
    if isinstance(v, str):
        return '"' + v.replace('"', '\\"') + '"'
    if isinstance(v, (list, tuple)):
        if all(not isinstance(e, (dict, list, tuple)) for e in v):
            return "{ " + ", ".join(lua(e) for e in v) + " }"
        inner = ind + "\t"
        return "{\n" + "".join(f"{inner}{lua(e, inner)},\n" for e in v) + ind + "}"
    if isinstance(v, dict):
        inner = ind + "\t"
        items = "".join(f"{inner}{k} = {lua(e, inner)},\n" for k, e in v.items() if e is not None)
        return "{\n" + items + ind + "}"
    raise TypeError(type(v))


def export(base_id, game_dir):
    layout = f"_{base_id}_layout"
    full = load(layout, 4)
    floors = 4
    parts = []
    for f in range(1, floors + 1):
        top = {key(c): c for c in load(layout, f).COLLIDERS if c["floor"] == f}
        mid = {key(c): c for c in load(layout, 4).COLLIDERS if c["floor"] == f} if f < floors else {}
        names = []
        # a name in both variants with different geometry (the top floor's taller turret wall): suffix each one
        both = {c["name"] for c in top.values()} & {c["name"] for k, c in mid.items() if k not in top}
        for k, c in list(top.items()) + [(k, c) for k, c in mid.items() if k not in top]:
            if c["name"] in KEPT_MOVED or c["name"] in KEPT_STILL or c["name"] in FROM_JAR:
                continue
            show = None
            if f < floors and k in top and k not in mid:
                show = "top"
            elif k in mid and k not in top:
                show = "covered"
            shape, size, pos, rot = part_frame(c)
            collide = c.get("collide", True)
            look = ROLE_LOOK.get(c["role"], ((168, 148, 110), "Metal"))
            name = c["name"]
            if show and name in both:
                name = f"{name}_{'Top' if show == 'top' else 'Mid'}"
            assert name not in names, f"duplicate part name {name} on floor {f}"
            names.append(name)
            parts.append({"name": name, "floor": f, "role": c["role"], "shape": shape,
                          "size": [round(v, 4) for v in size], "pos": pos, "rot": rot, "collide": collide,
                          "show": show, "color": list(look[0]), "material": look[1]})
    spots = {}
    for c in full.COLLIDERS:
        if c["name"] in KEPT_MOVED:
            shape, size, pos, rot = part_frame(c)
            spots[c["name"]] = {"pos": pos, "size": [round(v, 4) for v in size]}
    bridge = getattr(full, "BRIDGE", None)
    if "Bridge" not in spots and bridge:
        # a layout that gives the bridge as {width, from, to} (plot z of its ends): a plank 0.6 thick on the plot floor
        z0, z1 = bridge["from"], bridge["to"]
        spots["Bridge"] = {"pos": [0.0, 1.0, round((z0 + z1) / 2, 4)], "size": [bridge["width"], 0.6, round(abs(z1 - z0), 4)]}
    # pad yaw: the layouts use the game's convention already (WorldLayout.padYaw: 90 - the pad's plot angle)
    pads = [{"j": p["j"], "x": round(p["x"], 4), "z": round(p["y"], 4), "yaw": round(p.get("yaw", 0.0), 4)}
            for p in sorted(full.PADS, key=lambda p: p["j"])]
    ramps = []
    for r in full.RAMPS:
        if r["kind"] == "line":
            (ax, ay, az), (bx, by, bz) = r["a"], r["b"]
            ramps.append({"kind": "line", "name": r["name"], "a": [ax, az, ay], "b": [bx, bz, by], "width": r["width"]})
        else:
            # a helix round plot-local centre c (x, z): walking surface from radius r_in to r_out, rising `rise` from
            # y0 over `sweep` degrees from angle a0
            ramps.append({"kind": "helix", "name": r["name"], "c": [r["c"][0], r["c"][1]], "r_in": r["r_in"],
                          "r_out": r["r_out"], "a0": r["a0"], "sweep": r["sweep"], "y0": r["z0"], "rise": r["rise"]})
    ex = full.EXIT
    hx, hy, hz = ex["hatch"]
    lx, ly = ex["lands"]
    inside = getattr(full, "INSIDE", None) or {"kind": "box", "half": full.IN + full.WALL / 2}
    landings = [{"y": g["z"], "x": g["x"], "z": g["y"]} for g in getattr(full, "LANDINGS", [])]
    data = {
        "id": base_id,
        "name": full.NAME,
        "pads": pads,
        "door": {"x": full.DOOR["x"], "z": full.DOOR["y"], "width": full.DOOR["width"],
                 "height": full.DOOR["height"]},
        "vat": [full.VAT["x"], full.VAT["y"]],
        "lockButton": [full.LOCK_BUTTON["x"], full.LOCK_BUTTON["y"]],
        "spawn": [full.SPAWN[0], full.SPAWN[1]],
        "spots": spots,
        "exit": {"hatch": [hx, hz, hy], "lands": [lx, ly]},
        "inside": inside,
        "ramps": ramps,
        "landings": landings,
        "parts": parts,
    }
    name = "".join(w.capitalize() for w in base_id.split("_"))
    out_dir = os.path.join(game_dir, "src", "visuals", "shared", "BaseShapeData")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{name}.luau")
    head = (f"--!strict\n-- Generated by shared/modeling-kit/tools/export_base_shape.py from models/{layout}.py: do not edit"
            " by hand.\n-- The {name} base's numbers in plot-local axes (x right, y up, z back; the door at -z), see"
            " BaseShapes.\n").replace("{name}", full.NAME)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(head + "return " + lua(data) + "\n")
    # format like the rest of the game (CI runs stylua --check); run from the game dir so its rokit pin applies
    try:
        import subprocess
        subprocess.run(["stylua", path], cwd=game_dir, check=False, capture_output=True)
    except OSError:
        print("stylua not found: run `stylua` on the file before committing")
    print(f"wrote {path}: {len(parts)} parts, {len(pads)} pads, {len(ramps)} ramps")


if __name__ == "__main__":
    export(sys.argv[1], sys.argv[2])
