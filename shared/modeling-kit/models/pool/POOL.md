# Slime pool (concept, 2026-10-18)

A new set of slimes for Steal a Slime where every species looks different. Lineup:
`sheets/pool/slime_pool.png` (made by `tools/slime_pool_sheet.py`). Pitches: `roster.json`.

## Why the old slimes all looked alike
51 roster types shared **7 meshes** (`slime_base`, `_ears`, `_horns`, `_wobble` + leaf/crown/crystal),
and the type was told apart only by `MeshPart.Color`. The tint multiplies the vertex colours,
so a body can hold one hue and nothing else: no patterns, no two-tone belly, no coloured
accessories on the body. Faces came from 5 shared expressions picked by random genome eyes/mouth,
so a "Licorice Bull" and a "Pudding Slime" had the same face.

## The new approach
- **One species = one fully coloured mesh** (body, pattern, accessories, face). `MeshPart.Color`
  stays white, so the vertex colours show as painted. 32 species = 32 mesh assets.
- **Shape first**: bodies differ (round ball, wide mochi, boxy cube, tall ghost, flame top, rock
  lumps), then silhouette accessories (fins, ears, wings, horns, crown, ring), then pattern
  (bands, spots, stripes, belly), then face.
- **Rarity reads from the look**: commons are simple single-idea slimes; epic and up get bold
  silhouettes and more parts; mythic/secret get glow colours and floating/orbiting parts.
- Builder: `models/_slimepool.py` (Body with profile/bumps/bands/sectors, projected decals,
  face kit with 20 eye kinds and 16 mouth kinds, accessory primitives, metaball goo).

## Emotions: personality instead of random faces
Each species has a **signature face** that fits its character (Chomp's tooth grin, Pebble's
grumpy unibrow, Bumble's shades, Seraph's serene closed eyes). It is baked into the mesh.
Proposal for the "alive" feeling, cheap and readable at play distance:
- **Emote bubbles** above the slime for state changes: heart (fed / placed on its favourite pad),
  "!" (being stolen), sweat drop (carried by a thief), "Zzz" (night), anger mark (stolen back).
  One BillboardGui or small sprite per event, no extra meshes.
- **Squash and hop** stay procedural (VisualsClient), now on the species mesh.
- The genome `Eyes` / `Mouth` traits no longer pick the face. They can be dropped or reused as
  cosmetic "variants" later.

## Integration notes (game side, Phoenix owns it; nothing changed in the game yet)
- `SlimeLooks.get(id).kit` -> the species mesh; `SlimeMesh` sets `Mesh.Color = white` and
  **hides the procedural eyes, mouth, cheeks and pattern parts** when a species mesh is worn.
- Mutations can no longer tint the body. Show them with material + effects instead: Gold = Foil
  material + sparkles, Glow = Neon outline/aura, Lava = ember particles, Galaxy = star particles.
- Save ids are permanent: map the new species to the old ids or add new ids through CONTRACT.md.
- Size: meshes are modelled 3 studs wide at size 1 (same frame as the old kit); `ship()` prints
  the size and the bbox centre from the slime's bottom centre (Roblox axes) for placement.
- Triangle budget: 2.3k-4.5k per species (one MeshPart each, RenderFidelity Automatic for LOD).

## Open check
- **Vertex colours in Studio are still unverified** for kit meshes (LESSONS.md). Before uploading
  32 meshes: upload one species, put it in Studio with Color white, compare with the render.

## Animation: what is possible (prototype in `models/_slimerig.py`, preview `tools/slime_anim.py`)
Today the game moves a slime as one rigid piece: Motor6D Transforms on FaceRoot / SkinRoot (hop, look
left/right, wobble) plus a Size change for the squash (`ui/SlimeMotor`, `ui/SlimeLife*`), or the four
uploaded KeyframeSequences. A one-mesh species can carry **bones inside the mesh** (skinned MeshPart).
`Bone.Transform` is scriptable like `Motor6D.Transform` (CFrame only: Roblox bones don't scale), so a
client driver can do all of this with no uploaded animations:

| motion | bones | how |
|---|---|---|
| breathing / idle squish | Top, SideL/R/F/B | Top moves down, the side bones push out: the jelly keeps its volume |
| wobble / jiggle | Top | small tilts, lagging the hop |
| hop with anticipation, stretch, landing squash | Root + Top + sides | Root lifts, Top stretches up in the air, squashes on landing |
| blink | Eyes, Lids | eyes slide into the body, closed lids hidden inside slide out (~0.13 s) |
| expression swaps (moods) | one bone per hidden face set | same trick as the blink: happy / scared / sleepy faces baked in, swapped by moving bones (~200-400 tris per extra face) |
| wings flap, ears flop, tail wag, antennae wiggle, fins, tentacles | one bone per accessory | presets by part name, phase-shifted per side |

Rig naming convention for species scripts (the rig reads part names): `Body`, face parts (`Eye*`,
`Mouth*`...), and animated accessories start with `Wing`, `Ear`, `Ant`, `Tail`, `Fin`, `Pec`, `Tent`,
`Ribbon`, `Band`. Paired parts get one bone per side; a part touching an animated part rides its bone.
Build with `SLIME_RIG=1` to get the armature (exported with the FBX, max 4 influences per vertex).

Not verified yet: a kit FBX with this armature uploaded and driven in Studio. The old `slime_*` bodies
shipped a 2-bone rig, but nothing in the game uses those bones. Load rigged species as a Model
(InsertService:LoadAsset, as SlimeMesh does), not via CreateMeshPartAsync.
Known rough spots: eyes on bumps (Froggo) get no blink lid; Lop's long goo ears clip at full squash.

## Library notes from the modelers (todo for `_slimepool.py`)
- `decal()` makes one flat face: decals wider than ~0.5 stud sink into curved bodies. Three agents wrote a
  grid-projected decal locally (`grid_decal` in moo/pengoo, `ddecal` in froggo, `proj_sheet` in
  ninja/robo); move one into the library.
- `Face.brows("angry")` / `("worried")` are swapped (the angle sign). Species that use them were tuned
  by eye, so check them when fixing.
- `Face.mustache()` leaves a zero-length edge (8 non-manifold edges after `finish()`).
- `crystal()` / `gem()` whiten every other facet too much; a 3-colour ramp looks better (amethyst).
- Wishes: rounded-top profile helper, per-ball colours in `goo()`, twisted `lathe()` for spiral stripes,
  `Body` per-face flat shading, a `shell()` for capes/ribbons, wing helper facing a given yaw.

## Merge-only hybrids and boss slimes (`hybrids.json`)
15 hybrids that never spawn: they only come out of the merge vat from a recipe (the `parents` are a
suggestion; the progression design decides the real recipes and tiers). They reuse their parents'
features so players can guess the recipe from the Dex silhouette. 3 boss slimes (`kind: "boss"`) are
huge event slimes; they are modelled in the same 3-stud frame and scaled up in game.
Lineup: `python tools/slime_pool_sheet.py --roster hybrids.json --title "Hybrids and bosses" --out sheets/pool/slime_hybrids.png`.
