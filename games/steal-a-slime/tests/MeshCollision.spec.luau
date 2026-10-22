--!nocheck
-- Real mesh collision (Merijn #10, #11): the big slimes stacked at the fountain top
-- (slime_fountain_emerge) are solid, so a player is pushed out of them or stands on top,
-- never inside. MeshSwap passes MeshAssets.COLLISION to CreateMeshPartAsync (the only place a
-- fidelity sticks on a script-made MeshPart) and turns CanCollide on for exactly those meshes;
-- every other swapped mesh stays decor (CanCollide off). docs/COLLISION.md has the rules.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local PvpModels = require("../src/shared/PvpModels")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")
local VatDecor = require("../src/visuals/shared/VatDecor")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local VALID = { Box = true, Hull = true, Default = true, PreciseConvexDecomposition = true }

describe("MeshAssets.COLLISION", function()
	it("names only uploaded meshes and real Enum.CollisionFidelity values", function()
		for name, fidelity in MeshAssets.COLLISION do
			expect(MeshAssets.meshId(name) ~= nil).toBe(true)
			expect(VALID[fidelity]).toBe(true)
			expect(MeshAssets.collision(name)).toBe(fidelity)
		end
	end)
	it("makes the shop stands solid with a hull (CONTRACT.md §27.2)", function()
		expect(MeshAssets.collision("ranch_item_shop")).toBe("Hull")
		expect(MeshAssets.collision("ranch_upgrade_cabinet")).toBe("Hull")
	end)
	it("makes the fountain-top slimes solid with a hull (cheap, no standing in the gaps)", function()
		expect(MeshAssets.collision("slime_fountain_emerge")).toBe("Box")
		expect(MeshAssets.collision("ranch_pumpkin_patch")).toBe(nil) -- decor stays non-colliding
	end)
	it("registers the follow-pet cloud as non-colliding decor", function()
		local entry = MeshAssets.get("pet_cloud")
		expect(entry ~= nil).toBe(true)
		expect(MeshAssets.collision("pet_cloud")).toBe(nil) -- decor: CanCollide off
		local size = entry.size
		expect(size[1] > 3 and size[1] < 3.5).toBe(true)
		expect(size[2] > 1 and size[2] < 1.5).toBe(true)
		expect(size[3] > 2 and size[3] < 2.8).toBe(true)
	end)
end)

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-meshcol-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)

local asked = {} -- meshId -> the CollisionFidelity option CreateMeshPartAsync got
local rt = Runtime.new(path, {
	createMeshPart = function(meshId, options)
		asked[meshId] = options and options.CollisionFidelity
		local part = roblox.Instance.new("MeshPart")
		-- like the engine: the fidelity in the options is what the part has
		if options and options.CollisionFidelity then
			part.CollisionFidelity = options.CollisionFidelity
		end
		return part
	end,
})
rt:boot()
rt:advance(2)
fs.removeFile(path)

