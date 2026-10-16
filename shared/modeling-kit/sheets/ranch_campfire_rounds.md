# ranch_campfire rounds (archer, 2026-10-16)

Plaza fire pit: ember-bed lathe inside a ring of 9 chunky sandstone blobs, two crossed + two leaning
logs (heartwood end caps), 7 low-poly flame tongues (closed 5-sided lathes with curled tips, roof ->
butter outer / butter -> cream-butter inner, no neon), 3-leg wood tripod (one leg back, two front)
with twine lashing, pewter hook + bail + spout kettle (closed lathe with a goo-filled mouth), metaball
goo bulging over the front lip and dripping down the belly (lib/goo.py). All sheets: `--look roblox
--ground 120,196,108` in `sheets/ranch_campfire/`.

| Round | Wall | Tris | nm | What changed / why |
|---|---|---|---|---|
| r01 | 3.2 s | 1994 | 0 | First pass. Fire + tripod read. Problems: kettle (r 0.62) tiny under the tripod, and an 8-lens lip roll wrapped its front = a green bow tie; stones in tan/wood_dark read as bread rolls; 5.08 tall; flame tongues thin spikes; subdiv-1 grass tufts read as green gems. |
| r02 | 3.0 s | 1994 | 0 | Kettle r 0.85 x 1.13 lowered to 2.3, bigger spout/bail; goo = mouth dome + 4-lens roll at the front + 2 belly drips with fat drops; apex 4.25; flames x1.3 wide; stones flatter (z 0.68) and lighter (plaza -> path+cream). Kettle and drip read; pewter went muddy brown. |
| r03 | 3.1 s (+4.0 s turntable) | 1934 | 0 | Kettle rows metal -> mix(metal, cream, 0.45) (no wood_dark lows); goo dome raised so the green mouth shows from the front; tufts dropped. Turntable: fire, kettle and drip read from all angles. Final. |

Final: 1934 tris, 4.27 x 4.55 x 4.25 (W x H x D), nm 0, 1 mesh, FBX 64 KB.
