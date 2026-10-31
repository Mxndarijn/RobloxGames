--!strict
-- The claw show's timeline (Visuals.ClawShow, contract/exclusive-shop.md §7.2): the hand's path, where the prize is in
-- each step, when the pedestal's seat is out and the banner shows, the banner's words and the server's queue.
local ClawShow = require("../src/visuals/shared/ClawShow")
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local CLAW = Config.EXCLUSIVE_SHOP.claw
local LAYOUT = WorldLayout.EXCLUSIVE_CLAW

-- Start time of a step.
local function at(name: string): number
	local t = 0
	for _, step in ClawShow.STEPS do
		if step.name == name then
			return t
		end
		t += step.seconds
	end
	error(`no step {name}`)
end

local function near(a: { number }, b: { number }, places: number?)
	for i = 1, 3 do
		expect(a[i]).toBeCloseTo(b[i], places or 4)
	end
end

local IDLE = WorldLayout.clawPoint(LAYOUT.handIdle)
local MOUTH = WorldLayout.clawPoint(LAYOUT.chuteMouth)

describe("steps", function()
	it("run in order and add up to the show's length", function()
		local names, sum = {}, 0
		for _, step in ClawShow.STEPS do
			table.insert(names, step.name)
			expect(step.seconds > 0).toBe(true)
			sum += step.seconds
		end
		expect(names).toEqual({ "aim", "drop", "grab", "lift", "carry", "release", "pop", "show", "fly" })
		expect(ClawShow.DURATION).toBeCloseTo(sum, 6)
		expect(ClawShow.DURATION < 12).toBe(true) -- short enough that a busy shop doesn't build a long queue
	end)
	it("bring the hand home before the show ends", function()
		expect(at("pop") + CLAW.returnSeconds <= ClawShow.DURATION).toBe(true)
	end)
end)

describe("frame", function()
	for display = 0, #LAYOUT.displays do
		local target = ClawShow.target(display)
		it(`starts and ends with the hand at rest (display {display})`, function()
			near(ClawShow.frame(display, 0).hand, IDLE)
			local last = ClawShow.frame(display, ClawShow.DURATION)
			near(last.hand, IDLE)
			expect(last.done).toBe(true)
			expect(last.prize).toBeNil()
			expect(last.holding).toBe(false)
			expect(last.banner).toBe(false)
		end)
		it(`reaches down to the prize and holds it at grab depth (display {display})`, function()
			local grab = ClawShow.frame(display, at("grab") + 0.1)
			expect(grab.hand[2]).toBeCloseTo(target[2] + CLAW.grabDepth, 4)
			expect(grab.prize ~= nil).toBe(true)
			near((grab.prize :: any).pos, target)
			local lifted = ClawShow.frame(display, at("carry"))
			local prize = lifted.prize :: any
			expect(prize.pos[2]).toBeCloseTo(lifted.hand[2] - CLAW.grabDepth, 4)
			expect(prize.pos[1]).toBeCloseTo(lifted.hand[1], 4)
		end)
		it(`keeps the hand inside the claw box and never over the ceiling (display {display})`, function()
			local t = 0
			while t <= ClawShow.DURATION do
				local h = ClawShow.frame(display, t).hand
				expect(h[1] >= -LAYOUT.boxX[2] - 1e-6 and h[1] <= -LAYOUT.boxX[1] + 1e-6).toBe(true)
				expect(h[3] >= LAYOUT.boxZ[1] - 1e-6 and h[3] <= LAYOUT.boxZ[2] + 1e-6).toBe(true)
				expect(h[2] <= IDLE[2] + 1e-6).toBe(true)
				t += 0.05
			end
		end)
		it(
			`drops the prize in the funnel, then pops it out of the chute under the banner (display {display})`,
			function()
				local falling = ClawShow.frame(display, at("pop") - 0.01).prize :: any
				near(falling.pos, WorldLayout.clawPoint(LAYOUT.funnelTop), 1)
				local out = ClawShow.frame(display, at("show") + 0.1)
				local prize = out.prize :: any
				expect(out.banner).toBe(true)
				expect(prize.scale).toBeCloseTo(1, 4)
				near(prize.pos, { MOUTH[1], MOUTH[2] + CLAW.popRise, MOUTH[3] - CLAW.popOut })
				expect(ClawShow.frame(display, at("pop") - 0.01).banner).toBe(false)
			end
		)
	end
	it("takes the seat off its pedestal from the grab to the end, and a capsule never empties one", function()
		expect(ClawShow.frame(2, at("grab") - 0.01).holding).toBe(false)
		expect(ClawShow.frame(2, at("grab")).holding).toBe(true)
		expect(ClawShow.frame(2, ClawShow.DURATION - 0.01).holding).toBe(true)
		expect(ClawShow.frame(ClawShow.CAPSULE, at("show")).holding).toBe(false)
	end)
	it("aims at the pedestal tops and the capsule spot", function()
		near(ClawShow.target(1), WorldLayout.clawPoint(LAYOUT.displays[1]))
		near(ClawShow.target(ClawShow.CAPSULE), WorldLayout.clawPoint(LAYOUT.capsule))
	end)
end)

describe("bannerText", function()
	it("names the buyer and the item, a gift, or a prize", function()
		expect(ClawShow.bannerText({ startAt = 0, display = 1, buyer = "Mila", label = "UFO" })).toBe("Mila got UFO!")
		expect(ClawShow.bannerText({ startAt = 0, display = 1, buyer = "Mila", label = "UFO", gift = true })).toBe(
			"Mila gifted UFO!"
		)
		expect(ClawShow.bannerText({ startAt = 0, display = 0, buyer = "Mila" })).toBe("Mila got a prize!")
	end)
end)

describe("schedule", function()
	it("starts the first show after the lead and queues the next ones one after the other", function()
		local q = { nextFree = -math.huge }
		local first = ClawShow.schedule(q, 100) :: number
		expect(first).toBeCloseTo(100 + CLAW.lead, 6)
		local second = ClawShow.schedule(q, 101) :: number
		expect(second).toBeCloseTo(first + ClawShow.DURATION + CLAW.gap, 6)
		local later = ClawShow.schedule(q, 1000) :: number
		expect(later).toBeCloseTo(1000 + CLAW.lead, 6)
	end)
	it("skips a show that would wait longer than maxWait, and keeps the queue as it was", function()
		local q = { nextFree = -math.huge }
		local n = 0
		while ClawShow.schedule(q, 0) do
			n += 1
		end
		expect(n >= 1).toBe(true)
		local free = q.nextFree
		expect(ClawShow.schedule(q, 0)).toBeNil()
		expect(q.nextFree).toBe(free)
	end)
end)
