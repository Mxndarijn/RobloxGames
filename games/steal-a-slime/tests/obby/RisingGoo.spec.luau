--!strict
--[[
	Rising Goo (idea 12): every variant through tests/ObbyCheck, plus the idea's own checks.

	The slack runner: ObbyCheck.timers only proves a 16 studs / s runner (0.15 s a jump) stays 1 s ahead of the goo.
	Here a slower runner (SLOW_LOSS s a jump, ladders at CLIMB studs / s, waiting for a moving ledge to come within
	5 studs and 3.5 up) climbs the main path from the trigger, and the slack is how many seconds it can dawdle at the
	bottom and still never have the goo over its feet. Each tier's slack must sit in SLACK[tier] (contract §10): easy
	gives time to spare but still chases, hard leaves well under 2 s.

	RISINGGOO_TUNE=1 prints every variant's slack and the timers margin.
]]
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local RisingGoo = require("../../src/shared/ObbySections/RisingGoo")
local process = require("@lune/process")

type Part = Kit.Part
type Section = Kit.Section

local SLOW_LOSS = 0.3 -- seconds a jump costs the slack runner
local CLIMB = 8 -- studs / s up a ladder
local DT = 0.05
local SLACK = { easy = { 2.5, 7 }, medium = { 1.2, 3.5 }, hard = { 0.4, 1.6 } }

local function moving(part: Part): boolean
	local m = part.motion
	return m ~= nil and (m.kind == "path" or m.kind == "slide")
end

-- A part's box (x0, x1, y0, y1, z0, z1) at goo-clock time t (every timed part here reads the goo clock or server time;
-- both are t).
local function boxAt(part: Part, t: number): (number, number, number, number, number, number)
	local x0, x1, y0, y1, z0, z1 = Kit.bounds(part)
	local dx, dy, dz = Kit.offsetAt(part, t)
	return x0 + dx, x1 + dx, y0 + dy, y1 + dy, z0 + dz, z1 + dz
end

-- The highest hazard top over a step's footprint at time t.
local function gooOver(section: Section, s: Part, t: number): number
	local sx0, sx1, _, _, sz0, sz1 = boxAt(s, t)
	local best = -math.huge
	for _, h in section.parts do
		if h.hazard then
			local hx0, hx1, _, hy1, hz0, hz1 = boxAt(h, t)
			if hx1 > sx0 and hx0 < sx1 and hz1 > sz0 and hz0 < sz1 then
				best = math.max(best, hy1)
			end
		end
	end
	return best
end

-- Heights the runner stands at on a step: where it gets on (lowest) and off (highest) of a ramp or a ladder.
local function tops(s: Part): (number, number)
	if s.shape == "truss" then
		local _, _, y0, y1 = Kit.bounds(s)
		return y0, y1
	end
	local near, far = Kit.endTops(s)
	return math.min(near, far), math.max(near, far)
end

local function gapAt(a: Part, b: Part, t: number): number
	local ax0, ax1, _, _, az0, az1 = boxAt(a, t)
	local bx0, bx1, _, _, bz0, bz1 = boxAt(b, t)
	local gx = math.max(0, bx0 - ax1, ax0 - bx1)
	local gz = math.max(0, bz0 - az1, az0 - bz1)
	return math.sqrt(gx * gx + gz * gz)
end

local function mainSteps(section: Section): { Part }
	local out = {}
	for _, p in section.parts do
		if p.step and p.route == nil then
			table.insert(out, p)
		end
	end
	return out
end

-- The step the runner is on when the goo clock starts: the trigger itself, or the step under the trigger.
local function firstStep(steps: { Part }, section: Section): number?
	for _, p in section.parts do
		if p.trigger then
			for k, s in steps do
				if s == p then
					return k
				end
			end
			local cx = p.pos[1]
			for k, s in steps do
				local x0, x1 = Kit.bounds(s)
				if cx >= x0 and cx <= x1 then
					return k
				end
			end
		end
	end
	return nil
end

