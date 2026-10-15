# slime_fountain rounds (archer, 2026-10-15)

Steal a Slime hub centrepiece, Slime Ranch theme: wooden silo + goo fountain crown + spiral goo slide.
One mesh (`finish("slime_fountain")`). Colour sheets are `--look roblox --ground 120,196,108`.

| Round | Wall | Tris | What changed / why |
|---|---|---|---|
| r01 quick | 1.5 s | 6756 | First build. Silo = one surface of revolution (plinth, cream trim, staves with seams, 3 brass hoops, red dome, basin, goo mound) + U-trough slide swept along a helix (one closed surface, 12-vert profile) + brackets/posts + 3 gumdrop slimes. Silo stubby (wall 27), crown reads as a teapot knob, slide drops mostly in the outer flare. |
| r02 quick+colour | 2.2 / 5.2 s | 6748 | Wall to 30, fatter goo dome crown, slimes bigger, 1.75 turns, helix part drops 1.7x faster so the slide visibly winds round the silo. Colour: silo/roof/slide read well; goo streams read as beach-ball stripes; slide head sticks out like a diving board. |
| r03 colour | 3.2 s | 6748 | Goo collar (icing) + 11 drips; slide head sunk into the goo dome (r 4.8). 512 px close-up: **per-face goo colouring stair-steps** (pixelated checker edges) - unusable. |
| r04 colour | 5.0 s | 7452 | Rewrote the silo: "free" profile rows slide along the profile **per column** and are snapped onto the goo edge (wavy collar row, drip-tip rows, tip side columns raised = rounded V tip). Goo edges now follow mesh edges: crisp wavy icing + drips. Displacement from the face goo map (interior 0.4, edge 0.1, drip ridge + fat drop at the tip). SEGS 40 -> 48. Big step up. |
| r05 quick+colour | 1.6 / 3.4 s | 6360 | Tri diet: hoops 3 rows, pool 4 rows, slide 72 samples, slimes 10 segs. No visible loss. |
| r06 colour | 3.0 s | 6520 | Slimes 1.25-1.6x, tilted outward, sunk into the crown; a 4th slime sets off down the slide head. |
| r07 colour | 4.8 s | 6520 | Close-up: short dome drips made spiky red "teeth" and the collar hid the red dome. 11 -> 8 drips (1 short on the roof), collar up (2.7 avg). Door top band painted per row (was a cream->red smear). Support beams end under the trough. (The pale box left of the silo in front views is the 5-stud avatar far behind, not geometry.) |
| r08 colour | 3.2 s | 5764 | Under the 6000 target: SEGS 48 -> 44 (drips are column-based, so they survive), slide 66 samples, trough profile 12 -> 10 verts (slanted outer hull). Landing mouth: the last 10 % of the trough widens and its walls drop, so riders spill out. |
| r09 colour | 3.0 s | 5764 | Door re-aligned to the 44-column grid; the cream jambs read as a big cream patch (cream is small trim only), so: 4 columns of red barn-door planks + thin cream lintel. |
| r10 colour (final) | 3.1 s | 5764 | Depth was 66 > the 64-stud max decor axis: slide end r 37 -> 35.5, mouth flare 1.3 -> 1.2x. Now 54.5 x 43.3 x 63.9. Final sheets below. |

## Final
- `slime_fountain_after.png` (studio look), `slime_fountain_after_robloxlook.png` (+ `_turntable.png`, 8 angles), `slime_fountain_scene_robloxlook.png` (scene: plaza r55, landing ring 34..62, 6 riders + 2 landed slimes, 5-stud avatar; views 3,0,2 because bl_iterate has no view 4).
- 5764 tris, one mesh, 0 non-manifold, 54.5 (X) x 43.3 (height) x 63.9 (depth) studs, FBX 121 KB.
- Slide: 1.75 turns, 233 studs long, drop 35.7, avg grade 9.7 deg, max 14.2 deg, U trough 7 wide (floor 3.8 flat + curved walls 1.9 high), ends flat at r 35.5 at the front (-Y).
- **Placement:** finish() centres the mesh on its bbox; the silo axis sits at (-6.52, +7.75) studs from the bbox centre in kit axes (printed as SILO_AXIS). In Roblox the MeshPart pivot is the bbox centre, so put the part at hub centre + (6.52, *, -7.75) in Roblox X/Z (kit -Y = Roblox +Z), or set a PivotOffset.
- Process limits: the goo is fine as an analytic surface once the mesh rows follow the goo edge (r04). What it can't do: goo that leaves the surface (free-falling sheets or splashes off the eave) or slimes that really merge into the goo. The crown slimes are gumdrops sunk into the goo dome.
