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
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

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
		expect(MeshAssets.collision("ranch_shop_stand")).toBe("Hull")
	end)
	it("makes the fountain-top slimes solid with a hull (cheap, no standing in the gaps)", function()
		expect(MeshAssets.collision("slime_fountain_emerge")).toBe("Box")
		expect(MeshAssets.collision("ranch_pumpkin_patch")).toBe(nil) -- decor stays non-colliding
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
		local solid = {}
		local want = 0
		for name, fidelity in MeshAssets.COLLISION do
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
		local names = if Config.FEATURES.WorldShops then { "ItemShopStand", "UpgradeShopStand" } else { "ShopStand" }
		for _, name in names do
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
	it("every plot's merge vat is a solid Hull MeshPart over its disc (bug #16)", function()
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

-- bug #11 part 1 ------------------------------------------------------------------------------------------------
-- Every MeshAssets name is either solid (COLLISION) or listed here as decor with its reason, so a new mesh forces a decision.
local DECOR = {
	slime_fountain = "the tower: hand-placed Basin / Trim / Silo / Top + SlideColliders stay (docs/COLLISION.md, #252)",
	ranch_floor_deck = "B11 floor: flat timber plaza deck, 0.21 studs on the terrain; the terrain is the walk surface",
	ranch_floor_paths = "B11 floor: flat boardwalk ring + spokes, 0.21 studs on the terrain; the terrain is the walk surface (the gate ramps are parts)",
	phoenix_gate = "the entrance: a Box would close the 14-stud opening, the GatePost stand-ins keep the posts (PCD would be the mesh route)",
	phoenix_pad_crate = "the pad's own Pad part is the gameplay surface; the stand is its decor",
	phoenix_top_earners_board = "WorldProps Model: its invisible Collider keeps the Model's bounds",
	ranch_landing_ring = "ground-level tiles wilds land on: a Hull would be a 3-stud step wall round the fountain",
	ranch_goo_drain = "flat drain at the slide exit that wilds land on",
	ranch_horseshoe_pit = "1.8 stud flat sand pit, walk over it",
	ranch_lantern_post = "not placed (RanchProps.INTENTIONALLY_UNPLACED); its arm hangs overhead",
	ranch_pumpkin_patch = "low foliage patch, walk through",
	ranch_sunflower_patch = "foliage, walk through",
	plot_skin_mushroom = "client-cloned plot skin template, not a world slot",
	plot_skin_candy = "client-cloned plot skin template, not a world slot",
	plot_skin_crystal = "client-cloned plot skin template, not a world slot",
	fountain_tier_ring = "client-cloned tier decor, floats over the fountain",
	fountain_tier_crest = "client-cloned tier decor, floats over the fountain",
	rain_magnet = "client-cloned prop on the owner's plot",
	ranch_bat = "held Tool Handle mesh (Tool 'Bat'): CanCollide false, never placed in the world",
	giant_broadleaf = "border tree beyond the world wall ring, out of reach, canopy overhead",
	giant_pine_layered = "border tree beyond the world wall ring, out of reach",
	giant_round_canopy = "border tree beyond the world wall ring, out of reach, canopy overhead",
	giant_elder_oak = "border tree beyond the world wall ring, out of reach, canopy overhead",
	giant_sequoia_spire = "border tree beyond the world wall ring, out of reach",
	giant_cloud_tree = "border tree beyond the world wall ring, out of reach, canopy overhead",
	slime_lane = "the goo parade lane: a 0.43 stud flat strip players walk over",
}
for _, group in
	{
		"ranch_border_", -- the world border pieces: beyond the invisible wall ring (WorldBorder), out of reach
		"habitat_", -- 7.8 stud pad seats slimes rest in: low decor, players walk over
		"slime_acc_", -- worn by slimes
	}
do
	for _, name in MeshAssets.NAMES do
		if string.sub(name, 1, #group) == group then
			DECOR[name] = `{group}* decor`
		end
	end
end
for _, name in { "slime_base", "slime_ears", "slime_horns", "slime_wobble" } do
	DECOR[name] = "per-type slime kit mesh worn by slimes"
end

-- The invisible colliders bug #11 removed: each plot's five Wall* blocks, as plot-local (centre x, z, size x, z).
local REMOVED_COLLIDERS = {
	{ name = "WallBack", x = 0, z = 39.5, sx = 80, sz = 1 },
	{ name = "WallLeft", x = -39.5, z = 0, sx = 1, sz = 80 },
	{ name = "WallRight", x = 39.5, z = 0, sx = 1, sz = 80 },
	{ name = "WallFrontL", x = -25, z = -39.5, sx = 30, sz = 1 },
	{ name = "WallFrontR", x = 25, z = -39.5, sx = 30, sz = 1 },
}

describe("bug #11 part 1: real mesh collision", function()
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
	it("keeps decor out of COLLISION: the lane, the tower, the border, the habitats, worn slime meshes", function()
		for name in DECOR do
			expect(MeshAssets.COLLISION[name]).toBe(nil)
		end
		expect(MeshAssets.COLLISION.slime_lane).toBe(nil)
		expect(MeshAssets.COLLISION.slime_fountain).toBe(nil)
		expect(MeshAssets.COLLISION.phoenix_gate).toBe(nil)
	end)
	it("has Hull for blobs, Box for boxes, and PCD only on the marked walkable shape (barn loft)", function()
		local pcd = {}
		for name, fidelity in MeshAssets.COLLISION do
			if fidelity == "PreciseConvexDecomposition" then
				table.insert(pcd, name)
			end
		end
		table.sort(pcd)
		expect(pcd).toEqual({ "ranch_barn_loft" })
		local source = fs.readFile("src/shared/MeshAssets.luau")
		for _, name in pcd do
			expect(
				string.find(source, `{name} = "PreciseConvexDecomposition", -- PCD: Phoenix Studio check`, 1, true)
					~= nil
			).toBe(true)
		end
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
				"ranch_fence_20",
				"phoenix_fence_segment",
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
	it("MeshSwap passes the fidelity to CreateMeshPartAsync and turns CanCollide on (source-level)", function()
		local source = fs.readFile("src/server/MeshSwap.luau")
		expect(string.find(source, "MeshAssets.collision(name)", 1, true) ~= nil).toBe(true)
		expect(
			string.find(source, "options.CollisionFidelity = (Enum.CollisionFidelity :: any)[fidelity]", 1, true) ~= nil
		).toBe(true)
		expect(string.find(source, "mesh.CanCollide = fidelity ~= nil", 1, true) ~= nil).toBe(true)
	end)

	local WorldLayout = require("../src/visuals/shared/WorldLayout")
	local nodes = WorldLayout.build()
	local plots = nodes[2].children
	local function walk(node: any, visit: (any) -> ())
		visit(node)
		for _, c in node.children or {} do
			walk(c, visit)
		end
	end
	it("lists the removed colliders: no plot has a Wall* block any more", function()
		expect(#plots).toBe(Config.PLOT_COUNT)
		local removed = 0
		for _, plot in plots do
			walk(plot, function(n)
				for _, w in REMOVED_COLLIDERS do
					expect(n.name ~= w.name).toBe(true)
				end
			end)
			removed += #REMOVED_COLLIDERS
		end
		expect(removed).toBe(5 * Config.PLOT_COUNT) -- 40 parts saved
	end)
	it("covers every removed collider's footprint with a colliding Box fence slot (no walk-through gap)", function()
		local s = WorldLayout.PLOT_SIZE
		expect(s).toBe(80)
		for i, plot in plots do
			local centre, yaw = WorldLayout.plotCentre(i)
			local a = math.rad(yaw)
			local function toLocal(x: number, z: number): (number, number)
				local dx, dz = x - centre[1], z - centre[3]
				return dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
			end
			local slots = {}
			walk(plot, function(n)
				local mesh = n.attributes and n.attributes.MeshAsset
				if n.class == "Part" and n.attributes and n.attributes.FenceCollider then
					expect(n.canCollide ~= false).toBe(true) -- the placeholder box collides until the mesh lands
					expect(MeshAssets.collision(mesh)).toBe("Box")
					-- the wall was WALL_HEIGHT tall from y = 1; the panel is at least as tall and starts there
					expect(n.size[2] >= WorldLayout.WALL_HEIGHT).toBe(true)
					expect(math.abs(n.pos[2] - n.size[2] / 2 - 1) < 0.01).toBe(true)
					local lx, lz = toLocal(n.pos[1], n.pos[3])
					table.insert(
						slots,
						{ x = lx, z = lz, hx = n.size[1] / 2, hz = n.size[3] / 2, yaw = math.rad(n.rot[2]) - a }
					)
				end
			end)
			expect(#slots > 0).toBe(true)
			local function covered(px: number, pz: number): boolean
				for _, b in slots do
					local dx, dz = px - b.x, pz - b.z
					local c, sn = math.cos(b.yaw), math.sin(b.yaw)
					local lx, lz = dx * c + dz * sn, -dx * sn + dz * c
					if math.abs(lx) <= b.hx + 1e-6 and math.abs(lz) <= b.hz + 1e-6 then
						return true
					end
				end
				return false
			end
			for _, w in REMOVED_COLLIDERS do
				-- walk the old wall's centre line in 0.25 steps, across its whole span
				local alongX = w.sx > w.sz
				local half = (if alongX then w.sx else w.sz) / 2
				local t = -half
				while t <= half + 1e-9 do
					local px = if alongX then w.x + t else w.x
					local pz = if alongX then w.z else w.z + t
					expect(covered(px, pz)).toBe(true)
					t += 0.25
				end
			end
			-- and the gate opening stays open: nothing covers the middle of the entrance
			expect(covered(0, -39.5)).toBe(false)
			expect(covered(WorldLayout.GATE_CLEAR / 2 - 0.5, -39.5)).toBe(false)
			expect(covered(-(WorldLayout.GATE_CLEAR / 2 - 0.5), -39.5)).toBe(false)
		end
	end)
	it("leaves the fountain and slide colliders alone", function()
		local found = {}
		walk(nodes[1], function(n)
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

-- B9 plot-level half: every plot mesh has a decided collision --------------------------------------------------
-- mesh -> expected MeshAssets.COLLISION fidelity (nil = decor mesh; its collision is then a stand-in / the slot box).
local PLOT_MESHES = {
	ranch_fence_20 = "Box",
	phoenix_fence_segment = "Box",
	phoenix_corner_post = "Box",
	phoenix_gate = false, -- a Box/Hull would close the 14-stud opening; GatePostL / GatePostR stand-ins keep the posts
	phoenix_pad_crate = false, -- Pad_<j> (8 x 2.4 x 8, solid) is the surface
	phoenix_top_earners_board = false, -- shared with the world board (own Collider); the plot DexMesh slot box collides
}

describe("B9: plot-level collision", function()
	local WorldLayout = require("../src/visuals/shared/WorldLayout")
	local plots = WorldLayout.build()[2].children
	local function walk(node: any, visit: (any) -> ())
		visit(node)
		for _, c in node.children or {} do
			walk(c, visit)
		end
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
	it("the gate stays open for the owner; its posts, the pads and the dex board are solid", function()
		for _, plot in plots do
			local byName = {}
			walk(plot, function(n)
				byName[n.name] = n
			end)
			expect(byName.GateMesh.canCollide).toBe(false) -- the mesh slot would close the opening
			for _, name in { "GatePostL", "GatePostR", "GatePost", "DexMesh", "Pad_1", "Pad_8", "Pedestal" } do
				expect(byName[name].canCollide ~= false).toBe(true)
			end
			expect(byName.DexMesh.canQuery).toBe(false)
			expect(byName.DexMesh.canTouch).toBe(false)
			-- pads stay steppable: flat and low
			expect(byName.Pad_1.size[2] <= 3).toBe(true)
		end
	end)
	it("only the gate-side stand-ins sit beside the opening: nothing solid spans the walk-in", function()
		local clear = WorldLayout.GATE_CLEAR / 2
		for _, plot in plots do
			walk(plot, function(n)
				if n.class == "Part" and n.canCollide ~= false and n.pos and n.name ~= "Base" then
					local centre, yaw = WorldLayout.plotCentre(tonumber(string.match(plot.name, "%d+")) :: number)
					local a = math.rad(yaw)
					local dx, dz = n.pos[1] - centre[1], n.pos[3] - centre[3]
					local lx, lz = dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
					-- a low solid part (< 8 studs up) centred on the entrance line inside the clear width = blocked gate
					if math.abs(lz + 39.5) < 0.9 and math.abs(lx) < clear - 0.5 and n.pos[2] - n.size[2] / 2 < 8 then
						error(`{plot.name}.{n.name} blocks the gate opening`)
					end
				end
			end)
		end
	end)
end)
