# Slime meshes (models-v2, 2026-10-15)

New slime look for Steal a Slime, inspired by the *feel* of Slime Rancher (glossy gumdrop blobs, big
shiny eyes, soft highlights), with its own shapes. No Slime Rancher names or designs are copied.
Built with `models/_slime.py`; lineups: `sheets/slimes_lineup.png` (studio light) and
`sheets/slimes_lineup_robloxlook.png` (`--look roblox`), made by `tools/slime_lineup.py`.

## How a slime is put together (one Roblox Model)

| part | mesh | MeshPart.Color | why |
|---|---|---|---|
| body | `slime_base` / `slime_ears` / `slime_horns` / `slime_wobble` | **genome colour** (as `SlimeMesh.dress` does today) | body vertex colour is light grey/white, so the tint gives the hue; values (darker goo foot, lighter crown, highlight blob) give the volume |
| face | `slime_face_<expr>` | **white** (255,255,255) | its own true colours: black eyes with white catchlights, pink cheeks/tongue, white fang |
| accessory (some rarities) | `slime_acc_leaf` / `slime_acc_crown` / `slime_acc_crystal` | **white** | green leaf, gold crown with gems, pale crystals keep their colours on any body |

**Why faces are separate meshes, not baked into the body's vertex colours:** a MeshPart has one
`Color`, and vertex colours are (assumed to be, see below) multiplied by it. Baked into the body, the
eye whites, catchlights, cheeks and tongue would all turn the body colour (white x red = red), and only
black would survive. Separate faces keep their colours, can be swapped at runtime (4 bodies + 5 faces
+ 3 accessories = 12 assets instead of 4 x 5 x ... combinations), and are cheap (350-440 tris).
Every face fits every body: faces are projected onto the same analytic body surface, and all body
variants share the face area (z > 0.9 studs). Goo features (ears, horns, drips) are in the body mesh,
so they take the body tint.

**Assumption to verify in Studio:** `MeshPart.Color` multiplies the FBX vertex colours. The game already
relies on this (Detail.luau tints `plot_building` and `pad_trim` with the plot accent), but no kit mesh
has been checked side by side in Studio yet. If Roblox instead shows vertex colours *without* the tint,
the bodies would render light grey: then the fix is to bake the genome colour per slime (not practical)
or to give bodies a texture/SurfaceAppearance. Check this first at Phoenix's Studio gate.

## Rarity / genome mapping

| rarity (Config.RARITIES) | look | meshes | tris (body + acc + face, worst face) |
|---|---|---|---|
| 1 Common | plain gumdrop | `slime_base` | 816 + 440 = 1256 |
| 2 Uncommon | sprout on the peak | `slime_base` + `slime_acc_leaf` | 816 + 192 + 440 = 1448 |
| 3 Rare | round goo ears (inner ear darker) | `slime_ears` | 976 + 440 = 1416 |
| 4 Epic | curved horns, dark root -> light tip | `slime_horns` | 968 + 440 = 1408 |
| 5 Legendary | gold crown with red/blue gems | `slime_base` + `slime_acc_crown` | 816 + 396 + 440 = 1652 |
| 6 Mythic | pale crystal cluster growing from the peak | `slime_base` + `slime_acc_crystal` | 816 + 110 + 440 = 1366 |
| mutations (Glow/Lava/Galaxy/Gold) | melting goo: flared skirt + 5 drips running down | `slime_wobble` (+ any accessory) | 1216 + 440 = 1656 |

Crown and wobble are ~10% over the 1.5k-per-slime target with the biggest face (surprised); with the
default face they are 1584 / 1588.

| face mesh | expression | game genome (Config.EYES / MOUTHS) |
|---|---|---|
| `slime_face_default` | round glossy eyes, small smile, cheeks | eyes Round, Cyclops (fallback); mouth Smile |
| `slime_face_happy` | ^ ^ closed eyes, open smile + tongue, big blush | eyes Happy; mouth Open |
| `slime_face_sleepy` | closed content lids with lashes, tiny smile | eyes Sleepy; mouth Flat |
| `slime_face_surprised` | wide eyes, raised brows, small "o" | eyes Wide |
| `slime_face_mischievous` | half-lidded slanted eyes, smirk, one fang | eyes Angry; mouth Fang |

