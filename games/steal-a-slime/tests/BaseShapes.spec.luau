--!nocheck
-- Base shapes (CONTRACT.md §44): the generated Goo Factory data keeps the kit design's rules (pad spacing, wall
-- clearance, spawn, footprint, ramp width / slope / flush ends), its floors build with the right pieces, and a plot
-- turns from the jar into the factory and back keeping its pads, vat, lock and their prompts and meshes.
local roblox = require("@lune/roblox")

local Actions = require("../src/server/Actions")
local BaseShapes = require("../src/visuals/shared/BaseShapes")
local Config = require("../src/shared/Config")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")
local WorldBuilder = require("../src/visuals/shared/WorldBuilder")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local Factory = BaseShapes.data("factory")
local PAD = WorldLayout.PAD_SIZE
local GAP = 3 -- walkway between pads, edge to edge
local WALL_CLEAR = 4.5 -- pad edge to wall face
local MOAT_IN = WorldLayout.MOAT.inner

-- Roblox globals WorldBuilder uses at call time (as tests/PlaceSafety.spec does).
local GLOBALS = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}
local function withRoblox(fn: () -> ())
	local env = getfenv(WorldBuilder.build)
	local saved = {}
	for name, value in GLOBALS do
		saved[name] = env[name]
		env[name] = value
	end
	local ok, err = pcall(fn)
	for name in GLOBALS do
		env[name] = saved[name]
	end
	if not ok then
		error(err, 0)
	end
end

