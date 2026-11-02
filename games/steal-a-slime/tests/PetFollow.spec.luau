--!strict
-- PetFollow: how the follow pet + cloud flies after its owner (src/visuals/shared/PetFollow). Pure numbers, no Roblox.
local PetFollow = require("../src/visuals/shared/PetFollow")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local OX, OY, OZ = PetFollow.OFFSET_X, PetFollow.OFFSET_Y, PetFollow.OFFSET_Z
local DT = 1 / 60

-- A pet at rest at its snap spot behind an owner standing at the origin, facing -Z (yaw 0).
local function settled(): PetFollow.State
	local s = PetFollow.new(0)
	PetFollow.step(s, DT, 0, 0, 0, 0)
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

local function flat(s: PetFollow.State, rx: number, rz: number): number
	return math.sqrt((s.x - rx) ^ 2 + (s.z - rz) ^ 2)
end

-- Walks the owner from (x0, z0) to (x1, z1) at `speed` studs/s, then `rest` seconds still. Returns the owner's end.
local function walk(s: PetFollow.State, x0: number, z0: number, x1: number, z1: number, speed: number, rest: number?)
	local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local frames = math.max(1, math.floor(len / speed / DT))
	for i = 1, frames do
		local t = i / frames
		PetFollow.step(s, DT, x0 + (x1 - x0) * t, 0, z0 + (z1 - z0) * t, 0)
	end
	for _ = 1, math.floor((rest or 0) / DT) do
		PetFollow.step(s, DT, x1, 0, z1, 0)
	end
end

describe("PetFollow snap", function()
	it("the first step puts it at the owner's back-right offset", function()
		local s = settled()
		expect(s.x).toBeCloseTo(OX)
		expect(s.y).toBeCloseTo(OY)
		expect(s.z).toBeCloseTo(OZ)
	end)
	it("turns that snap offset with the owner's heading", function()
		local s = PetFollow.new(0)
		PetFollow.step(s, DT, 10, 5, 20, math.pi) -- facing +Z: behind is -Z, right is -X
		expect(s.x).toBeCloseTo(10 - OX)
		expect(s.z).toBeCloseTo(20 - OZ)
		expect(s.y).toBeCloseTo(5 + OY)
	end)
	it("snaps on a teleport (> SNAP_DISTANCE) and flies below it", function()
		local s = settled()
		PetFollow.step(s, DT, 500, 0, 0, 0)
		expect(s.x).toBeCloseTo(500 + OX)
		expect(s.vx).toBe(0)
		local t = settled()
		PetFollow.step(t, DT, PetFollow.SNAP_DISTANCE - 10, 0, 0, 0)
		expect(t.x < PetFollow.SNAP_DISTANCE / 2).toBe(true) -- one frame later it has barely moved
	end)
	it("the snap spot is on the leash", function()
		expect(PetFollow.FOLLOW).toBeCloseTo(math.sqrt(OX * OX + OZ * OZ), 1e-9)
		expect(PetFollow.NEAR < PetFollow.FOLLOW).toBe(true)
	end)
end)

