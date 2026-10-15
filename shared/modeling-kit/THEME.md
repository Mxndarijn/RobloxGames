# Theme: Slime Ranch

**Locked by Merijn, 2026-10-15.** Warm wood, soft fields, gooey farm props. Models first, quality over speed. Every new or remade Steal a Slime mesh follows this file. (The old Volcanic Meadow rules are in `THEME_volcanic_meadow_dropped.md`; don't use them.)

**Mood:** cozy, soft, rounded, gooey, sunny farm. Not volcanic, not sci-fi, not realistic.

## Palette (sRGB 0–255, vertex colours; names in `lib/color.py` PALETTE as `ranch_*`)
| Name | RGB | Use |
|---|---|---|
| ranch_field | 120, 196, 108 | ground grass (sheet `--ground`) |
| ranch_field_light | 156, 216, 124 | grass tufts, hedge tops, light foliage |
| ranch_field_dark | 88, 160, 92 | foliage undersides (lightest dark allowed) |
| ranch_path | 226, 196, 146 | paths, landing ring, packed dirt |
| ranch_cream | 248, 236, 212 | plaza floor, trim, silo bands, painted wood |
| ranch_wood | 196, 138, 86 | planks, barn boards, fences |
| ranch_wood_dark | 158, 108, 68 | posts, beams, shadow side of wood (darkest wood) |
| ranch_roof | 214, 92, 84 | barn red roofs, signs |
| ranch_roof_dark | 176, 70, 70 | roof undersides / ridge |
| ranch_goo | 110, 226, 170 | goo pools, slide floor, spills |
| ranch_goo_hi | 196, 250, 220 | goo highlights, drip tips, glossy rims |
| ranch_pink | 250, 150, 182 | candy accents, flowers, bunting |
| ranch_lilac | 196, 166, 232 | accents, second goo flavour |
| ranch_butter | 252, 216, 110 | hay, signs, gameplay highlights |
| ranch_metal | 176, 186, 196 | hoops, bolts, silo rings (small areas only) |

**Slime saturation:** slimes are the most saturated, brightest objects on screen. Props stay one step softer: no prop surface larger than a slime may beat slime saturation; goo props use `ranch_goo`, never the slime genome colours.

## Shape language
- Rounded and chunky: big simple volumes, thick parts (planks ≥ 0.4, posts ≥ 0.8), soft bevels on every box edge that reads at game size.
- Gooey: goo pools, rims and drips are part of the surface (indented or displaced), never stuck-on tubes (see LESSONS: separate drip primitives read as stubby limbs).
- Hand-made farm: slight tilts and uneven planks are fine; no perfect CAD symmetry, no thin greebles.
- Gradients: dark below, light above on each part.

## Do / don't
- DO: warm wood + cream + red roof, soft green fields, pastel goo accents, chunky rounded silhouettes.
- DON'T: basalt, lava, rock walls, torches, near-black darks (keep value ≥ ~115, wood ≥ ~140), cold blue-greys, near-white pastels on big surfaces, sci-fi metal.
- **Neon only for gameplay signals** (buttons, live goo the player interacts with, despawn countdown, FX). Never decorative.

## Scale (studs, vs the grey 5-stud avatar block)
Player 5 · slime 3 · plot floor 80 × 80 · gate opening 14 · walls 8 tall · beam over a walkway ≥ 9. Hub sizes: `models/FOUNTAIN_SIZES.md`.

## Budgets
- Tris per prop 500–2000 target; hero centrepiece up to ~6000; kit fails at ≥ 10,000 per mesh.
- MeshParts per map ≤ 150 (count the whole map before splitting into small pieces). Decor ≤ 1500 instances / 1200 parts / 850 decor parts / 80 lights (CONTRACT §10). Max decor axis 64 unless agreed.
- One material per MeshPart; colour lives in vertex colours `Col`.

## Per-model checklist
- [ ] Read `LESSONS.md` (Slime Ranch section) and this file.
- [ ] Silhouette reads at game size next to the 5-stud avatar and a 3-stud slime.
- [ ] Only palette colours; no darks under the floors above.
- [ ] Final sheet: `--look roblox --ground 120,196,108` (turntable for hero props), looked at with Read.
- [ ] Tris + MeshPart count in budget; 0 non-manifold edges.
- [ ] Rounds logged in `sheets/<name>_rounds.md`.
- [ ] LESSONS entry appended.

## LESSONS rule
Every bot appends one short entry to `LESSONS.md` → `## Slime Ranch` after each model, format `- [model/YYYY-MM-DD/bot] lesson`. Archer curates (merges duplicates, promotes rules into this file). Palette or rule changes go through Archer; propose them in your report.
