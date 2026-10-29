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
local function run(
	persona: SlimePersona.Persona,
	speed: number,
	seconds: number,
	seed: number?,
	setup: ((SlimeGait.State) -> ())?
)
	local rand = lcg(seed or 1)
	local st = SlimeGait.new(0, 0, 0, 0)
	if setup then
		setup(st)
	end
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
	it("a hopper that landed past a stopped anchor waits for the lane instead of hopping back to it", function()
		local rand = lcg(5)
		local st = SlimeGait.new(-2.6, 0, 0, 0) -- landed 2.6 studs past an anchor at 0 (heading -X)
		local hopped = false
		for f = 1, 3 * FPS do
			local p = SlimeGait.step(st, GUMMY, 0, 0, -1, 0, f / FPS, rand, nil, 0, 0)
			hopped = hopped or p.air == true or st.stage ~= "ground"
		end
		expect(hopped).toBe(false)
		-- far past it (a correction, not a beat) it does go back
		local far = SlimeGait.new(-(SlimeGait.OVERSHOOT + 1), 0, 0, 0)
		local back = false
		for f = 1, 3 * FPS do
			SlimeGait.step(far, GUMMY, 0, 0, -1, 0, f / FPS, rand, nil, 0, 0)
			back = back or far.stage ~= "ground"
		end
		expect(back).toBe(true)
	end)
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
		local launch = SlimeGait.shape("air", SlimeGait.PUSH, 1.5, "normal")
		expect(launch.sy > 1.1).toBe(true)
		expect(SlimeGait.shape("air", SlimeGait.PUSH / 2, 1.5, "normal").lift).toBe(0) -- feet down while it pushes
		local apex = SlimeGait.shape("air", SlimeGait.PUSH + (1 - SlimeGait.PUSH) / 2, 1.5, "normal")
		expect(apex.lift).toBeCloseTo(1.5, 1e-9)
		expect(math.abs(apex.sy - 1) < 0.06).toBe(true) -- nearly round at the top
		expect(apex.face).toBeNil() -- a plain hop keeps its eyes open
		local bigApex = SlimeGait.shape("air", SlimeGait.PUSH + (1 - SlimeGait.PUSH) / 2, 1.5, "big")
		expect(bigApex.face).toBe("happy") -- a big leap: happy shut eyes
		local splat = SlimeGait.shape("land", 0.05, 1.5, "normal")
		expect(splat.sy < 0.92 and splat.sy >= 0.65).toBe(true) -- a splat, never so flat the face sinks in
		expect(splat.face).toBeNil() -- eyes open on a plain landing
		expect(SlimeGait.shape("land", 0.05, 1.5, "big").face).toBe("squeeze") -- a hard landing squeezes them
		local settled = SlimeGait.shape("land", 2, 1.5, "normal")
		expect(math.abs(settled.sy - 1) < 0.01).toBe(true)
	end)
	it("never snaps the pose: the squat flows into the take-off and the flight into the landing", function()
		local function turn(a: number, b: number): number -- angle difference, a full turn counts as none
			return math.abs((a - b + math.pi) % (2 * math.pi) - math.pi)
		end
		for _, kind in { "normal", "big", "small", "zig", "boing", "belly" } do
			local crouchEnd = SlimeGait.shape("crouch", 1, 1.5, kind)
			local takeOff = SlimeGait.shape("air", 0, 1.5, kind)
			expect(math.abs(crouchEnd.sy - takeOff.sy) < 0.02).toBe(true)
			expect(turn(crouchEnd.tilt, takeOff.tilt) < 0.02).toBe(true)
			local fallEnd = SlimeGait.shape("air", 1, 1.5, kind)
			local touchDown = SlimeGait.shape("land", 0, 1.5, kind)
			expect(math.abs(fallEnd.sy - touchDown.sy) < 0.02).toBe(true)
			expect(turn(fallEnd.tilt, touchDown.tilt) < 0.02).toBe(true)
			-- in the air, no frame tips it more than 0.25 rad (a flip takes about 20 frames)
			local prevAir = SlimeGait.shape("air", 0, 1.5, kind)
			for f = 1, 30 do
				local cur = SlimeGait.shape("air", f / 30, 1.5, kind)
				expect(turn(cur.tilt, prevAir.tilt) < 0.5).toBe(true) -- two 60 fps frames per step
				prevAir = cur
			end
			-- at 60 frames a second no frame changes the height more than a quarter or the tilt more than 0.1 rad
			local prev = SlimeGait.shape("land", 0, 1.5, kind)
			for f = 1, 30 do
				local cur = SlimeGait.shape("land", f / 60, 1.5, kind)
				expect(math.abs(cur.sy - prev.sy) < 0.25 and math.abs(cur.tilt - prev.tilt) < 0.1).toBe(true)
				prev = cur
			end
		end
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
	it("waddlers rock from side to side but keep their feet on the ground", function()
		for _, id in { "pengoo", "moo" } do
			local rocked, highest = false, 0
			for _, r in run(SlimePersona.of(id), 4, 3) do
				highest = math.max(highest, r.p.lift)
				rocked = rocked or math.abs(r.p.roll) > 0.1
			end
			expect(rocked).toBe(true)
			expect(highest < 0.05).toBe(true)
		end
	end)
	it("floaters hover above the ground even standing still", function()
		for _, r in run(SlimePersona.of("bumble"), 0, 2) do
			expect(r.p.lift > 0.5).toBe(true)
		end
	end)
end)

describe("SlimeGait boss steps", function()
	-- counts the waddle's steps: the roll flips side on every step
	local function steps(stride: number): number
		local n, last = 0, 0
		for _, r in
			run(SlimePersona.of("klawdius"), 4.5, 6, 1, function(st)
				st.stride = stride
			end)
		do
			local side = if r.p.roll > 0.01 then 1 elseif r.p.roll < -0.01 then -1 else 0
			if side ~= 0 and side ~= last then
				n += 1
				last = side
			end
		end
		return n
	end
	it("a boss-sized stride takes proportionally fewer, bigger steps", function()
		local small, big = steps(1), steps(3)
		expect(big > 2).toBe(true)
		expect(math.abs(small / big - 3) < 0.6).toBe(true)
	end)
	it("without tricks a hopper only does plain hops (no belly flops, boings or zig-zags)", function()
		local kinds = {}
		for _, r in
			run(SlimePersona.of("pumpking"), 4, 60, 7, function(st)
				st.tricks = false
			end)
		do
			if r.p.kind then
				kinds[r.p.kind] = true
			end
		end
		for kind in kinds do
			expect(kind == "normal" or kind == "big").toBe(true)
		end
		expect(kinds.normal).toBe(true)
	end)
end)
