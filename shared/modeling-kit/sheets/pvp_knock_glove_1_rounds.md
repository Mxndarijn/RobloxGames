# pvp_knock_glove_1 "Bonk Glove" (Knockback rank 1): rounds

Shared builder `models/_pvp_glove.py` (metaball mitt + separate metaball thumb + cuff lathe). `_close` sheets are the same round rendered with `--no-ref` (glove fills the tile) for detail; the plain sheet is the scale check. `sheets/pvp_knock_glove_lineup.png` shows all five ranks side by side (`models/_pvp_glove_lineup.py`).

| Round | Wall | Tris | What changed / why |
|---|---|---|---|
| q01 (quick) | 1.2 s | 672 | First shape: one metaball body with the thumb inside it. The thumb melted in: read as a mushroom / light bulb on a cuff. |
| r01 | 1.4 s | 722 | Thumb as its own metaball shell (crisp crease), taller tapered cuff (top 0.62 -> 0.80), longer mitt. Reads as a boxing glove; thumb barely visible from the front. |
| r02 | 1.8 s | 722 | Thumb bigger and further out (-X), narrower wrist ball, less cuff lip flare. Thumb now reads in the front view. |
| r03 | 1.8 s | 652 | Rank 1 should be the simplest: mitt 380 -> 320 tris, thumb 90 -> 80. No visible loss. Final (`_after.png`). |
| roblox look | ~3 s | 652 | `--look roblox --turntable --ground 120,196,108`: red stays red on the shadow side, white cuff not muddy. |

Final: 652 tris, 1.64 x 2.01 x 1.40 studs (Roblox X, Y, Z), 0 nm, PASS. Grip (hand centre, inside the cuff): 0.50 above the cuff bottom; from the bbox centre (Roblox axes) [0.08, -0.51, -0.03].
In-hand check (blocky R15 arm, fist forward, scratch render): the cuff swallows the hand and the forearm block enters the cuff; the glove is ~1.6x the arm width (cartoon boxing glove).
