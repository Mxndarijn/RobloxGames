# ranch_windmill rounds (archer, 2026-10-16)

Slime Ranch wind pump: splayed 4-leg wood lattice tower, plank deck, pewter turntable, wood housing
under a small red gable cap, 8 goo-tinted vanes on wood spokes (rotor faces -Y), metaball goo lip on
every vane tip + short drips from the 3 lowest tips, butter tail fin in a red frame (+Y), pump rod into
a small wooden goo tub with a front spill + ground puddle. All sheets: `--look roblox --ground 120,196,108`
in `sheets/ranch_windmill/`.

| Round | Wall | Tris | nm | What changed / why |
|---|---|---|---|---|
| r01 | 3.2 s | 3372 | 0 | First pass. Reads as a windmill at once (16-17 studs vs avatar). Problems: spokes rendered **in front** of the vanes (local y -> world -Y flips the sign), vanes too narrow (0.8-1.45) so the rotor read as a spiky wheel, tip lips + 0.9-1.6 drips read as stuck-on green tubes, 3372 tris. |
| r02 | 3.5 s | 2756 | 0 | Spokes moved behind vanes, vanes widened to 1.05-1.9 x 0.3, lips = flat lenses (0.2 x 0.3 x 0.21) sunk into the tip edge, drips only where the tip points down (d.z < -0.3) and shortened to 0.45-0.65 with a fat drop; WOOD_LO lifted (mix 0.6); rails/braces 4-seg. Rotor now reads as a chunky goo fan. |
| r03 | 2.9 s | 2064 | 0 | Tri pass from a per-part count: unbevelled spokes (-256, hidden behind the vanes) and feet (-128), goo decimate 560->400 / 320->220, fin frame unbevelled, tub 10-seg; fin face lows lifted toward cream (was going olive). |
| r04 | 2.9 s (+4.2 s turntable) | 1970 | 0 | Goo 360/190, legs 5-seg. Turntable checked: rotor, red cap and butter fin read from all 8 angles; lattice stays open. Final. |

Final: 1970 tris, 8.38 x 17.39 x 9.65 (W x H x D), nm 0, 1 mesh, FBX 58 KB.
