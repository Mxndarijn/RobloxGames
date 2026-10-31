--!strict
-- Crusher Alley (obby idea 1): every variant through ObbyCheck, the variant list against its design file, the tier
-- bands of the hazard windows (contract §10), and the timing twists the shared checks don't see: trip plates that
-- slam a set time after you land, the fake-out half drop that still hits, the wave that travels at walking speed and
-- the floods that punish waiting.
local T = require("../TestRunner")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local describe, it, expect = T.describe, T.it, T.expect
local CrusherAlley = require("../../src/shared/ObbySections/CrusherAlley")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

-- The tightest hazard window a variant of a tier must have: the floor is ObbyCheck.WINDOW, the ceiling sits well inside
-- contract §10 (easy <= 2.0 s, medium <= 1.4, hard <= 1.0) so the "not too easy" tuning can't drift back.
local BAND = {
	easy = { lo = 1.4, hi = 1.7 },
	medium = { lo = 1.0, hi = 1.15 },
	hard = { lo = 0.75, hi = 0.9 },
}

local function variantNamed(name: string): Kit.Variant
	for _, v in CrusherAlley.variants do
		if v.name == name then
			return v
		end
	end
	error(`no Crusher Alley variant {name}`)
end

local function hazards(section: Kit.Section): { Kit.Part }
	local out = {}
	for _, part in section.parts do
		if part.hazard then
			table.insert(out, part)
		end
	end
	return out
end

-- The step a part hangs over (the highest step top under its centre).
local function floorUnder(section: Kit.Section, part: Kit.Part): number
	local best = -math.huge
	for _, s in section.parts do
		if s.step then
			local x0, x1, _, y1, z0, z1 = Kit.bounds(s)
			if part.pos[1] >= x0 and part.pos[1] <= x1 and part.pos[3] >= z0 and part.pos[3] <= z1 then
				best = math.max(best, y1)
			end
		end
	end
	return best
end

-- Bottom of a crusher over its floor at time t (on its own clock).
local function headroom(section: Kit.Section, part: Kit.Part, t: number?): number
	local _, dy = Kit.offsetAt(part, t)
	return part.pos[2] - part.size[2] / 2 + dy - floorUnder(section, part)
end