describe("PetFollow leash", function()
	it("doesn't move at all when the owner turns on the spot", function()
		local s = settled()
		local x, z, yaw = s.x, s.z, s.yaw
		for i = 1, 600 do
			PetFollow.step(s, DT, 0, 0, 0, i * 0.05) -- spins round and round
		end
		expect(s.x).toBeCloseTo(x, 1e-9)
		expect(s.z).toBeCloseTo(z, 1e-9)
		expect(s.yaw).toBeCloseTo(yaw, 1e-9) -- and doesn't turn either
	end)
	it("is pulled in to FOLLOW when the owner walks away, and settles without passing it", function()
		local s = settled()
		local last = math.huge
		for i = 1, 600 do
			PetFollow.step(s, DT, 20, 0, -20, 0) -- owner stepped far off (one jump of the goal)
			local d = flat(s, 20, -20)
			if i > 1 then
				expect(d <= last + 1e-9).toBe(true) -- only ever closes in
			end
			expect(d >= PetFollow.FOLLOW - 1e-6).toBe(true) -- never past the leash
			last = d
		end
		expect(last).toBeCloseTo(PetFollow.FOLLOW, 1e-3)
	end)
	it("stays put while the owner is within the leash band", function()
		local s = settled()
		local x, z = s.x, s.z
		-- Owner shuffles 0.5 studs toward the pet, slower than WALKING: distance stays between NEAR and FOLLOW.
		walk(s, 0, 0, 0.3, 0.4, 1, 1)
		expect(flat(s, 0.3, 0.4) <= PetFollow.FOLLOW + 1e-6).toBe(true)
		expect(math.abs(s.x - x) + math.abs(s.z - z) < 1e-6).toBe(true)
	end)
	it("backs off to NEAR when the owner stands right next to it", function()
		local s = settled()
		local rx, rz = s.x - 0.5, s.z -- owner steps up to 0.5 studs from it and stands there
		for _ = 1, 600 do
			PetFollow.step(s, DT, rx, 0, rz, 0)
		end
		expect(flat(s, rx, rz)).toBeCloseTo(PetFollow.NEAR, 1e-2)
	end)
	it("trails behind-right of a walking owner, about the leash away", function()
		local s = settled()
		walk(s, 0, 0, 0, -80, 16, 0) -- along -Z: behind is +Z, right is +X
		expect(s.z > -80).toBe(true) -- behind
		expect(s.x > 0.5).toBe(true) -- to the right of the path
		local d = flat(s, 0, -80)
		expect(d > PetFollow.FOLLOW - 0.2 and d < PetFollow.FOLLOW + 3).toBe(true) -- spring lag only
	end)
	it("works the same walking along +X (right of +X is +Z)", function()
		local s = settled()
		walk(s, 0, 0, 80, 0, 16, 0)
		expect(s.x < 80).toBe(true)
		expect(s.z > 0.5).toBe(true)
	end)
	it("steps aside when the owner walks straight at it, instead of fleeing ahead", function()
		local s = settled() -- pet at (OX, OZ), behind-right
		local px, pz = s.x, s.z
		-- Owner walks through the pet's spot and 20 studs beyond.
		local len = math.sqrt(px * px + pz * pz)
		local ex, ez = px / len * (len + 20), pz / len * (len + 20)
		walk(s, 0, 0, ex, ez, 16, 1)
		-- The pet ends behind the owner (relative to where they walked), not ahead of them.
		local tx, tz = ex / (len + 20), ez / (len + 20)
		expect((s.x - ex) * tx + (s.z - ez) * tz < 0).toBe(true)
	end)
	it("never swings round the owner faster than SWING_SPEED, even walked into head-on", function()
		local s = settled()
		local px, pz = s.x, s.z
		local len = math.sqrt(px * px + pz * pz)
		local frames = math.floor((len + 20) / 16 / DT)
		local lx, lz = s.x, s.z
		for i = 1, frames do
			local t = i / frames * (len + 20) / len
			PetFollow.step(s, DT, px * t, 0, pz * t, 0)
			local speed = math.sqrt((s.x - lx) ^ 2 + (s.z - lz) ^ 2) / DT
			expect(speed < PetFollow.SWING_SPEED + 16 * 1.5).toBe(true) -- swing plus keeping pace with the owner
			lx, lz = s.x, s.z
		end
	end)
	it("keeps clear of an owner walking straight at it", function()
		local s = settled()
		local px, pz = s.x, s.z
		local len = math.sqrt(px * px + pz * pz)
		local frames = math.floor((len + 20) / 16 / DT)
		for i = 1, frames do
			local t = i / frames * (len + 20) / len
			PetFollow.step(s, DT, px * t, 0, pz * t, 0)
			expect(flat(s, px * t, pz * t) > PetFollow.NEAR * 0.6).toBe(true)
		end
	end)
	it("ends in about the same place at 30 and 144 fps", function()
		local ends = {}
		for _, fps in { 30, 144 } do
			local s = settled()
			local dt = 1 / fps
			for i = 1, fps * 3 do
				PetFollow.step(s, dt, 0, 0, -16 * i * dt, 0)
			end
			for _ = 1, fps do
				PetFollow.step(s, dt, 0, 0, -48, 0)
			end
			table.insert(ends, s)
		end
		expect(math.abs(ends[1].x - ends[2].x) < 0.3).toBe(true)
		expect(math.abs(ends[1].z - ends[2].z) < 0.3).toBe(true)
	end)
end)

