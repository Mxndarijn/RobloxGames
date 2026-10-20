--!nocheck
-- Bug B9 (every object uses its own collision): tests/PropCollision is the inventory of every collidable or
-- solid-looking prop. This spec keeps it honest against MeshAssets.COLLISION, the built map and a booted server world,
-- and checks the geometry helpers the pc-watcher probe (luau/b9_prop_walk) uses.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local PropCollision = require("./PropCollision")
local PvpModels = require("../src/shared/PvpModels")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")
local VatDecor = require("../src/visuals/shared/VatDecor")
local WorldBorder = require("../src/visuals/shared/WorldBorder")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ENTRIES = PropCollision.ENTRIES
local COLLISIONS = { colliders = true, off = true }

-- Jolt-owned entries that may be "off": nothing a player can bump into (ground cover, flat markings, hidden stand-ins,
-- the slime-only ride, floor features, the border behind its wall).
local NON_BLOCKING = {
	fountain_standins = true,
	fountain_chute = true,
	ritual_circle = true,
	floor_deck = true, -- B11 floor meshes: flat planks on the terrain
	floor_boardwalk = true,
	parade_lane = true,
	decor_pumpkin_patch = true,
	decor_horseshoe_pit = true,
	decor_sunflower_patch = true,
	meadow_grass = true,
	meadow_flowers = true,
	meadow_pebbles = true,
}

