# Roblox asset uploads (Open Cloud Assets API) (2026-10-15)

Short how-to for uploading meshes from a game repo. Background, limits, verification and sourcing: [roblox-assets.md](roblox-assets.md). Making the meshes: [roblox-modeling-process.md](roblox-modeling-process.md).

## Prerequisites

- `ROBLOX_OPEN_CLOUD_API_KEY` with scopes **`asset:read` + `asset:write`** (never print it). Reading inner mesh ids also needs `universe.place.luau-execution-session:write`.
- Creator = owner of the experience: `ROBLOX_CREATOR_USER_ID=1040646178` (Mxndarijn) or `ROBLOX_CREATOR_GROUP_ID`.
- Merijn's OK before `--go`: every upload is a permanent, moderated asset (quota 200 / 30 days).

## Flow

`assets/upload.py` is on the v17+ steal-a-slime branches (e.g. `/workspace/roblox/wt-v23-ui/assets/upload.py`), not yet in `RobloxGames` main or `steal-a-slime-b0`.

```sh
cd games/steal-a-slime                          # your worktree
python3 assets/upload.py                        # dry run: lists assets/meshes/*.fbx not yet in uploaded.json
python3 assets/upload.py --go rock_a            # upload named meshes (max 10 per run, <= 20 MB each)
python3 /workspace/roblox/assets/tools/probe_meshids.py assets/uploaded.json   # inner meshId + meshSize via Luau Execution
lune run src/visuals/tools/gen-mesh-assets.luau        # regenerate src/visuals/shared/MeshAssets.luau
lune run src/visuals/tools/gen-mesh-assets.luau check  # exit 1 if stale (check-map runs this)
```

What `upload.py` does:

1. `POST https://apis.roblox.com/assets/v1/assets` (multipart: `request` JSON with `assetType: "Model"` + `fileContent` as `model/fbx`).
2. Gets an operation and polls `GET /assets/v1/operations/<id>` until `done`; `response.assetId` is the Model id.
3. Writes it to `assets/uploaded.json` (names already there are skipped).

The ids module is generated, never hand-edited: `gen-mesh-assets.luau` turns `uploaded.json` into `MeshAssets.luau` (meshId, meshSize, center). Commit `uploaded.json` and the generated module together. Don't use an asset until moderation is `Approved` (`GET /assets/v1/assets/<id>?readMask=moderationResult,state`).

## Prefer FBX

Only `.fbx` Model assets can be updated in place: a revision becomes a new **version of the same asset id**, so code and `MeshAssets.luau` keep working. glTF/OBJ revisions need a new upload, which means a new id and regenerated ids. FBX also keeps vertex colours (OBJ doesn't).

Model id vs mesh id: the upload returns a Model (package) id. `MeshPart.MeshId` needs the inner mesh id (`meshId` from the probe).