describe("PetFollow height", function()
	it("keeps its height while the owner jumps", function()
		local s = settled()
		for i = 1, 48 do -- a 0.8 s jump, up to 7 studs
			local h = 7 * math.sin(math.pi * i / 48)
			PetFollow.step(s, DT, 0, h, 0, 0, false)
		end
		expect(s.y).toBeCloseTo(OY, 1e-9)
		PetFollow.step(s, DT, 0, 0, 0, 0, true)
		expect(s.y).toBeCloseTo(OY, 1e-6)
	end)
	it("follows a drop below the take-off height even in the air", function()
		local s = settled()
		for _ = 1, 600 do
			PetFollow.step(s, DT, 0, -20, 0, 0, false) -- fell off a ledge
		end
		expect(s.y).toBeCloseTo(-20 + OY, 1e-3)
	end)
	it("rises when the owner stands higher (steps, ramps), without overshoot", function()
		local s = settled()
		for _ = 1, 600 do
			PetFollow.step(s, DT, 0, 4, 0, 0, true)
			expect(s.y <= 4 + OY + 1e-9).toBe(true)
		end
		expect(s.y).toBeCloseTo(4 + OY, 1e-3)
	end)
	it("follows the height after AIR_HOLD in the air (a long fall, or a wrong grounded flag)", function()
		local s = settled()
		for _ = 1, math.ceil((PetFollow.AIR_HOLD + 2) / DT) do
			PetFollow.step(s, DT, 0, 6, 0, 0, false)
		end
		expect(s.y).toBeCloseTo(6 + OY, 1e-2)
	end)
	it("nil grounded counts as grounded", function()
		local s = settled()
		for _ = 1, 600 do
			PetFollow.step(s, DT, 0, 3, 0, 0)
		end
		expect(s.y).toBeCloseTo(3 + OY, 1e-3)
	end)
end)

describe("PetFollow robustness", function()
	it("is finite at dt 0, 1, a huge, negative and NaN dt", function()
		for _, dt in { 0, 1, 1e9, -1, 0 / 0, math.huge } do
			local s = settled()
			PetFollow.step(s, dt, 7, 1, 3, 1)
			expect(finite(s)).toBe(true)
			PetFollow.step(s, dt, -4, 2, 8, -2, false)
			expect(finite(s)).toBe(true)
		end
		local s = settled()
		local before = s.x
		PetFollow.step(s, 0, 9, 0, 0, 0)
		expect(s.x).toBeCloseTo(before, 1e-9) -- dt 0 does not move it
	end)
	it("is finite with the owner exactly on the pet", function()
		local s = settled()
		for _ = 1, 120 do
			PetFollow.step(s, DT, s.x, 0, s.z, 0)
			expect(finite(s)).toBe(true)
		end
	end)
	it("treats a hitch as MAX_DT", function()
		local a, b = settled(), settled()
		PetFollow.step(a, 1, 20, 0, 0, 0)
		PetFollow.step(b, PetFollow.MAX_DT, 20, 0, 0, 0)
		expect(a.x).toBe(b.x)
	end)
	it("does not allocate per step", function()
		local s = settled()
		PetFollow.step(s, DT, 3, 0, 0, 0)
		local before = collectgarbage("count")
		for i = 1, 20000 do
			PetFollow.step(s, DT, i % 50, 0, 0, i * 0.01, i % 3 == 0)
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
	it("faces where it flies, and keeps that facing at rest", function()
		local s = settled()
		walk(s, 0, 0, 40, 0, 16, 0) -- owner runs along +X
		-- moving +X is yaw -pi/2 (look vector (-sin, -cos))
		expect(math.abs(PetFollow.angleDelta(s.yaw, -math.pi / 2)) < 0.25).toBe(true)
		for _ = 1, 60 do
			PetFollow.step(s, DT, 40, 0, 0, 0) -- stops; the pet glides to rest
		end
		local held = s.yaw
		for i = 1, 600 do
			PetFollow.step(s, DT, 40, 0, 0, i * 0.1) -- then spins on the spot
		end
		expect(math.abs(PetFollow.angleDelta(s.yaw, held)) < 0.05).toBe(true)
	end)
	it("never turns faster than YAW_MAX_RATE", function()
		local s = settled()
		local last = s.yaw
		walk(s, 0, 0, 0, 0.001, 16, 0)
		for i = 1, 240 do
			local a = i * 0.08
			PetFollow.step(s, DT, 30 * math.cos(a), 0, 30 * math.sin(a), 0) -- owner runs a tight circle
			expect(math.abs(PetFollow.angleDelta(last, s.yaw)) <= PetFollow.YAW_MAX_RATE * DT + 1e-9).toBe(true)
			last = s.yaw
		end
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
			PetFollow.step(s, DT, 0, 0, 0, 0)
			lo, hi = math.min(lo, s.bob), math.max(hi, s.bob)
			expect(math.abs(s.bob) <= PetFollow.BOB_AMPLITUDE + 1e-12).toBe(true)
		end
		expect(hi > PetFollow.BOB_AMPLITUDE * 0.95).toBe(true)
		expect(lo < -PetFollow.BOB_AMPLITUDE * 0.95).toBe(true)
		expect(PetFollow.BOB_AMPLITUDE <= 0.25).toBe(true) -- gentle
		expect(s.y).toBeCloseTo(OY, 1e-9) -- the spring state itself does not bob
	end)
end)
