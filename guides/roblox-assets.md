# Roblox 3D assets via Open Cloud (headless, Linux)

> **Restored 2026-10-15 from workspace notes after /guides loss; verify.** Sections "Prerequisites" through "Security checklist" are the original text (2026-10-14 21:13Z), recovered from a Claude Code transcript. "Sourcing and strategy" at the end is new and summarises `/workspace/roblox/3d-assets-research.md` and `/workspace/roblox/graphics-strategy.md`.

How bots upload a mesh (FBX/glTF/glb) to Roblox without Studio, and how a Rojo game uses it.
First proven 2026-10-14 with `/workspace/roblox/assets/slime.fbx` → asset **103340234939607**.
Related: [roblox-toolchain-linux.md](roblox-toolchain-linux.md) (build and publish places). Background research: `/workspace/roblox/3d-assets-research.md`.

## Prerequisites
- Open Cloud API key in `ROBLOX_OPEN_CLOUD_API_KEY` (e.g. `export ROBLOX_OPEN_CLOUD_API_KEY=...`). **Never print, commit or log it**, and never use `set -x`. Python reads it from `os.environ`, so it never shows up in argv or `ps`.
- Scopes: `asset:read` and `asset:write` (Assets API). Optional extras:
  - `legacy-asset:manage`: download content through the Asset Delivery API.
  - `universe.place.luau-execution-session:write`: run Luau in a test place.
  - Today's key has **neither** extra (see Verification).
  - *[restore note, 2026-10-15]:* `universe.place.luau-execution-session:write` was granted around 09:20 on 2026-10-15 (see `roblox-live-testing.md`). Whether the key has `legacy-asset:manage`: TODO, unverified. Whether `InsertService:LoadAsset(103340234939607)` has been run through Luau Execution since: TODO, not found in notes. The live-testing guide does record that `LoadAsset` works in a task (SlimeLook came back `Mesh`).
- Python 3 with `requests`.
- The mesh must be ≤ 20,000 triangles per mesh, ≤ 20 MB per upload, quads/tris (no n-gons) and one UV set. Use FBX or glTF/glb if you need vertex colours (OBJ loses them). Only `.fbx` Model assets can be updated in place later, which creates new versions.

## 1. Determine the creator (user vs group)
The asset's creator must be the owner of the experience that will use it. Find it without exposing the key:
```python
# POST the key to the introspection endpoint (the body is not logged); print only metadata
r = requests.post("https://apis.roblox.com/api-keys/v1/introspect", json={"apiKey": os.environ["ROBLOX_OPEN_CLOUD_API_KEY"]})
print(r.json()["authorizedUserId"], r.json()["scopes"])   # user-owned keys return authorizedUserId
# confirm who owns the universe
requests.get("https://apis.roblox.com/cloud/v2/universes/<UNIVERSE>", headers={"x-api-key": key}).json()["user"]  # or ["group"]
```
- Current key: user-owned, `authorizedUserId` **1040646178** (Mxndarijn).
- Test universe 10770917350 returns `user: users/1040646178`, so use `creator.userId`.
- For a group-owned game, use a group key and `creator.groupId`.
- The public games API showed "unknown creator" because the universe is private. The Open Cloud v2 universe endpoint shows the owner.

## 2. Upload and poll
Use the reusable script `/workspace/roblox/assets/tools/upload_asset.py`. It reads the key from the environment, never prints it, and scrubs it from the saved output.
```bash
cd /workspace/roblox/assets
python3 -I tools/upload_asset.py slime.fbx --user-id 1040646178 \
  --name "StealASlime Proof Slime" --desc "..." --out slime-upload-result.json
```
What the script does:
- Sends `POST https://apis.roblox.com/assets/v1/assets` as multipart with two parts:
  - `request` (JSON): `{"assetType":"Model","displayName":..,"description":..,"creationContext":{"creator":{"userId":"<id>"}}}`
  - `fileContent`: the file, content type `model/fbx`, `model/gltf-binary` or `model/gltf+json`.
- Gets back an operation (`{"path":"operations/<id>","done":false}`).
- Polls `GET https://apis.roblox.com/assets/v1/operations/<id>` with backoff until `done: true`. The `response` holds `assetId`, `state` and `moderationResult.moderationState`. If the operation has an `error`, the upload failed.
- Create is rate-limited to 120 requests/min per key owner. The endpoint is **Beta**.
- For the slime, the operation finished in a few seconds with `moderationState: Approved` and `state: Active`. The result is saved in `/workspace/roblox/assets/slime-upload-result.json`.

