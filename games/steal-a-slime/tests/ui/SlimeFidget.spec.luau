--!strict
-- Pad fidgets and put-downs (src/ui/SlimeFidget.luau, contract/slime-life.md "Alive motion"): a pad slime fidgets
-- every few seconds by temperament, never the same fidget twice in a row, every pose starts and ends at rest, and
-- the put-downs (drop, arrive) land with one splat.
local SlimeFidget = require("../../src/ui/SlimeFidget")
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

-- Steps a fidget state for `seconds`; returns every pose and the kinds it played in order.
local function run(temper: string, seconds: number, seed: number): ({ SlimeFidget.Pose }, { string })
	local rand = lcg(seed)
	local st = SlimeFidget.new(temper, 0, rand)
	local poses, kinds = {}, {}
	local current: string? = nil
	for f = 1, math.floor(seconds * FPS) do
		local p = table.clone(SlimeFidget.step(st, f / FPS, rand))
		table.insert(poses, p)
		if st.kind ~= current then
			current = st.kind
			if current then
				table.insert(kinds, current)
			end
		end
	end
	return poses, kinds
end

local ALL = { "hop", "bounce", "shake", "stretch", "spin", "nap", "peek", "huff", "wiggle", "drop", "arrive" }

describe("SlimeFidget schedule", function()
	it("every temperament fidgets every few seconds", function()
		for _, temper in SlimePersona.TEMPERS do
			local _, kinds = run(temper, 60, 3)
			local lo = math.floor(60 / (SlimeFidget.EVERY[2] + 5))
			expect(#kinds >= lo).toBe(true)
			expect(#kinds <= 60 / SlimeFidget.EVERY[1] + 1).toBe(true)
		end
	end)

	it("never plays the same fidget twice in a row", function()
		for _, temper in SlimePersona.TEMPERS do
			local _, kinds = run(temper, 240, 11)
			for i = 2, #kinds do
				expect(kinds[i] ~= kinds[i - 1]).toBe(true)
			end
		end
	end)

	it("picks by temperament: a Lazy slime naps, a Feisty one huffs, a Showoff spins", function()
		local function count(temper: string, kind: string): number
			local _, kinds = run(temper, 600, 7)
			local n = 0
			for _, k in kinds do
				if k == kind then
					n += 1
				end
			end
			return n
		end
		expect(count("Lazy", "nap") > 0).toBe(true)
		expect(count("Feisty", "huff") > 0).toBe(true)
		expect(count("Showoff", "spin") > 0).toBe(true)
		expect(count("Lazy", "spin")).toBe(0)
		expect(count("Shy", "huff")).toBe(0)
	end)

	it("is at rest between fidgets", function()
		local st = SlimeFidget.new("Bouncy", 0, function()
			return 0.99
		end)
		local p = SlimeFidget.step(st, 0.5, math.random)
		expect(p.lift).toBe(0)
		expect(p.sy).toBe(1)
		expect(p.yawWeight).toBe(0)
	end)
end)

describe("SlimeFidget poses", function()
	it("every kind starts and ends at rest, inside sane bounds", function()
		for _, kind in ALL do
			local D = SlimeFidget.SECONDS[kind]
			local first = SlimeFidget.pose(kind, 0)
			local last = SlimeFidget.pose(kind, D)
			if kind ~= "drop" then -- a drop starts in the air
				expect(math.abs(first.lift) < 1e-6).toBe(true)
			end
			expect(math.abs(last.lift) < 0.02).toBe(true)
			expect(math.abs(last.sy - 1) < 0.05).toBe(true)
			expect(math.abs(last.roll) < 0.03).toBe(true)
			for u = 0, D, 0.01 do
				local p = SlimeFidget.pose(kind, u)
				expect(p.sy > 0.55 and p.sy < 1.4).toBe(true)
				expect(p.lift >= -1e-6 and p.lift <= SlimeFidget.DROP_HEIGHT + 1e-6).toBe(true)
				expect(math.abs(p.roll) < 0.4 and math.abs(p.tilt) < 0.5).toBe(true)
				expect(p.carry >= 0 and p.carry <= 1).toBe(true)
			end
		end
	end)

	it("a hop leaves the ground and squats first", function()
		expect(SlimeFidget.pose("hop", 0.08).sy < 0.95).toBe(true)
		local top = 0
		for u = 0, 1, 0.01 do
			top = math.max(top, SlimeFidget.pose("hop", u).lift)
		end
		expect(top > 0.5).toBe(true)
	end)

	it("a spin turns a full circle in the air", function()
		local most = 0
		for u = 0, SlimeFidget.SECONDS.spin, 0.01 do
			local p = SlimeFidget.pose("spin", u)
			if p.yawWeight > 0 then
				most = math.max(most, p.yaw)
			end
		end
		expect(most > 2 * math.pi - 0.2).toBe(true)
	end)

	it("a nap shuts the eyes and shows z", function()
		local p = SlimeFidget.pose("nap", 2)
		expect(p.face).toBe("asleep")
		expect(p.emote).toBe("sleep")
		expect(p.sy < 1).toBe(true)
	end)

	it("a drop falls from DROP_HEIGHT, splats flat and wobbles back", function()
		expect(SlimeFidget.pose("drop", 0).lift).toBeCloseTo(SlimeFidget.DROP_HEIGHT, 6)
		expect(SlimeFidget.pose("drop", 0.32).sy < 0.75).toBe(true)
		expect(math.abs(SlimeFidget.pose("drop", 1.5).sy - 1) < 0.05).toBe(true)
	end)

	it("an arrive carries the slime from the old spot to the new one in the air", function()
		expect(SlimeFidget.pose("arrive", 0.05).carry).toBe(1)
		local mid = SlimeFidget.pose("arrive", 0.1 + (SlimeFidget.MOVE_HOP - 0.1) / 2)
		expect(mid.carry > 0.4 and mid.carry < 0.6).toBe(true)
		expect(mid.lift > 1).toBe(true)
		expect(SlimeFidget.pose("arrive", SlimeFidget.MOVE_HOP + 0.05).carry).toBe(0)
	end)

	it("reports each landing splat once", function()
		local st = SlimeFidget.new("Bouncy", 0, math.random)
		SlimeFidget.play(st, "bounce", 0)
		local splats = 0
		for f = 1, 90 do
			if SlimeFidget.step(st, f / FPS, math.random).splat > 0 then
				splats += 1
			end
		end
		expect(splats).toBe(2)
		SlimeFidget.play(st, "drop", 10)
		local drops = 0
		for f = 1, 150 do
			if SlimeFidget.step(st, 10 + f / FPS, math.random).splat > 0 then
				drops += 1
			end
		end
		expect(drops).toBe(1)
	end)
end)
