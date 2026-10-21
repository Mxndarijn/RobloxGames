--!strict
-- Species gaits (src/ui/SlimeGait.luau, contract/slime-life.md): hoppers stand, squat, jump to where the anchor
-- will be, splat and wobble, and never stray more than a leap from the anchor; the other gaits stay on the anchor
-- and only step while it moves.
local SlimeGait = require("../../src/ui/SlimeGait")
local SlimePersona = require("../../src/shared/SlimePersona")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function lcg(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local FPS = 60

-- Walks an anchor along +X at `speed` studs / s for `seconds` and records every pose.
local function run(persona: SlimePersona.Persona, speed: number, seconds: number, seed: number?)
	local rand = lcg(seed or 1)
	local st = SlimeGait.new(0, 0, 0, 0)
	local poses = {}
	for f = 1, math.floor(seconds * FPS) do
		local t = f / FPS
		local p = SlimeGait.step(st, persona, speed * t, 0, 1, 0, t, rand)
		table.insert(poses, { t = t, x = speed * t, p = table.clone(p) })
	end
	return poses
end

local GUMMY = SlimePersona.of("gummy")

describe("SlimeGait hops", function()
	it("a standing hopper never jumps", function()
		for _, r in run(GUMMY, 0, 5) do
			expect(r.p.air).toBe(false)
			expect(r.p.lift).toBe(0)
			expect(math.abs(r.p.dx) < 1e-9 and math.abs(r.p.dz) < 1e-9).toBe(true)
		end
	end)
	it("a walking hopper jumps again and again and stays within one leap of the anchor", function()
		local jumps, landings, lastAir = 0, 0, false
		local top = 0
		for _, r in run(GUMMY, 4, 12) do
			if r.p.air and not lastAir then
				jumps += 1
			end
			if r.p.landed > 0 then
				landings += 1
			end
			lastAir = r.p.air
			top = math.max(top, r.p.lift)
			expect(math.sqrt(r.p.dx ^ 2 + r.p.dz ^ 2) <= SlimeGait.MAX_GAP).toBe(true)
		end
		expect(jumps >= 6).toBe(true)
		expect(landings >= 5).toBe(true)
		expect(top > GUMMY.hop.height * 0.5).toBe(true)
	end)
	it("lands close to the anchor (it aims where the anchor will be)", function()
		local worst = 0
		for _, r in run(GUMMY, 4, 12) do
			if r.p.landed > 0 then
				-- one frame after landing the anchor moved on by speed / FPS at most
				worst = math.max(worst, math.abs(r.p.dx) - 4 / FPS)
			end
		end
		expect(worst < 1.5).toBe(true)
	end)
	it("waits on the ground between jumps and squats before each one", function()
		local crouched = false
		local groundFrames = 0
		for _, r in run(GUMMY, 4, 8) do
			if not r.p.air then
				groundFrames += 1
				if r.p.sy < 0.9 and r.p.sx > 1 then
					crouched = true
				end
			end
		end
		expect(groundFrames > 8 * FPS * 0.2).toBe(true)
		expect(crouched).toBe(true)
	end)
	it("a far jump (a teleport) snaps the body back to the anchor", function()
		local st = SlimeGait.new(0, 0, 0, 0)
		SlimeGait.step(st, GUMMY, 0, 0, 1, 0, 0.1, lcg(3))
		local p = SlimeGait.step(st, GUMMY, 50, 0, 1, 0, 0.2, lcg(3))
		expect(math.abs(p.dx) < 1e-6).toBe(true)
	end)
	it("Shy hoppers jump lower than Bouncy ones", function()
		local function peak(id: string): number
			local top = 0
			for _, r in run(SlimePersona.of(id), 4, 10) do
				if r.p.kind == "normal" then
					top = math.max(top, r.p.lift)
				end
			end
			return top
		end
		expect(peak("lop") / SlimePersona.of("lop").hop.height < peak("gummy") / GUMMY.hop.height).toBe(true)
	end)
	it(
		"a hopper left behind (a long landing, then its anchor stops for a beat) catches up instead of sitting there",
		function()
			local rand = lcg(4)
			local st = SlimeGait.new(0, 0, 0, 0)
			st.kind, st.landedAt = "belly", 0 -- lying flat after a belly flop
			-- meanwhile the anchor runs ahead (a beat's catch-up), then stands still (the next beat)
			local x = 0
			local p
			for f = 1, 4 * FPS do
				local t = f / FPS
				local v = if t < 0.8 then 5 else 0
				if t < 0.8 then
					x = 5 * t
				end
				-- a lane slime's anchor speed is known from lane math: it drops to 0 the moment the beat stops it
				p = SlimeGait.step(st, GUMMY, x, 0, 1, 0, t, rand, nil, v, 0)
			end
			-- four seconds in: drawn within one hop's wait of where it should stand, not stranded behind
			expect(math.abs(p.dx) <= SlimeGait.CATCH_UP).toBe(true)
		end
	)
	it("cuts a belly flop's lie-down short when it falls CATCH_UP behind", function()
		local rand = lcg(2)
		local st = SlimeGait.new(0, 0, 0, 0)
		st.kind, st.landedAt = "belly", 0 -- just landed a belly flop
		local worst = 0
		for f = 1, 2 * FPS do
			local t = f / FPS
			local p = SlimeGait.step(st, GUMMY, 6 * t, 0, 1, 0, t, rand)
			worst = math.max(worst, -p.dx)
		end
		-- the flop would lie 0.75 s longer; at 6 studs / s that is 4.5 studs behind
		expect(worst < SlimeGait.CATCH_UP + 6 * (GUMMY.hop.settle + SlimeGait.CROUCH) + 0.5).toBe(true)
	end)
end)

describe("SlimeGait.shape", function()
	it("squats, stretches in the air, is round at the top and splats on landing", function()
		local crouch = SlimeGait.shape("crouch", 1, 1.5, "normal")
		expect(crouch.sy < 1).toBe(true)
		local launch = SlimeGait.shape("air", 0.05, 1.5, "normal")
		expect(launch.sy > 1.1).toBe(true)
		local apex = SlimeGait.shape("air", 0.5, 1.5, "normal")
		expect(apex.lift).toBeCloseTo(1.5, 1e-9)
		expect(math.abs(apex.sy - 1) < 0.02).toBe(true)
		expect(apex.face).toBe("happy")
		local splat = SlimeGait.shape("land", 0, 1.5, "normal")
		expect(splat.sy < 0.85 and splat.sy >= 0.65).toBe(true) -- a splat, never so flat the face sinks in
		expect(splat.face).toBe("squeeze")
		local settled = SlimeGait.shape("land", 2, 1.5, "normal")
		expect(math.abs(settled.sy - 1) < 0.01).toBe(true)
	end)
	it("a boing flips all the way round; a belly flop lands flat and peels up", function()
		expect(SlimeGait.shape("air", 1, 1.5, "boing").tilt).toBeCloseTo(2 * math.pi, 1e-6)
		local flat = SlimeGait.shape("land", 0.2, 1.5, "belly")
		expect(flat.sy < 0.75 and flat.sy >= 0.65 and flat.face == "dizzy").toBe(true)
		expect(math.abs(SlimeGait.shape("land", 2.5, 1.5, "belly").sy - 1) < 0.02).toBe(true)
	end)
end)

describe("SlimeGait other gaits", function()
	it("stay on the anchor and step only while it moves", function()
		for _, id in { "mochi", "pengoo", "pebble" } do
			local persona = SlimePersona.of(id)
			for _, r in run(persona, 0, 2) do
				expect(r.p.dx == 0 and r.p.dz == 0).toBe(true)
				expect(math.abs(r.p.sy - 1) < 1e-6).toBe(true)
			end
			local moved = false
			for _, r in run(persona, 4, 3) do
				expect(r.p.dx == 0 and r.p.dz == 0).toBe(true)
				if math.abs(r.p.sy - 1) > 0.02 or math.abs(r.p.roll) > 0.02 then
					moved = true
				end
			end
			expect(moved).toBe(true)
		end
	end)
	it("floaters hover above the ground even standing still", function()
		for _, r in run(SlimePersona.of("bumble"), 0, 2) do
			expect(r.p.lift > 0.5).toBe(true)
		end
	end)
end)
