#!/usr/bin/env python3
"""PR gate budget check (stdlib only).

Usage: budget_check.py COUNTS_JSON BUDGETS_JSON FBX_DIR SHARED_BUDGETS_JSON

COUNTS_JSON comes from budget_counts.luau (mesh slots per kit mesh, parts).
Triangles per mesh are read from FBX_DIR/<name>.fbx (binary FBX 7.x, the
modeling kit's output); world triangles = sum(slots * tris). Exit 1 when any
limit is exceeded or a counted mesh has no FBX.

world_triangles (FAIL) and mesh_parts (SOFT: warns, never fails) come from SHARED_BUDGETS_JSON =
tools/pipeline/pc-watcher/budgets.json, the single source also read by the watcher and the runtime gate;
BUDGETS_JSON keeps only the build-time limits (parts, border parts, max triangles per mesh).
"""

import json
import os
import struct
import sys
import zlib
from pathlib import Path


def fbx_triangles(path: Path) -> int:
    """Triangles in every Geometry of a binary FBX (n-gon of n verts = n-2)."""
    data = path.read_bytes()
    if not data.startswith(b"Kaydara FBX Binary  \x00"):
        raise ValueError(f"{path}: not a binary FBX")
    version = struct.unpack_from("<I", data, 23)[0]
    wide = version >= 7500  # 64-bit node header fields
    hdr = "<QQQ" if wide else "<III"
    hdr_len = 25 if wide else 13
    tris = 0

    def read_array(off: int, code: str):
        n, enc, clen = struct.unpack_from("<III", data, off)
        off += 12
        raw = data[off : off + clen]
        if enc == 1:
            raw = zlib.decompress(raw)
        fmt = {"i": "i", "l": "q", "f": "f", "d": "d", "b": "?"}[code]
        return list(struct.unpack(f"<{n}{fmt}", raw)), off + clen

    def skip_prop(off: int) -> int:
        code = chr(data[off])
        off += 1
        size = {"Y": 2, "C": 1, "I": 4, "F": 4, "D": 8, "L": 8}.get(code)
        if size is not None:
            return off + size
        if code in "ifdlb":
            _, _, clen = struct.unpack_from("<III", data, off)
            return off + 12 + clen
        if code in "SR":
            (ln,) = struct.unpack_from("<I", data, off)
            return off + 4 + ln
        raise ValueError(f"{path}: unknown FBX property type {code!r}")

    def walk(off: int, end: int, in_geometry: bool):
        nonlocal tris
        while off < end:
            end_off, nprops, plen = struct.unpack_from(hdr, data, off)
            if end_off == 0:
                return
            nlen = data[off + hdr_len - 1]
            name = data[off + hdr_len : off + hdr_len + nlen].decode("ascii", "replace")
            p = off + hdr_len + nlen
            props_start = p
            if in_geometry and name == "PolygonVertexIndex" and nprops == 1 and chr(data[p]) == "i":
                idx, _ = read_array(p + 1, "i")
                count = 0
                for v in idx:
                    count += 1
                    if v < 0:  # last vertex of a polygon is stored as ~index
                        tris += max(count - 2, 0)
                        count = 0
            p = props_start + plen
            if p < end_off:
                walk(p, end_off, in_geometry or name == "Geometry")
            off = end_off

    walk(27, len(data), False)
    return tris


def main() -> int:
    counts = json.loads(Path(sys.argv[1]).read_text())
    budgets = json.loads(Path(sys.argv[2]).read_text())
    fbx_dir = Path(sys.argv[3])
    limits = dict(budgets["limits"])
    shared = json.loads(Path(sys.argv[4]).read_text())
    limits["world_triangles"] = shared["world_triangles"]["fail"]
    mesh_soft = shared["mesh_parts"]["warn"]

    tris_per_mesh = {}
    missing = []
    for name in sorted(counts["meshes"]):
        fbx = fbx_dir / f"{name}.fbx"
        if fbx.is_file():
            tris_per_mesh[name] = fbx_triangles(fbx)
        else:
            missing.append(name)
    world_tris = sum(counts["meshes"][n] * t for n, t in tris_per_mesh.items())
    worst = max(tris_per_mesh.items(), key=lambda kv: kv[1], default=("-", 0))

    rows = [
        ("parts", counts["parts"], limits["parts"]),
        ("border_parts", counts["border_parts"], limits["border_parts"]),
        ("world_triangles", world_tris, limits["world_triangles"]),
        (f"max_triangles_per_mesh ({worst[0]})", worst[1], limits["max_triangles_per_mesh"]),
    ]
    failed = False
    mesh_slots = counts["mesh_slots"]
    print(f"  {'budget':<46} {'current':>9} {'limit':>9}  use")
    for label, value, limit in rows:
        ok = value <= limit
        failed |= not ok
        print(f"  {label:<46} {value:>9} {limit:>9}  {100 * value / limit:5.1f}% {'ok' if ok else 'OVER'}")
    warn = mesh_slots > mesh_soft
    print(
        f"  {'mesh_slots (MeshParts, SOFT)':<46} {mesh_slots:>9} {mesh_soft:>9}  {100 * mesh_slots / mesh_soft:5.1f}% "
        f"{'WARN' if warn else 'ok'}"
    )
    if warn:
        msg = f"MeshParts {mesh_slots} > soft budget {mesh_soft} (never fails; limits are world triangles and unique meshes)"
        print(f"  WARN: {msg}")
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::warning::budget: {msg}")
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as fh:
                fh.write(f"- :warning: budget: {msg}\n")
    if missing:
        failed = True
        print(f"  FAIL: no FBX in {fbx_dir} for counted meshes (triangles unknown): {', '.join(missing)}")

    # The game's own constants must not drift above the gate's limits.
    src = counts.get("source_budgets", {})
    for key, gate_key in (("PART_BUDGET", "parts"), ("BORDER_PART_BUDGET", "border_parts")):
        if key in src and src[key] > limits[gate_key]:
            failed = True
            print(f"  FAIL: WorldLayout.{key} = {src[key]} is above budgets.json {gate_key} = {limits[gate_key]}")
    # The soft MeshPart constant mirrors the shared file; a drift would be a second, silent number.
    if "MESH_SLOT_BUDGET" in src and src["MESH_SLOT_BUDGET"] != mesh_soft:
        failed = True
        print(f"  FAIL: WorldLayout.MESH_SLOT_BUDGET = {src['MESH_SLOT_BUDGET']} differs from budgets.json mesh_parts.warn = {mesh_soft}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