(One face per slime: pick by eyes first, the mouth columns show which mouths fit each face best.)

## Sizes and attachment (Roblox studs, X right, Y up, Z: the slime faces **-Z** like SlimeLayout)

All meshes are modelled in one frame: origin = the slime's **bottom centre**, size 1 (body 3 studs wide,
`Config.SLIME_BASE_DIAMETER`). A MeshPart is centred on its mesh bounding box, so place each part at
`bottomCentre * CFrame.new(center)` with the same rotation as the body, and scale sizes and centres by
`d / 3` (d = body diameter after `size` and `SlimeScale`).

| mesh | native size (X, Y, Z) | center from slime bottom centre (X, Y, Z) |
|---|---|---|
| `slime_base` | 3.000, 3.000, 3.000 | 0, 1.500, 0 |
| `slime_ears` | 3.000, 3.012, 3.000 | 0, 1.506, 0 |
| `slime_horns` | 3.000, 3.522, 3.000 | 0, 1.761, 0 |
| `slime_wobble` | 3.230, 3.000, 3.307 | 0.005, 1.500, 0.104 |
| `slime_acc_leaf` | 0.764, 1.207, 0.420 | -0.051, 3.450, 0.360 |
| `slime_acc_crown` | 2.122, 0.855, 2.061 | 0, 2.658, -0.049 |
| `slime_acc_crystal` | 1.595, 1.599, 1.146 | 0.006, 3.043, 0.296 |
| `slime_face_default` | 2.057, 0.922, 0.549 | 0, 1.530, -1.233 |
| `slime_face_happy` | 2.098, 0.707, 0.590 | 0, 1.418, -1.214 |
| `slime_face_sleepy` | 2.098, 0.397, 0.554 | 0, 1.418, -1.196 |
| `slime_face_surprised` | 1.604, 0.949, 0.588 | 0, 1.579, -1.206 |
| `slime_face_mischievous` | 2.016, 0.704, 0.507 | 0, 1.441, -1.253 |

Useful points (size 1, from the bottom centre): eye centres (+-0.50, 1.62, -1.3); mouth (0, 1.27, -1.42);
peak / tip (0, 3.00, +0.32: the peak leans back); crown band z 2.28-2.60 (body radius 0.86-0.6 there);
widest body ring 1.5 studs radius at y 0.52-0.78.

### What the game code would need (not changed here: the game repos are read-only for the modeler)
- `SlimeMesh.dress()` sets `mesh.Size = body.Size` (the 3 x 3 x 3 ball box). That fits `slime_base`
  exactly (3 x 3 x 3), but would squash `slime_horns` / `slime_wobble`. Use
  `mesh.Size = template.Size * (body.Size.X / 3)` and the centres above instead.
- With the mesh look, hide the procedural eyes, mouth, cheeks and gloss parts (SlimeLayout) and add
  the face MeshPart: the procedural face sits on a sphere, the new body is a gumdrop (narrower above
  the eyes), so the old parts would float slightly.
- Accessory/face MeshParts: `Color = white`, `Material = SmoothPlastic`, welded to Body, no collision,
  `CanQuery = false`. Body keeps the genome colour + mutation material as today.
- Tier rim / halo / aura / wings from SlimeLayout can stay as they are.

## Build / preview
```sh
python3 iterate.py models/slime_base.py                    # ships: faces Roblox -Z (sheet "front" shows the back)
SLIME_PREVIEW=1 SLIME_VARIANT=slime_horns SLIME_FACE=happy SLIME_TINT=180,80,255 \
  python3 iterate.py models/_slime_preview.py --no-export   # tinted body + accessory + face, facing the camera
python3 tools/slime_lineup.py --out sheets/slimes_lineup.png [--look roblox]
```
