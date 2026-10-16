--!strict
-- SlimeAnim: event schedule, shared track loading and the LOD cap of the
-- animated slime rig.
local SlimeAnim = require("../../src/ui/SlimeAnim")
local SlimeLife = require("../../src/ui/SlimeLife")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function lcg(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

describe("SlimeAnim.tick", function()
	it("plays hops and looks over time, never two hops at once, and lands after every hop", function()
		local rand = lcg(7)
		local params = SlimeLife.params(3, "Wild")
		local sched = SlimeAnim.newSchedule(params, 0, rand)
		local hops, lands, looks = 0, 0, 0
		local airborne = false
		for i = 1, 6000 do
			for _, event in SlimeAnim.tick(sched, params, i / 20, rand) do
				if event == "Hop" then
					expect(airborne).toBe(false)
					airborne = true
					hops += 1
				elseif event == "Land" then
					expect(airborne).toBe(true)
					airborne = false
					lands += 1
				else
					expect(airborne).toBe(false)
					looks += 1
				end
			end
		end
		expect(hops > 20).toBe(true)
		expect(looks > 20).toBe(true)
		expect(hops - lands <= 1).toBe(true)
	end)

	it("doesn't queue catch-up hops after a long gap", function()
		local rand = lcg(3)
		local params = SlimeLife.params(1, "Pad")
		local sched = SlimeAnim.newSchedule(params, 0, rand)
		local hops = 0
		for _, event in SlimeAnim.tick(sched, params, 1000, rand) do
			if event == "Hop" then
				hops += 1
			end
		end
		expect(hops <= 1).toBe(true)
	end)
end)

describe("SlimeAnim.newTracks", function()
	it("loads each animation once per rig, however often it is asked for", function()
		local loaded = 0
		local tracks = SlimeAnim.newTracks(function(key: string)
			loaded += 1
			return { key = key }
		end)
		for _ = 1, 10 do
			tracks:get("idle")
			tracks:get("hop")
		end
		expect(loaded).toBe(2)
		expect(tracks.loads).toBe(2)
	end)

	it("retries a failed load later and caches nothing for it", function()
		local fail = true
		local tracks = SlimeAnim.newTracks(function(key: string)
			return if fail then nil else { key = key }
		end)
		expect(tracks:get("idle")).toBeNil()
		fail = false
		expect(tracks:get("idle") ~= nil).toBe(true)
	end)
end)

describe("animation LOD (SlimeLife.select with onScreen)", function()
	it("caps active rigs at MAX_ACTIVE, nearest first", function()
		local cands: { SlimeLife.Candidate } = {}
		for i = 1, 40 do
			table.insert(cands, { id = `s{i}`, distance = i, state = "Wild", tier = 1, onScreen = true })
		end
		local active = SlimeLife.select(cands, nil)
		local n = 0
		for id in active do
			n += 1
			expect(tonumber(string.sub(id, 2)) :: number <= SlimeLife.MAX_ACTIVE).toBe(true)
		end
		expect(n).toBe(SlimeLife.MAX_ACTIVE)
	end)

	it("skips slimes off screen or too far, even when they were active", function()
		local cands: { SlimeLife.Candidate } = {
			{ id = "a", distance = 5, state = "Wild", onScreen = false },
			{ id = "b", distance = 5, state = "Wild", onScreen = true },
			{ id = "c", distance = 500, state = "Wild", onScreen = true },
			{ id = "d", distance = 5, state = "Wild" },
		}
		local active = SlimeLife.select(cands, { a = true, c = true })
		expect(active.a).toBeNil()
		expect(active.b).toBe(true)
		expect(active.c).toBeNil()
		expect(active.d).toBe(true)
	end)
end)
