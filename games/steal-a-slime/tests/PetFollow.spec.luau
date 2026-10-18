--!strict
-- PetFollow: the glide of the follow pet + cloud (src/visuals/shared/PetFollow). Pure numbers, no Roblox.
local PetFollow = require("../src/visuals/shared/PetFollow")
local TestRunner = require("./TestRunner")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local OX, OY, OZ = PetFollow.OFFSET_X, PetFollow.OFFSET_Y, PetFollow.OFFSET_Z

-- A pet at rest at its goal behind an owner standing at the origin, facing -Z (yaw 0).
local function settled(): PetFollow.State
	local s = PetFollow.new(0)
	PetFollow.step(s, 1 / 60, 0, 0, 0, 0)
	return s
end

local function finite(s: PetFollow.State): boolean
	for _, v in { s.x, s.y, s.z, s.vx, s.vy, s.vz, s.yaw, s.bob } do
		if v ~= v or v == math.huge or v == -math.huge then
			return false
		end
	end
	return true
end

describe("PetFollow goal and snap", function()
	it("the first step snaps onto the owner's back offset", function()
		local s = settled()
		expect(s.x).toBeCloseTo(OX)
		expect(s.y).toBeCloseTo(OY)
		expect(s.z).toBeCloseTo(OZ)
		expect(OX).toBe(2.6)
		expect(OZ).toBe(3.2)
	end)
	it("turns the offset with the owner's heading", function()
		local s = PetFollow.new(0)
		PetFollow.step(s, 1 / 60, 10, 5, 20, math.pi) -- facing +Z: behind is -Z, right is -X
		expect(s.x).toBeCloseTo(10 - OX)
		expect(s.z).toBeCloseTo(20 - OZ)
		expect(s.y).toBeCloseTo(5 + OY)
	end)
	it("snaps on a teleport (> SNAP_DISTANCE) and glides below it", function()
		local s = settled()
		PetFollow.step(s, 1 / 60, 500, 0, 0, 0)
		expect(s.x).toBeCloseTo(500 + OX)
		expect(s.vx).toBe(0)
		local t = settled()
		PetFollow.step(t, 1 / 60, PetFollow.SNAP_DISTANCE - 10, 0, 0, 0)
		expect(t.x < PetFollow.SNAP_DISTANCE / 2).toBe(true) -- one frame later it has barely moved
	end)
end)

describe("PetFollow spring", function()
	it("converges to a still target without overshoot", function()
		local s = settled()
		local goal = 12 + OX
		local last = s.x
		for _ = 1, 600 do
			PetFollow.step(s, 1 / 60, 12, 0, 0, 0)
			expect(s.x >= last - 1e-9).toBe(true) -- monotonic
			expect(s.x <= goal + 1e-9).toBe(true) -- never past the goal
			last = s.x
		end
		expect(s.x).toBeCloseTo(goal, 1e-3)
		expect(s.z).toBeCloseTo(OZ, 1e-3)
	end)
	it("gives the same place after 1 s at 30, 60 and 144 fps", function()
		local out = {}
		for _, fps in { 30, 60, 144 } do
			local s = settled()
			local dt = 1 / fps
			PetFollow.step(s, dt, 0, 0, 0, 0)
			for _ = 1, fps do
				PetFollow.step(s, dt, 14, 0, -6, 0)
			end
			table.insert(out, s)
		end
		for i = 2, 3 do
			expect(out[i].x).toBeCloseTo(out[1].x, 1e-3)
			expect(out[i].z).toBeCloseTo(out[1].z, 1e-3)
			expect(out[i].vx).toBeCloseTo(out[1].vx, 1e-3)
		end
	end)
	it("tracks a walking owner at about the same lag at any frame rate", function()
		local ends = {}
		for _, fps in { 30, 144 } do
			local s = settled()
			local dt = 1 / fps
			for i = 1, fps * 3 do
				PetFollow.step(s, dt, 0, 0, -16 * i * dt, 0) -- 16 studs/s along -Z
			end
			table.insert(ends, s.z)
		end
		expect(math.abs(ends[1] - ends[2]) < 0.6).toBe(true) -- a stepped goal costs about v * dt of lag
		-- steady lag of a critically damped spring is 2 v / w behind the goal
		expect(ends[2] > -48 + OZ).toBe(true)
	end)
	it("is finite at dt 0, 1, a huge, negative and NaN dt", function()
		for _, dt in { 0, 1, 1e9, -1, 0 / 0, math.huge } do
			local s = settled()
			PetFollow.step(s, dt, 7, 1, 3, 1)
			expect(finite(s)).toBe(true)
			PetFollow.step(s, dt, -4, 2, 8, -2)
			expect(finite(s)).toBe(true)
		end
		local s = settled()
		local before = s.x
		PetFollow.step(s, 0, 9, 0, 0, 0)
		expect(s.x).toBeCloseTo(before, 1e-9) -- dt 0 does not move it
	end)
	it("treats a hitch as MAX_DT", function()
		local a, b = settled(), settled()
		PetFollow.step(a, 1, 20, 0, 0, 0)
		PetFollow.step(b, PetFollow.MAX_DT, 20, 0, 0, 0)
		expect(a.x).toBe(b.x)
	end)
	it("does not allocate per step", function()
		local src = fs.readFile("src/visuals/shared/PetFollow.luau")
		local body = string.match(src, "function PetFollow%.step.-\nend\n") :: string
		expect(body ~= nil).toBe(true)
		expect(string.find(body, "{", 1, true)).toBeNil() -- no table, no closure state
		expect(string.find(body, "function", 8, true)).toBeNil()
		local s = settled()
		PetFollow.step(s, 1 / 60, 3, 0, 0, 0)
		local before = collectgarbage("count")
		for i = 1, 20000 do
			PetFollow.step(s, 1 / 60, i % 50, 0, 0, i * 0.01)
		end
		expect(collectgarbage("count") - before < 256).toBe(true) -- KB
	end)
end)

