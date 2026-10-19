# habitat_mushroom_ring_overlay rounds

| round | wall | tris (export) | change / why |
|---|---|---|---|
| r01 | 4.2 s | 1168 | Moss frame (field_light, wobble 0.1), 8 toadstools on band_spots(8) (corners s1.15, edges s0.75) + a small companion per corner, 8 moss tufts. Read as a fairy ring at once, but bbox 8.03 (companions pushed off the band) and caps small vs the avatar. |
| r02 | 4.2 s | 1440 | Corners s1.3 at inset 0.1 (lathe phase pi/8 so no cap vert points diagonally into the mat), medium s0.85 on edge middles, small s0.5 either side of each corner on band_spots(16). 7.64 wide, over_mat 0. |
| r03 | 4.4 s | 1520 | Moss hump under each corner toadstool, bigger tufts. Found blobs dipping below z=0 move the export's origin (Habitats `drop` > 0): added `on_deck()` that flattens verts below the deck. Height now 2.085 = cap top. |
| r04 | 6.7 s | 1520 | Roblox look: stems went grey in the cap shadow; stem colour lifted to a warm near-white. Minor gain (it is mostly shadow). Final. |

Final: 1520 tris, OVERLAY 7.654 x 2.085 x 7.639 centre=(0,0) over_mat=0, `out/habitat_mushroom_ring_overlay.fbx`.
