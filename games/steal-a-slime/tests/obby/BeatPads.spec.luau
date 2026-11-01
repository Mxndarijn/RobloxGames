--!strict
-- Beat Pads (obby idea 18): every variant through ObbyCheck, plus the beat windows the shared checks don't measure
-- (shrinking pads are not hazards): for every pair of steps where something moves, the longest stretch the gap is
-- jumpable must sit in the tier's band (contract §10), and chained over the whole section you can wait on every pad
-- (while it is still a character wide) until the next jump opens. BEATPADS_PRINT=1 prints every window for tuning.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local BeatPads = require("../../src/shared/ObbySections/BeatPads")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

-- Jump windows a tier earns: at least `lo` seconds a pair, and none longer than `hi` (contract §10).
local BAND = {
	easy = { lo = 1.4, hi = 2.0 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}

local HORIZON = 36 -- seconds: 60 beats, a common multiple of every pad period used
local DT = 0.01

-- Edge-to-edge gap between two axis-aligned steps at time t (nil when one of them is not there).
local function gapAt(a: Kit.Part, b: Kit.Part, t: number): number?
	local adx, _, adz, _, as, aon = Kit.offsetAt(a, t)
	local bdx, _, bdz, _, bs, bon = Kit.offsetAt(b, t)
	if not aon or not bon then
		return nil
	end
	local gx = math.abs((a.pos[1] + adx) - (b.pos[1] + bdx)) - (a.size[1] * as + b.size[1] * bs) / 2
	local gz = math.abs((a.pos[3] + adz) - (b.pos[3] + bdz)) - (a.size[3] * as + b.size[3] * bs) / 2
	gx, gz = math.max(gx, 0), math.max(gz, 0)
	return math.sqrt(gx * gx + gz * gz)
end

-- The longest stretch (s) over the horizon when step b can be jumped to from step a.
local function windowOf(a: Kit.Part, b: Kit.Part): number
	local rise = (b.pos[2] + b.size[2] / 2) - (a.pos[2] + a.size[2] / 2)
	if rise > Kit.RISE_MAX then
		return 0
	end
	local best, runLen = 0, 0
	local n = math.floor(HORIZON / DT)
	for k = 0, n do
		local g = gapAt(a, b, k * DT)
		if g and g <= Kit.GAP_MAX + 1e-9 then
			runLen += DT
			best = math.max(best, runLen)
		else
			runLen = 0
		end
	end
	return best
end

-- Per step after the first: the best window from either of the two steps before it (rows allow both).
local function windows(section: Kit.Section): { { index: number, window: number, timed: boolean } }
	local steps = {}
	for _, p in section.parts do
		if p.step then
			table.insert(steps, p)
		end
	end
	local out = {}
	for i = 2, #steps do
		local best, timed = 0, false
		for j = math.max(1, i - 2), i - 1 do
			local a, b = steps[j], steps[i]
			local w = if a.motion or b.motion then windowOf(a, b) else math.huge
			if w > best then
				best, timed = w, (a.motion ~= nil or b.motion ~= nil)
			end
		end
		table.insert(out, { index = i, window = best, timed = timed })
	end
	return out
end

-- A pad you can stand on at time t: its footprint is still at least a character wide (STAND studs) both ways.
local STAND = 2
local function standable(p: Kit.Part, t: number): boolean
	local _, _, _, _, scale, on = Kit.offsetAt(p, t)
	return on and math.min(p.size[1], p.size[3]) * scale >= STAND - 1e-9
end

--[[
	Chained timing: the times you can land on each step if you started on the entry at any time, waited on every pad
	only while it could still hold you, and jumped (from either of the two steps before) while the gap was at most
	Kit.GAP_MAX. Returns per step the longest run of landing times (s). A pad that is too small to wait on until the
	next jump opens shows here, not in the pairwise windows.
]]
local function chained(section: Kit.Section): { number }
	local steps = {}
	for _, p in section.parts do
		if p.step then
			table.insert(steps, p)
		end
	end
	local n = math.floor(HORIZON * 2 / DT)
	local onAt: { { boolean } } = {}
	local out = {}
	for i, b in steps do
		local land = table.create(n + 1, false)
		if i == 1 then
			for k = 0, n do
				land[k + 1] = true
			end
		else
			for j = math.max(1, i - 2), i - 1 do
				local a = steps[j]
				local rise = (b.pos[2] + b.size[2] / 2) - (a.pos[2] + a.size[2] / 2)
				if rise <= Kit.RISE_MAX then
					for k = 0, n do
						if not land[k + 1] and onAt[j][k + 1] and standable(b, k * DT) then
							local g = gapAt(a, b, k * DT)
							land[k + 1] = g ~= nil and g <= Kit.GAP_MAX + 1e-9
						end
					end
				end
			end
		end
		-- On the pad from a landing until it gets too small to hold you.
		local on = table.create(n + 1, false)
		local holding = false
		for k = 0, n do
			holding = (holding or land[k + 1]) and standable(b, k * DT)
			on[k + 1] = holding
		end
		onAt[i] = on
		-- Longest run of landing times, skipping the first period (start-up).
		local best, runLen = 0, 0
		for k = math.floor(HORIZON / DT), n do
			if land[k + 1] then
				runLen += DT
				best = math.max(best, runLen)
			else
				runLen = 0
			end
		end
		out[i] = best
	end
	return out
end

describe("BeatPads", function()
	it("every variant passes ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(BeatPads) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("keeps the variants in the design file's order", function()
		local names = {}
		for _, v in BeatPads.variants do
			table.insert(names, v.name)
		end
		expect(table.concat(names, ", ")).toBe(
			"Four on the Floor, Ping Pong, Ride the Wave, Drum Rest, Backwave, Off-Beat Hop, Speed Up, Waltz, "
				.. "Hold and Hurry, Beat Stairs, Zigzag Groove, Beat and Flip, Silent Bar, Double Time, Goo Heartbeat, "
				.. "Two Drummers, Rush Climb, Night Groove"
		)
	end)

	it("every beat pad lasts whole beats and peaks on a beat or its 'and'", function()
		local problems = {}
		for _, v in BeatPads.variants do
			for i, p in v.build(1).parts do
				local m = p.motion
				if m and (m.kind == "shrink" or m.kind == "flip") then
					local beats = Kit.periodOf(p) / Kit.beat(1)
					local peak = (m.phase or 0) * beats * 2 -- half-beats into the period
					if
						math.abs(beats - math.floor(beats + 0.5)) > 1e-9
						or math.abs(peak - math.floor(peak + 0.5)) > 1e-6
					then
						table.insert(problems, `{v.name} part {i}: {beats} beats, phase {m.phase}`)
					end
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("has the tiers of the design file and no generator", function()
		local tiers = {}
		for _, v in BeatPads.variants do
			tiers[v.tier] = (tiers[v.tier] or 0) + 1
		end
		expect(tiers.easy).toBe(4)
		expect(tiers.medium).toBe(9)
		expect(tiers.hard).toBe(5)
		expect(BeatPads.generator).toBeNil()
	end)

	it("prints windows (BEATPADS_PRINT)", function()
		if not require("@lune/process").env.BEATPADS_PRINT then
			return
		end
		for _, v in BeatPads.variants do
			local sec = v.build(1)
			local ws = {}
			for _, w in windows(sec) do
				table.insert(ws, if w.timed then string.format("%.2f", w.window) else "-")
			end
			local cs = {}
			for i, c in chained(sec) do
				if i > 1 then
					table.insert(cs, string.format("%.2f", c))
				end
			end
			print(`{v.name} ({v.tier}) len {sec.length} parts {#sec.parts}: {table.concat(ws, " ")}`)
			print(`    chained: {table.concat(cs, " ")}`)
		end
	end)

	it("you can wait on every pad until the next jump opens, for at least the tier's window", function()
		local problems = {}
		for _, v in BeatPads.variants do
			local band = BAND[v.tier]
			for i, w in chained(v.build(1)) do
				if i > 1 and w < band.lo - 1e-6 then
					table.insert(problems, `{v.name} ({v.tier}) step {i}: land {w} s (at least {band.lo})`)
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("every jump between moving pads is open for the tier's window, and no longer", function()
		local problems = {}
		for _, v in BeatPads.variants do
			local band = BAND[v.tier]
			for _, w in windows(v.build(1)) do
				if w.timed then
					local s = math.floor(w.window * 100 + 0.5) / 100
					if w.window < band.lo - 1e-6 or w.window > band.hi + 1e-6 then
						table.insert(problems, `{v.name} ({v.tier}) step {w.index}: open {s} s ({band.lo}..{band.hi})`)
					end
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)
end)
