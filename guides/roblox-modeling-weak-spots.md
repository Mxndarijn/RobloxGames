# Roblox modeling & visuals: weak spots (as of v17, 2026-10-15)

Each item: what we do now, why the feedback is weak, the impact on quality, and a line for Merijn's replacement.

1. **Blender models written as Python scripts, with no viewport**
   - Now: Claude Code writes Python scripts that build each mesh in Blender with no window open, so nobody looks at the model while it's made.
   - Weak: you only see the shape after a full render, often minutes per change.
   - Impact: blocky, generic shapes and few improvement rounds.
   - Replacement (Merijn):

2. **Blender renders without a GPU stand in for Roblox**
   - Now: low-sample renders on the box's processor, used as "the look".
   - Weak: Roblox lights, shades and draws materials and round shapes differently, so the renders mislead.
   - Impact: colours, shine and atmosphere look different in-game.
   - Replacement (Merijn):

3. **Shapes placed by Luau code are judged blind**
   - Now: slimes, fences, ground patches and the boundary are basic Roblox shapes placed by code.
   - Weak: you only see them through approximate Blender renders, and Roblox makes Ball parts perfectly round.
   - Impact: faces and drips may sit wrong, and the scenes feel samey.
   - Replacement (Merijn):

4. **Lighting tuned without seeing it**
   - Now: Sky, Bloom, haze and the night look are set as numbers in code or the project file.
   - Weak: we have never seen them in Roblox; we only find out at Phoenix's Studio check.
   - Impact: too much or too little glow, muddy nights.
   - Replacement (Merijn):

5. **Mesh ids come from a cloud test session**
   - Now: we upload as Model assets, then load each one in a cloud test session to read its mesh id.
   - Weak: an extra round trip for every asset, and an unusual setup that can break.
   - Impact: slow updates, and a risk of wrong or stale ids.
   - Replacement (Merijn):

6. **Default collision on meshes**
   - Now: the world files can't store box collision, so meshes keep the default; the volcano uses invisible stand-in blocks.
   - Weak: never tested by actually walking into things.
   - Impact: players may snag on meshes, or walk through them.
   - Replacement (Merijn):

7. **Phone-size check only at release**
   - Now: 390x844 screenshots come from renders or Phoenix's gate, late in the process.
   - Weak: problems that only show on small screens are found last.
   - Impact: clipped or hard-to-read signs and UI on phones.
   - Replacement (Merijn):

8. **Real screenshots only from Studio on Merijn's PC**
   - Now: Studio doesn't run on Linux, and the AI-testing rules keep bots off the real Roblox client.
   - Weak: the only true view depends on Merijn's PC and Phoenix's gate, hours after a change.
   - Impact: few chances to iterate, and visual bugs reach review.
   - Replacement (Merijn):

9. **Tight budgets, and nothing can be checked by eye in the engine**
   - Now: 834 of 850 decor parts and 148 of 150 meshes are used, checked by count in code.
   - Weak: we can't measure frame rate or see how dense the scene looks on a real device.
   - Impact: no room to add detail; real performance is unknown.
   - Replacement (Merijn):

10. **Organic goo shapes (drips, blends, merges)**
   - Now: slimes are built from hard-edged pieces in bpy scripts; drips are made by pushing the body surface out.
   - Weak: separate drip pieces read as stubby legs; smooth blends, see-through goo and textures can't be scripted cleanly.
   - Impact: slimes look clean but stylised, well short of Slime Rancher quality.
   - Needs: sculpting, metaballs/remeshing, or a 3D generator service.
   - Replacement (Merijn):