## 3. Moderation and status checks
- `GET https://apis.roblox.com/assets/v1/assets/<id>?readMask=moderationResult,state,assetType,displayName` returns the current state: `Reviewing`, `Approved` or `Rejected`.
- `GET .../assets/<id>/versions` lists the versions and the moderation result for each one.
- Don't use an asset in-game until it is `Approved`. Rejected assets render as nothing.

## 4. Verify without Studio (what works / what doesn't)
| Check | Result with current key |
|---|---|
| Assets API details / versions | ✅ Approved, Active, `published: true` |
| Public thumbnail render: `https://thumbnails.roblox.com/v1/assets?assetIds=<id>&size=420x420&format=Png` (poll until `state: Completed`, ~seconds) | ✅ **Best headless proof.** Roblox's renderer drew the slime green with eyes, upright, so the mesh imported and its colours survived. Saved at `/workspace/roblox/assets/slime-roblox-thumbnail.png`. |
| `economy.roblox.com/v2/assets/<id>/details` | ✅ AssetTypeId 10 (Model), Creator user 1040646178 |
| Download the package (.rbxm) to read MeshPart/MeshId: `apis.roblox.com/asset-delivery-api/v1/assetId/<id>` | ❌ 403 "Scope not authorized". Needs the `legacy-asset:manage` scope. Legacy `assetdelivery.roblox.com` also returns 403 with an API key. |
| Luau Execution (`InsertService:LoadAsset` in the test place) | ❌ 403: missing `universe.place.luau-execution-session:<universe>:write` |

With those two scopes added to the key, you can:
- Download the `.rbxm` and inspect it with Lune: `roblox.deserializeModel`, then list each MeshPart's `MeshId` and `Size`.
- Or POST this Luau to `https://apis.roblox.com/cloud/v2/universes/<U>/places/<P>/luau-execution-session-tasks`:
  ```lua
  local m = game:GetService("InsertService"):LoadAsset(<id>)
  local o = {}
  for _, d in m:GetDescendants() do
    table.insert(o, d.ClassName .. ":" .. d.Name .. (d:IsA("MeshPart") and (" MeshId=" .. d.MeshId) or ""))
  end
  return table.concat(o, "\n")
  ```
  Then poll the task. Running it doesn't publish anything.

## 5. Using it in a Rojo game
The upload gives you a **package/Model asset id** (a Model containing MeshPart(s)), not a bare mesh id.
- **Runtime, recommended for now.** In server code:
  ```lua
  local model = InsertService:LoadAsset(103340234939607)
  local slime = model:FindFirstChildWhichIsA("MeshPart", true)
  ```
  Then clone it, and set `Color`, `Size` and `Material` from the genome. `LoadAsset` only works in live servers, not in plain Lune/luau. It works for assets owned by the experience's creator, so user-owned asset + user-owned game is fine.
- **Build time.** To put a MeshPart directly in a Rojo project (`"MeshId": "rbxassetid://<meshId>"` in a `.model.json`), you need the inner **mesh** id from the package. Get it from the `.rbxm` or from Luau Execution (section 4), or have Merijn read it in Studio.
  - Scripts can't set `MeshPart.MeshId` at runtime. The runtime alternative is `AssetService:CreateMeshPartAsync(Content.fromUri("rbxassetid://<meshId>"))`.
  - Collision geometry for a Rojo-authored MeshId is untested. Prefer the runtime path.
- Publishing the place is a separate step (see the toolchain guide). Uploading an asset never publishes a place.

## Model vs Mesh asset type
- An Open Cloud upload with `assetType: "Model"` (what `upload_asset.py` and `assets/upload.py` send) returns a **Model** asset id: a package that wraps one or more MeshParts. That id is not a mesh.
- `MeshPart.MeshId` needs the **inner Mesh** id. `rbxassetid://<model id>` in a MeshId does not load.
- To find the inner id, run Luau Execution against the place: `InsertService:LoadAsset(<model id>)`, then list each descendant MeshPart's `MeshId` (and `Size`, which is the native size). `/workspace/roblox/assets/tools/probe_meshids.py <uploaded.json>` does this for every entry. It reads the key from the environment and only loads assets; nothing is published and no DataStore is touched.
- Store the result per asset in the game repo's `assets/uploaded.json` as `meshId` (digits only) next to `assetId` (the Model id), plus `meshSize`. In Steal a Slime, `lune run src/visuals/tools/gen-mesh-assets.luau` turns that file into `src/visuals/shared/MeshAssets.luau`, and `check-map` fails if a `meshSize` doesn't match the local OBJ.