describe("Crusher Alley", function()
	it("passes every shared check for every variant, seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(CrusherAlley) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("builds every variant of docs/obby-variants/1.json, in its order and tiers", function()
		local doc = serde.decode("json", fs.readFile("docs/obby-variants/1.json"))
		local design = doc.ideas[1]
		expect(CrusherAlley.id).toBe("CrusherAlley")
		expect(CrusherAlley.name).toBe(design.name)
		expect(CrusherAlley.idea).toBe(design.id)
		expect(#CrusherAlley.variants).toBe(#design.variants)
		for i, v in design.variants do
			expect(CrusherAlley.variants[i].name).toBe(v.name)
			expect(CrusherAlley.variants[i].tier).toBe(v.tier)
		end
		expect(CrusherAlley.generator).toBeNil()
	end)

	it("keeps the tightest hazard window of every variant in its tier's band", function()
		local off = {}
		for _, case in ObbyCheck.cases(CrusherAlley) do
			local section = case.build(1)
			-- Trip plates run on your own landing clock: the shared runner never waits for them (see below).
			local clocked = true
			for _, h in hazards(section) do
				clocked = clocked and h.start ~= nil
			end
			if not clocked then
				local tight = math.huge
				for _, w in ObbyCheck.windows(section) do
					tight = math.min(tight, w.slack)
				end
				local band = BAND[case.tier]
				if tight < band.lo - 1e-6 or tight > band.hi + 1e-6 then
					table.insert(off, `{case.name}: tightest window {tight} s ({band.lo}..{band.hi})`)
				end
			end
		end
		expect(table.concat(off, "\n")).toBe("")
	end)

	it("never lets a straight walk through, on any line or start time", function()
		for _, case in ObbyCheck.cases(CrusherAlley) do
			expect(ObbyCheck.straightWalk(case.build(1))).toBeNil()
		end
	end)
end)

describe("Crusher Alley timing twists", function()
	it(
		"Trip Plate: a crusher sleeps until its plate, slams 0.7 s after it and misses a walker who keeps going",
		function()
			local section = variantNamed("Trip Plate").build(1)
			local plates: { [string]: Kit.Part } = {}
			for _, part in section.parts do
				if part.trigger then
					plates[part.trigger] = part
				end
			end
			local n = 0
			for _, c in hazards(section) do
				n += 1
				local plate = plates[c.start :: string]
				expect(plate ~= nil).toBe(true)
				expect(headroom(section, c, nil)).toBeCloseTo(11, 1e-6) -- asleep: up at rest
				-- Up (over a head) for the first 0.7 s after you land on the plate.
				for k = 0, 69 do
					expect(headroom(section, c, k / 100) > Kit.HEAD).toBe(true)
				end
				-- Down to the floor soon after.
				local low = math.huge
				for k = 70, 130 do
					low = math.min(low, headroom(section, c, k / 100))
				end
				expect(low < 0.01).toBe(true)
				-- Walking on from the plate's near edge, you are clear of the crusher (with a body's width) before it gets
				-- under head height.
				local px0 = Kit.bounds(plate)
				local _, cx1 = Kit.bounds(c)
				local clear = (cx1 + ObbyCheck.BODY - px0) / Kit.WALK
				for k = 0, math.floor(clear * 100) do
					expect(headroom(section, c, k / 100) > Kit.HEAD).toBe(true)
				end
			end
			expect(n).toBe(5)
		end
	)

	it(
		"Slow Trio, Rare Line-Up, Half Lane, Cross-Punch, Head-On Wave: the whole row is one run, no pocket to wait in",
		function()
			for _, name in { "Slow Trio", "Rare Line-Up", "Half Lane", "Cross-Punch", "Head-On Wave" } do
				local section = variantNamed(name).build(1)
				expect(`{name}: {#ObbyCheck.windows(section)}`).toBe(`{name}: 1`)
			end
		end
	)

	it("Fake Out: the half drop still comes under head height", function()
		local section = variantNamed("Fake Out").build(1)
		for _, c in hazards(section) do
			local m = c.motion :: Kit.Motion
			expect(m.kind).toBe("pattern")
			local half
			for _, b in m.beats :: { Kit.Beat } do
				if b.kind == "half" then
					half = b
				end
			end
			expect(half ~= nil).toBe(true)
			-- Mid-hold of the half beat, on the part's own clock (cycle = t / period + phase).
			local period = Kit.periodOf(c)
			local t = ((half :: Kit.Beat).at + Kit.SLAM_OUT + Kit.SLAM_HOLD / 2 - (m.phase or 0) * period) % period
			local room = headroom(section, c, t)
			expect(room < Kit.HEAD).toBe(true) -- it hits a head ...
			expect(room > 0.5).toBe(true) -- ... but visibly stops short of the floor
		end
	end)

	it("Head-On Wave: each crusher slams a walking step after the one before", function()
		local section = variantNamed("Head-On Wave").build(1)
		local list = hazards(section)
		table.sort(list, function(a, b)
			return a.pos[1] < b.pos[1]
		end)
		for i = 2, #list do
			local a, b = list[i - 1], list[i]
			local period = Kit.periodOf(a)
			local lag = ((a.motion :: Kit.Motion).phase :: number - ((b.motion :: Kit.Motion).phase :: number)) % 1
			expect(lag * period).toBeCloseTo((b.pos[1] - a.pos[1]) / Kit.WALK, 1e-6)
		end
	end)

	it("Don't Dawdle and Hurry Up Hall: the goo floods only after a run that goes on the first good beats", function()
		for _, name in { "Don't Dawdle", "Hurry Up Hall" } do
			local section = variantNamed(name).build(1)
			local flood, trigger
			for _, part in section.parts do
				if part.motion and part.motion.kind == "rise" then
					flood = part
				end
				if part.trigger then
					trigger = part
				end
			end
			expect(flood ~= nil and trigger ~= nil).toBe(true)
			local f = flood :: Kit.Part
			expect(f.start).toBe((trigger :: Kit.Part).trigger)
			-- When the goo first reaches the floor top (0) over its stretch.
			local wet = math.huge
			for k = 0, 4000 do
				local _, dy = Kit.offsetAt(f, k / 100)
				if f.pos[2] + f.size[2] / 2 + dy > 0 then
					wet = k / 100
					break
				end
			end
			-- A run that walks the flooded stretch and, at every crusher over it, waits out the part of the beat it is
			-- down (half a period). Don't Dawdle floods only the entry pad: waiting out two slams there is still safe.
			local _, fx1 = Kit.bounds(f)
			local run = fx1 / Kit.WALK
			for _, c in hazards(section) do
				if c ~= f then
					if name == "Don't Dawdle" then
						run = math.max(run, fx1 / Kit.WALK + Kit.periodOf(c))
					elseif c.pos[1] < fx1 then
						run += 0.5 * Kit.periodOf(c)
					end
				end
			end
			expect(wet > run).toBe(true)
			-- And it does come: waiting it out is not a way through.
			expect(wet < 20).toBe(true)
		end
	end)
end)
