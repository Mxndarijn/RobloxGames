# slime_fountain_split: the shipped slime_fountain.fbx cut into 5 pieces (FEATURES.FountainSplit, option (a) of the
# fountain collision choice: one PreciseConvexDecomposition mesh per tower piece).
#
#   blender -b --python models/slime_fountain_split.py            (from the kit root; ~/.local/bin/blender)
#
# NOT a generator: it imports out/slime_fountain.fbx, so the geometry is exactly what the game draws today. Faces are
# partitioned (no re-meshing, no new faces, no cap): each face goes to one piece, normals (custom split normals) and
# vertex colours stay as they are, so the assembled pieces draw the original. Tower pieces are cut by face-centroid
# height at the silo profile rings of models/slime_fountain.py (silo: wall + plinth + its drips; eave: z 30.0..31.3;
# dome: the red shoulder up to 35.9; basin: the rim, the basin floor and the goo crown above 35.9). The metaball goo crown
# is one connected mesh that runs down the staves, so its faces are banded the same way (a cut through a drip
# leaves two open edges with coincident vertices; no gap is visible). Everything that is not the silo shell or the
# goo crown (slide trough, slide goo, supports) is the "slide" piece: decor only, the slide keeps SlideColliders.
#
# Every piece keeps the original's frame (origin included). Roblox centres a MeshPart on its bbox, so each piece is
# placed at (original bbox centre + offset); offset = piece bbox centre - original bbox centre, written to
# out/fountain_split.json in kit axes and in Roblox slot axes (X, Y, Z) = (kit x, kit z, -kit y), the same convention
# as FOUNTAIN_EMERGE_OFFSET (models/FOUNTAIN_SIZES.md; MeshAssets.IMPORT_YAW turns it with the slot).
import json, math, os, sys
import bmesh, bpy
from mathutils import Vector

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(KIT, "out", "slime_fountain.fbx")
OUT = os.path.join(KIT, "out")

# Silo profile heights (models/slime_fountain.py): WALL_TOP, Z0 = WALL_TOP + 1.3, and the 90 deg shoulder ring.
Z_EAVE, Z_DOME, Z_BASIN = 30.0, 31.3, 35.9
PIECES = ["basin", "dome", "eave", "silo", "slide"]  # collision: PCD for the first four, none for slide
EXPORT = dict(use_selection=True, object_types={"MESH"}, use_mesh_modifiers=True, apply_scale_options="FBX_SCALE_UNITS",
              axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE", colors_type="SRGB", add_leaf_bones=False,
              bake_anim=False)


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)  # default axes (-Z forward, Y up) = the exporter's: back in kit space
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    assert len(objs) == 1, objs
    return objs[0]


def tri_count(me):
    return sum(max(1, len(p.vertices) - 2) for p in me.polygons)


def bbox(me):
    xs = [v.co for v in me.vertices]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    return lo, hi