describe("MeshSwap collision in the live server", function()
	it("boots clean", function()
		expect(#rt.errors).toBe(0)
	end)
	it("asks CreateMeshPartAsync for the fidelity, and only for meshes that have one", function()
		local emerge = MeshAssets.meshId("slime_fountain_emerge")
		expect(asked[emerge]).toBe(roblox.Enum.CollisionFidelity.Box)
		-- the meshes the world places: every MeshAsset slot under Map and Plots, and the vat mesh MeshSwap adds
		local placed = { [VatDecor.MESH] = true }
		for _, root in { rt.workspace.Map, rt.workspace.Plots } do
			for _, d in root:GetDescendants() do
				local name = d:GetAttribute("MeshAsset")
				if type(name) == "string" then
					placed[name] = true
				end
			end
		end
		local solid = {}
		local want = 0
		-- the FEATURES.FountainSplit pieces are only created with the flag on (tests/FountainSplit.spec)
		local splitPieces = {}
		for _, piece in MeshAssets.FOUNTAIN_SPLIT do
			splitPieces[piece] = true
		end
		for name, fidelity in MeshAssets.COLLISION do
			if splitPieces[name] then
				if not Config.FEATURES.FountainSplit then
					continue
				end
			elseif not placed[name] then
				continue -- no world slot asks for it
			end
			if name == "fountain_split_slide" and not Config.FEATURES.SlidePCD then
				continue -- the slide piece is PCD only with FEATURES.SlidePCD (MeshSwap.splitFidelity)
			end
			solid[MeshAssets.meshId(name)] = (roblox.Enum.CollisionFidelity :: any)[fidelity]
			want += 1
		end
		local count = 0
		for meshId, fidelity in asked do
			if fidelity ~= nil then
				count += 1
				expect(fidelity).toBe(solid[meshId])
			end
		end
		expect(count).toBe(want)
	end)
	it("the shop stands are solid Hull MeshParts (no extra collider boxes)", function()
		for _, name in { "ItemShopStand", "UpgradeShopStand" } do
			local mesh = rt.workspace.Map[name]:FindFirstChild("Mesh")
			expect(mesh ~= nil).toBe(true)
			expect(mesh.CanCollide).toBe(true)
			expect(mesh.CollisionFidelity).toBe(roblox.Enum.CollisionFidelity.Hull)
			expect(mesh.CanQuery).toBe(false)
		end
	end)
	it("the emerge slimes on the fountain are a solid Box MeshPart", function()
		local mesh = rt.workspace.Map.Volcano.EmergeMesh:FindFirstChild("Mesh")
		expect(mesh ~= nil).toBe(true)
		expect(mesh.CanCollide).toBe(true)
		expect(mesh.CollisionFidelity).toBe(roblox.Enum.CollisionFidelity.Box)
		expect(mesh.Anchored).toBe(true)
		expect(mesh.CanQuery).toBe(false)
		expect(mesh.CanTouch).toBe(false)
	end)
	it("every plot's merge vat is a solid Hull MeshPart over its disc", function()
		expect(MeshAssets.collision("merge_vat")).toBe("Hull")
		local vats = 0
		for _, plot in rt.workspace.Plots:GetChildren() do
			local vat = plot:FindFirstChild("MergeVat")
			local mesh = vat and vat:FindFirstChild("VatMesh")
			if mesh then
				vats += 1
				expect(mesh.CanCollide).toBe(true)
				expect(mesh.CollisionFidelity).toBe(roblox.Enum.CollisionFidelity.Hull)
				expect(mesh.CanQuery).toBe(false)
				expect(mesh.CanTouch).toBe(false)
			end
		end
		expect(vats > 0).toBe(true)
	end)
	it("a swapped mesh collides exactly when MeshAssets.COLLISION names it, and then its slot box is off", function()
		local decor, solid = 0, 0
		for _, root in { rt.workspace.Map, rt.workspace.Plots } do
			for _, d in root:GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "Mesh" and d.Parent.Name ~= "EmergeMesh" then
					local want = MeshAssets.collision(d.Parent:GetAttribute("MeshAsset"))
					expect(d.CanCollide).toBe(want ~= nil)
					if want then
						solid += 1
						expect(d.CollisionFidelity).toBe((roblox.Enum.CollisionFidelity :: any)[want])
						if d.Parent:IsA("Part") then
							expect(d.Parent.CanCollide).toBe(false) -- the mesh is the collider, not its slot box too
						end
					else
						decor += 1
					end
				end
			end
		end
		expect(decor > 10).toBe(true)
		expect(solid > 20).toBe(true)
	end)
	it("decor ranch prop slots (no COLLISION entry) never collide, even as a placeholder box", function()
		local seen = 0
		for _, d in rt.workspace.Map.Decor:GetChildren() do
			local mesh = d:GetAttribute("MeshAsset")
			if d:IsA("Part") and mesh and MeshAssets.collision(mesh) == nil then
				seen += 1
				expect(d.CanCollide).toBe(false)
			end
		end
		expect(seen > 0).toBe(true)
	end)
end)

-- Every mesh has a collision decision --------------------------------------------------------------------------
-- Every MeshAssets name is either solid (COLLISION) or listed here as decor with its reason, so a new mesh forces a decision.
local DECOR = {
	goo_cork_stand = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_foot = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_stair = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_door = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_door_ring = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_stopper = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_lock_button = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_mascot = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_crown = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_glass_1_mid = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_glass_2_mid = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_glass_3_mid = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_glass_1_top = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_glass_2_top = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_glass_3_top = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_glass_4_top = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_trim_1_mid = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_trim_2_mid = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_trim_3_mid = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_trim_1_top = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_trim_2_top = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_trim_3_top = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_trim_4_top = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_deck_2 = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_deck_3 = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_jar_deck_4 = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_drop_tube_glass_2 = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_drop_tube_glass_3 = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_drop_tube_glass_4 = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_drop_tube_goo_2 = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_drop_tube_goo_3 = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	goo_drop_tube_goo_4 = "goo jar tower look: decor over primitive colliders (the jar walls, decks, stair, lid, pads, stopper, button)",
	slime_fountain = "the tower: hand-placed Basin / Trim / Silo / Top + SlideColliders stay (docs/COLLISION.md, #252)",
	ranch_floor_deck = "B11 floor: flat timber plaza deck, 0.21 studs on the terrain; the terrain is the walk surface",
	ranch_floor_paths = "B11 floor: flat boardwalk ring + spokes, 0.21 studs on the terrain; the terrain is the walk surface (the gate ramps are parts)",
	phoenix_gate = "not placed: no world slot uses it (the jar's door is glass and primitives)",
	phoenix_pad_crate = "the pad's own Pad part is the gameplay surface; the stand is its decor",
	phoenix_top_earners_board = "WorldProps Model: its invisible Collider keeps the Model's bounds",
	ranch_guide = "WorldProps Model: the TutorialNpc's hidden primitive body parts stay the collider",
	ranch_landing_ring = "mesh stays decor (bbox 10 deep x 3.1 tall: Box/Hull = invisible wall); the stones are solid through thin Plaza colliders (LandingCurb/LandingStake, PropCollision landing_ring)",
	ranch_goo_drain = "mesh stays decor; solid through the DrainCurb disc + post + plaque colliders (PropCollision goo_drain), so the slide exit stays open",
	ranch_horseshoe_pit = "1.8 stud flat sand pit, walk over it",
	ranch_pumpkin_patch = "low foliage patch, walk through",
	ranch_sunflower_patch = "foliage, walk through",
	plot_skin_mushroom = "client-cloned plot skin template, not a world slot",
	plot_skin_candy = "client-cloned plot skin template, not a world slot",
	plot_skin_crystal = "client-cloned plot skin template, not a world slot",
	pet_cloud = "follow pet cloud (published by MeshSwap, cloned by client FollowPets): CanCollide false, never placed in the world",
	ranch_bat = "held Tool Handle mesh (Tool 'Bat'): CanCollide false, never placed in the world",
	giant_broadleaf = "border tree beyond the world wall ring, out of reach, canopy overhead",
	giant_pine_layered = "border tree beyond the world wall ring, out of reach",
	giant_round_canopy = "border tree beyond the world wall ring, out of reach, canopy overhead",
	giant_elder_oak = "border tree beyond the world wall ring, out of reach, canopy overhead",
	giant_sequoia_spire = "border tree beyond the world wall ring, out of reach",
	giant_cloud_tree = "border tree beyond the world wall ring, out of reach, canopy overhead",
	slime_lane = "the goo parade lane: a 0.43 stud flat strip players walk over",
}
for _, name in PvpModels.MESHES do
	DECOR[name] = "held PvP item (server/PvpHeld): CanCollide false, never placed in the world"
end
for _, group in
	{
		"ranch_border_", -- the world border pieces: beyond the invisible wall ring (WorldBorder), out of reach
		"habitat_", -- overlays on the pad deck round the slime: low client-only decor
	}
do
	for _, name in MeshAssets.NAMES do
		if string.sub(name, 1, #group) == group then
			DECOR[name] = `{group}* decor`
		end
	end
end

describe("real mesh collision", function()
	it("gives every COLLISION mesh a real Enum.CollisionFidelity name", function()
		local n = 0
		for name, fidelity in MeshAssets.COLLISION do
			n += 1
			expect(VALID[fidelity]).toBe(true)
			expect((roblox.Enum.CollisionFidelity :: any)[fidelity] ~= nil).toBe(true)
			expect(MeshAssets.get(name) ~= nil).toBe(true)
		end
		expect(n >= 40).toBe(true)
	end)
	it("classifies every mesh: solid (COLLISION) xor decor with a reason", function()
		local missing = {}
		for _, name in MeshAssets.NAMES do
			if (MeshAssets.COLLISION[name] ~= nil) == (DECOR[name] ~= nil) then
				table.insert(missing, name)
			end
		end
		expect(missing).toEqual({})
	end)
	it("has Hull for blobs, Box for boxes, and PCD only on the marked walkable shape (barn loft)", function()
		local pcd = {}
		local split = {} -- the FEATURES.FountainSplit tower pieces, flag off by default: tests/FountainSplit.spec
		for _, piece in MeshAssets.FOUNTAIN_SPLIT do
			split[piece] = true
		end
		for name, fidelity in MeshAssets.COLLISION do
			if fidelity == "PreciseConvexDecomposition" and not split[name] then
				table.insert(pcd, name)
			end
		end
		table.sort(pcd)
		expect(pcd).toEqual({ "ranch_barn_loft" })
		local count = { Hull = 0, Box = 0 }
		for _, fidelity in MeshAssets.COLLISION do
			if count[fidelity] then
				count[fidelity] += 1
			end
		end
		expect(count.Hull >= 13).toBe(true)
		expect(count.Box >= 15).toBe(true)
		for _, name in
			{
				"phoenix_corner_post",
				"ranch_crate",
				"ranch_wagon",
				"ranch_barrel",
				"ranch_well",
				"ranch_fence_stile",
			}
		do
			expect(MeshAssets.COLLISION[name]).toBe("Box")
		end
		for _, name in { "ranch_windmill", "ranch_shed" } do
			expect(MeshAssets.COLLISION[name]).toBe("Hull")
		end
	end)

	local WorldLayout = require("../src/visuals/shared/WorldLayout")
	local function walk(node: any, visit: (any) -> ())
		visit(node)
		for _, c in node.children or {} do
			walk(c, visit)
		end
	end
	it("leaves the fountain and slide colliders alone", function()
		local found = {}
		walk(WorldLayout.build()[1], function(n)
			found[n.name] = true
		end)
		for _, name in { "BasinCollider", "TrimCollider", "SiloCollider", "TopCollider1" } do
			expect(found[name]).toBe(true)
		end
		local SlideColliders = require("../src/shared/SlideColliders")
		expect(#SlideColliders.build(WorldLayout.SLIDE_PATH) > 0).toBe(true)
		expect(fs.isFile("src/server/FountainColliders.luau")).toBe(true)
		expect(MeshAssets.COLLISION.slime_fountain).toBe(nil)
	end)
end)

-- Plot-level collision: every plot mesh has a decided collision, and the goo jar keeps the owner's way in open ----
-- mesh -> expected MeshAssets.COLLISION fidelity (false = decor mesh; its collision is then the slot box / a part).
local PLOT_MESHES = {
	goo_cork_stand = false, -- goo jar tower look, the primitives under it collide
	goo_jar_foot = false, -- goo jar tower look, the primitives under it collide
	goo_jar_stair = false, -- goo jar tower look, the primitives under it collide
	goo_jar_door = false, -- goo jar tower look, the primitives under it collide
	goo_jar_door_ring = false, -- goo jar tower look, the primitives under it collide
	goo_jar_stopper = false, -- goo jar tower look, the primitives under it collide
	goo_lock_button = false, -- goo jar tower look, the primitives under it collide
	goo_jar_mascot = false, -- goo jar tower look, the primitives under it collide
	goo_jar_crown = false, -- goo jar tower look, the primitives under it collide
	goo_jar_glass_1_mid = false, -- goo jar tower look, the primitives under it collide
	goo_jar_glass_2_mid = false, -- goo jar tower look, the primitives under it collide
	goo_jar_glass_3_mid = false, -- goo jar tower look, the primitives under it collide
	goo_jar_glass_1_top = false, -- goo jar tower look, the primitives under it collide
	goo_jar_glass_2_top = false, -- goo jar tower look, the primitives under it collide
	goo_jar_glass_3_top = false, -- goo jar tower look, the primitives under it collide
	goo_jar_glass_4_top = false, -- goo jar tower look, the primitives under it collide
	goo_jar_trim_1_mid = false, -- goo jar tower look, the primitives under it collide
	goo_jar_trim_2_mid = false, -- goo jar tower look, the primitives under it collide
	goo_jar_trim_3_mid = false, -- goo jar tower look, the primitives under it collide
	goo_jar_trim_1_top = false, -- goo jar tower look, the primitives under it collide
	goo_jar_trim_2_top = false, -- goo jar tower look, the primitives under it collide
	goo_jar_trim_3_top = false, -- goo jar tower look, the primitives under it collide
	goo_jar_trim_4_top = false, -- goo jar tower look, the primitives under it collide
	goo_jar_deck_2 = false, -- goo jar tower look, the primitives under it collide
	goo_jar_deck_3 = false, -- goo jar tower look, the primitives under it collide
	goo_jar_deck_4 = false, -- goo jar tower look, the primitives under it collide
	goo_drop_tube_glass_2 = false, -- goo jar tower look, the primitives under it collide
	goo_drop_tube_glass_3 = false, -- goo jar tower look, the primitives under it collide
	goo_drop_tube_glass_4 = false, -- goo jar tower look, the primitives under it collide
	goo_drop_tube_goo_2 = false, -- goo jar tower look, the primitives under it collide
	goo_drop_tube_goo_3 = false, -- goo jar tower look, the primitives under it collide
	goo_drop_tube_goo_4 = false, -- goo jar tower look, the primitives under it collide
	phoenix_pad_crate = false, -- Pad_<j> (8 x 2.4 x 8, solid) is the surface
	phoenix_top_earners_board = false, -- the plaza Top Earners board's skin (the board keeps its own Collider)
}

describe("plot-level collision", function()
	local LayoutMath = require("../src/visuals/shared/LayoutMath")
	local WorldLayout = require("../src/visuals/shared/WorldLayout")
	local plots = WorldLayout.build()[2].children
	local function walk(node: any, visit: (any) -> ())
		visit(node)
		for _, c in node.children or {} do
			walk(c, visit)
		end
	end
	local function byName(plot: any): { [string]: any }
		local out = {}
		walk(plot, function(n)
			out[n.name] = n
		end)
		return out
	end
	-- True when plot-local (x, y, z) of plot i lies inside the part node (a yaw-turned block, or an upright disc).
	local function inside(node: any, i: number, x: number, y: number, z: number): boolean
		local centre, yaw = WorldLayout.plotCentre(i)
		local p = LayoutMath.apply(
			LayoutMath.orientation({ 0, -yaw, 0 }),
			{ node.pos[1] - centre[1], node.pos[2] - centre[2], node.pos[3] - centre[3] }
		)
		local dx, dy, dz = x - p[1], y - p[2], z - p[3]
		local s = node.size
		if node.shape == "Cylinder" then
			return math.abs(dy) <= s[1] / 2 + 1e-6 and dx * dx + dz * dz <= (s[2] / 2) ^ 2 + 1e-6
		end
		local a = math.rad(node.rot[2] - yaw)
		local lx = dx * math.cos(a) - dz * math.sin(a)
		local lz = dx * math.sin(a) + dz * math.cos(a)
		return math.abs(lx) <= s[1] / 2 + 1e-6 and math.abs(dy) <= s[2] / 2 + 1e-6 and math.abs(lz) <= s[3] / 2 + 1e-6
	end

	it("every mesh slot on a plot is classified, with the expected fidelity and no PCD", function()
		local seen = 0
		for _, plot in plots do
			walk(plot, function(n)
				local mesh = n.attributes and n.attributes.MeshAsset
				if mesh then
					seen += 1
					local want = PLOT_MESHES[mesh]
					expect(want ~= nil).toBe(true)
					expect(MeshAssets.collision(mesh)).toBe(if want then want else nil)
					expect(MeshAssets.collision(mesh) ~= "PreciseConvexDecomposition").toBe(true)
				end
			end)
		end
		expect(seen > 0).toBe(true)
	end)
	it("the pads, pedestal, bridge, sign and the jar's glass, lintel and lid are solid; its moat is decor", function()
		for _, plot in plots do
			local n = byName(plot)
			for _, name in { "PadCollider", "Pedestal", "Bridge", "Sign" } do
				expect(n[name].canCollide ~= false).toBe(true)
			end
			-- pads stay steppable: flat and low
			expect(n.Pad_1.size[2] <= 3).toBe(true)
			-- the pad box itself doesn't collide: its round collider (the dish's diameter) does
			expect(n.Pad_1.canCollide).toBe(false)
			expect(n.PadCollider.shape).toBe("Cylinder")
			expect(n.PadCollider.size[2]).toBeCloseTo(2 * WorldLayout.PAD_DECK.half)
			local walls, lintel, lid = 0, 0, 0
			for _, part in n.Jar.children do
				expect(part.canCollide ~= false).toBe(true)
				if string.match(part.name, "^Wall_%d+$") then
					walls += 1
					expect(part.canQuery).toBe(false) -- prompts and raycasts reach through the glass
				elseif part.name == "DoorLintel" then
					lintel += 1
				elseif part.name == "Lid" then
					lid += 1
					expect(part.attributes.JarLid).toBe(1)
				end
			end
			expect(walls).toBe(WorldLayout.JAR_WALL_SEGMENTS - 1)
			expect(lintel).toBe(1)
			expect(lid).toBe(1)
			for _, name in { "Moat", "JarFloor", "ParkedStopper" } do
				expect(n[name].canCollide).toBe(false)
			end
			expect(n.Stopper.canCollide).toBe(false) -- shipped unlocked; the server makes it solid while locked
		end
	end)
	it("closes jar 1's glass all the way round, open only at the doorway, and the lid sits on it", function()
		local f1 = WorldLayout.floorTop(1)
		local r = WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL / 2
		local door = WorldLayout.doorway()
		for i, plot in plots do
			local jar = byName(plot).Jar.children
			local function covered(x: number, y: number, z: number): boolean
				for _, part in jar do
					if inside(part, i, x, y, z) then
						return true
					end
				end
				return false
			end
			for _, h in { 0.5, 7, WorldLayout.FLOOR_HEIGHT - 1.5 } do
				for deg = 0, 359.5, 0.5 do
					local x, z = WorldLayout.jarWallPoint(1, deg)
					local inDoor = z < 0 and math.abs(x) < door.halfWidth and h < WorldLayout.DOOR.height
					if inDoor and math.abs(x) < door.halfWidth - 0.5 then
						expect(covered(x, f1 + h, z)).toBe(false)
					elseif not inDoor then
						expect(covered(x, f1 + h, z)).toBe(true)
					end
				end
			end
			-- the lid caps the glass: over the whole wall ring, from the wall top up
			for deg = 0, 359, 3 do
				local x, z = WorldLayout.polar(r, deg)
				expect(covered(x, f1 + WorldLayout.FLOOR_HEIGHT - 0.5, z)).toBe(true)
			end
		end
	end)
	it("the doorway is clear for the owner: no solid part but the Stopper inside WorldLayout.doorway()", function()
		local door = WorldLayout.doorway()
		local f1 = WorldLayout.PLOT_FLOOR_TOP
		local clear = door.halfWidth - 0.5 -- the glass either side may reach a few tenths into the box's edges
		expect(clear * 2 >= 6).toBe(true) -- still wide enough for a character
		for i, plot in plots do
			local solid = {}
			walk(plot, function(n)
				if n.class == "Part" and n.canCollide ~= false and n.name ~= "Stopper" then
					table.insert(solid, n)
				end
			end)
			local blocked = {}
			local seen = {}
			-- above the floor and the bridge planks (a step), under the lintel
			for y = f1 + 0.5, f1 + WorldLayout.DOOR.height - 0.25, 1 do
				for x = -clear, clear + 1e-9, 0.5 do
					for z = door.zOuter, door.zInner + 1e-9, 0.5 do
						for _, n in solid do
							if not seen[n] and inside(n, i, x, y, z) then
								seen[n] = true
								table.insert(blocked, `{plot.name}.{n.name}`)
							end
						end
					end
				end
			end
			expect(blocked).toEqual({})
		end
	end)
	it("the bridge spans the moat from the plot edge to the door", function()
		local door = WorldLayout.doorway()
		for i, plot in plots do
			local bridge = byName(plot).Bridge
			local top = WorldLayout.PLOT_FLOOR_TOP + 0.3
			for z = -(WorldLayout.PLOT_SIZE / 2 - 0.1), door.zOuter, 0.5 do
				for _, x in { -door.halfWidth, 0, door.halfWidth } do
					expect(inside(bridge, i, x, top, z)).toBe(true)
				end
			end
		end
	end)
end)
