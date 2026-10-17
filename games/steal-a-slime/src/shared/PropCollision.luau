--!strict
--[[
	PropCollision (pure, no Roblox APIs; bug B9 "every object uses its own collision")

	The machine-readable inventory of every collidable or solid-looking prop in the built map, both halves
	(Jolt: the shared world; Gojo: plot-level props). One entry per kind (a MeshAssets mesh in one place, or a group of
	primitive parts). docs/COLLISION.md has the rules, MeshAssets.COLLISION is the single list of mesh fidelities.

	Entry:
	  kind       unique id
	  mesh       the MeshAssets name, or "part" (primitives / colliders / terrain)
	  owner      "jolt" | "gojo" | "ambiguous" (ambiguous = not changed by either half; reported, soft probe)
	  count      instances in the booted default-flags world (a MeshAsset slot / Model / part counted once)
	  collision  "Box" | "Hull" | "Default" | "PreciseConvexDecomposition" (= MeshAssets.COLLISION[mesh]) |
	             "colliders" (hand colliders or primitive parts that collide on their own) | "off" (CanCollide false)
	  now        the CanCollide state in the booted world (text, for the inventory)
	  reason     why: required for "off" and "colliders", one line for the others
	  find       how tests and the play probe locate the instances (see PropCollision.matches)
	  also       extra solids of the same instance outside its find path (the fountain tower's colliders)
	  was        before B9, when this entry changed
	  walk       false = the play probe does not walk into it (slide: bug09 probes it; Terrain; floors)
	  flag       { name, off } = a Config.FEATURES flag and the count while it is off

	find = {
	  under  dotted path under workspace the instance sits below ("Map.Decor", "Plots"),
	  mesh   the MeshAsset attribute value (slots and WorldProps Models),
	  names  list of Lua patterns an instance name must match one of (anchored by the caller),
	  parts  true = only BaseParts count as instances (else Models and parts both),
	}
	Gojo adds entries by appending to ENTRIES; the spec and the play probe read the list, nothing else to edit.
]]

export type Find = {
	under: string,
	mesh: string?,
	names: { string }?,
	parts: boolean?,
}

export type Entry = {
	kind: string,
	mesh: string,
	owner: string,
	count: number,
	collision: string,
	now: string,
	reason: string,
	find: Find?,
	also: Find?,
	was: string?,
	walk: boolean?,
	flag: { name: string, off: number }?,
}

local PropCollision = {}

local FIDELITIES = { Box = true, Hull = true, Default = true, PreciseConvexDecomposition = true }
PropCollision.FIDELITIES = table.freeze(FIDELITIES)
PropCollision.OWNERS = table.freeze({ jolt = true, gojo = true, ambiguous = true })

-- The border's wall ring (WorldBorder.RADIUS 292, 80 studs tall) is the only collision of everything "behind the wall".
local BEHIND_WALL =
	"behind the 80-stud wall ring (WorldBorder.RADIUS 292): players cannot reach it, the walls are the collision (spec: every piece's footprint starts outside the wall's inner face)"

local entries: { Entry } = {}

local function add(e: Entry)
	table.insert(entries, e)
end

-- A mesh slot / WorldProps Model located by its MeshAsset attribute.
local function mesh(
	kind: string,
	meshName: string,
	owner: string,
	count: number,
	collision: string,
	under: string,
	now: string,
	reason: string,
	more: { was: string?, walk: boolean?, flag: { name: string, off: number }? }?
)
	local m = more or {}
	add({
		kind = kind,
		mesh = meshName,
		owner = owner,
		count = count,
		collision = collision,
		now = now,
		reason = reason,
		find = { under = under, mesh = meshName },
		was = m.was,
		walk = m.walk,
		flag = m.flag,
	})
end

-- Primitive parts (or Models) located by name patterns.
local function parts(
	kind: string,
	owner: string,
	count: number,
	collision: string,
	under: string,
	names: { string }?,
	now: string,
	reason: string,
	more: {
		also: Find?,
		was: string?,
		walk: boolean?,
		models: boolean?,
		flag: { name: string, off: number }?,
	}?
)
	local m = more or {}
	add({
		kind = kind,
		mesh = "part",
		owner = owner,
		count = count,
		collision = collision,
		now = now,
		reason = reason,
		find = { under = under, names = names, parts = not m.models },
		also = m.also,
		was = m.was,
		walk = m.walk,
		flag = m.flag,
	})
end

local MAP = "Map"
-- the fountain model keeps its legacy internal name (docs/COLLISION.md); only the path is spelled here
local FOUNTAIN = MAP .. "." .. "Volcano"
local DECOR = "Map.Decor"
local PLAZA = "Map.Plaza"
local BORDER = "Map.Border"
local ON_MESH = "mesh on, slot box off"

--------------------------------------------------------------------------------------------------------------------
-- JOLT: fountain, slide, vat, shops, signs, board, NPC, world decor
--------------------------------------------------------------------------------------------------------------------

-- Fountain and slide: the hand colliders stay exactly as they are (bug #9, #10; docs/COLLISION.md).
add({
	kind = "fountain_tower",
	mesh = "slime_fountain",
	owner = "jolt",
	count = 1,
	collision = "colliders",
	now = "mesh off; 22 colliders on (TopCollider1..19, Silo, Trim, Basin)",
	reason = "the tower and the slide are one MeshPart, so the hand colliders (shared/SlideColliders, server/FountainColliders) stay; mesh collision would make the trough walkable (#9)",
	find = { under = FOUNTAIN, names = { "^FountainMesh$" } },
	also = { under = FOUNTAIN, names = { "^%a+Collider%d*$" }, parts = true },
})
parts(
	"fountain_slide_colliders",
	"jolt",
	257,
	"colliders",
	FOUNTAIN .. ".SlideColliders",
	nil,
	"on (Floor, Fill, wedge roof, Joint, Skirt)",
	"solid slide block so nobody enters or climbs the trough; slimes ride it anchored with CanCollide=false (bug #9). Unchanged, probed by bug09_slide_stand (257 parts with FEATURES.SlideCollision, the low stretch only, 113, without)",
	{ walk = false, flag = { name = "SlideCollision", off = 113 } }
)
mesh(
	"fountain_emerge",
	"slime_fountain_emerge",
	"jolt",
	1,
	"Box",
	FOUNTAIN,
	ON_MESH,
	"stacked big slimes at the top: a flat-topped box (bug #10), StackGuard ejects overlaps"
)
parts(
	"fountain_standins",
	"jolt",
	6,
	"off",
	FOUNTAIN,
	{ "^Crater$", "^Bowl$", "^Column$", "^Pool$", "^BasinRim$", "^Rock%d+$" },
	"off",
	"hidden stand-ins of the fountain mesh (basin, crater, column, pool); the tower colliders are the collision"
)
parts(
	"fountain_chute",
	"jolt",
	32,
	"off",
	"Map.Chute",
	nil,
	"off",
	"the slime ride surface: wild slimes ride it anchored and non-colliding by design; players are kept out by the slide block (#9)"
)

parts(
	"merge_vat",
	"jolt",
	8,
	"Hull",
	"Plots",
	{ "^MergeVat$" },
	"disc on + Hull VatMesh on (+ Goo disc)",
	"blobby cauldron (bug #16, MeshSwap.swapPlotVats): the Hull closes the gaps under the funnel spouts; mesh = merge_vat, found by its disc",
	{ walk = false }
)
entries[#entries].mesh = "merge_vat"

add({
	kind = "shop_stand",
	mesh = "ranch_shop_stand",
	owner = "jolt",
	count = 2,
	collision = "Hull",
	now = "Hull mesh on + primitive Counter / Back / Awning / Posts on",
	reason = "solid counter (CONTRACT §27.2), not a box to stand inside; the primitive counter parts stay collidable under the mesh",
	find = { under = MAP, names = { "^ItemShopStand$", "^UpgradeShopStand$", "^ShopStand$" } },
	flag = { name = "WorldShops", off = 1 },
})
add({
	kind = "top_earners_board",
	mesh = "phoenix_top_earners_board",
	owner = "jolt",
	count = 1,
	collision = "colliders",
	now = "Collider + Frame + PostL/PostR on (Collider widened to the skin's 20.6 x 19.5)",
	reason = "the board Model keeps its own Collider; MeshSwap widens it to the skin's width and height (20.6 x 19.5; depth and front unchanged) so the overhanging sides are solid. Not a COLLISION entry: the same mesh is the plots' DexMesh (Gojo)",
	find = { under = MAP, names = { "^LeaderboardBoard$" } },
	was = "Collider 15 x 17 x 1.6 under a 20.6 wide mesh: 2.8 studs each side walkable",
})
parts(
	"tutorial_npc",
	"jolt",
	1,
	"colliders",
	MAP,
	{ "^TutorialNpc$" },
	"body parts on (Head, Torso, arms, legs); hat and face off",
	"a standing NPC is solid; the hat and face details are tiny",
	{ models = true }
)
parts(
	"ground_and_hub_spawn",
	"jolt",
	2,
	"colliders",
	"",
	{ "^Ground$", "^HubSpawn$" },
	"on",
	"the void-safety floor under the voxel terrain and the hub SpawnLocation pad",
	{ walk = false }
)
add({
	kind = "terrain",
	mesh = "part",
	owner = "jolt",
	count = 1,
	collision = "colliders",
	now = "on (voxel Terrain: ground, border hills)",
	reason = "Terrain collides by itself (GroundTerrain, BorderTerrain); no mesh or collider part",
	walk = false,
})
parts(
	"ritual_circle",
	"jolt",
	7,
	"off",
	"Map.RitualCircle",
	nil,
	"off",
	"flat glowing discs (0.2 thick) on the ground, a sign lying at 1.8 studs and a hovering orb: walk-through markings",
	{ flag = { name = "CoopRitual", off = 0 } }
)

-- World signs
mesh(
	"plaza_signpost",
	"ranch_plaza_signpost",
	"jolt",
	1,
	"Box",
	PLAZA,
	ON_MESH,
	"sign boards on posts, 12.6x14.5x7.5; the old slot box was this bbox"
)
mesh("goo_sign", "ranch_goo_sign", "jolt", 1, "Box", DECOR, ON_MESH, "8.8x8.2x3.7 signboard")
for i = 1, 3 do
	mesh(
		`plaza_podium_{i}`,
		`phoenix_plaza_podium_{i}`,
		"jolt",
		1,
		"Box",
		PLAZA,
		ON_MESH,
		"stepped block podium: players and rigs stand on its flat top"
	)
end
-- Plaza ground features
mesh(
	"landing_ring",
	"ranch_landing_ring",
	"jolt",
	11,
	"off",
	PLAZA,
	"mesh off, slot off",
	"curb stones round the wild-slime drop zone: players and slimes cross it (the slot box is deeper than the stones and must not leave an invisible wall, WorldLayout). DECISION for Merijn: a solid ring would wall players off the slime landing area",
	{ walk = false }
)
mesh(
	"goo_drain",
	"ranch_goo_drain",
	"jolt",
	1,
	"off",
	PLAZA,
	"mesh off, slot off",
	"the goo drain at the slide exit: a floor feature the slimes and the splash use. DECISION for Merijn (a Box would close the slide exit)",
	{ walk = false }
)
parts(
	"parade_lane",
	"jolt",
	1,
	"off",
	"Map.Plaza.ParadeLane",
	{ "^Lane$" },
	"off",
	"the goo parade lane: one 0.43-stud-thick curved strip on the ground that walkers cross",
	{ walk = false, flag = { name = "Parade", off = 0 } }
)

-- World decor (RanchProps): bug #11 converted these; kept exactly. Box / Hull per docs/COLLISION.md.
local DECOR_PROPS: { { string | number } } = {
	-- kind, mesh, count, fidelity, reason
	{ "decor_crate", "ranch_crate", 1, "Box", "3x3x3 cube: the box is the shape" },
	{ "decor_crate_goo", "ranch_crate_goo", 1, "Box", "3x3x3 cube: the box is the shape" },
	{ "decor_feed_trough", "ranch_feed_trough", 1, "Box", "6x2.3x2.5 low box" },
	{ "decor_hay_bale", "ranch_hay_bale", 1, "Box", "4x2.6x2.6 bale" },
	{
		"decor_barrel",
		"ranch_barrel",
		1,
		"Box",
		"2.5x2.6x2.7 near-cylinder, a box has faces a walker stops against (v196)",
	},
	{ "decor_fence_stile", "ranch_fence_stile", 1, "Box", "5.8x5.5x4.9 solid block players jump onto (v196)" },
	{ "decor_hitching_post", "ranch_hitching_post", 1, "Box", "7.3x4.8x3.2 rail between posts" },
	{ "decor_water_trough", "ranch_water_trough", 1, "Box", "9.7x3.6x3.2 low box" },
	{ "decor_wagon", "ranch_wagon", 1, "Box", "9.9x3x5.8 cart, flat bed to stand on" },
	{ "decor_compost_bin", "ranch_compost_bin", 1, "Box", "5.5x4.8x5.3 slatted bin" },
	{ "decor_tool_rack", "ranch_tool_rack", 1, "Box", "7.7x8x3 rack, a flat wall" },
	{ "decor_flower_planter", "ranch_flower_planter", 1, "Box", "5.2x3.2x2 planter box" },
	{ "decor_picnic_table", "ranch_picnic_table", 1, "Box", "8.1x3.4x6 table with benches" },
	{ "decor_well", "ranch_well", 1, "Box", "6.9x7.7x5.5 stone well with a roof (v196)" },
	{ "decor_bench", "ranch_bench", 1, "Box", "6x4x2.4 bench with a back" },
	{ "decor_shed", "ranch_shed", 1, "Hull", "10.6x9.3x8.6 gabled shed: the hull follows the roof" },
	{ "decor_slime_coop", "ranch_slime_coop", 1, "Hull", "7.4x7.7x7.8 gabled coop" },
	{ "decor_rain_barrel", "ranch_rain_barrel", 1, "Hull", "3.3x5.6x5.5 barrel with a pipe" },
	{ "decor_barrel_stack", "ranch_barrel_stack", 1, "Hull", "5.2x5.4x4.7 pyramid of barrels" },
	{ "decor_milk_churn", "ranch_milk_churn", 1, "Hull", "2.7x6.1x2.5 churn" },
	{ "decor_scarecrow", "ranch_scarecrow", 1, "Hull", "7.2x9x3.5 pole with arms" },
	{ "decor_goo_bucket", "ranch_goo_bucket", 1, "Hull", "2.2x2.8x2.1 bucket" },
	{ "decor_goo_hive", "ranch_goo_hive", 1, "Hull", "3.8x5.7x4.8 dome" },
	{ "decor_weathervane", "ranch_weathervane", 1, "Hull", "5x8.6x3.4 vane on a pole" },
	{ "decor_wheelbarrow", "ranch_wheelbarrow", 1, "Hull", "6.6x3.5x3.8 wheelbarrow" },
	{ "decor_feed_sacks", "ranch_feed_sacks", 1, "Hull", "5.2x3.5x5.3 pile of sacks" },
	{
		"decor_windmill",
		"ranch_windmill",
		1,
		"Hull",
		"8.4x17.4x9.7 tower: the hull is the tower, the sails are overhead",
	},
	{ "decor_birdhouse", "ranch_birdhouse", 1, "Hull", "3.6x8x3.4 house on a pole" },
	{ "decor_water_pump", "ranch_water_pump", 1, "Hull", "3.8x4.4x4.9 pump" },
	{ "decor_campfire", "ranch_campfire", 1, "Hull", "4.3x4.6x4.3 stone ring and logs" },
	{ "decor_log_pile", "ranch_log_pile", 1, "Hull", "10.9x4x6.8 stacked logs" },
	{
		"decor_barn_loft",
		"ranch_barn_loft",
		1,
		"PreciseConvexDecomposition",
		"loft platform over an open ground floor: walk under and onto it (the one PCD)",
	},
}
for _, d in DECOR_PROPS do
	mesh(d[1] :: string, d[2] :: string, "jolt", d[3] :: number, d[4] :: string, DECOR, ON_MESH, d[5] :: string)
end
-- the stile's post is the plot fence's corner post mesh, placed once beside the stile
add({
	kind = "decor_stile_post",
	mesh = "phoenix_corner_post",
	owner = "jolt",
	count = 1,
	collision = "Box",
	now = ON_MESH,
	reason = "2.8x9.7x2.8 square post beside the fence stile",
	find = { under = DECOR, mesh = "phoenix_corner_post" },
})
-- per-plot mailbox slots: Gojo's plot decor skins them (PlotDecor.applySkin)
mesh(
	"plot_mailbox",
	"ranch_mailbox",
	"ambiguous",
	8,
	"Box",
	DECOR,
	ON_MESH,
	"1.4x5.4x2.7 box on a post at each plot's front edge: a Map.Decor slot of the world, but the per-plot mailbox that plot skins replace"
)
for _, p in
	{
		{
			"decor_pumpkin_patch",
			"ranch_pumpkin_patch",
			"a patch of pumpkins on the ground (crops): walk-through ground cover, 3.5 studs of squat pumpkins (COLLISION.md: patches stay passable)",
		},
		{ "decor_horseshoe_pit", "ranch_horseshoe_pit", "a sand pit 2.2 studs thick: ground level, walked over" },
		{
			"decor_sunflower_patch",
			"ranch_sunflower_patch",
			"a bed of sunflowers: thin stalks and flowers, walk-through plants (COLLISION.md: patches stay passable)",
		},
	}
do
	mesh(p[1], p[2], "jolt", 1, "off", DECOR, "mesh off, slot off", p[3])
end

-- Scattered primitives (WorldLayout.scatter): they collide on their own
parts(
	"decor_rocks",
	"jolt",
	45,
	"colliders",
	DECOR,
	{ "^Rock%d+$" },
	"on (Ball primitives, half sunk)",
	"scattered boulders (3-10 studs) are plain Ball parts that collide: nobody walks through them"
)
parts(
	"decor_mushrooms",
	"jolt",
	15,
	"colliders",
	DECOR,
	{ "^Mushroom%d+$" },
	"on (cap Ball + stem)",
	"mushrooms (1.6-3.2 studs) are primitives that collide on their own",
	{ models = true }
)
-- Meadow clusters (visuals/shared/Meadow): ground cover
parts(
	"meadow_grass",
	"jolt",
	146,
	"off",
	"Map.Decor.Meadow",
	{ "^M%d+Tuft%d+Blade%d+$" },
	"off",
	"grass blades: ground cover players walk through"
)
parts(
	"meadow_flowers",
	"jolt",
	233,
	"off",
	"Map.Decor.Meadow",
	{ "^M%d+Flower%d+Head$", "^M%d+Flower%d+Stem$", "^M%d+Bunch%d+Head%d+$", "^M%d+Bunch%d+Leaves$" },
	"off",
	"flowers, stems and leafy bunches (0.2 - 3.4 studs): ground cover players walk through"
)
parts(
	"meadow_pebbles",
	"jolt",
	17,
	"off",
	"Map.Decor.Meadow",
	{ "^M%d+Rock%d+$" },
	"off",
	"pebbles sunk to their top fifth (d 2.1 - 2.7, at most ~1.3 studs above the ground, Meadow.stone): below ankle-to-knee height, walked over"
)

-- Border: walls collide, everything else is behind them
parts(
	"border_walls",
	"jolt",
	48,
	"colliders",
	"Map.Border.Walls",
	nil,
	"on (48 invisible blocks, 80 tall)",
	"the closed wall ring at WorldBorder.RADIUS: the only collision of the edge",
	{ walk = false }
)
local BORDER_MESHES: { { string | number } } = {
	-- kind, mesh, count, what
	{ "border_giant_elder_oak", "giant_elder_oak", 5, "giant tree (v6)" },
	{ "border_giant_cloud_tree", "giant_cloud_tree", 5, "giant tree (v6)" },
	{ "border_giant_pine_layered", "giant_pine_layered", 5, "giant tree (v5)" },
	{ "border_giant_broadleaf", "giant_broadleaf", 5, "giant tree (v5)" },
	{ "border_giant_sequoia_spire", "giant_sequoia_spire", 5, "giant tree (v6)" },
	{ "border_giant_round_canopy", "giant_round_canopy", 5, "giant tree (v5)" },
	{ "border_chunk_h", "ranch_border_chunk_h", 1, "corner grove" },
	{ "border_chunk_h_m", "ranch_border_chunk_h_m", 1, "corner grove (mirrored)" },
	{ "border_chunk_b", "ranch_border_chunk_b", 1, "corner hill rocks" },
	{ "border_chunk_d", "ranch_border_chunk_d", 1, "corner pine grove" },
	{ "border_hill_ridge", "ranch_border_hill_ridge", 4, "backdrop hill" },
	{ "border_hill_dome", "ranch_border_hill_dome", 3, "backdrop hill" },
	{ "border_hill_twin", "ranch_border_hill_twin", 1, "backdrop hill" },
	{ "border_grove_rocky", "ranch_border_grove_rocky", 6, "rocky grove" },
	{ "border_grove_mixed", "ranch_border_grove_mixed", 7, "mixed grove" },
	{ "border_grove_pine", "ranch_border_grove_pine", 5, "pine grove" },
	{ "border_pine_tall", "ranch_border_pine_tall", 4, "pine" },
	{ "border_pine_broad", "ranch_border_pine_broad", 5, "pine" },
	{ "border_oak_round", "ranch_border_oak_round", 1, "oak" },
	{ "border_sapling_trio", "ranch_border_sapling_trio", 1, "saplings" },
	{ "border_rock_slab", "ranch_border_rock_slab", 1, "rock" },
	{ "border_rock_boulder", "ranch_border_rock_boulder", 1, "rock" },
	{ "border_rock_cluster", "ranch_border_rock_cluster", 1, "rock" },
	{ "border_fence_straight", "ranch_border_fence_straight", 8, "fence" },
	{ "border_fence_long", "ranch_border_fence_long", 5, "fence" },
	{ "border_hedge_long", "ranch_border_hedge_long", 6, "hedge" },
	{ "border_hedge_xl", "ranch_border_hedge_xl", 6, "hedge" },
	{ "border_hedge_round", "ranch_border_hedge_round", 1, "hedge" },
	{ "border_accent_pumpkin_patch", "ranch_pumpkin_patch", 1, "accent prop" },
}
for _, b in BORDER_MESHES do
	mesh(
		b[1] :: string,
		b[2] :: string,
		"jolt",
		b[3] :: number,
		"off",
		BORDER,
		"mesh off, slot off",
		`{b[4]}: {BEHIND_WALL}`,
		{ walk = false }
	)
end
-- the one border piece that is a collidable mesh (a ranch accent, Hull), also behind the wall
mesh(
	"border_accent_windmill",
	"ranch_windmill",
	"jolt",
	1,
	"Hull",
	BORDER,
	ON_MESH,
	"ranch accent behind the wall ring; keeps the shared windmill Hull",
	{ walk = false }
)

--------------------------------------------------------------------------------------------------------------------
-- GOJO: plot-level props (reported; the play probe only fails what is already collidable)
--------------------------------------------------------------------------------------------------------------------

mesh(
	"plot_fence_20",
	"ranch_fence_20",
	"gojo",
	112,
	"Box",
	"Plots",
	ON_MESH,
	"22x9x1.8 panel, a flat wall (replaces the old Wall* blocks)"
)
mesh("plot_fence_segment", "phoenix_fence_segment", "gojo", 16, "Box", "Plots", ON_MESH, "half panel beside the gate")
mesh(
	"plot_gate_corner_post",
	"phoenix_corner_post",
	"gojo",
	8,
	"Box",
	"Plots",
	ON_MESH,
	"square post at the gate's right stub"
)
mesh(
	"plot_gate_mesh",
	"phoenix_gate",
	"gojo",
	8,
	"off",
	"Plots",
	"mesh off, slot off",
	"a Box or Hull would close the 14-stud gate opening; the GatePostL/R stand-ins keep the posts"
)
parts(
	"plot_gate_posts",
	"gojo",
	16,
	"colliders",
	"Plots",
	{ "^GatePostL$", "^GatePostR$" },
	"on",
	"the gate's posts as simple blocks (the gate mesh is decor)"
)
mesh(
	"plot_pad_stand",
	"phoenix_pad_crate",
	"gojo",
	64,
	"off",
	"Plots",
	"mesh off, slot off",
	"the Pad part is the walkable surface"
)
parts("plot_pads", "gojo", 64, "colliders", "Plots", { "^Pad_%d+$" }, "on", "the pad is the stand-on surface")
parts(
	"plot_base",
	"gojo",
	8,
	"colliders",
	"Plots",
	{ "^Base$" },
	"on",
	"plot floor, the stand-on surface",
	{ walk = false }
)
parts(
	"plot_sign",
	"gojo",
	32,
	"colliders",
	"Plots",
	{ "^Sign$", "^Beam$", "^PostL$", "^PostR$" },
	"on (board, beam, two posts)",
	"plot name sign on posts"
)
parts(
	"plot_lock_button",
	"gojo",
	16,
	"colliders",
	"Plots",
	{ "^LockButton$", "^Pedestal$" },
	"on",
	"lock button and its pedestal"
)
parts(
	"plot_lock_sign",
	"gojo",
	24,
	"off",
	"Plots",
	{ "^LockSign$", "^Lamp$", "^Post$" },
	"off",
	"0.5 stud lamp post and a 0.3 thick sign: slim, in the plot front"
)
parts(
	"plot_lock_barrier",
	"gojo",
	32,
	"off",
	"Plots",
	{ "^Right$", "^Left$", "^Back$", "^Front$" },
	"off (PlotLockGuard / WorldView.enforceLocks ejects instead)",
	"locked-base teleport (Gojo, B1): the barriers are not solid; the lock is enforced by ejecting",
	{ walk = false }
)
mesh(
	"plot_dex_mesh",
	"phoenix_top_earners_board",
	"gojo",
	8,
	"off",
	"Plots",
	"mesh off, slot off",
	"the plot's SlimeDex board skin; its frame and legs are primitives (plot_dex_board)"
)
parts(
	"plot_dex_board",
	"gojo",
	112,
	"off",
	"Plots",
	{ "^Gem_%d+$", "^BarFill$", "^BarBack$", "^Shelf$", "^LegR$", "^LegL$", "^Frame$", "^Board$" },
	"off",
	"SlimeDex board primitives, all decor today (legs are 0.4 studs thick)"
)
parts(
	"plot_rebirth_decor",
	"gojo",
	112,
	"off",
	"Plots",
	{ "^Crown$", "^Banner_[RL]$", "^PillarCap_%d+$", "^Pillar_%d+$", "^Trim_%a+$" },
	"off",
	"rebirth cosmetics (pillars 2.2 studs, banners, trims): shown after rebirths"
)
parts(
	"plot_home_zone",
	"gojo",
	8,
	"off",
	"Plots",
	{ "^HomeZone$" },
	"off",
	"an invisible sensor volume",
	{ walk = false }
)

--------------------------------------------------------------------------------------------------------------------
-- Meshes in MeshAssets that no world slot places (templates, client decor, unused): nothing to collide
--------------------------------------------------------------------------------------------------------------------

-- name -> { owner, reason }
local UNPLACED: { [string]: { string } } = {
	ranch_border_fence_broken = { "jolt", "border piece not used by WorldBorder.CHUNKS / DEFS" },
	ranch_border_hedge_stepped = { "jolt", "border piece not used by WorldBorder.DEFS" },
	ranch_border_pine_twin = { "jolt", "border piece not used by WorldBorder.DEFS" },
	ranch_border_rock_spire = { "jolt", "border piece not used by WorldBorder.DEFS" },
	ranch_border_chunk_b_m = { "jolt", "mirrored twin not placed in this seed's corners" },
	ranch_border_chunk_d_m = { "jolt", "mirrored twin not placed in this seed's corners" },
	ranch_lantern_post = { "jolt", "no RanchProps placement (decor, not in the map)" },
	fountain_tier_ring = {
		"jolt",
		"client template cloned round the fountain at tier 2+ (FountainTierFx), visual only",
	},
	fountain_tier_crest = {
		"jolt",
		"client template cloned over the fountain at tier 3+ (FountainTierFx), visual only",
	},
	rain_magnet = { "gojo", "client template standing on the owner's plot (RainMagnetFx), visual only" },
	plot_skin_mushroom = { "gojo", "client plot-skin decor over Mailbox_<i> (PlotDecor.applySkin), visual only" },
	plot_skin_candy = { "gojo", "client plot-skin decor over Mailbox_<i> (PlotDecor.applySkin), visual only" },
	plot_skin_crystal = { "gojo", "client plot-skin decor over Mailbox_<i> (PlotDecor.applySkin), visual only" },
	habitat_crystal_grotto = { "gojo", "habitat pad seat cloned by the client (HabitatPads), pad part is the surface" },
	habitat_candy_patch = { "gojo", "habitat pad seat cloned by the client (HabitatPads), pad part is the surface" },
	habitat_barn_crate = { "gojo", "habitat pad seat cloned by the client (HabitatPads), pad part is the surface" },
	habitat_flower_bed = { "gojo", "habitat pad seat cloned by the client (HabitatPads), pad part is the surface" },
	habitat_hay_nest = { "gojo", "habitat pad seat cloned by the client (HabitatPads), pad part is the surface" },
	habitat_mushroom_ring = { "gojo", "habitat pad seat cloned by the client (HabitatPads), pad part is the surface" },
	habitat_rodeo_barrel = { "gojo", "habitat pad seat cloned by the client (HabitatPads), pad part is the surface" },
	habitat_show_stool = { "gojo", "habitat pad seat cloned by the client (HabitatPads), pad part is the surface" },
	habitat_syrup_pool = { "gojo", "habitat pad seat cloned by the client (HabitatPads), pad part is the surface" },
	slime_base = { "jolt", "slime kit mesh cloned per slime (SlimeMesh), never a world prop" },
	slime_acc_leaf = { "jolt", "slime kit mesh cloned per slime (SlimeMesh), never a world prop" },
	slime_ears = { "jolt", "slime kit mesh cloned per slime (SlimeMesh), never a world prop" },
	slime_horns = { "jolt", "slime kit mesh cloned per slime (SlimeMesh), never a world prop" },
	slime_acc_crown = { "jolt", "slime kit mesh cloned per slime (SlimeMesh), never a world prop" },
	slime_acc_crystal = { "jolt", "slime kit mesh cloned per slime (SlimeMesh), never a world prop" },
	slime_wobble = { "jolt", "slime kit mesh cloned per slime (SlimeMesh), never a world prop" },
	slime_lane = { "jolt", "the parade lane strip (entry parade_lane), laid by ParadeView, not a MeshAsset slot" },
}

PropCollision.ENTRIES = entries
PropCollision.UNPLACED = UNPLACED

-- Does an instance belong to `find`? `path` = dotted path under workspace ("Map.Decor.Barrel_8", "" prefix for the
-- workspace itself), `name` its name, `meshAttr` its MeshAsset attribute (or nil), `isPart` = it is a BasePart.
function PropCollision.matches(find: Find, path: string, name: string, meshAttr: string?, isPart: boolean): boolean
	if find.under ~= "" and path:sub(1, #find.under + 1) ~= find.under .. "." then
		return false
	end
	if find.parts and not isPart then
		return false
	end
	if find.mesh then
		return meshAttr == find.mesh
	end
	local names = find.names
	if names then
		for _, pattern in names do
			if string.find(name, pattern) then
				return true
			end
		end
		return false
	end
	return true
end

-- Expected count in a world where Config.FEATURES[flag] is `flagOn` (a flag the entry names, else count).
function PropCollision.expectedCount(entry: Entry, flags: { [string]: boolean }): number
	local flag = entry.flag
	if flag and not flags[flag.name] then
		return flag.off
	end
	return entry.count
end

function PropCollision.byKind(): { [string]: Entry }
	local out = {}
	for _, e in entries do
		out[e.kind] = e
	end
	return out
end

-- Counts per owner (entries and instances) for the inventory.
function PropCollision.totals(): { [string]: { kinds: number, instances: number, off: number, colliding: number } }
	local out = {}
	for owner in PropCollision.OWNERS do
		out[owner] = { kinds = 0, instances = 0, off = 0, colliding = 0 }
	end
	for _, e in entries do
		local t = out[e.owner]
		t.kinds += 1
		t.instances += e.count
		if e.collision == "off" then
			t.off += e.count
		else
			t.colliding += e.count
		end
	end
	return out
end

-- Pure geometry for the play probe and its spec. A prop's frame: centre (x, z), yaw (radians) and half extents
-- (hx, hz). The four sides are +-X and +-Z of that frame; the walker starts `gap` studs outside the edge and
-- MoveTos a point `past` studs beyond the centre (so it must cross the prop to arrive).
export type Side = { name: string, start: { number }, target: { number }, dir: { number } }

function PropCollision.sides(cx: number, cz: number, yaw: number, hx: number, hz: number, gap: number): { Side }
	local c, s = math.cos(yaw), math.sin(yaw)
	-- CFrame.Angles(0, yaw, 0): local (lx, lz) -> world (cx + lx*c + lz*s, cz - lx*s + lz*c)
	local function world(lx: number, lz: number): { number }
		return { cx + lx * c + lz * s, cz - lx * s + lz * c }
	end
	local out: { Side } = {}
	for _, d in { { "+X", 1, 0 }, { "-X", -1, 0 }, { "+Z", 0, 1 }, { "-Z", 0, -1 } } do
		local ux, uz = d[2] :: number, d[3] :: number
		local reach = (if ux ~= 0 then hx else hz) + gap
		table.insert(out, {
			name = d[1] :: string,
			start = world(-ux * reach, -uz * reach),
			target = world(ux * reach, uz * reach),
			dir = { ux * c + uz * s, -ux * s + uz * c },
		})
	end
	return out
end

-- Is the world point (x, z) inside the footprint rectangle (centre, yaw, half extents) grown by `margin`?
function PropCollision.insideFootprint(
	x: number,
	z: number,
	cx: number,
	cz: number,
	yaw: number,
	hx: number,
	hz: number,
	margin: number
): boolean
	local dx, dz = x - cx, z - cz
	local c, s = math.cos(yaw), math.sin(yaw)
	local lx = dx * c - dz * s
	local lz = dx * s + dz * c
	return math.abs(lx) <= hx + margin and math.abs(lz) <= hz + margin
end

return PropCollision
