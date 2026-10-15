# slime_fountain goo polish (archer, 2026-10-15)

Start (merged model): 5764 tris, 54.45 x 43.3 x 63.851 (W x H x D), nm 0. `before.png`, `before_robloxlook.png`.
Close-ups (`r0N_crown*.png`, `_exit`, `_slide`) come from the preview `models/_slime_fountain_crop.py` (CROP=crown|exit|slide); not assets.

| round | wall | tris | size (W x H x D) | nm | what changed and why |
|---|---|---|---|---|---|
| r01 | 2.8 s | 6072 | 54.45 x 41.633 x 63.851 | 0 | Goo crown as METABALLS (`lib/goo.py`: elements -> `new_from_object` -> COLLAPSE decimate to 1300 tris -> `Col` + keep_smooth): basin dome, 22 flat collar lenses on the roof shoulder, 8 drips as chains of flat lenses along the silo profile + a fat round tip ball. Silo lost its displaced goo and the hidden pool rows. Slimes removed (-> `slime_fountain_emerge.py`). Drips fuse into the collar and the roof, tips round: works first time. Height dropped (slime tips were the top). |
| r02 | 5.0 s | 6932 | 54.45 x 43.237 x 63.851 | 0 | Splash pool past the slide mouth (flat lens + 14-lens ripple ring + thin pour sheet over the lip + 3 fat drops sunk into the rim, bottom clamped to z 0.02) and 6 goo lumps on the slide floor. First pool: drops floated as separate nubs (too high to fuse) and bbox D grew 0.23: lowered drops, narrowed pool. Crown top bubble raised for height. |
| r03 | 2.8 s | 6668 | 54.45 x 43.237 x 63.851 | 0 | Slide lumps were invisible (goo on goo) then beads (path samples are 3.5 studs apart): teardrops of 5 lenses interpolated within one segment, goo_hi on the up-facing tops. Merged 4 silo wall rows (12.5, 18, 20.5, 23) into one at 19.5: they only served the old drip snapping (-264 tris). Roblox look: colours hold, but the crown top is a pointed onion. |
| r04 | 3.4 s | 6668 | 54.45 x 43.316 x 63.851 | 0 | Crown: nested ellipsoid fields summed into a cone (reads volcano). Rebuilt as a flat basin lens + ring of 5 fat bubbles + one big centre bubble (CROWN_TOP sets the height): bubbling cupcake top, height back to 43.3. |
| r05 | 3.0 s | 6814 | 54.45 x 43.316 x 63.851 | 0 | Drips vary in width (0.8-1.3) with tip size following, long runs carry a merged bead half way; crown budget 1450. Emerge model built and checked in place (`r05_crown_with_emerge.png`): slimes re-seated on the new, taller crown bubbles. |
| r06 | 2.9 s | 6814 | 54.45 x 43.316 x 63.851 | 0 | Colour: goo_hi only on steep up-facing crown tops (n.z^2), low drips darkened less (shade 0.95) so they stay green on the roblox-look shadow side. Final. |

Final: `after.png`, `after_robloxlook.png` (+ `_turntable.png`, 10.7 s with turntable), `emerge.png` (640 tris, nm 0).
Budget: silo 2728, slide 1316, crown 1446, slide goo 400, pool 460, supports 464 (metaball build + decimate adds ~0.05 s to the model step).
Emerge offset (printed by `slime_fountain_emerge.py`): emerge bbox centre - fountain bbox centre = kit (-11.20, 8.25, 18.94), Roblox (X, Y, Z) (-11.20, 18.94, -8.25) for an unrotated fountain.
