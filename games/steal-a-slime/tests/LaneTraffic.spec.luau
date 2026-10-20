--!strict
-- Slimes never walk into each other (src/shared/LaneTraffic.luau, contract/slime-life.md): lane slimes queue behind
-- the one ahead, catch up afterwards and still drain on time; walkers off the lane step round bodies in the way.
local Config = require("../src/shared/Config")
local LaneTraffic = require("../src/shared/LaneTraffic")
local ParadeChoreo = require("../src/shared/ParadeChoreo")
local ParadeLane = require("../src/shared/ParadeLane")
local SlimePersona = require("../src/shared/SlimePersona")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function walker(id: string, s: number, lateral: number?, radius: number?): LaneTraffic.Walker
	return { id = id, s = s, lateral = lateral or 0, radius = radius or 1.5, pace = 4 }
end

describe("LaneTraffic.step", function()
	it("a slime catching up with a stopped one waits behind it, touching neither", function()
		local state = {}
		local room = 1.5 + 1.5 + LaneTraffic.GAP
		LaneTraffic.step({ walker("a", 20), walker("b", 10) }, state, 0)
		for f = 1, 120 do
			-- a stands still at 20, b's plan walks on through it
			LaneTraffic.step({ walker("a", 20), walker("b", 10 + f * 4 / 30) }, state, 1 / 30)
			expect(state.a).toBe(20)
			expect(state.b <= 20 - room + 1e-9).toBe(true)
		end
		expect(state.b).toBeCloseTo(20 - room, 1e-9)
	end)
	it("then catches up with its plan, never faster than CATCH_SPEED and never backwards", function()
		local state = { a = 20, b = 15 }
		local prev = 15
		for f = 1, 300 do
			LaneTraffic.step({ walker("a", 20 + f * 4 / 30), walker("b", 26) }, state, 1 / 30)
			expect(state.b >= prev - 1e-9).toBe(true)
			expect(state.b - prev <= LaneTraffic.CATCH_SPEED * 4 / 30 + 1e-9).toBe(true)
			prev = state.b
		end
		expect(state.b).toBe(26)
	end)
	it("slimes side by side don't hold each other up", function()
		local state = {}
		LaneTraffic.step({ walker("a", 20, -2), walker("b", 20, 2) }, state, 1 / 30)
		expect(state.a).toBe(20)
		expect(state.b).toBe(20)
	end)
	it("lets go before the drain: the floor beats the queue", function()
		local state = { a = 20, b = 17 }
		local w = walker("b", 19)
		w.floor = 19
		LaneTraffic.step({ walker("a", 20), w }, state, 1 / 30)
		expect(state.b).toBe(19)
		expect(LaneTraffic.holdLimit(0, 4)).toBe(0)
		expect(LaneTraffic.holdLimit(10, 4) > 0).toBe(true)
	end)
	it("keeps a whole lane of beats and a run of bonus drops apart from spawn to drain", function()
		local LIFE = Config.WILD_LIFETIME
		local slimes = {}
		local times = { 0, 4, 8, 9.6, 11.2, 12.8, 14.4, 16, 20, 24 } -- regular drops and bonus drops on SLIDE_GAP slots
		for i, at in times do
			local id = `w{i}`
			local startAt, seconds, lead = ParadeLane.walkTimes(at, at + LIFE)
			local temper = SlimePersona.TEMPERS[(i % #SlimePersona.TEMPERS) + 1]
			table.insert(slimes, {
				id = id,
				at = at,
				startAt = startAt,
				plan = ParadeChoreo.plan(ParadeChoreo.seedFor(id), temper, seconds, lead),
				lateral = ((i * 7) % 5 - 2) * 0.4, -- crowded: all within 1.6 studs of the centreline
				radius = 1.2 + (i % 4) * 0.4,
			})
		end
		local pace = ParadeLane.walkSpeed(LIFE)
		local state = {}
		local worst = math.huge
		for f = 0, math.floor((24 + LIFE) * 30) do
			local now = f / 30
			local walkers = {}
			for _, sl in slimes do
				if ParadeLane.phase(sl.at, sl.at + LIFE, now) == "Walk" then
					local s = ParadeLane.distance(sl.at, sl.at + LIFE, now)
						+ ParadeChoreo.offset(sl.plan, now - sl.startAt) * pace
					local left = sl.at + LIFE - ParadeLane.DRAIN_SECONDS - now
					table.insert(walkers, {
						id = sl.id,
						s = s,
						lateral = sl.lateral,
						radius = sl.radius,
						pace = pace,
						floor = s - LaneTraffic.holdLimit(left, pace),
					})
				end
			end
			LaneTraffic.step(walkers, state, 1 / 30)
			for i = 1, #walkers do
				for j = i + 1, #walkers do
					local a, b = walkers[i], walkers[j]
					local room = a.radius + b.radius
					if math.abs(a.lateral - b.lateral) < room then
						worst = math.min(worst, math.abs(state[a.id] - state[b.id]) - room)
					end
				end
			end
		end
		expect(worst >= -1e-6).toBe(true)
	end)
end)

describe("LaneTraffic.push", function()
	it("is the smallest step that clears every body, and nothing when clear", function()
		local px, pz = LaneTraffic.push(0, 0, 1, { { x = 2, z = 0, radius = 1.5 } })
		expect(px).toBeCloseTo(-(1 + 1.5 + LaneTraffic.GAP - 2), 1e-9)
		expect(pz).toBeCloseTo(0, 1e-9)
		local cx, cz = LaneTraffic.push(0, 0, 1, { { x = 10, z = 0, radius = 1.5 } })
		expect(cx == 0 and cz == 0).toBe(true)
	end)
end)