-- Horizontal corners of a part (plot-local x, z), turned by its orientation.
local function corners(p): { { number } }
	local cf = roblox.CFrame.new(p.pos[1], p.pos[2], p.pos[3])
		* roblox.CFrame.fromOrientation(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local w =
					cf:PointToWorldSpace(roblox.Vector3.new(sx * p.size[1] / 2, sy * p.size[2] / 2, sz * p.size[3] / 2))
				table.insert(out, { w.X, w.Z })
			end
		end
	end
	return out
end

-- Distance from (x, z) to a wall part's footprint rectangle (axis-aligned walls).
local function toWall(x: number, z: number, p): number
	local xs, zs = {}, {}
	for _, c in corners(p) do
		table.insert(xs, c[1])
		table.insert(zs, c[2])
	end
	local dx = math.max(math.min(table.unpack(xs)) - x, 0, x - math.max(table.unpack(xs)))
	local dz = math.max(math.min(table.unpack(zs)) - z, 0, z - math.max(table.unpack(zs)))
	return math.sqrt(dx * dx + dz * dz)
end

local function padsOn(f: number)
	local out = {}
	for _, pad in Factory.pads do
		if math.ceil(pad.j / Config.PADS_PER_FLOOR) == f then
			table.insert(out, pad)
		end
	end
	return out
end

describe("base shapes: the Goo Factory's generated layout", function()
	it("has PADS_PER_FLOOR pads on each of the 4 floors", function()
		expect(#Factory.pads).toBe(#Config.BASE_FLOORS * Config.PADS_PER_FLOOR)
		for f = 1, #Config.BASE_FLOORS do
			expect(#padsOn(f)).toBe(Config.PADS_PER_FLOOR)
		end
	end)
	it("keeps a 3-stud walkway between pads and 4.5 studs to the walls on every floor", function()
		for f = 1, #Config.BASE_FLOORS do
			local pads = padsOn(f)
			for a = 1, #pads do
				for b = a + 1, #pads do
					local d = math.max(math.abs(pads[a].x - pads[b].x), math.abs(pads[a].z - pads[b].z)) - PAD
					expect(d >= GAP - 1e-6).toBe(true)
				end
				for _, p in Factory.parts do
					if p.floor == f and p.role == "wall" then
						expect(toWall(pads[a].x, pads[a].z, p) - PAD / 2 >= WALL_CLEAR - 1e-6).toBe(true)
					end
				end
			end
		end
	end)
	it("keeps the spawn spot clear and the vat and lock button inside the door", function()
		local sx, sz = WorldLayout.SPAWN_SPOT[1], WorldLayout.SPAWN_SPOT[2]
		expect(Factory.spawn[1]).toBe(sx)
		expect(Factory.spawn[2]).toBe(sz)
		for _, pad in padsOn(1) do
			expect(math.sqrt((pad.x - sx) ^ 2 + (pad.z - sz) ^ 2) - PAD / 2 >= 3).toBe(true)
		end
		expect(Factory.vat[2] > Factory.door.z + 1).toBe(true)
		expect(Factory.lockButton[2] > Factory.door.z + 1).toBe(true)
	end)
	it("stays inside the moat: no collider reaches past its inner edge", function()
		for _, p in Factory.parts do
			if p.role == "drop pipe guard" then
				continue -- round the drop pipe, out over the moat like the pipe itself
			end
			for _, c in corners(p) do
				expect(math.sqrt(c[1] * c[1] + c[2] * c[2]) <= MOAT_IN + 1e-6).toBe(true)
			end
		end
	end)
	it("climbs on ramps at least 4 wide, no steeper than 32 degrees, each ending on a floor or the landing", function()
		expect(#Factory.ramps > 0).toBe(true)
		for _, r in Factory.ramps do
			expect(r.width >= 4).toBe(true)
			local run = math.sqrt((r.b[1] - r.a[1]) ^ 2 + (r.b[3] - r.a[3]) ^ 2)
			expect(math.deg(math.atan2(r.b[2] - r.a[2], run)) <= 32).toBe(true)
			local top = r.b[2]
			local flush = false
			for f = 1, #Config.BASE_FLOORS do
				local floor = WorldLayout.floorTop(f)
				flush = flush
					or math.abs(top - floor) < 0.1
					or math.abs(top - (floor + WorldLayout.FLOOR_HEIGHT / 2)) < 0.1
			end
			expect(flush).toBe(true)
		end
	end)
	it("turns every drop hatch's +Z out of the building (BaseFloors puts the prompt 1.5 studs in on -Z)", function()
		local seen = 0
		for _, p in Factory.parts do
			if p.name == "DropHatch" then
				seen += 1
				local cf = roblox.CFrame.fromOrientation(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
				local out = cf.LookVector * -1 -- local +Z
				-- the outward normal of the wall it sits in
				local normal = if math.abs(p.pos[1]) > math.abs(p.pos[3])
					then roblox.Vector3.new(math.sign(p.pos[1]), 0, 0)
					else roblox.Vector3.new(0, 0, math.sign(p.pos[3]))
				expect(out:Dot(normal) > 0.99).toBe(true)
			end
		end
		expect(seen).toBe(#Config.BASE_FLOORS - 1)
	end)
end)

describe("base shapes: no way out of a locked factory", function()
	it("plugs the drop hatch hole of every floor a floor stands on (a closed hatch stops colliding)", function()
		local plugs = {}
		for _, p in Factory.parts do
			if p.name == "HatchPlug" then
				expect(p.show).toBe("covered")
				expect(p.collide).toBe(true)
				plugs[p.floor] = true
			end
		end
		for f = 2, #Config.BASE_FLOORS - 1 do
			expect(plugs[f]).toBe(true)
		end
		expect(plugs[#Config.BASE_FLOORS]).toBeNil() -- the top floor is never covered: its hatch is the exit
	end)
	it("lets the owner take the drop exit only from inside the factory's top floor", function()
		local top = #Config.BASE_FLOORS
		local y = WorldLayout.floorTop(top) + 3
		expect(Actions.insideJar(top, 20, y, 20, "factory")).toBe(true)
		expect(Actions.insideJar(top, 20, y, 20)).toBe(false) -- the jar's glass is round
		expect(Actions.insideJar(top, 26, y, 0, "factory")).toBe(false)
		expect(Actions.insideJar(top, 0, WorldLayout.floorTop(top - 1) + 3, 0, "factory")).toBe(false)
	end)
end)

describe("base shapes: the Mushroom Pagoda's generated layout", function()
	local Pagoda = BaseShapes.data("pagoda")
	it("has its own shape: every base but the jar does (none falls back to the jar)", function()
		for _, base in Config.PLOT_BASES do
			expect(`{base.id}: {BaseShapes.get(base.id).id}`).toBe(`{base.id}: {base.id}`)
		end
	end)
	it("climbs a helix at least 4 wide and no steeper than 32 degrees where feet go", function()
		expect(#Pagoda.ramps).toBe(#Config.BASE_FLOORS - 1)
		for _, r in Pagoda.ramps do
			expect(r.kind).toBe("helix")
			expect(r.r_out - r.r_in >= 4).toBe(true)
			local walk = (r.r_in + r.r_out) / 2
			local slope = math.deg(math.atan2(r.rise, math.rad(r.sweep) * walk))
			expect(slope <= 32).toBe(true)
		end
	end)
	it("keeps the pads clear of the round room's wall and of each other", function()
		for f = 1, #Config.BASE_FLOORS do
			local pads = {}
			for _, pad in Pagoda.pads do
				if math.ceil(pad.j / Config.PADS_PER_FLOOR) == f then
					table.insert(pads, pad)
				end
			end
			expect(#pads).toBe(Config.PADS_PER_FLOOR)
			local room = Pagoda.inside.radii[f]
			for a = 1, #pads do
				local r = math.sqrt(pads[a].x ^ 2 + pads[a].z ^ 2)
				expect(room - r - PAD / 2 * math.sqrt(2) >= 3).toBe(true)
				for b = a + 1, #pads do
					local d = math.sqrt((pads[a].x - pads[b].x) ^ 2 + (pads[a].z - pads[b].z) ^ 2)
					expect(d - PAD >= GAP - 0.1).toBe(true)
				end
			end
		end
	end)
	it("has a drop hatch facing out on floors 2-4, and the dome only in the roof folder", function()
		local pagoda = BaseShapes.get("pagoda")
		for f = 2, #Config.BASE_FLOORS do
			local hatch = nil
			for _, child in pagoda.floor(1, f)[1].children :: { any } do
				-- floors 2-3 keep their dome in the roof folder; floor 4 is always the top, so its dome stands on it
				-- (its mesh slots stay on every floor, shown only while it is the top one)
				local slot = child.attributes and child.attributes.MeshAsset
				if f < #Config.BASE_FLOORS and not slot then
					expect(string.sub(child.name, 1, 4) ~= "Dome").toBe(true)
				end
				if child.name == "DropHatch" then
					hatch = child
				end
			end
			expect(hatch ~= nil).toBe(true)
		end
		local roof = (pagoda.top :: any)(1, 2)
		expect(roof.name).toBe("TopColliders")
		expect(roof.attributes.TopFloor).toBe(2)
		local domes = 0
		for _, child in roof.children do
			if string.sub(child.name, 1, 4) == "Dome" then
				domes += 1
			end
		end
		expect(domes > 0).toBe(true)
	end)
end)

describe("base shapes: shapes", function()
	it("gives the jar for nil and unknown ids", function()
		expect(BaseShapes.get(nil).id).toBe("jar")
		expect(BaseShapes.get("castle").id).toBe("jar")
		expect(BaseShapes.get("factory").id).toBe("factory")
	end)
	it("knows the factory's square walls and the jar's round glass", function()
		local factory, jar = BaseShapes.get("factory"), BaseShapes.get("jar")
		expect(factory.inside(1, 23, 23)).toBe(true)
		expect(factory.inside(1, 25, 0)).toBe(false)
		expect(factory.inside(1, 24.9, 0, 1.5)).toBe(true)
		expect(jar.inside(1, 23, 23)).toBe(false) -- outside the jar's glass (radius 31)
		expect(jar.inside(1, 30, 0)).toBe(true)
		expect(factory.guard.square).toBe(true)
	end)
	it("builds each factory floor as Floor_<f> with its pads, the roof shown only on the top floor", function()
		local factory = BaseShapes.get("factory")
		for f = 2, #Config.BASE_FLOORS do
			local nodes = factory.floor(1, f)
			expect(nodes[1].name).toBe(`Floor_{f}`)
			expect(#nodes).toBe(1 + Config.PADS_PER_FLOOR)
			local names, roof = {}, nil
			for _, child in nodes[1].children do
				expect(names[child.name]).toBeNil()
				names[child.name] = true
				if child.name == "Roof" then
					roof = child
				end
			end
			expect(names.DropHatch).toBe(true)
			expect(roof ~= nil).toBe(true)
			if f < #Config.BASE_FLOORS then
				expect(roof.attributes.JarShow).toBe("top")
				expect(roof.attributes.JarCollide).toBe(true)
			end
		end
		expect(factory.top).toBeNil()
		expect(factory.route).toBe(false)
	end)
end)

-- Every node under `nodes` (depth first) whose name matches `pattern`.
local function findNodes(nodes: { any }, pattern: string, out: { any }?): { any }
	local found = out or {}
	for _, node in nodes do
		if string.match(node.name, pattern) then
			table.insert(found, node)
		end
		if node.children then
			findNodes(node.children, pattern, found)
		end
	end
	return found
end

describe("base shapes: nobody stands inside a drop tube", function()
	for _, id in { "factory", "pagoda" } do
		it(`guards the {id}'s drop tube where it can be reached from the ground, on every top floor`, function()
			local shape = BaseShapes.get(id)
			local data = BaseShapes.data(id)
			local lands = data.exit.lands
			for f = 2, #Config.BASE_FLOORS do
				-- on the floor (shown and solid only while it is the top one), or in the roof folder built for the top
				-- floor (a base with one)
				local onFloor = findNodes(shape.floor(1, f), "^DropGuard_%d+$")
				local inRoof = if shape.top then findNodes((shape.top :: any)(1, f).children, "^DropGuard_%d+$") else {}
				expect(#onFloor + #inRoof > 0).toBe(true)
				local guards = table.clone(onFloor)
				table.move(inRoof, 1, #inRoof, #guards + 1, guards)
				for _, g in guards do
					-- solid, invisible and never anyone's look
					expect(g.canCollide ~= false).toBe(true)
					expect(g.transparency).toBe(1)
					local a = g.attributes or {}
					expect(a.JarShowSelf).toBeNil()
					expect(a.MeshStandIn).toBeNil()
				end
				for _, g in onFloor do
					if f < #Config.BASE_FLOORS then
						local a = g.attributes or {}
						expect(a.JarShow).toBe("top")
						expect(a.JarCollide).toBe(true)
					end
				end
				for _, g in guards do
					-- from the plot floor up past a jump, so it can't be climbed
					expect(math.abs(g.pos[2] - g.size[2] / 2 - WorldLayout.PLOT_FLOOR_TOP) < 1e-3).toBe(true)
					expect(g.size[2] > 7.5).toBe(true)
				end
				-- the drop lands clear of every guard
				for _, p in data.parts do
					if p.floor == f and string.match(p.name, "^DropGuard_") then
						expect(toWall(lands[1], lands[2], p) > 1.5).toBe(true)
					end
				end
			end
		end)
	end
	it("hides the pagoda's eave slabs behind the mushroom cap of their floor", function()
		local pagoda = BaseShapes.get("pagoda")
		local eaves = findNodes(pagoda.floor1(1), "^Eave1_%d+$")
		for f = 2, #Config.BASE_FLOORS - 1 do
			findNodes(pagoda.floor(1, f), `^Eave{f}_%d+$`, eaves)
		end
		expect(#eaves > 0).toBe(true)
		for _, e in eaves do
			local f = tonumber(string.match(e.name, "^Eave(%d)_"))
			expect(e.attributes.MeshStandIn).toBe(`pagoda_cap_{f}_mid`)
		end
	end)
end)

describe("base shapes: jar -> pagoda -> factory -> jar", function()
	it("moves the door to the pagoda's wall and every base's own pieces come and go", function()
		withRoblox(function()
			local plot = WorldBuilder.ensure(roblox.Instance.new("Folder"), WorldLayout.plotNode(1))
			local pad1 = plot:FindFirstChild("Pad_1")
			local jarRing = plot:FindFirstChild("DoorRing").CFrame
			WorldBuilder.rebase(plot, 1, nil, "pagoda")
			local ring = plot:FindFirstChild("DoorRing")
			local moved = jarRing:PointToObjectSpace(ring.CFrame.Position)
			expect(math.abs(moved.Magnitude - 3) < 1e-3).toBe(true)
			expect(plot:FindFirstChild("Jar")).toBeNil()
			expect(plot:FindFirstChild("BaseShape"):GetAttribute("PlotBase")).toBe("pagoda")
			expect(plot:FindFirstChild("FootLook"):GetAttribute("MeshAsset")).toBe("goo_jar_foot")
			WorldBuilder.rebase(plot, 1, "pagoda", "factory")
			expect(plot:FindFirstChild("BaseShape"):GetAttribute("PlotBase")).toBe("factory")
			expect(plot:FindFirstChild("DoorRing")).toBeNil()
			expect(plot:FindFirstChild("OpenDoorCollider")).toBeNil()
			WorldBuilder.rebase(plot, 1, "factory", nil)
			expect(plot:FindFirstChild("BaseShape")).toBeNil()
			expect(plot:FindFirstChild("Jar") ~= nil).toBe(true)
			expect((plot:FindFirstChild("DoorRing").CFrame.Position - jarRing.Position).Magnitude < 1e-3).toBe(true)
			expect(plot:FindFirstChild("Pad_1")).toBe(pad1)
		end)
	end)
end)

describe("base shapes: turning a plot into another base and back", function()
	it("keeps the pads, vat, lock and their children, swaps the jar's own pieces for the factory's", function()
		withRoblox(function()
			local plot = WorldBuilder.ensure(roblox.Instance.new("Folder"), WorldLayout.plotNode(1))
			local pad1 = plot:FindFirstChild("Pad_1")
			local button = plot:FindFirstChild("LockButton")
			local prompt = roblox.Instance.new("ProximityPrompt")
			prompt.Parent = button
			local look = plot:FindFirstChild("ButtonLook")
			local mesh = roblox.Instance.new("Part")
			mesh.Name = "Mesh"
			mesh.CFrame = look.CFrame
			mesh.Parent = look
			local jarPad = pad1.CFrame

			local created = WorldBuilder.rebase(plot, 1, nil, "factory")
			-- the BaseShape model, the factory's own looks the game finds on the plot (foot, shut and open shutter) and
			-- the planks on its bridge
			local made = {}
			for _, inst in created do
				made[inst.Name] = true
			end
			expect(#created).toBe(5)
			for _, name in { "BaseShape", "FootLook", "StopperShut", "StopperParked", "BridgeLook" } do
				expect(made[name]).toBe(true)
			end
			expect(plot:FindFirstChild("FootLook"):GetAttribute("MeshAsset")).toBe("factory_foot")
			expect(plot:FindFirstChild("BaseShape") ~= nil).toBe(true)
			for _, name in { "Jar", "JarLooks", "DoorLook", "DoorRing", "OpenDoorCollider" } do
				expect(plot:FindFirstChild(name)).toBeNil()
			end
			-- the lock's look is the factory's shutter now (the jar's stopper is gone)
			expect(plot:FindFirstChild("StopperShut"):GetAttribute("MeshAsset")).toBe("factory_shutter_shut")
			expect(plot:FindFirstChild("Pad_1")).toBe(pad1)
			expect(prompt.Parent).toBe(button)
			local at = WorldLayout.plotFrame(1)
			local want = at({ Factory.pads[1].x, 0, Factory.pads[1].z })
			expect(math.abs(pad1.CFrame.Position.X - want[1]) < 1e-3).toBe(true)
			expect(math.abs(pad1.CFrame.Position.Z - want[3]) < 1e-3).toBe(true)
			-- the button's look mesh rode along with its slot
			expect((mesh.CFrame.Position - look.CFrame.Position).Magnitude < 1e-3).toBe(true)
			local stopper = plot:FindFirstChild("LockBarrier"):FindFirstChild("Stopper")
			expect(math.abs(stopper.Size.X - Factory.spots.LockBarrier.size[1]) < 1e-3).toBe(true)

			WorldBuilder.rebase(plot, 1, "factory", nil)
			expect(plot:FindFirstChild("BaseShape")).toBeNil()
			expect(plot:FindFirstChild("StopperShut"):GetAttribute("MeshAsset")).toBe("goo_jar_stopper")
			expect(plot:FindFirstChild("FootLook"):GetAttribute("MeshAsset")).toBe("goo_jar_foot")
			for _, name in { "Jar", "JarLooks", "DoorLook", "DoorRing", "StopperShut", "OpenDoorCollider" } do
				expect(plot:FindFirstChild(name) ~= nil).toBe(true)
			end
			expect(plot:FindFirstChild("Pad_1")).toBe(pad1)
			expect((pad1.CFrame.Position - jarPad.Position).Magnitude < 1e-3).toBe(true)
			expect((mesh.CFrame.Position - look.CFrame.Position).Magnitude < 1e-3).toBe(true)
		end)
	end)
end)

describe("base shapes: the pagoda's stair turret counts as inside", function()
	it("inside() and the lock guard keep someone on the turret ramp inside, on every floor", function()
		local pagoda = BaseShapes.get("pagoda")
		-- the back of the turret's ramp (0, 25 + 7.5): past every upper room's radius, inside the turret
		local x, z = 0, 32.5
		for f = 1, #Config.BASE_FLOORS do
			expect(pagoda.inside(f, x, z)).toBe(true)
			local y = WorldLayout.floorTop(f) + 4
			expect(PlotLockGuard.insideJar(x, y, z, pagoda.guard :: any, #Config.BASE_FLOORS, true)).toBe(true)
		end
		-- just outside the turret wall, beside it: still outside
		expect(pagoda.inside(3, 10.5, 25)).toBe(false)
		expect(pagoda.inside(3, 0, 34)).toBe(false)
	end)
end)

-- The round Exclusive bases share one inside (kit models/_round_base_layout.py): a centre spiral ramp, 8 pads a
-- floor on a ring, the door, vat and lock on floor 1's front, the owner hatch on floors 2-4, the roof on the top floor.
local ROUND = { "carousel", "rocket", "treehouse", "lighthouse", "snowglobe" }

local function padsOf(data, f: number)
	local out = {}
	for _, pad in data.pads do
		if math.ceil(pad.j / Config.PADS_PER_FLOOR) == f then
			table.insert(out, pad)
		end
	end
	return out
end

describe("base shapes: the round Exclusive bases' generated layouts", function()
	for _, id in ROUND do
		local data = BaseShapes.data(id)
		it(`{id}: has its own data and shape`, function()
			expect(data ~= nil).toBe(true)
			expect(data.id).toBe(id)
			expect(BaseShapes.get(id).id).toBe(id)
			expect(BaseShapes.get(id).route).toBe(false)
		end)
		it(`{id}: keeps the pads clear of the room wall, the ramp shaft and each other on every floor`, function()
			local shaft = 0
			for _, r in data.ramps do
				shaft = math.max(shaft, r.r_out)
			end
			for f = 1, #Config.BASE_FLOORS do
				local pads = padsOf(data, f)
				expect(#pads).toBe(Config.PADS_PER_FLOOR)
				local room = data.inside.radii[f]
				for a = 1, #pads do
					local r = math.sqrt(pads[a].x ^ 2 + pads[a].z ^ 2)
					expect(room - r - PAD / 2 * math.sqrt(2) >= GAP).toBe(true)
					expect(r - PAD / 2 * math.sqrt(2) - shaft >= GAP - 1.5).toBe(true)
					for b = a + 1, #pads do
						local d = math.sqrt((pads[a].x - pads[b].x) ^ 2 + (pads[a].z - pads[b].z) ^ 2)
						expect(d - PAD >= GAP - 0.1).toBe(true)
					end
				end
			end
		end)
		it(`{id}: climbs a centre helix at least 4 wide and no steeper than 32 degrees, one per floor`, function()
			expect(#data.ramps).toBe(#Config.BASE_FLOORS - 1)
			for k, r in data.ramps do
				expect(r.kind).toBe("helix")
				expect(r.r_out - r.r_in >= 4).toBe(true)
				local walk = (r.r_in + r.r_out) / 2
				expect(math.deg(math.atan2(r.rise, math.rad(r.sweep) * walk)) <= 32).toBe(true)
				expect(math.abs(r.y0 - WorldLayout.floorTop(k)) < 1e-3).toBe(true)
				expect(math.abs(r.y0 + r.rise - WorldLayout.floorTop(k + 1)) < 1e-3).toBe(true)
			end
		end)
		it(`{id}: stays inside the moat and puts the vat and lock inside the door, the spawn in floor 1`, function()
			for _, p in data.parts do
				if p.collide and p.role ~= "mascot" then
					for _, c in corners(p) do
						expect(math.sqrt(c[1] ^ 2 + c[2] ^ 2) <= MOAT_IN + 1e-3).toBe(true)
					end
				end
			end
			local shape = BaseShapes.get(id)
			for _, spot in { data.vat, data.lockButton, data.spawn } do
				expect(spot[2] > data.door.z + 1).toBe(true)
				expect(shape.inside(1, spot[1], spot[2])).toBe(true)
			end
			expect(data.spawn[1]).toBe(WorldLayout.SPAWN_SPOT[1])
		end)
		it(`{id}: has a drop hatch on floors 2-4 and its roof only on the top floor`, function()
			local shape = BaseShapes.get(id)
			for f = 2, #Config.BASE_FLOORS do
				local hatch, roofHere = nil, false
				for _, child in shape.floor(1, f)[1].children :: { any } do
					if child.name == "DropHatch" then
						hatch = child
					end
					if
						string.sub(child.name, 1, 4) == "Roof" and not (child.attributes and child.attributes.MeshAsset)
					then
						roofHere = true
					end
				end
				expect(hatch ~= nil).toBe(true)
				-- floors 2-3 keep their roof in the TopColliders folder; floor 4 is always the top one
				expect(roofHere).toBe(f == #Config.BASE_FLOORS)
			end
			local roof = (shape.top :: any)(1, 2)
			expect(roof.name).toBe("TopColliders")
			local pieces = 0
			for _, child in roof.children do
				if string.sub(child.name, 1, 4) == "Roof" then
					pieces += 1
				end
			end
			expect(pieces > 0).toBe(true)
		end)
		it(`{id}: counts the ramp shaft as inside and the moat as outside, on every floor`, function()
			local shape = BaseShapes.get(id)
			for f = 1, #Config.BASE_FLOORS do
				expect(shape.inside(f, 0, 4.8)).toBe(true)
				expect(shape.inside(f, 0, -(data.inside.radii[f] - 1))).toBe(true)
				expect(shape.inside(f, 0, -(data.inside.radii[f] + 2))).toBe(false)
				expect(shape.inside(f, 36, 0)).toBe(false)
				local y = WorldLayout.floorTop(f) + 4
				expect(PlotLockGuard.insideJar(0, y, 4.8, shape.guard :: any, #Config.BASE_FLOORS, true)).toBe(true)
			end
		end)
	end
end)

describe("base shapes: jar -> each round base -> jar", function()
	it("moves the jar's door to each base's wall and builds its own pieces, keeping the pads", function()
		withRoblox(function()
			local plot = WorldBuilder.ensure(roblox.Instance.new("Folder"), WorldLayout.plotNode(1))
			local pad1 = plot:FindFirstChild("Pad_1")
			local jarRing = plot:FindFirstChild("DoorRing").CFrame
			local from = nil
			for _, id in ROUND do
				local data = BaseShapes.data(id)
				WorldBuilder.rebase(plot, 1, from, id)
				from = id
				expect(plot:FindFirstChild("BaseShape"):GetAttribute("PlotBase")).toBe(id)
				expect(plot:FindFirstChild("Jar")).toBeNil()
				expect(plot:FindFirstChild("FootLook"):GetAttribute("MeshAsset")).toBe("goo_jar_foot")
				local moved = jarRing:PointToObjectSpace(plot:FindFirstChild("DoorRing").CFrame.Position)
				local shift = (WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL / 2) + data.door.z
				expect(math.abs(moved.Magnitude - math.abs(shift)) < 1e-3).toBe(true)
				expect(plot:FindFirstChild("OpenDoorCollider") ~= nil).toBe(true)
				-- the door's two looks LockMotion swings between, moved with the door
				for _, look in { "StopperShut", "StopperParked" } do
					local node = plot:FindFirstChild(look)
					expect(node ~= nil).toBe(true)
					local off = jarRing:PointToObjectSpace(node.CFrame.Position)
					expect(math.abs(off.Magnitude) < 20).toBe(true)
				end
				expect(plot:FindFirstChild("Pad_1")).toBe(pad1)
				local at = WorldLayout.plotFrame(1)
				local want = at({ data.pads[1].x, 0, data.pads[1].z })
				expect(math.abs(pad1.CFrame.Position.X - want[1]) < 1e-3).toBe(true)
				expect(math.abs(pad1.CFrame.Position.Z - want[3]) < 1e-3).toBe(true)
			end
			WorldBuilder.rebase(plot, 1, from, nil)
			expect(plot:FindFirstChild("BaseShape")).toBeNil()
			expect(plot:FindFirstChild("Jar") ~= nil).toBe(true)
			expect((plot:FindFirstChild("DoorRing").CFrame.Position - jarRing.Position).Magnitude < 1e-3).toBe(true)
		end)
	end)
end)
