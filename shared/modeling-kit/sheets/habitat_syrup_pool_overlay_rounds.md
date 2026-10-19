# habitat_syrup_pool_overlay rounds (preview = HABITAT_PREVIEW=1, crate drawn under it)

| r | wall | tris (overlay) | change / why |
|---|---|---|---|
| 01 | 4.2 s | 1720 | Amber syrup frame (wobble 0.1), metaball drips over all 4 edges down the crate sides (2 per side, mirrored), 3-cake stack, small honey pot + thin dipper, 2 bubble corners. Reads as syrup; props too small, dipper a twig. |
| 02 | 4.1 s | 2220 | 4 bigger cakes with a metaball glaze running down the front, butter pat; lathe honey pot with cream band, syrup run over its lip, dipper head; 3-blob bubble clusters. Cake stack poked to -4.07 (footprint 8.05, centre off 0.05). |
| 03 | 4.4 s | 2052 | 5 cakes r 0.64 pulled in; drips decimate 420. Drips alone reached 3.987 in y (decimation asymmetry): footprint 7.97. |
| 04 | 4.7 s | 1660 | Drip lenses thinner outward (0.065) and centred 3.83: footprint 7.85 x 7.86, centre (0,0). Fewer segs (cakes/pot 10), glaze 180 / pot goo 140 tris. 512 px check: dipper still thin. |
| 05 | 4.2 s | 1688 | Dipper handle r 0.13, 5-disc head raised above the rim. Roblox look: cake + pot shadow sides went brown. |
| 06 | 4.6 s | 1688 | Lifted SYR_D (216,128,42) and CAKE_D (208,146,78). Final. DECK bbox z -1.058..2.550 (DROP 1.058), over_mat 0 deck-relative. |
| 07 | 6.2 s | 1510 | Tri trim: drips decimate 280, glaze 140, pot goo 140->110, dipper 4 discs; removed the debug edge print. Drips still read; footprint 7.855 x 7.859, centre (0.001,-0.001), DROP 1.058, deck-relative over_mat 0. Final (after + roblox look re-run). |