## Security checklist
- The key is only ever in the env var and in the `x-api-key` header. No `echo`, no `set -x`, no key in files, PRs or guides.
- Saved responses are operation and asset JSON only, with no request headers. The script also replaces any accidental occurrence of the key.
- Upload only what you mean to: every upload is a permanent, moderated asset on the owner's account.

## Sourcing and strategy (summary)

Full detail, prices and sources: `/workspace/roblox/3d-assets-research.md` (2026-10-14) and `/workspace/roblox/graphics-strategy.md` (2026-10-15). Both are research only: nothing was bought or signed up for.

**Default pipeline:** procedural meshes made by a bot in headless Blender → FBX → Open Cloud Assets API (Model) → appearance set at runtime.
- It's $0, unattended and reproducible, and it's the only option that scales to the slime genome. Bodies and faces come from a small mesh library; `Color`, `Size` and `Material` are set at runtime, so ~20 assets cover thousands of combinations.
- Proof: `roblox/assets/tools/make_slime.py` produced a 1,816-triangle `slime.fbx` (9% of the limit), checked with `verify_mesh.py`. Run Blender with `blender -b --factory-startup -P make_slime.py -- <outdir>`.
- Quality gates before any upload: re-import and assert ≤ 20,000 tris per mesh, render a preview PNG for the PR, and Merijn's play-test is the final visual gate.

**Roblox limits:**
- ≤ 20,000 triangles per mesh, ≤ 20 MB per Open Cloud upload.
- Textures up to 4096² (1024² UV guidance). SurfaceAppearance PBR works on MeshParts only.
- Vertex colours survive FBX/glTF, not OBJ.
- `MeshPart.MeshId` can't be set by scripts; use `AssetService:CreateMeshPartAsync`.
- Upload quota per 30 days: 200 for ID-verified accounts, 10 for unverified ones.
- Performance: reuse one mesh ID (instancing), prefer built-in materials over custom textures, and avoid partial transparency.

**Asset sources, in licence order (graphics-strategy §1):**
1. **Kenney:** CC0, no account needed.
2. **Poly Pizza:** CC0 models only, or keep a `CREDITS.md` for CC-BY ones.
3. **Sketchfab:** CC0 search works without an account; downloading needs Merijn's token. Avoid `-nc` and Editorial licences.
4. **Creator Store:** only assets Merijn hand-picks. Strip scripts (`require(<id>)`, `loadstring`, `getfenv`, `InsertService:LoadAsset`, obfuscated code).

**Quaternius:** commercial use is fine, but no redistribution. Keep uploaded meshes Restricted, never Open Use.

**AI generation** is for one-off hero props only (volcano, merge vat), not genome slimes:
- Try Roblox Cube / Assistant `/generate_mesh` in Studio first; it appears to be free (unverified).
- If paying: Tripo Pro ($20/mo) by hand, or Meshy Pro ($20/mo) if a bot needs an API.
- Rodin/Hyper3D: skip (the API needs the $120/mo plan).

**Graphics plan (graphics-strategy §6):**
1. Lighting pass.
2. Atmosphere and post effects.
3. Palette and materials.
4. Blender hero meshes.
5. Kenney decor.
6. Slime mesh library.
7. Cube hero prop.
8. MaterialVariants.
9. Paid AI, only if needed.

Items 1–3 cost no assets and were committed in steal-a-slime-b0 as `21a48b5`, unpublished at the time (`live-testing/cc5.log`). `Lighting.Technology` can't be set by scripts: it goes in `default.project.json`, or Merijn sets it once in Studio.

**Art-bot verdict:** not yet. Give the builder bot an "art skill" instead: patch → `export.luau` + `render_graphics.py` → before/after PNGs in the PR → mesh upload. Revisit once mesh upload is proven and the need is more than ~20 assets a week.

**Open questions (need Merijn or Studio):**
- Do the vertex colours and scale survive an Open Cloud Model upload in-game?
- Can Rojo-built parts reuse the inner MeshId?
- Does group-owned upload behave the same?
