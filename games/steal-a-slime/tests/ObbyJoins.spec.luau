--!strict
-- Flush joins (contract/obby-sections.md §1): every section's entry floor starts at x = 0 with its top at 0 and its exit
-- floor ends at x = length with its top at `rise`, exactly; no part of a section reaches out over the connectors; and
-- in whole courses every connector, the start pad and the finish pad meet the floors next to them with no step, gap
-- or overlap, and cover them across the lane.
local T = require("./TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local ObbyCheck = require("./ObbyCheck")
local ObbyCourse = require("../src/shared/ObbyCourse")
local ObbySections = require("../src/shared/ObbySections")
local Kit = ObbySections.Kit

type Part = Kit.Part
type Section = Kit.Section

local EXACT = 1e-6 -- studs: tops and ends meet exactly (float noise only)
local REACH = 0.1 -- studs a part's top face may reach past the section's ends (a tilted ghost mark's corner)
local SEEDS = { 1, 2, 3, 7, 42, 777 }
local SLOTS = 120

local function firstStep(parts: { Part }): Part?
	for _, part in parts do
		if part.step then
			return part
		end
	end
	return nil
end

local function lastStep(parts: { Part }): Part?
	for i = #parts, 1, -1 do
		if parts[i].step then
			return parts[i]
		end
	end
	return nil
end

-- What is wrong with a section's ends ("" when nothing).
local function sectionProblems(name: string, s: Section): { string }
	local out = {}
	local first, last = firstStep(s.parts), lastStep(s.parts)
	if not first or not last then
		return { `{name}: no steps` }
	end
	local near, _, x0 = Kit.endTops(first)
	if math.abs(x0) > EXACT or math.abs(near) > EXACT then
		table.insert(out, `{name}: entry floor starts at x {x0}, top {near} (0, 0)`)
	end
	local _, far, _, x1 = Kit.endTops(last)
	if math.abs(x1 - s.length) > EXACT or math.abs(far - s.rise) > EXACT then
		table.insert(out, `{name}: exit floor ends at x {x1}, top {far} ({s.length}, {s.rise})`)
	end
	for i, part in s.parts do
		if part.look ~= "banner" then
			for _, c in Kit.topCorners(part) do
				if c[1] < -REACH or c[1] > s.length + REACH then
					table.insert(out, `{name}: part {i} ({part.look}) reaches x {c[1]}, outside 0..{s.length}`)
					break
				end
			end
		end
	end
	return out
end

local function zRange(part: Part): (number, number)
	local _, _, _, _, lo, hi = Kit.bounds(part)
	return lo, hi
end

-- `a` ends where `b` starts, at the same top, and `cover` (the start pad, a connector or the finish) spans the
-- other one's z range.
local function joinProblem(tag: string, a: Part, b: Part, cover: Part, other: Part): string?
	local _, aTop, _, ax1 = Kit.endTops(a)
	local bTop, _, bx0 = Kit.endTops(b)
	if math.abs(aTop - bTop) > EXACT then
		return `{tag}: step of {bTop - aTop} ({a.id} top {aTop}, {b.id} top {bTop})`
	end
	if math.abs(ax1 - bx0) > EXACT then
		return `{tag}: {if bx0 > ax1 then "gap" else "overlap"} of {math.abs(bx0 - ax1)} along x ({a.id} -> {b.id})`
	end
	local clo, chi = zRange(cover)
	local olo, ohi = zRange(other)
	if olo < clo - EXACT or ohi > chi + EXACT then
		return `{tag}: {cover.id} spans z {clo}..{chi}, {other.id} z {olo}..{ohi}`
	end
	return nil
end

local function courseProblems(slot: number): { string }
	local course = ObbyCourse.build(slot)
	local byId: { [string]: Part } = {}
	local steps: { [number]: { Part } } = {}
	for _, part in course.parts do
		local id = part.id :: string
		byId[id] = part
		local i = tonumber(string.match(id, "^(%d+)%.%d+$"))
		if i then
			steps[i] = steps[i] or {}
			table.insert(steps[i], part)
		end
	end
	local out = {}
	local n = #course.picks
	for i = 1, n do
		local pick = course.picks[i]
		local tag = `slot {slot} section {i} ({pick.id} variant {pick.variant} seed {pick.seed})`
		local first, last = firstStep(steps[i]), lastStep(steps[i])
		assert(first and last, tag)
		local before = if i == 1 then byId.s else byId[`l{i - 1}`]
		local after = if i == n then byId.f else byId[`l{i}`]
		local inProblem = joinProblem(`{tag} entry`, before, first, before, first)
		local outProblem = joinProblem(`{tag} exit`, last, after, after, last)
		if inProblem then
			table.insert(out, inProblem)
		end
		if outProblem then
			table.insert(out, outProblem)
		end
	end
	return out
end

describe("Obby joins", function()
	it(`every variant and generator tier starts and ends flush, seeds {table.concat(SEEDS, ", ")}`, function()
		local problems = {}
		for _, idea in ObbySections.ALL do
			for _, case in ObbyCheck.cases(idea) do
				for _, seed in SEEDS do
					for _, p in sectionProblems(`{case.name} seed {seed}`, case.build(seed)) do
						table.insert(problems, p)
					end
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it(`start pad, connectors and finish meet the sections flush, slots 1..{SLOTS}`, function()
		local problems = {}
		for slot = 1, SLOTS do
			for _, p in courseProblems(slot) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("catches a section whose entry sits half a stud low, starts late, or pokes back over the connector", function()
		local function section(parts: { Part }): Section
			return { length = 20, rise = 0, parts = parts }
		end
		local exit = Kit.slab(16, 0, 0, 8, 8, "jelly")
		expect(#sectionProblems("flush", section({ Kit.slab(4, 0, 0, 8, 8, "jelly"), exit }))).toBe(0)
		expect(#sectionProblems("low", section({ Kit.slab(4, -0.5, 0, 8, 8, "jelly"), exit }))).toBe(1)
		expect(#sectionProblems("late", section({ Kit.slab(5, 0, 0, 8, 8, "jelly"), exit }))).toBe(1)
		local poke = Kit.slab(1, -4, 0, 6, 8, "ice")
		expect(#sectionProblems("poke", section({ Kit.slab(4, 0, 0, 8, 8, "jelly"), poke, exit }))).toBe(1)
	end)
end)