describe("PropCollision inventory", function()
	it("has unique kinds, a valid owner and an explicit collision choice with a reason for every entry", function()
		local seen = {}
		for _, e in ENTRIES do
			expect(seen[e.kind]).toBe(nil)
			seen[e.kind] = true
			expect(PropCollision.OWNERS[e.owner] == true).toBe(true)
			expect(PropCollision.FIDELITIES[e.collision] == true or COLLISIONS[e.collision] == true).toBe(true)
			expect(type(e.reason) == "string" and #e.reason > 10).toBe(true)
			expect(type(e.now) == "string" and #e.now > 0).toBe(true)
			expect(e.count >= 1 or (e.flag ~= nil and e.flag.off >= 1)).toBe(true) -- or it exists with its flag off
			expect(e.mesh == "part" or MeshAssets.get(e.mesh) ~= nil).toBe(true)
		end
		expect(#ENTRIES > 100).toBe(true)
	end)
	it("every entry without a find says why (terrain)", function()
		for _, e in ENTRIES do
			if e.find == nil then
				expect(e.kind).toBe("terrain")
			end
		end
	end)
	it("matches MeshAssets.COLLISION for every mesh entry, both ways", function()
		for _, e in ENTRIES do
			if e.mesh ~= "part" then
				local want = MeshAssets.collision(e.mesh)
				if PropCollision.FIDELITIES[e.collision] then
					expect(want).toBe(e.collision)
				else
					expect(want).toBe(nil)
				end
			end
		end
		for name, fidelity in MeshAssets.COLLISION do
			local found = false
			for _, e in ENTRIES do
				found = found or (e.mesh == name and e.collision == fidelity)
			end
			expect(found).toBe(true)
		end
	end)
	it(
		"lists every MeshAssets mesh a world slot, WorldProps or MeshSwap places; the rest are unplaced with a reason",
		function()
			local placed = {}
			local function walk(n)
				local a = n.attributes or {}
				local mesh = a.MeshAsset or a.BorderMesh
				if type(mesh) == "string" then
					placed[mesh] = true
				end
				for _, ch in n.children or {} do
					walk(ch)
				end
			end
			for _, root in WorldLayout.build() do
				walk(root)
			end
			for _, mesh in WorldLayout.PROP_MESHES do
				placed[mesh] = true
			end
			for _, stand in WorldLayout.SHOP_STANDS do -- whichever stands FEATURES.WorldShops places
				placed[stand.mesh] = true
			end
			placed[VatDecor.MESH] = true
			local inventory = {}
			for _, e in ENTRIES do
				inventory[e.mesh] = true
			end
			for mesh in placed do
				expect(inventory[mesh]).toBe(true)
				expect(PropCollision.UNPLACED[mesh]).toBe(nil)
			end
			local held: { [string]: boolean } = {} -- held PvP items (server/PvpHeld): never a world slot, no entry until uploaded
			for _, name in PvpModels.MESHES do
				held[name] = true
			end
			for _, name in MeshAssets.NAMES do
				expect(inventory[name] == true or PropCollision.UNPLACED[name] ~= nil or held[name] == true).toBe(true)
				if PropCollision.UNPLACED[name] then
					expect(inventory[name]).toBe(nil)
					expect(#PropCollision.UNPLACED[name][2] > 10).toBe(true)
				end
			end
			for name, info in PropCollision.UNPLACED do
				expect(MeshAssets.get(name) ~= nil).toBe(true)
				expect(PropCollision.OWNERS[info[1]] == true).toBe(true)
			end
		end
	)
	it("never leaves a Jolt-owned blocking prop off", function()
		for _, e in ENTRIES do
			if e.owner == "jolt" and e.collision == "off" then
				expect(NON_BLOCKING[e.kind] == true or e.kind:sub(1, 7) == "border_").toBe(true)
			end
		end
		for kind in NON_BLOCKING do
			local found = false
			for _, e in ENTRIES do
				found = found or e.kind == kind
			end
			expect(found).toBe(true)
		end
	end)
	it("keeps every 'off' border piece behind the wall ring", function()
		local least = math.huge
		for _, p in WorldBorder.pieces() do
			local yaw = math.rad(p.yaw)
			local c, s = math.cos(yaw), math.sin(yaw)
			for i = -10, 10 do
				for j = -10, 10 do
					local lx, lz = p.size[1] / 2 * i / 10, p.size[3] / 2 * j / 10
					local x = p.pos[1] + lx * c + lz * s
					local z = p.pos[3] - lx * s + lz * c
					least = math.min(least, math.sqrt(x * x + z * z))
				end
			end
		end
		-- a round hill's empty bbox corner may reach 2 studs inside the wall's inner face (292); never further
		expect(least >= WorldBorder.RADIUS - 3).toBe(true)
		expect(WorldBorder.WALL_HEIGHT >= 40).toBe(true)
	end)
	it("totals add up per owner", function()
		local totals = PropCollision.totals()
		local n = 0
		for _, t in totals do
			n += t.kinds
		end
		expect(n).toBe(#ENTRIES)
		expect(totals.jolt.colliding > 0 and totals.gojo.colliding > 0).toBe(true)
	end)
end)

describe("PropCollision geometry", function()
	it("walks in from the four sides of the prop's frame towards a point past its centre", function()
		local sides = PropCollision.sides(10, 20, 0, 3, 2, 4)
		expect(#sides).toBe(4)
		local byName = {}
		for _, s in sides do
			byName[s.name] = s
		end
		expect(byName["+X"].start[1]).toBe(10 - 7)
		expect(byName["+X"].target[1]).toBe(10 + 7)
		expect(byName["+Z"].start[2]).toBe(20 - 6)
		expect(byName["-Z"].dir[2]).toBe(-1)
	end)
	it("turns with the prop's yaw", function()
		local half = math.pi / 2
		local sides = PropCollision.sides(0, 0, half, 3, 2, 4)
		local plusX
		for _, s in sides do
			if s.name == "+X" then
				plusX = s
			end
		end
		-- yaw 90 deg: the prop's +X axis points along world -Z
		expect(math.abs(plusX.dir[1]) < 1e-9).toBe(true)
		expect(math.abs(plusX.dir[2] + 1) < 1e-9).toBe(true)
		expect(PropCollision.insideFootprint(0, -2.5, 0, 0, half, 3, 2, 0)).toBe(true)
		expect(PropCollision.insideFootprint(2.5, 0, 0, 0, half, 3, 2, 0)).toBe(false)
		expect(PropCollision.insideFootprint(2.5, 0, 0, 0, half, 3, 2, 1)).toBe(true)
	end)
end)

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-propcol-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {
	createMeshPart = function(_, options)
		local part = roblox.Instance.new("MeshPart")
		if options and options.CollisionFidelity then
			part.CollisionFidelity = options.CollisionFidelity
		end
		return part
	end,
})
rt:boot()
for _ = 1, 15 * 30 do -- the parade lane, slide colliders and MeshSwap have run
	rt:step(1 / 30)
end
fs.removeFile(path)

local function relPath(d): string
	return (d:GetFullName():gsub("^Workspace%.?", ""))
end

-- every instance of an entry: the Instance list (find.also solids are collected separately)
local function instances(find): { any }
	local out = {}
	for _, d in rt.workspace:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder") then
			local a = d:GetAttribute("MeshAsset")
			if
				not (d:IsA("MeshPart") and d.Name == "Mesh")
				and PropCollision.matches(
					find,
					relPath(d),
					d.Name,
					if type(a) == "string" then a else nil,
					d:IsA("BasePart")
				)
			then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- the solid parts of one instance: itself and its descendants with CanCollide on
local function solids(inst): { any }
	local out = {}
	if inst:IsA("BasePart") and inst.CanCollide then
		table.insert(out, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			table.insert(out, d)
		end
	end
	return out
end

local flags = Config.FEATURES

describe("PropCollision against the booted world", function()
	it("boots clean", function()
		expect(#rt.errors).toBe(0)
	end)
	for _, e in ENTRIES do
		if e.find then
			it(
				`{e.kind} ({e.owner}): {PropCollision.expectedCount(e, flags)} instance(s), collision {e.collision}`,
				function()
					local list = instances(e.find)
					expect(#list).toBe(PropCollision.expectedCount(e, flags))
					local extra = if e.also then instances(e.also) else {}
					for _, inst in list do
						local own = solids(inst)
						local mesh = if inst:IsA("MeshPart") then inst else inst:FindFirstChild("Mesh")
						if e.kind == "merge_vat" then
							mesh = inst:FindFirstChild("VatMesh")
						end
						if PropCollision.FIDELITIES[e.collision] then
							expect(mesh ~= nil).toBe(true)
							expect(mesh.CanCollide).toBe(true)
							expect(mesh.CollisionFidelity).toBe((roblox.Enum.CollisionFidelity :: any)[e.collision])
						elseif e.collision == "colliders" then
							expect(#own + #extra > 0).toBe(true)
						else
							expect(#own).toBe(0) -- off means off, mesh and slot
						end
					end
				end
			)
		end
	end
	it("keeps the Top Earners board's Collider as wide and tall as its skin, depth and front unchanged", function()
		local board = rt.workspace.Map.LeaderboardBoard
		local mesh, collider = board:FindFirstChild("Mesh"), board:FindFirstChild("Collider")
		expect(mesh ~= nil and collider ~= nil).toBe(true)
		expect(math.abs(collider.Size.X - mesh.Size.X) < 0.01).toBe(true)
		expect(math.abs(collider.Size.Y - mesh.Size.Y) < 0.01).toBe(true)
		expect(math.abs(collider.Size.Z - 1.6) < 0.01).toBe(true) -- Props.leaderboardBoard's depth: the skin's front stays flush with it
		local c = collider.CFrame:PointToObjectSpace(mesh.CFrame.Position)
		expect(math.abs(c.X) < 0.01 and math.abs(c.Y) < 0.01).toBe(true)
		expect(collider.CanCollide).toBe(true)
	end)
	it("keeps the fountain tower's 22 colliders and the slide's colliders as they were", function()
		local volcano = rt.workspace.Map.Volcano
		local n = 0
		for _, d in volcano:GetChildren() do
			if d.Name:match("^%a+Collider%d*$") then
				n += 1
				expect(d.CanCollide).toBe(not flags.FountainSplit) -- FountainSplit: the PCD pieces collide instead
			end
		end
		expect(n).toBe(22)
		expect(#volcano.SlideColliders:GetChildren()).toBe(
			if flags.SlideCollision then (if flags.SlidePCD and flags.FountainSplit then 132 else 145) else 67
		)
	end)
	it("puts no spawn, plot spawn or other prop's centre inside a collidable prop", function()
		local floors = { ground_and_hub_spawn = true, plot_base = true, plot_pads = true, terrain = true }
		local Vector3 = roblox.Vector3
		local blockers = {} -- { kind, inst, part }
		local centres = {} -- { name, inst, pos }
		for _, e in ENTRIES do
			if e.find and e.collision ~= "off" and not floors[e.kind] then
				for _, inst in instances(e.find) do
					for _, part in solids(inst) do
						-- FountainSplit PCD pieces are concave (the bowl holds the emerge pile): a box test would flag it
						if part.Name:sub(1, 15) ~= "fountain_split_" then
							table.insert(blockers, { kind = e.kind, inst = inst, part = part })
						end
					end
					if inst:IsA("BasePart") and e.owner ~= "gojo" and e.walk ~= false then
						table.insert(
							centres,
							{ name = relPath(inst), kind = e.kind, inst = inst, pos = inst.CFrame.Position }
						)
					end
				end
			end
		end
		local hub = rt.workspace:FindFirstChild("HubSpawn")
		local spawns = { { name = "HubSpawn", pos = hub.CFrame.Position + Vector3.new(0, 3, 0) } }
		for _, plot in rt.workspace.Plots:GetChildren() do
			local base = plot:FindFirstChild("Base")
			table.insert(spawns, {
				name = relPath(plot) .. " spawn",
				pos = base.CFrame.Position + Vector3.new(0, base.Size.Y / 2 + 4, 0),
			})
		end
		local function inside(part, pos): boolean
			local p = part.CFrame:PointToObjectSpace(pos)
			local h = part.Size / 2
			return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
		end
		local bad = {}
		for _, s in spawns do
			for _, b in blockers do
				-- the character stands at the spawn: check feet, waist and head
				for _, y in { 0.5, 3, 5.5 } do
					if inside(b.part, Vector3.new(s.pos.X, y, s.pos.Z)) then
						table.insert(bad, `{s.name} in {relPath(b.part)} ({b.kind})`)
						break
					end
				end
			end
		end
		-- a prop's own placement (slot centre, ground level) inside another prop's collision = two props overlapping
		for _, c in centres do
			for _, b in blockers do
				if
					b.kind ~= c.kind
					and b.inst ~= c.inst
					and not c.inst:IsDescendantOf(b.inst)
					and not b.inst:IsDescendantOf(c.inst)
					and inside(b.part, Vector3.new(c.pos.X, math.max(c.pos.Y, 0.5), c.pos.Z))
				then
					table.insert(bad, `{c.name} centre in {relPath(b.part)} ({b.kind})`)
					break
				end
			end
		end
		if #bad > 0 then
			error(table.concat(bad, "; "))
		end
		expect(#bad).toBe(0)
	end)
end)