def components(bm):
    seen, comps = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, comp = [f], []
        seen.add(f.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        comps.append(comp)
    return comps


def band(z):
    return "silo" if z < Z_EAVE else "eave" if z < Z_DOME else "dome" if z < Z_BASIN else "basin"


def assign(me):
    """piece name per polygon index."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    comps = sorted(components(bm), key=len, reverse=True)
    # the two tower comps: the goo crown (highest top) and the silo shell (lowest centroid spread / axis)
    crown = max(comps[:3], key=lambda c: max(v.co.z for f in c for v in f.verts))
    silo = next(c for c in comps[:3] if c is not crown and max(v.co.z for f in c for v in f.verts) < 37.5
                and min(v.co.z for f in c for v in f.verts) < 0.01 and len(c) > 1000)
    assert len(crown) > 1000 and len(silo) > 1000, (len(crown), len(silo))
    # the silo shell is a surface of revolution: every vertex is on one of the profile radii of the axis; the
    # slide trough (comps[2] there) has the same z span, so tell them apart by the shell's closed bottom fan
    tower = {f.index for f in crown} | {f.index for f in silo}
    out = []
    for f in bm.faces:
        z = sum(v.co.z for v in f.verts) / len(f.verts)
        out.append(band(z) if f.index in tower else "slide")
    bm.free()
    return out


def piece_object(src, keep, name):
    """keep[i]: polygon i goes to this piece. Deleting the others leaves the cut edges' vertex normals to be
    recomputed from the kept faces only, so the source's corner normals are written back as custom normals."""
    me = src.data.copy()
    src_n = src.data.corner_normals
    normals = [src_n[li].vector.copy() for p in src.data.polygons if keep[p.index] for li in p.loop_indices]
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    drop = [f for f in bm.faces if not keep[f.index]]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()
    assert len(normals) == len(me.loops), (len(normals), len(me.loops))
    me.normals_split_custom_set(normals)
    return o


def corners(o):
    """multiset of (position, loop normal, colour) per corner, rounded, to compare the pieces with the source."""
    me = o.data
    col = me.color_attributes["Col"]
    n = me.corner_normals
    out = []
    for p in me.polygons:
        for li in p.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            c = col.data[li].color if col.domain == "CORNER" else col.data[me.loops[li].vertex_index].color
            out.append((tuple(round(x, 3) for x in v), tuple(n[li].vector),
                        tuple(round(x, 3) for x in c)))
    return out


def check_corners(want, got, what, tol=0.02):
    """same corners (position, colour exact to 1e-3; normals within `tol`: custom normals are stored quantised)."""
    assert len(want) == len(got), (what, len(want), len(got))
    bucket = {}
    for pos, n, c in want:
        bucket.setdefault((pos, c), []).append(n)
    worst = 0.0
    for pos, n, c in got:
        cands = bucket.get((pos, c))
        assert cands, (what, "no corner at", pos, c)
        d, i = min((max(abs(a - b) for a, b in zip(n, m)), i) for i, m in enumerate(cands))
        worst = max(worst, d)
        assert d <= tol, (what, pos, n, cands)
        cands.pop(i)
    print(f"corners {what}: {len(got)} match, worst normal diff {worst:.4f}")


def export(o, path):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.fbx(filepath=path, **EXPORT)


def main():
    src = load(SRC)
    me = src.data
    lo0, hi0 = bbox(me)
    c0 = (lo0 + hi0) / 2
    tris0 = tri_count(me)
    names = assign(me)
    pieces, res = {}, {}
    for name in PIECES:
        keep = [n == name for n in names]
        pieces[name] = piece_object(src, keep, f"fountain_split_{name}")
    mats = [mat.name for mat in me.materials]
    for name, o in pieces.items():
        o.data.materials.clear()
        for m in me.materials:
            o.data.materials.append(m)
        o.data.color_attributes.active_color = o.data.color_attributes["Col"]
        lo, hi = bbox(o.data)
        c, size = (lo + hi) / 2, hi - lo
        d = c - c0  # kit axes
        t = tri_count(o.data)
        res[name] = {
            "tris": t, "faces": len(o.data.polygons), "verts": len(o.data.vertices),
            "bbox_kit": [[round(x, 4) for x in lo], [round(x, 4) for x in hi]],
            "size_roblox": [round(size.x, 3), round(size.z, 3), round(size.y, 3)],  # (X, Y up, Z) = (kit x, z, y)
            "offset_kit": [round(x, 3) for x in d],
            "offset_roblox": [round(d.x, 3), round(d.z, 3), round(-d.y, 3)],  # (kit x, kit z, -kit y)
        }
    assert sum(r["tris"] for r in res.values()) == tris0, (res, tris0)
    assert sum(r["faces"] for r in res.values()) == len(me.polygons)
    # assembled bbox == original bbox
    alo = Vector((min(r["bbox_kit"][0][i] for r in res.values()) for i in range(3)))
    ahi = Vector((max(r["bbox_kit"][1][i] for r in res.values()) for i in range(3)))
    assert (alo - lo0).length < 1e-3 and (ahi - hi0).length < 1e-3, (alo, lo0, ahi, hi0)
    # corner multiset (position, normal, colour) of the pieces == the source's
    check_corners(corners(src), [c for o in pieces.values() for c in corners(o)], "pieces vs source")
    for name, o in pieces.items():
        path = os.path.join(OUT, f"fountain_split_{name}.fbx")
        export(o, path)
        r = res[name]
        stats = {"name": f"fountain_split_{name}", "source": "out/slime_fountain.fbx (models/slime_fountain_split.py)",
                 "tris": r["tris"], "size_studs": r["size_roblox"], "offset_roblox": r["offset_roblox"],
                 "units": "1 Blender unit = 1 stud; size_studs is Roblox [X, Y(up), Z]", "pass": True, "fails": [],
                 "warnings": [], "fbx_bytes": os.path.getsize(path)}
        json.dump(stats, open(os.path.join(OUT, f"fountain_split_{name}.stats.json"), "w"), indent=2)
    roundtrip = []
    for name in PIECES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, f"fountain_split_{name}.fbx"))
        roundtrip += corners([o for o in bpy.context.scene.objects if o.type == "MESH"][0])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=SRC)
    check_corners(corners([o for o in bpy.context.scene.objects if o.type == "MESH"][0]), roundtrip, "exported FBX vs source")
    summary = {
        "source": "out/slime_fountain.fbx", "tris": tris0,
        "size_roblox": [round(hi0.x - lo0.x, 3), round(hi0.z - lo0.z, 3), round(hi0.y - lo0.y, 3)],
        "cuts_z": {"eave": Z_EAVE, "dome": Z_DOME, "basin": Z_BASIN},
        "offset_convention": "piece bbox centre - original bbox centre; Roblox slot axes (kit x, kit z, -kit y); "
                             "rotate with the fountain (MeshSwap applies MeshAssets.IMPORT_YAW to the mesh, not the offset)",
        "pieces": res,
    }
    json.dump(summary, open(os.path.join(OUT, "fountain_split.json"), "w"), indent=2)
    print(json.dumps({k: (v["tris"], v["size_roblox"], v["offset_roblox"]) for k, v in res.items()}, indent=1))
    print("OK sum tris", tris0, "materials", mats)


main()
