# Roblox modeling kit

**Read `roblox-modeling-process.md`**: that is the official process (what the kit is, how a round works, timings, limits, the report-to-SuperBottie rule). The bot rules are in the kit's `CLAUDE.md`, and the flags and timings in its `README.md`.

Repo: `/workspace/roblox/modeling-kit` (local git, never pushed). Owner: Archer.

## Reference detail (not repeated elsewhere)
- **Scale proof**: 1 Blender unit = 1 stud. v17 `pad_trim` was modelled 9.4 BU wide and `uploaded.json` records `meshSize` 9.4.
- **v17 map rules when placing**: decor axis ≤ 64 studs, a collidable canopy needs its underside ≥ 7 studs up, MeshParts ≤ 150 per map.
- **Upload endpoints** (`upload.py`, dry run unless `--go`, needs Merijn's OK):
  - Create: `--go` → `POST /assets/v1/assets` (Model, creator userId 1040646178).
  - New version: `--go --update <assetId>` → `PATCH /assets/v1/assets/{id}`.
  - Both poll the operation and record the assetId in `uploaded.json`. `--size-check` then runs `/workspace/roblox/assets/tools/probe_meshids.py` (Luau Execution, loads the asset only) to read MeshId and Size.
  - The key comes from `ROBLOX_OPEN_CLOUD_API_KEY`. Only with `--go`, if it's unset, `~/.config/roblox-ci.env` is loaded into the process env. The key is never printed.
- **Engines**: EEVEE is about 31 s per render without a GPU; don't use it.
- **First result**: v17 `tree_oak` (164 tris) remade in 6 rounds to 1404 tris. See `sheets/tree_oak_{before,after,quick,after_robloxlook}.png` and `out/tree_oak.fbx`. Not uploaded.
