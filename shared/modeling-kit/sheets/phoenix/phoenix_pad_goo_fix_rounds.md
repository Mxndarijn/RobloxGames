# phoenix_pad_goo small fix (2026-10-16, phoenix)
#8 review: lumpy goo pad. Before: `phoenix_pad_goo_fix_before.png` (two icosphere spill blobs on the +X staves = dark green clump).

| round | wall | tris | size W x H x D | change / why |
|---|---|---|---|---|
| fix r01 | 2.8 s | 1148 | 7.91 x 2.09 x 7.86 | spill blobs -> one metaball (lip roll on the rim + 3 flat lenses down the stave face + round tip above the upper hoop), resolution 0.08, decimate 240. Fuses into the rim, no clump. Width 7.83 -> 7.91 (still under hay's 7.96). |
