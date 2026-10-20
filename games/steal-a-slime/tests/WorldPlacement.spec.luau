--!strict
-- World placement after the v28 playtest (live v27, TODO #6-#11): the fountain
-- silo is the map centre and everything fountain-shaped is laid out from it,
-- shops and key props face what they are for, and every placed prop stands on
-- its floor (no floating slots). The silo offset is also checked against the
-- kit's own exported mesh (shared/modeling-kit/out/slime_fountain.obj).
local fs = require("@lune/fs")

local BorderTerrain = require("../src/visuals/shared/BorderTerrain")
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local Meadow = require("../src/visuals/shared/Meadow")
local MeshAssets = require("../src/shared/MeshAssets")
local RanchProps = require("../src/visuals/shared/RanchProps")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Node = WorldLayout.WorldNode
type Vec = LayoutMath.Vec

local FOUNTAIN_OBJ = "../../shared/modeling-kit/out/slime_fountain.obj"
local CENTRE_TOL = 0.05
local FACE_TOL = 3 -- degrees
local GROUND_TOL = 0.1

local world = WorldLayout.build()

local function walk(nodes: { Node }?, visit: (Node, string) -> (), path: string?)
	for _, node in nodes or {} do
		local p = `{path or ""}/{node.name}`
		visit(node, p)
		walk(node.children, visit, p)
	end
end

local function find(path: string): Node
	local hit: Node? = nil
	walk(world, function(node, p)
		if p == path then
			hit = node
		end
	end)
	assert(hit, `no {path}`)
	return hit :: Node
end

local function flat(a: Vec, b: Vec): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
end

-- Signed difference a - b in degrees, in -180..180.
local function angleDiff(a: number, b: number): number
	return (a - b + 180) % 360 - 180
end

-- Bearing (yaw of a kit front, +Z turned yaw) from `from` towards `to`.
local function bearing(from: Vec, to: Vec): number
	return math.deg(math.atan2(to[1] - from[1], to[3] - from[3]))
end

local function slotYaw(node: Node): number
	return (node.rot :: Vec)[2]
end

describe("fountain at the map centre (TODO #6)", function()
	local c = WorldLayout.FOUNTAIN_CENTRE
	local slot = find("/Map/Volcano/FountainMesh")
	local silo = WorldLayout.FOUNTAIN_SILO_OFFSET

	it("puts the silo axis within 0.05 of the origin", function()
		expect(flat(c, { 0, 0, 0 }) < CENTRE_TOL).toBe(true)
		local axis = LayoutMath.add(slot.pos :: Vec, silo)
		expect(flat(axis, { 0, 0, 0 }) < CENTRE_TOL).toBe(true)
		-- the mesh slot is its native box, unturned, standing on the ground
		expect(slot.size).toEqual(WorldLayout.FOUNTAIN_MESH_SIZE)
		expect(slotYaw(slot)).toBe(0)
		expect((slot.pos :: Vec)[2] - (slot.size :: Vec)[2] / 2).toBeCloseTo(0)
	end)

	it("matches the silo offset of the kit's exported mesh (OBJ stave circle fit)", function()
		-- Blender OBJ: Roblox axes (x, z-up -> y, -y -> z), bbox-centred in X/Z.
		local xs, ys, zs = {}, {}, {}
		for line in string.gmatch(fs.readFile(FOUNTAIN_OBJ), "[^\n]+") do
			local x, y, z = string.match(line, "^v (%S+) (%S+) (%S+)")
			if x then
				table.insert(xs, tonumber(x) :: number)
				table.insert(ys, tonumber(y) :: number)
				table.insert(zs, tonumber(z) :: number)
			end
		end
		local function mid(t: { number }): number
			return (math.min(table.unpack(t)) + math.max(table.unpack(t))) / 2
		end
		local cx, cz = mid(xs), mid(zs)
		-- Algebraic circle fit (x^2 + z^2 = 2ax + 2bz + k) of the stave vertices
		-- round the expected axis, between the plinth and the eave.
		local m = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
		local v = { 0, 0, 0 }
		local n = 0
		for i = 1, #xs do
			local x, z = xs[i] - cx, zs[i] - cz
			local r = math.sqrt((x - silo[1]) ^ 2 + (z - silo[3]) ^ 2)
			if ys[i] > 5 and ys[i] < 29 and r > 10.5 and r < 12.2 then
				local row = { 2 * x, 2 * z, 1 }
				local rhs = x * x + z * z
				for a = 1, 3 do
					v[a] += row[a] * rhs
					for b = 1, 3 do
						m[a][b] += row[a] * row[b]
					end
				end
				n += 1
			end
		end
		expect(n > 100).toBe(true)
		-- Solve the 3x3 normal equations (Cramer).
		local function det(q: { { number } }): number
			return q[1][1] * (q[2][2] * q[3][3] - q[2][3] * q[3][2])
				- q[1][2] * (q[2][1] * q[3][3] - q[2][3] * q[3][1])
				+ q[1][3] * (q[2][1] * q[3][2] - q[2][2] * q[3][1])
		end
		local function solve(col: number): number
			local q = table.clone(m)
			for r = 1, 3 do
				q[r] = table.clone(m[r])
				q[r][col] = v[r]
			end
			return det(q) / det(m)
		end
		local ax, az = solve(1), solve(2)
		expect(math.abs(ax - silo[1]) < CENTRE_TOL).toBe(true)
		expect(math.abs(az - silo[3]) < CENTRE_TOL).toBe(true)
	end)

	it("keeps the emerge slot, colliders and crater on the same axis", function()
		local emerge = find("/Map/Volcano/EmergeMesh")
		local want = LayoutMath.add(slot.pos :: Vec, WorldLayout.FOUNTAIN_EMERGE_OFFSET)
		for k = 1, 3 do
			expect((emerge.pos :: Vec)[k]).toBeCloseTo(want[k])
		end
		-- the emerge offset is (-11.20, 18.94, -8.25) from the fountain bbox centre
		expect(WorldLayout.FOUNTAIN_EMERGE_OFFSET).toEqual({ -11.2, 18.94, -8.25 })
		local fp = WorldLayout.FOUNTAIN_PROFILE
		for name, radius in
			{ BasinCollider = fp.plinthRadius, TrimCollider = fp.trimRadius, SiloCollider = fp.wallRadius }
		do
			local node = find(`/Map/Volcano/{name}`)
			expect(flat(node.pos :: Vec, c) < CENTRE_TOL).toBe(true)
			expect((node.size :: Vec)[2]).toBeCloseTo(radius * 2)
		end
		expect(fp.plinthRadius).toBe(13.1)
		expect(fp.wallRadius).toBe(11.2)
		expect(fp.trimRadius).toBe(12.3)
		expect(flat(find("/Map/Volcano/Crater").pos :: Vec, c) < CENTRE_TOL).toBe(true)
	end)

	it("winds the slide round the silo axis and rings the landing tiles on it", function()
		local path = WorldLayout.SLIDE_PATH
		expect(math.abs(flat(path[1], c) - 4.8) < 0.1).toBe(true)
		expect(math.abs(flat(path[#path], c) - WorldLayout.SLIDE_END_RADIUS) < 0.1).toBe(true)
		-- the mouth is on +Z of the axis (the mesh's slide exit)
		expect(path[#path][3] - c[3] > 30).toBe(true)
		local tiles = find("/Map/Plaza/LandingRing").children or {}
		expect(#tiles).toBe(11) -- 18 less the 7 left out where the slide lands slimes
		local r0 = nil
		for _, tile in tiles do
			local p = tile.pos :: Vec
			local r = flat(p, c)
			r0 = r0 or r
			expect(r).toBeCloseTo(r0 :: number)
			-- each 20 degree tile's bbox centre sits on +Z of its turn (arc centre = axis)
			expect(math.abs(angleDiff(slotYaw(tile), bearing(c, p))) < 0.01).toBe(true)
		end
	end)
end)

describe("shops face the map centre (TODO #10)", function()
	it("turns the plaza ShopStand's Props front (-Z) at the fountain", function()
		for _, name in { Constants.SHOP_STAND_ITEM, Constants.SHOP_STAND_UPGRADE } do
			local spot = WorldLayout.PROP_SPOTS[name]
			-- Props front is local -Z: kit-front bearing = yaw + 180
			local diff = angleDiff(spot.yaw + 180, bearing(spot.pos, WorldLayout.FOUNTAIN_CENTRE))
			expect(math.abs(diff) < FACE_TOL).toBe(true)
			expect(WorldLayout.PROP_MESHES[name]).toBe(WorldLayout.BUY_STAND_MESH)
		end
	end)
	it(
		"turns the Top Earners board's front (-Z, the SurfaceGui) at the map centre within 3 degrees (v29 B3)",
		function()
			local spot = WorldLayout.PROP_SPOTS[Constants.LEADERBOARD_BOARD]
			local diff = angleDiff(spot.yaw + 180, bearing(spot.pos, WorldLayout.FOUNTAIN_CENTRE))
			expect(math.abs(diff) < 3).toBe(true)
		end
	)
end)

describe("prop facing audit (TODO #11)", function()
	local props: { [string]: WorldLayout.RanchProp } = {}
	for _, p in WorldLayout.RANCH_PROPS do
		props[p.name] = p
	end
	local function faces(name: string, target: Vec, tol: number?)
		local p = props[name]
		local diff = angleDiff(p.yaw, bearing(p.pos, target))
		if math.abs(diff) >= (tol or FACE_TOL) then
			error(`{name} faces {p.yaw}, {diff} off its target`)
		end
	end

	it("sits the camp bench facing its campfire", function()
		faces("CampBench", props.Campfire.pos)
	end)
	it("gives every plot a mailbox and turns its door at the spoke path", function()
		for i = 1, Config.PLOT_COUNT do
			local _, plotYaw = WorldLayout.plotCentre(i)
			local name = `Mailbox_{i}`
			local p = props[name]
			expect(p ~= nil).toBe(true)
			expect(p.mesh).toBe("ranch_mailbox")
			-- the spoke path runs along the plot's local z axis (x = 0)
			local centre = WorldLayout.plotCentre(i)
			local local_ = LayoutMath.apply(
				LayoutMath.orientation({ 0, -plotYaw, 0 }),
				{ p.pos[1] - centre[1], 0, p.pos[3] - centre[3] }
			)
			local foot = LayoutMath.add(
				centre,
				LayoutMath.apply(LayoutMath.orientation({ 0, plotYaw, 0 }), {
					0,
					0,
					local_[3],
				})
			)
			faces(name, foot)
			expect(RanchProps.ENTRANCE_PATH_YAW[p.mesh] ~= nil).toBe(true)
		end
	end)
	it("faces the plaza vignettes, signs and wedge / shed fronts at the fountain", function()
		for _, name in
			{
				"Campfire",
				"Well",
				"WellPump",
				"PicnicTable",
				"Sunflowers",
				"HorseshoePit",
				"GooSign",
				"Birdhouse",
				"Planter",
				"Ranch1",
				"Ranch2",
				"Ranch3",
				"Ranch4",
				"Shed",
			}
		do
			faces(name, WorldLayout.FOUNTAIN_CENTRE)
		end
	end)
	it("faces the plaza signpost and podium plaques at the fountain", function()
		for _, def in WorldLayout.PLAZA_PROPS do
			local node = find(`/Map/Plaza/{def.name}`)
			local diff = angleDiff(slotYaw(node), bearing(node.pos :: Vec, WorldLayout.FOUNTAIN_CENTRE))
			expect(math.abs(diff) < FACE_TOL).toBe(true)
		end
	end)
	it("faces each farmyard prop back towards its plot (the entrance side)", function()
		for _, row in RanchProps.PLACEMENTS do
			if row.plot and row.cluster == "farm" then
				local centre = WorldLayout.plotCentre(row.plot)
				faces(row.name, centre, 45)
			end
		end
	end)
	it("faces dex boards at the entrance and the jar's name label out of the jar", function()
		for i = 1, Config.PLOT_COUNT do
			local centre = WorldLayout.plotCentre(i)
			-- the Sign's text is on its Front face (local -Z), half a turn from a kit front
			local sign = find(`/Plots/Plot_{i}/Sign`)
			local out = bearing(centre, sign.pos :: Vec)
			expect(math.abs(angleDiff(slotYaw(sign) + 180, out)) < FACE_TOL).toBe(true)
			local dex = find(`/Plots/Plot_{i}/DexBoard/DexMesh`)
			expect(math.abs(angleDiff(slotYaw(dex), bearing(dex.pos :: Vec, centre))) < FACE_TOL).toBe(true)
		end
	end)
end)

-- Floor under (x, z): a plot Base top (1) inside a plot square, else the
-- Ground top (0). The plaza disc and paths are <= 0.25 sand overlays.
local function floorAt(x: number, z: number): number
	for i = 1, Config.PLOT_COUNT do
		local c, yaw = WorldLayout.plotCentre(i)
		local l = LayoutMath.apply(LayoutMath.orientation({ 0, -yaw, 0 }), { x - c[1], 0, z - c[3] })
		local h = WorldLayout.PLOT_SIZE / 2
		if math.abs(l[1]) <= h and math.abs(l[3]) <= h then
			return 1
		end
	end
	return 0
end

describe("ground contact (TODO #9)", function()
	it("stands every mesh slot on its floor (bottom within 0.1)", function()
		local bad, n = {}, 0
		walk(world, function(node, path)
			local a = node.attributes
			local mesh = a and (a.MeshAsset or a.BorderMesh)
			if node.class ~= "Part" or not mesh then
				return
			end
			-- the emerge slimes sit in the fountain's goo crown, by design
			if mesh == "slime_fountain_emerge" then
				return
			end
			n += 1
			local p, size = node.pos :: Vec, node.size :: Vec
			local bottom = p[2] - size[2] / 2
			local floor = floorAt(p[1], p[3])
			if string.find(path, "/Decor/Giant", 1, true) then
				-- border v4 giant trees stand on the terrain hills (rooted at the lowest footprint sample, a stud in), not the Ground
				local h = BorderTerrain.field().height(p[1], p[3])
				if bottom > h + GROUND_TOL or bottom < h - 30 then
					table.insert(bad, `{path} ({mesh}) bottom {bottom}, terrain {h}`)
				end
				return
			end
			if math.abs(bottom - floor) > GROUND_TOL then
				table.insert(bad, `{path} ({mesh}) bottom {bottom}, floor {floor}`)
			end
		end)
		expect(n > 300).toBe(true)
		expect(bad).toEqual({})
	end)
	it("rests every Map.Decor.Meadow piece on its floor (none floats, none buried)", function()
		local bad, n = {}, 0
		walk(find("/Map/Decor/Meadow").children, function(node, path)
			if node.class ~= "Part" then
				return
			end
			n += 1
			local p, size = node.pos :: Vec, node.size :: Vec
			local floor = floorAt(p[1], p[3])
			local low = if node.shape == "Ball"
				then p[2] - size[1] / 2
				else Meadow.blockBottom(size, p, node.rot or { 0, 0, 0 })
			local high = if node.shape == "Ball" then p[2] + size[1] / 2 else 2 * p[2] - low
			-- flower heads rest on their stem / leaves (tests/Meadow.spec); every
			-- other piece touches (or sinks into) the floor, and shows above it
			local head = string.match(node.name, "Head%d*$") ~= nil
			if (not head and low > floor + GROUND_TOL) or high < floor + GROUND_TOL then
				table.insert(bad, `{path} bottom {low}, top {high}, floor {floor}`)
			end
		end, "/Map/Decor/Meadow")
		expect(n > 100).toBe(true)
		expect(bad).toEqual({})
	end)
	it("stands every RanchProps prop on the ground", function()
		for _, p in WorldLayout.RANCH_PROPS do
			expect(math.abs(p.pos[2] - p.size[2] / 2 - floorAt(p.pos[1], p.pos[3])) <= GROUND_TOL).toBe(true)
		end
	end)
	it("stands the WorldProps Props (shop, board, NPC) on the ground at their spots", function()
		local Props = StaticWorld.visual("Props")
		for name, build in
			{
				[Constants.SHOP_STAND_ITEM] = Props.shopStand,
				[Constants.SHOP_STAND_UPGRADE] = Props.shopStand,
				[Constants.LEADERBOARD_BOARD] = Props.leaderboardBoard,
				[Constants.TUTORIAL_NPC] = Props.tutorialNpc,
			}
		do
			local spot = WorldLayout.PROP_SPOTS[name]
			expect(spot.pos[2]).toBe(0)
			local lowest = math.huge
			for _, d in (build() :: any):GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					lowest = math.min(lowest, d.CFrame.Position.Y - d.Size.Y / 2)
				end
			end
			expect(math.abs(lowest) <= GROUND_TOL).toBe(true)
		end
	end)
end)

describe("hub spawn pad (TODO #8: the yellow slab)", function()
	it("is an invisible pad flush with the plaza sand", function()
		expect(StaticWorld.SPAWN_TRANSPARENCY).toBe(1)
		local size = StaticWorld.SPAWN_SIZE
		local top = StaticWorld.spawnPosition()[2] + size[2] / 2
		local plazaTop = 0 -- the GroundTerrain surface
		expect(math.abs(top - plazaTop) <= GROUND_TOL).toBe(true)
		expect(size[2] <= 0.25).toBe(true)
	end)
	it("is the only SpawnLocation-like slab in the built place's Workspace root", function()
		local spawn
		for _, inst in StaticWorld.build() do
			if inst.Name == StaticWorld.SPAWN_NAME then
				spawn = inst
			end
		end
		expect(spawn ~= nil).toBe(true)
		expect(spawn.Transparency).toBe(1)
		expect(spawn.CanCollide).toBe(true)
		expect(spawn.Anchored).toBe(true)
	end)
end)

describe("kit mesh import turn", function()
	it("is one constant MeshSwap applies (see tests/MeshFit.spec)", function()
		expect(MeshAssets.IMPORT_YAW).toBe(180)
	end)
end)
