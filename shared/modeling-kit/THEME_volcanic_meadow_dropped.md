# Theme: Volcanic Meadow

**Locked by Merijn, 2026-10-15.** Every new or remade mesh for Steal a Slime follows these rules. A bright green meadow with a dark volcano in it; the volcano's lava is the only strong glow, and the slimes are the most colourful thing on screen.

## Rules
- **Ground:** meadow green, about `98,160,70` (`PALETTE["meadow"]`).
- **Paths:** warm pavement or sand (`path_sand` 214,186,138). No cold grey concrete.
- **Volcano:** dark basalt (`basalt`, `basalt_hi`) with lava neon and cracks (`lava`, `lava_crack`). The lava is the **only strong glow** in the world.
- **Signs and fences:** wood (`wood`, `bark`, `bark_dark`).
- **Plot accents:** saturated mid-value colours. No near-white pastels (they wash out in the Roblox look and under MeshPart tint).
- **Slimes:** glossy gumdrop blobs, the **highest saturation on screen**. Faces and accessories are separate MeshParts tinted white, so they keep their own colours (see LESSONS.md, "Vertex colour x MeshPart.Color"). Slime bodies render light grey in the kit because the game tints them with the genome colour.
- **Neon only for gameplay signals:** lava, buttons, goo. Nothing decorative glows.
- **No muddy or blue greys.** Stone is warm (`stone_warm`, `rock`).

## Palette (`lib/color.py` `PALETTE`, sRGB 0-255)
| Key | R | G | B | Use |
|---|---|---|---|---|
| `bark` | 120 | 78 | 50 | tree trunks, fence posts |
| `bark_dark` | 86 | 56 | 38 | trunk shadow side (dark: see note below) |
| `leaf` | 86 | 170 | 64 | foliage |
| `leaf_light` | 138 | 206 | 80 | foliage tops |
| `leaf_dark` | 56 | 124 | 54 | foliage undersides |
| `pine` | 46 | 112 | 74 | fir foliage |
| `rock` | 140 | 128 | 116 | warm stone |
| `slate` | 104 | 100 | 98 | dark stone accents (sparingly) |
| `blossom` | 246 | 160 | 190 | blossom tree |
| `slime` | 90 | 220 | 120 | default slime green |
| `lava` | 255 | 140 | 50 | lava, glow |
| `wood` | 150 | 100 | 60 | signs, fences, planks |
| `meadow` | 98 | 160 | 70 | ground |
| `path_sand` | 214 | 186 | 138 | paths |
| `basalt` | 58 | 52 | 56 | volcano body |
| `basalt_hi` | 84 | 76 | 80 | volcano ledges and lit faces |
| `lava_crack` | 255 | 96 | 24 | lava cracks and gullies |
| `stone_warm` | 150 | 138 | 120 | warm stone, rock highlights |

## How to check
Render every theme mesh in the game's lighting on meadow ground:

```
python3 iterate.py models/<name>.py --look roblox --no-export --ground 98,160,70 --sheet sheets/v3-theme/<name>_meadow_robloxlook.png
```

Look for: parts going black on the shadow side, pastels washing out, grey that reads blue or muddy against the green, and anything glowing that isn't lava or a gameplay signal. The v3 audit (all 21 meshes, plus before/after for volcano, rock_b and rock_c) is in `sheets/v3-theme/`.

**Known:** the very dark basalt goes near-black on the shadow side in the Roblox look. That's OK because the lava carries the volcano. If it looks too heavy in Studio, raise `basalt`/`basalt_hi` by about 15%.

## Open questions for Merijn (not blocking)
- **Day or night by default?** The game runs a day/night cycle; the theme and `--look roblox` are tuned for day (ClockTime 14.5). A night default would make lava the main light and need a darker-ground check.
- **Glossier or translucent goo?** Real gloss and translucency on slimes and goo need sculpting or a 3D generator; the bpy process can't do it (see CLAUDE.md, "Report the limits").
