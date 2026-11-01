--!strict
-- Collapsing Bridge (obby idea 24): every variant through ObbyCheck, plus what the shared checks don't time: a
-- stricter runner (0.3 s a turn on top of ObbyCheck.timers' 0.15 s a jump) leaves every collapsing plank on every
-- route within its tier's band of spare seconds (not too easy, not unfair), the off half of every Two Halves row falls
-- ahead of you, and the early holes of Holes Ahead are open before a walker could reach them.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local CollapsingBridge = require("../../src/shared/ObbySections/CollapsingBridge")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

type Part = Kit.Part

local TURN = 0.3
-- Seconds the runner leaves the tightest plank before it drops, per tier: at least the check's 1 s, at most this.
local BAND = { easy = { 1.5, 1.8 }, medium = { 1.15, 1.4 }, hard = { 1.0, 1.15 } }

local function topOf(p: Part): number
	return p.pos[2] + p.size[2] / 2
end

local function gapOf(a: Part, b: Part): number
	local dx = math.max(
		0,
		(b.pos[1] - b.size[1] / 2) - (a.pos[1] + a.size[1] / 2),
		(a.pos[1] - a.size[1] / 2) - (b.pos[1] + b.size[1] / 2)
	)
	local dz = math.max(
		0,
		(b.pos[3] - b.size[3] / 2) - (a.pos[3] + a.size[3] / 2),
		(a.pos[3] - a.size[3] / 2) - (b.pos[3] + b.size[3] / 2)
	)
	return math.sqrt(dx * dx + dz * dz)
end

-- The steps of a route in order (untagged plus that route's).
local function routeSteps(section: Kit.Section, route: string): { Part }
	local out = {}
	for _, p in section.parts do
		if p.step and (p.route == nil or p.route == route) then
			table.insert(out, p)
		end
	end
	return out
end

-- The smallest spare (drop time minus when the runner leaves the plank) over every route and trigger.
local function tightest(section: Kit.Section): number
	local best = math.huge
	local routes = { "main" }
	for _, p in section.parts do
		if p.step and p.route and not table.find(routes, p.route) then
			table.insert(routes, p.route)
		end
	end
	for _, route in routes do
		local steps = routeSteps(section, route)
		for k0, trig in steps do
			local g = trig.trigger
			if g then
				local at = 0
				local dirX: number?, dirZ: number? = nil, nil
				for k = k0, #steps do
					local s = steps[k]
					if k > k0 then
						local p = steps[k - 1]
						local dx, dz = s.pos[1] - p.pos[1], s.pos[3] - p.pos[3]
						local len = math.sqrt(dx * dx + dz * dz)
						local jump = gapOf(p, s) > 0.5 or math.abs(topOf(s) - topOf(p)) > 0.5
						at += len / Kit.WALK + (if jump then Kit.JUMP_LOSS else 0)
						if len > 0 then
							if dirX and dirZ and (dirX * dx + dirZ * dz) / len < 0.87 then
								at += TURN
							end
							dirX, dirZ = dx / len, dz / len
						end
					end
					local m = s.motion
					if m and m.kind == "drop" and s.start == g then
						best = math.min(best, (m.at :: number) - (at + s.size[1] / 2 / Kit.WALK))
					end
				end
			end
		end
	end
	return best
end

describe("CollapsingBridge", function()
	it("every variant passes ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(CollapsingBridge :: any) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("builds all 18 designed variants in the design file's order", function()
		local names = {}
		for _, v in CollapsingBridge.variants do
			table.insert(names, v.name)
		end
		expect(table.concat(names, ",")).toBe(
			"First Crumble,Little Hops,Catch Your Breath,Corner,Big Chunks,Two Halves,Speeding Up,S-Bend,"
				.. "Downhill Drops,Goo Spots,Two Breathers,Long Leaps,Boost Plank,Split Bridge,Sprint,Holes Ahead,"
				.. "Final Dash,Boost or Bust"
		)
	end)

	it("the wave leaves the runner a tier's worth of spare seconds at the tightest plank", function()
		local problems = {}
		for i, v in CollapsingBridge.variants do
			local spare = tightest(v.build(1))
			local band = BAND[v.tier]
			if spare < band[1] or spare > band[2] then
				table.insert(problems, `#{i} {v.name} ({v.tier}): {spare} s spare, want {band[1]}..{band[2]}`)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("every collapsing piece has a trigger and the exit ledge never drops", function()
		local problems = {}
		for i, v in CollapsingBridge.variants do
			local section = v.build(1)
			local last
			for _, p in section.parts do
				if p.step then
					last = p
				end
			end
			if last.motion then
				table.insert(problems, `#{i} {v.name}: the exit ledge moves`)
			end
			local drops = 0
			for _, p in section.parts do
				if p.motion and p.motion.kind == "drop" then
					drops += 1
				end
			end
			if drops < 4 then
				table.insert(problems, `#{i} {v.name}: only {drops} collapsing pieces`)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("Two Halves: the off half of each row falls before you get there, and the safe side switches", function()
		local section = CollapsingBridge.variants[6].build(1)
		local trig, safe, off = nil, {}, {}
		for _, p in section.parts do
			if p.trigger then
				trig = p
			elseif p.motion and p.motion.kind == "drop" then
				table.insert(if p.step then safe else off, p)
			end
		end
		expect(#off).toBe(#safe)
		local x0 = trig.pos[1] - trig.size[1] / 2
		local switches = 0
		for i, o in off do
			local s = safe[i]
			expect(s.pos[1]).toBe(o.pos[1])
			expect(s.pos[3] * o.pos[3] < 0).toBe(true)
			local at = (o.motion :: any).at
			local reach = (o.pos[1] - o.size[1] / 2 - x0) / Kit.WALK
			expect(at < reach or at <= 0.9 + 1e-6).toBe(true) -- gone (or cracking from the start) as you arrive
			expect((s.motion :: any).at - at >= 1).toBe(true)
			if i > 1 and safe[i - 1].pos[3] * s.pos[3] < 0 then
				switches += 1
			end
		end
		expect(switches >= 3).toBe(true)
	end)

	it("Holes Ahead: every early hole is open before a walker could get there", function()
		local section = CollapsingBridge.variants[16].build(1)
		local first
		for _, p in section.parts do
			if p.trigger then
				first = p
				break
			end
		end
		local x0 = first.pos[1] - first.size[1] / 2
		local early = 0
		for _, p in section.parts do
			if not p.step and p.motion and p.motion.kind == "drop" then
				early += 1
				local reach = (p.pos[1] - p.size[1] / 2 - x0) / Kit.WALK
				expect((p.motion :: any).at < reach).toBe(true)
				expect((p.motion :: any).at > 0.8).toBe(true) -- its 0.8 s of cracks play after the trigger
			end
		end
		expect(early).toBe(4)
	end)
end)