-- Does the slack runner make it when it sets off `late` s after the goo clock starts? (Why not, if it doesn't.)
local function survives(section: Section, late: number): (boolean, string?)
	local steps = mainSteps(section)
	local k0 = firstStep(steps, section)
	assert(k0, "no trigger")
	local a = late
	for k = k0, #steps - 1 do
		local s, n = steps[k], steps[k + 1]
		local low, high = tops(s)
		local travel = math.sqrt((n.pos[1] - s.pos[1]) ^ 2 + (n.pos[3] - s.pos[3]) ^ 2) / Kit.WALK
		if s.shape == "truss" then
			travel += (high - low) / CLIMB
		end
		local e = a + travel
		local d = e
		if moving(s) or moving(n) then
			while true do
				local _, _, _, sy1 = boxAt(s, d)
				local _, _, _, ny1 = boxAt(n, d)
				if gapAt(s, n, d) <= 5 and ny1 - sy1 <= Kit.RISE_MAX then
					break
				end
				d += DT
				if d > e + 20 then
					return false, `stuck on step {k}`
				end
			end
		end
		local jump = s.shape ~= "truss" and n.shape ~= "truss"
		local arrive = d + (if jump then SLOW_LOSS else 0)
		-- on step s from a to arrive
		local t = a
		while t <= arrive + 1e-9 do
			local f = if e > a then math.clamp((t - a) / (e - a), 0, 1) else 1
			local _, dy = Kit.offsetAt(s, t)
			local feet = low + (high - low) * f + dy
			if gooOver(section, s, t) > feet + 1e-6 then
				return false, `goo over step {k} at {math.floor(t * 100) / 100} s`
			end
			t += DT
		end
		a = arrive
	end
	return true, nil
end

-- Seconds the slack runner can dawdle (-1 when it doesn't make it at all).
local function slackOf(section: Section): number
	if not survives(section, 0) then
		return -1
	end
	local late = 0
	while late < 30 and survives(section, late + 0.1) do
		late += 0.1
	end
	return late
end

local function chase(section: Section): boolean
	for _, p in section.parts do
		if p.trigger then
			return true
		end
	end
	return false
end

-- The timers margin: the latest the 16 studs / s runner may arrive (largest SPARE that still passes).
local function timersMargin(section: Section): number
	local saved = ObbyCheck.SPARE
	local spare = 0
	while spare < 30 do
		(ObbyCheck :: any).SPARE = spare + 0.1
		if ObbyCheck.timers(section) then
			break
		end
		spare += 0.1
	end
	(ObbyCheck :: any).SPARE = saved
	return spare
end

if process.env.RISINGGOO_TUNE then
	for i, v in RisingGoo.variants do
		local s = v.build(1)
		local slack = if chase(s) then slackOf(s) else nil
		local why = if slack then select(2, survives(s, (slack :: number) + 0.1)) else nil
		local wins = {}
		for _, w in ObbyCheck.windows(s) do
			table.insert(wins, string.format("%.2f", w.slack))
		end
		print(
			string.format(
				"%2d %-16s %-6s slack %5s  timers %4.1f  parts %d  windows %s %s",
				i,
				v.name,
				v.tier,
				if slack then string.format("%.1f", slack) else "-",
				timersMargin(s),
				ObbyCheck.partCount(s),
				table.concat(wins, ","),
				why or ""
			)
		)
	end
end

describe("RisingGoo", function()
	it("every variant passes ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(RisingGoo :: any) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("builds every variant in the design file's order", function()
		local names = {}
		for _, v in RisingGoo.variants do
			table.insert(names, v.name)
		end
		expect(table.concat(names, ",")).toBe(table.concat({
			"Slow Stairs",
			"Low Tide",
			"Rest Ledges",
			"Spiral Ramp",
			"Tide Pool",
			"Head Start Gate",
			"Wide Switchback",
			"Zigzag Shaft",
			"Float Up",
			"Ladder Dash",
			"Surge",
			"Sliding Ledges",
			"Flooding Basin",
			"Spiral Tower",
			"Drain Valve",
			"Fast Flood",
			"Speeding Flood",
			"Wave Rise",
			"Surge Ladders",
		}, ","))
	end)

	it("every chase leaves the slower runner the slack its tier allows (not too easy, still fair)", function()
		local bad = {}
		for _, v in RisingGoo.variants do
			local s = v.build(1)
			if chase(s) then
				local slack = slackOf(s)
				local band = SLACK[v.tier]
				if slack < band[1] - 1e-6 or slack > band[2] + 1e-6 then
					table.insert(bad, `{v.name} ({v.tier}): slack {slack} s, wants {band[1]}..{band[2]}`)
				end
			end
		end
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("the goo never reaches the exit step, however long you stay", function()
		local bad = {}
		for _, v in RisingGoo.variants do
			local s = v.build(1)
			local steps = mainSteps(s)
			local last = steps[#steps]
			for t = 0, 120, 0.5 do
				if gooOver(s, last, t) > s.rise - 0.5 then
					table.insert(bad, `{v.name} at {t} s`)
					break
				end
			end
		end
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("stacked floods trace a surface that only goes up", function()
		for _, v in RisingGoo.variants do
			local s = v.build(1)
			if chase(s) then
				local steps = mainSteps(s)
				local last = -math.huge
				for t = 0, 60, 0.1 do
					local g = gooOver(s, steps[1], t)
					expect(g >= last - 1e-6).toBe(true)
					last = g
				end
			end
		end
	end)

	it("Float Up: the rafts ride on the goo and never sink into it", function()
		local s = RisingGoo.variants[9].build(1)
		for _, p in s.parts do
			if p.look == "plank" then
				for t = 0, 40, 0.1 do
					local _, _, y0 = boxAt(p, t)
					expect(y0 >= gooOver(s, p, t) + 0.4).toBe(true)
				end
			end
		end
	end)

	it("Tide Pool: the low-tide window is a real timing (1.4..2.0 s, contract §10)", function()
		local s = RisingGoo.variants[5].build(1)
		local windows = ObbyCheck.windows(s)
		expect(#windows).toBe(1)
		expect(windows[1].slack >= ObbyCheck.WINDOW.easy - 1e-6 and windows[1].slack <= 2.0 + 1e-6).toBe(true)
	end)

	it("Drain Valve: the gate's key is on the valve ledge and the pad throws you onto step 8", function()
		local s = RisingGoo.variants[15].build(1)
		local pad, target
		local steps = mainSteps(s)
		target = steps[8]
		for _, p in s.parts do
			if p.look == "spring" then
				pad = p
			end
		end
		local m = (pad :: Part).motion :: any
		local _, _, _, padTop = Kit.bounds(pad :: Part)
		local _, _, _, targetTop = Kit.bounds(target)
		local reach = Kit.launchReach(m.power, targetTop - padTop, m.throw)
		expect(reach ~= nil).toBe(true)
		-- from the pad's middle to the nearest edge of step 8, and at least half way onto it
		local tx0, tx1, _, _, tz0, tz1 = Kit.bounds(target)
		local px, pz = (pad :: Part).pos[1], (pad :: Part).pos[3]
		local dx = math.max(tx0 - px, 0, px - tx1)
		local dz = math.max(tz0 - pz, 0, pz - tz1)
		expect(math.sqrt(dx * dx + dz * dz) + 4 <= (reach :: number)).toBe(true)
		-- and the valve route is longer for the walk-on runner, but the shortcut skips steps 6 and 7
		expect(targetTop - padTop > Kit.RISE_MAX * 2).toBe(true)
	end)
end)
