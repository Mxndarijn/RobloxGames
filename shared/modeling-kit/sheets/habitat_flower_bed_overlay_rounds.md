# habitat_flower_bed_overlay rounds

| round | wall | tris (export) | change / why |
|---|---|---|---|
| r01 | 5.5 s | 3552 | Soil frame, 12 soil mounds, 5-petal daisies everywhere (corner clusters of 3 + 8 edge) with leaf pairs. Too many tris (each petal is a 20-tri blob) and flowers tiny/sparse: read as bare soil with specks. |
| r02 | 6.9 s | 1824 | Kept 5-petal daisies only as 4 corner heroes; 12 round blooms (one squashed blob + centre bead, planter lesson); alternating leaf bushes / soil tufts. Still sparse and small. |
| r03 | 7.2 s | 1904 | 16 leafy bushes r0.6 all round the band, soil tufts on the outer edge between them, bloom heads r0.42, hero daisies r0.66. Reads as a full flower bed. |
| r04 | 5.1 s | 1904 | Roblox look: soil frame went near-black and lilac went dark purple. SOIL 132/92/64 -> 152/108/76, lilac mixed 25 % toward cream, dark bush variant lighter. Final. |

Final: 1904 tris, OVERLAY 7.577 x 1.836 x 7.574 centre=(0,0) over_mat=0, `out/habitat_flower_bed_overlay.fbx`.