describe("PetFollow yaw", function()
	it("angleDelta takes the shortest way round", function()
		expect(PetFollow.angleDelta(3.0, -3.0)).toBeCloseTo(2 * math.pi - 6, 1e-9)
		expect(PetFollow.angleDelta(-3.0, 3.0)).toBeCloseTo(6 - 2 * math.pi, 1e-9)
		expect(PetFollow.angleDelta(0, 0.5)).toBeCloseTo(0.5, 1e-9)
		expect(PetFollow.angleDelta(0.1, 0.1 + 4 * math.pi)).toBeCloseTo(0, 1e-9)
	end)
	it("turns through the +/-pi seam, not the long way", function()
		local s = PetFollow.new(0)
		PetFollow.step(s, 1 / 60, 0, 0, 0, 3.0) -- snap with yaw 3.0
		PetFollow.step(s, 1 / 60, 0, 0, 0, -3.0)
		expect(s.yaw > 3.0).toBe(true) -- towards +pi (0.28 away), not back through 0 (6.0 away)
		for _ = 1, 300 do
			PetFollow.step(s, 1 / 60, 0, 0, 0, -3.0)
		end
		expect(math.abs(PetFollow.angleDelta(s.yaw, -3.0)) < 1e-3).toBe(true)
	end)
	it("faces its travel direction while moving and the owner's heading at rest", function()
		local s = settled()
		for i = 1, 90 do
			PetFollow.step(s, 1 / 60, 0.3 * i, 0, 0, 0) -- owner runs along +X
		end
		-- moving +X is yaw -pi/2 (look vector (-sin, -cos))
		expect(math.abs(PetFollow.angleDelta(s.yaw, -math.pi / 2)) < 0.15).toBe(true)
		for _ = 1, 600 do
			PetFollow.step(s, 1 / 60, 27, 0, 0, 0.8) -- stops, owner faces yaw 0.8
		end
		expect(math.abs(PetFollow.angleDelta(s.yaw, 0.8)) < 1e-2).toBe(true)
	end)
	it("yawOf matches CFrame.Angles(0, yaw, 0) looking along -Z", function()
		expect(PetFollow.yawOf(0, -1)).toBeCloseTo(0, 1e-9)
		expect(PetFollow.yawOf(-1, 0)).toBeCloseTo(math.pi / 2, 1e-9)
		expect(PetFollow.yawOf(0, 0)).toBe(0)
	end)
end)

describe("PetFollow bob", function()
	it("stays within BOB_AMPLITUDE, uses most of it and moves nothing else", function()
		local s = PetFollow.new(1.3)
		local lo, hi = 0, 0
		for _ = 1, 1200 do
			PetFollow.step(s, 1 / 60, 0, 0, 0, 0)
			lo, hi = math.min(lo, s.bob), math.max(hi, s.bob)
			expect(math.abs(s.bob) <= PetFollow.BOB_AMPLITUDE + 1e-12).toBe(true)
		end
		expect(hi > PetFollow.BOB_AMPLITUDE * 0.95).toBe(true)
		expect(lo < -PetFollow.BOB_AMPLITUDE * 0.95).toBe(true)
		expect(PetFollow.BOB_AMPLITUDE <= 0.25).toBe(true) -- gentle
		expect(s.y).toBeCloseTo(OY, 1e-9) -- the spring state itself does not bob
	end)
end)
