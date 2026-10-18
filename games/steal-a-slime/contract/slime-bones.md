# 31. Slime bones: the species meshes move on the client

**Status:** contract first. Client only (`src/ui`): no remote, no State field, no save, no flag, no new Instances. Nothing replicates; the server never reads a Bone.

A species mesh (§30) is a rigged Model: `SlimeMesh` clones its MeshPart as the slime's `"Mesh"` part and keeps its `Bone` children. The rig comes from `shared/modeling-kit/models/_slimerig.py` (see `models/pool/POOL.md`, "Animation"); the reference motion is `kit/bl_slime_anim.py` (`pose_at`, `secondary`).

## Bones the client drives (by name)

| bone | role | motion |
|---|---|---|
| `Root` | foot | not written (the SkinRoot Motor6D already lifts, turns and tilts the whole slime) |
| `Top` | mid-body up | moves down by the squash (`(1 - sy) * H`), tilts a little (wobble, lagging the hop) |
| `SideL` `SideR` `SideF` `SideB` | sides | push out by `0.55 * squash` and down by `0.3 * squash`, so the jelly keeps its volume |
| `Eyes` | open eyes | blink: into the body by `0.13 * scale / eyeShare` studs |
| `Lids` | hidden closed-eye arcs | blink: out of the body by `0.165 * scale / eyeShare` studs |
| `Wing*` `Ear*` `Ant*` `Tail*` `Fin*` `Pec*` `Tent*` `Ribbon*` `Band*` `Flame*` | one per accessory | presets by name prefix (below) |

- `H` = body height from the rig itself: the `Top` bone sits at `0.45 H` above `Root`. `scale` = `Mesh.Size.Y / Mesh.MeshSize.Y` (1 when unknown). `eyeShare` = the mesh's `EyeShare` attribute when set, else `SlimeBones.EYE_SHARE`.
- Directions come from each bone's rest position in the Mesh's own space (Y up): a side pushes along its horizontal offset from the axis, the eyes go in and the lids come out along the `Eyes` / `Lids` horizontal offset (the face side). So `MeshAssets.IMPORT_YAW` and the FBX axis swap need no special case: only "Y is up" is assumed.
- `Bone.Transform` is in the bone's own space. At attach the client composes each bone's rest frame (its `CFrame` chain up to the Mesh) and turns every Mesh-space move and axis into that frame once; per frame it only builds the CFrame.
- Blink: every `BLINK_EVERY` (random in the range) for `BLINK_TIME` s; the eyes stay closed (happy `^^`) through the middle of a hop's air time.

### Accessory presets (angle about a Mesh-space axis at the bone's pivot)

`outward` = the bone's horizontal offset from the axis, `tang = up x outward` (so a left and a right part mirror each other), `phase = atan2` of that offset.

| prefix | axis | angle |
|---|---|---|
| `Wing` | tang | `(28 + 10 * air)` deg x `sin(4 Hz)`: flap |
| `Ear` | tang | `(10 + 14 * air)` deg x `sin(1.3 Hz - 0.8)`: flop |
| `Ant` | tang + 0.6 front | `14` deg x `sin(2 Hz + phase)`: wiggle |
| `Tail` | up | `22` deg x `sin(2 Hz + 1.5 phase)`: wag, each tail its own phase |
| `Fin` `Pec` | tang | `12` deg x `sin(1.6 Hz + phase)`: sway |
| `Tent` `Ribbon` `Band` `Flame` | tang | `16` deg x `sin(1.5 Hz + 2 phase)`: sway |

`air` = 1 while the slime is in the air during a hop, else 0. Other bone names are left alone.

## Wiring (`ui/SlimeBones`, `ui/SlimeMotor`, `ui/SlimeLifeRunner`)

- `SlimeBones` is pure apart from CFrame / Vector3 at call time: `kind(name)`, `preset(name)`, `body(sy, H)`, `tilt(params, t, hopDt)`, `blink(now, blinkAt, hopDt)`, `accessory(preset, t, phase, air)` return numbers; `attach(mesh, now, rand)`, `step`, `squish`, `park`, `release` drive a rig.
- `SlimeMotor.attach` attaches `SlimeBones` when the `"Mesh"` MeshPart has Bones. A boned slime then **does not change the Mesh's Size** (no `LifeSkinSize` attribute either): the squash and stretch of the breathing and of SlimeLife's hops (anticipation, stretch, landing squash) go through `Top` / `Side*` instead, so they don't double up. The SkinRoot / FaceRoot Transform keeps the hop lift, look yaw and wobble tilt, without the squashed-centre drop.
- LOD (`SlimeLod`, `SlimeLife.MAX_ACTIVE` and on-screen cull unchanged): near = full bone pose every frame; mid = body squash only on the mid frames (eyes and accessories put back to rest once); far = every Transform reset once, then skipped.
- Release (the slime leaves the active set, changes State, despawns, is removed): every Transform back to identity. `SlimeBones` makes no connections and no Instances, so `release` is its whole cleanup; it rides the runner's one RenderStepped loop.
- Cost: bone lists, rest frames, directions and axes are cached per rig at attach; a frame allocates no tables, only the CFrames it writes (one per driven bone, at most `MAX_ACTIVE` near slimes).
- Not driven: the uploaded-animation path (`"anim"`, `FEATURES.SlimeAnimations`) and the unrigged `"weld"` path keep their Size squash.
