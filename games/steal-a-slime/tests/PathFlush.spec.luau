--!strict
-- v29 B5: the ring and spoke paths are flush with the Ground, not 0.2 raised
-- tiles. Every path part's top sits within 0.02 of the others and within 0.05
-- of the Ground top (y 0); the centreline of the ring and of every spoke is
-- covered with no gap; no two overlapping parts share a top face (z-fight);
-- and the part / mesh budgets still hold.
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local GROUND_TOP = 0 -- Map.Ground: 640 x 2 x 640 centred at y -1

local function pathParts(): { any }
	local out = {}
	for _, c in WorldLayout.build()[1].children do
		if c.name == "Paths" then
			for _, n in c.children do
				table.insert(out, n)
			end
		end
	end
	return out
end

local function top(n: any): number
	-- an upright Cylinder (the Plaza) lies along X: its height is size[1]
	return n.pos[2] + (if n.shape == "Cylinder" then n.size[1] else n.size[2]) / 2
end

-- Is the ground point (x, z) over the part's top face? Disc: Plaza.
local function covers(n: any, x: number, z: number): boolean
	if n.shape == "Cylinder" then
		return x * x + z * z <= (n.size[2] / 2) ^ 2
	end
	local yaw = math.rad((n.rot or { 0, 0, 0 })[2])
	local dx, dz = x - n.pos[1], z - n.pos[3]
	-- local axes of CFrame.Angles(0, yaw, 0): X = (cos, -sin), Z = (sin, cos)
	local lx = dx * math.cos(yaw) - dz * math.sin(yaw)
	local lz = dx * math.sin(yaw) + dz * math.cos(yaw)
	return math.abs(lx) <= n.size[1] / 2 and math.abs(lz) <= n.size[3] / 2
end

local function covered(parts: { any }, x: number, z: number): boolean
	for _, n in parts do
		if covers(n, x, z) then
			return true
		end
	end
	return false
end

describe("flush path (v29 B5)", function()
	local parts = pathParts()
	local ring, spokes = {}, {}
	for _, n in parts do
		if string.match(n.name, "^Ring%d+$") then
			table.insert(ring, n)
		elseif string.match(n.name, "^Path%d+$") then
			table.insert(spokes, n)
		end
	end

	it("builds the ring and one spoke per plot", function()
		expect(#spokes).toBe(Config.PLOT_COUNT)
		expect(#ring).toBe(WorldLayout.PATH_RING_SEGMENTS)
	end)
	it("keeps every path top within 0.02 of the others", function()
		local lo, hi = math.huge, -math.huge
		for _, n in parts do
			lo, hi = math.min(lo, top(n)), math.max(hi, top(n))
		end
		expect(hi - lo <= 0.02).toBe(true)
	end)
	it("sticks nothing above the Ground by more than 0.05", function()
		for _, n in parts do
			expect(top(n) - GROUND_TOP <= 0.05).toBe(true)
			-- and shows above it, so the Ground never covers the path
			expect(top(n) - GROUND_TOP >= 0.02).toBe(true)
		end
	end)
	it("gives overlapping parts different tops (no coplanar z-fight)", function()
		local flat = {}
		for _, n in parts do
			if n.shape ~= "Cylinder" then
				table.insert(flat, n)
			end
		end
		for i, a in flat do
			for j = i + 1, #flat do
				local b = flat[j]
				if math.abs(top(a) - top(b)) >= 0.004 then
					continue
				end
				-- same top: their rectangles must not overlap (probe a's corners, pulled in)
				for _, sx in { -0.45, 0.45 } do
					for _, sz in { -0.45, 0.45 } do
						local yaw = math.rad((a.rot or { 0, 0, 0 })[2])
						local lx, lz = sx * a.size[1], sz * a.size[3]
						local x = a.pos[1] + lx * math.cos(yaw) + lz * math.sin(yaw)
						local z = a.pos[3] - lx * math.sin(yaw) + lz * math.cos(yaw)
						if covers(b, x, z) then
							error(`{a.name} and {b.name} overlap on one top face`)
						end
					end
				end
			end
		end
	end)
	it("has no gap along the ring centreline", function()
		local r, steps = WorldLayout.RING_PATH_RADIUS, 2880
		for k = 0, steps - 1 do
			local a = 2 * math.pi * k / steps
			if not covered(parts, math.sin(a) * r, math.cos(a) * r) then
				error(`ring centreline uncovered at {math.deg(a)} degrees`)
			end
		end
	end)
	it("has no gap near the ring's edges either (the inner edge is a chord, 74 at the least)", function()
		for _, r in { WorldLayout.RING_PATH_RADIUS - 3, WorldLayout.RING_PATH_RADIUS + 3 } do
			for k = 0, 1439 do
				local a = 2 * math.pi * k / 1440
				if not covered(parts, math.sin(a) * r, math.cos(a) * r) then
					error(`ring uncovered at r {r}, {math.deg(a)} degrees`)
				end
			end
		end
	end)
	it("has no gap along every spoke centreline, plaza edge to plot", function()
		local from, to = WorldLayout.PLAZA_RADIUS, WorldLayout.PLOT_RING_RADIUS - WorldLayout.PLOT_SIZE / 2
		for i = 1, Config.PLOT_COUNT do
			local yaw = math.rad((i - 1) * 360 / Config.PLOT_COUNT)
			for _, off in { -3.9, 0, 3.9 } do
				local d = from
				while d <= to do
					-- spoke i runs along direction (sin yaw, cos yaw); off is sideways
					local x = math.sin(yaw) * d + math.cos(yaw) * off
					local z = math.cos(yaw) * d - math.sin(yaw) * off
					if not covered(parts, x, z) then
						error(`spoke {i} uncovered at d {d}, off {off}`)
					end
					d += 0.25
				end
			end
		end
	end)
	it("stays inside the part and mesh budgets", function()
		local built = WorldLayout.build()
		local count = 0
		local function walk(n: any, inBorder: boolean)
			local border = inBorder or n.name == "Border"
			if n.class == "Part" and not border then
				count += 1
			end
			for _, c in n.children or {} do
				walk(c, border)
			end
		end
		for _, n in built do
			walk(n, false)
		end
		expect(count <= WorldLayout.PART_BUDGET).toBe(true)
		-- the path takes no mesh slot
		for _, n in parts do
			expect((n.attributes or {}).MeshAsset).toBe(nil)
		end
	end)
	it("starts exactly at the slide exit and runs unbroken to spoke 1 (v30 C1)", function()
		local exit = WorldLayout.SLIDE_PATH[#WorldLayout.SLIDE_PATH]
		local slideExit
		for _, n in parts do
			if n.name == "SlideExit" then
				slideExit = n
			end
		end
		expect(slideExit ~= nil).toBe(true)
		-- its near end is the last slide point
		expect(math.abs(slideExit.pos[3] - slideExit.size[3] / 2 - exit[3]) < 1e-6).toBe(true)
		expect(math.abs(slideExit.pos[1] - exit[1]) < 1e-6).toBe(true)
		local d = exit[3]
		while d <= WorldLayout.PLAZA_RADIUS + 4 do
			for _, off in { -3.9, 0, 3.9 } do
				if not covered(parts, exit[1] + off, d) then
					error(`slide exit path uncovered at z {d}, off {off}`)
				end
			end
			d += 0.05
		end
	end)
end)
