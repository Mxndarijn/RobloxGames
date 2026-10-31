--!strict
-- The obby section kit (contract/obby-sections.md): the registry, every variant of every idea through tests/ObbyCheck
-- for seeds 1..20, the checks' own models, and the rotation that picks ideas, variants and seeds.
local T = require("./TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Config = require("../src/shared/Config")
local ObbyCheck = require("./ObbyCheck")
local ObbyCourse = require("../src/shared/ObbyCourse")
local ObbySections = require("../src/shared/ObbySections")
local Kit = ObbySections.Kit

local OBBY = Config.OBBY
local TIERS = { easy = true, medium = true, hard = true }

-- How many ideas have something of `tier`.
local function ideasWith(tier: string): number
	local n = 0
	for _, idea in ObbySections.ALL do
		local has = idea.generator ~= nil and table.find(idea.generator.tiers, tier) ~= nil
		for _, v in idea.variants do
			has = has or v.tier == tier
		end
		if has then
			n += 1
		end
	end
	return n
end

local function slotsOf(tier: string): number
	local n = 0
	for _, t in OBBY.ORDER do
		if t == tier then
			n += 1
		end
	end
	return n
end

describe("ObbySections registry", function()
	it("lists the ideas in idea order with their own ids, names and tiers", function()
		expect(#ObbySections.ALL > 0).toBe(true)
		local numbers = {}
		for i, idea in ObbySections.ALL do
			expect(ObbySections.byId[idea.id]).toBe(idea)
			expect(table.find(ObbySections.IDS, idea.id) ~= nil).toBe(true)
			expect(type(idea.name)).toBe("string")
			expect(numbers[idea.idea]).toBeNil()
			numbers[idea.idea] = true
			if i > 1 then
				expect(idea.idea > ObbySections.ALL[i - 1].idea).toBe(true)
			end
			for _, v in idea.variants do
				expect(TIERS[v.tier]).toBe(true)
				expect(type(v.name)).toBe("string")
			end
			for _, tier in (idea.generator and idea.generator.tiers) or {} do
				expect(TIERS[tier]).toBe(true)
			end
		end
	end)
end)

describe("ObbySections variants pass ObbyCheck", function()
	for _, idea in ObbySections.ALL do
		it(`{idea.id}: every variant, seeds 1..{ObbyCheck.SEEDS}`, function()
			local problems = {}
			for _, case in ObbyCheck.cases(idea) do
				for _, p in ObbyCheck.run(case) do
					table.insert(problems, p)
				end
			end
			expect(table.concat(problems, "\n")).toBe("")
		end)
	end
end)

-- Small hand-made sections that prove each check catches what it should.
describe("ObbyCheck models", function()
	local function part(size: Kit.Vec, pos: Kit.Vec, extra: { [string]: any }?): Kit.Part
		local p: { [string]: any } = { size = size, pos = pos, look = "goo", step = true }
		for k, v in extra or {} do
			p[k] = v
		end
		return p :: any
	end
	local function section(parts: { Kit.Part }, length: number, rise: number?): Kit.Section
		return { length = length, rise = rise or 0, parts = parts }
	end
	local function floor(x0: number, x1: number, extra: { [string]: any }?): Kit.Part
		return part({ x1 - x0, 1, Kit.WIDTH }, { (x0 + x1) / 2, -0.5, 0 }, extra)
	end

	it("a walker holding forward crosses a plain bridge, a 3-stud hole and a slow belt", function()
		expect(ObbyCheck.walkStop(section({ floor(0, 40) }, 40), 0, 0)).toBeNil()
		expect(ObbyCheck.walkStop(section({ floor(0, 18), floor(21, 40) }, 40), 0, 0)).toBeNil()
		expect(ObbyCheck.walkStop(section({ floor(0, 40, { conveyor = { 0, 0, 3 } }) }, 40), 0, 0)).toBeNil()
		expect(ObbyCheck.straightWalk(section({ floor(0, 40) }, 40)) ~= nil).toBe(true)
	end)

	it("a 4-stud hole, a wall, a hazard or a fast side belt stops the walker", function()
		expect(ObbyCheck.walkStop(section({ floor(0, 18), floor(22, 40) }, 40), 0, 0) ~= nil).toBe(true)
		local wall = part({ 1, 9, Kit.WIDTH }, { 20, 4.5, 0 }, { step = false })
		expect(ObbyCheck.walkStop(section({ floor(0, 40), wall }, 40), 0, 0) ~= nil).toBe(true)
		local goo = Kit.hazard({ 4, 4, Kit.WIDTH }, { 20, 2, 0 })
		expect(ObbyCheck.walkStop(section({ floor(0, 40), goo }, 40), 0, 0) ~= nil).toBe(true)
		local belt = floor(0, 40, { conveyor = { 0, 0, 12 } })
		expect(ObbyCheck.walkStop(section({ belt }, 40), 0, 0) ~= nil).toBe(true)
	end)

	it("a launch pad that throws the walker over a hole counts as walking across", function()
		local pad = part(
			{ 8, 1, Kit.WIDTH },
			{ 14, -0.5, 0 },
			{ look = "spring", motion = { kind = "bounce", power = 75 } }
		)
		local s = section({ floor(0, 10), pad, floor(21, 40) }, 40)
		expect(ObbyCheck.walkStop(s, 0, 0)).toBeNil()
	end)

	it("makeable: a 7-stud gap or a 4-stud rise fails, a launch pad reaches", function()
		expect(ObbyCheck.makeable(section({ floor(0, 10), floor(16, 30) }, 30))).toBeNil()
		expect(ObbyCheck.makeable(section({ floor(0, 10), floor(17, 30) }, 30)) ~= nil).toBe(true)
		local high = part({ 14, 1, Kit.WIDTH }, { 23, 3.5, 0 })
		expect(ObbyCheck.makeable(section({ floor(0, 10), high }, 30)) ~= nil).toBe(true)
		local pad = part(
			{ 8, 1, Kit.WIDTH },
			{ 4, -0.5, 0 },
			{ look = "spring", motion = { kind = "bounce", power = 62 } }
		)
		expect(ObbyCheck.makeable(section({ pad, part({ 14, 1, Kit.WIDTH }, { 21, 5.5, 0 }) }, 30))).toBeNil()
		expect(ObbyCheck.makeable(section({ pad, part({ 14, 1, Kit.WIDTH }, { 23, 5.5, 0 }) }, 30)) ~= nil).toBe(true)
	end)

	it("makeable: a moving beam counts at its closest point of the period", function()
		local beam = part(
			{ 6, 1, 8 },
			{ 18, -0.5, 0 },
			{ motion = { kind = "slide", axis = "x", amp = 4, period = 4 } }
		)
		expect(ObbyCheck.makeable(section({ floor(0, 10), beam, floor(28, 40) }, 40))).toBeNil()
		local still = part({ 6, 1, 8 }, { 18, -0.5, 0 })
		expect(ObbyCheck.makeable(section({ floor(0, 10), still, floor(28, 40) }, 40)) ~= nil).toBe(true)
	end)

	it("makeable: a branch may leave the main path and join it again later", function()
		local s = section({
			floor(0, 10),
			part({ 8, 1, 10 }, { 14, -0.5, -7 }),
			part({ 8, 1, 10 }, { 26, -0.5, -7 }),
			part({ 8, 1, 10 }, { 14, -0.5, 7 }, { route = "fast" }),
			floor(32, 40),
		}, 40)
		expect(ObbyCheck.makeable(s)).toBeNil()
		expect(#ObbyCheck.routes(s)).toBe(2)
	end)

	it("widths: a 6-wide floor fails, a 3-wide beam passes, a 2-wide one fails", function()
		expect(ObbyCheck.widths(section({ floor(0, 10), part({ 10, 1, 6 }, { 15, -0.5, 0 }) }, 20)) ~= nil).toBe(true)
		local beam = part({ 10, 1, 3 }, { 15, -0.5, 0 }, { look = "beam" })
		expect(ObbyCheck.widths(section({ floor(0, 10), beam }, 20))).toBeNil()
		local thin = part({ 10, 1, 2 }, { 15, -0.5, 0 }, { look = "beam" })
		expect(ObbyCheck.widths(section({ floor(0, 10), thin }, 20)) ~= nil).toBe(true)
	end)

	it("fairness: a crusher gets the tier's window, a too-fast one fails", function()
		local function slammer(period: number): Kit.Section
			local crusher = Kit.hazard({ 8, 4, Kit.WIDTH }, { 20, 13, 0 }, {
				motion = { kind = "punch", axis = "y", amp = -11, period = period },
			})
			return section({ floor(0, 40), crusher }, 40)
		end
		expect(ObbyCheck.fairness(slammer(4), "easy")).toBeNil()
		expect(ObbyCheck.fairness(slammer(2.4), "easy") ~= nil).toBe(true)
		expect(ObbyCheck.fairness(slammer(2.4), "hard") ~= nil).toBe(true)
		expect(ObbyCheck.fairness(slammer(2.8), "hard")).toBeNil()
		local always = Kit.hazard({ 8, 4, Kit.WIDTH }, { 20, 2, 0 })
		expect(ObbyCheck.fairness(section({ floor(0, 40), always }, 40), "hard") ~= nil).toBe(true)
		local half = Kit.hazard({ 8, 4, 12 }, { 20, 2, 6 })
		expect(ObbyCheck.fairness(section({ floor(0, 40), half }, 40), "hard")).toBeNil()
	end)

	it("timers: a collapse must leave the runner a second", function()
		local function bridge(at: number): Kit.Section
			return section({
				floor(0, 10, { trigger = "go" }),
				floor(10, 30, { start = "go", motion = { kind = "drop", at = at } }),
				floor(30, 40),
			}, 40)
		end
		-- the runner reaches the middle piece's far edge about 1.6 s after the trigger
		expect(ObbyCheck.timers(bridge(4))).toBeNil()
		expect(ObbyCheck.timers(bridge(2)) ~= nil).toBe(true)
	end)

	it("fields: unknown motions and fields, a start without a trigger and a gate without keys fail", function()
		local base = floor(0, 40)
		expect(ObbyCheck.fields(section({ base }, 40))).toBeNil()
		expect(ObbyCheck.fields(section({ floor(0, 40, { motion = { kind = "warp", period = 1 } }) }, 40)) ~= nil).toBe(
			true
		)
		expect(ObbyCheck.fields(section({ floor(0, 40, { wobble = true }) }, 40)) ~= nil).toBe(true)
		expect(
			ObbyCheck.fields(section({ floor(0, 40, { start = "g", motion = { kind = "drop", at = 1 } }) }, 40)) ~= nil
		).toBe(true)
		local gate = part(
			{ 1, 9, 8 },
			{ 20, 4.5, 0 },
			{ step = false, look = "gate", gate = { group = "k", need = 2 } }
		)
		local key = part({ 1, 1, 1 }, { 10, 2, 0 }, { step = false, ghost = true, look = "key", key = "k" })
		expect(ObbyCheck.fields(section({ base, gate, key }, 40)) ~= nil).toBe(true)
		local key2 = part({ 1, 1, 1 }, { 12, 2, 4 }, { step = false, ghost = true, look = "key", key = "k" })
		expect(ObbyCheck.fields(section({ base, gate, key, key2 }, 40))).toBeNil()
		expect(
			ObbyCheck.fields(
				section({ floor(0, 40, { motion = { kind = "punch", axis = "y", amp = 2, period = 2 } }) }, 40)
			) ~= nil
		).toBe(true)
	end)

	it("challenge: a section that is just walking fails", function()
		expect(ObbyCheck.challenge(section({ floor(0, 40) }, 40)) ~= nil).toBe(true)
		expect(ObbyCheck.challenge(section({ floor(0, 40), Kit.hazard({ 2, 2, 2 }, { 20, 1, 0 }) }, 40))).toBeNil()
	end)

	it("budget counts marker decor and gate locks, and keeps parts in the lane", function()
		local s = section({
			floor(0, 40, { marker = "chevrons" }),
			part({ 1, 9, 8 }, { 20, 4.5, 0 }, { gate = { group = "k", need = 3 } }),
		}, 40)
		expect(ObbyCheck.partCount(s)).toBe(2 + 4 + 3)
		local wide = section({
			floor(0, 40),
			part(
				{ 4, 1, 8 },
				{ 20, 3, 6 },
				{ step = false, motion = { kind = "slide", axis = "z", amp = 4, period = 3 } }
			),
		}, 40)
		expect(ObbyCheck.budget(wide) ~= nil).toBe(true)
		expect(ObbyCheck.budget(section({ floor(0, 20) }, 20)) ~= nil).toBe(true)
	end)

	it("Kit.section checks a variant's ends", function()
		expect(pcall(Kit.section, 40, 0, { floor(0, 40) })).toBe(true)
		expect(pcall(Kit.section, 40, 0, { floor(6, 40) })).toBe(false)
		expect(pcall(Kit.section, 44, 0, { floor(0, 40) })).toBe(false)
		expect(pcall(Kit.section, 40, 2, { floor(0, 40) })).toBe(false)
		local ramp = Kit.ramp(0, 0, 40, 4, 0, 10, "goo")
		expect(pcall(Kit.section, 40, 4, { ramp })).toBe(true)
	end)

	it("Kit motion clocks: a path holds, moves at constant speed and ping-pongs; a sweep reaches both ends", function()
		local m: Kit.Motion = { kind = "path", points = { { 0, 0, 0 }, { 10, 0, 0 } }, period = 6, hold = 1 }
		expect(Kit.pathAt(m, 0.5, 6)[1]).toBe(0)
		expect(Kit.pathAt(m, 2.5, 6)[1]).toBe(7.5)
		expect(Kit.pathAt(m, 3.5, 6)[1]).toBe(10)
		expect(Kit.pathAt(m, 5, 6)[1]).toBe(5)
		local sweep: Kit.Motion = { kind = "sweep", amp = 30, period = 4, hold = 0.5 }
		local lo, hi = math.huge, -math.huge
		for k = 0, 99 do
			local a = Kit.sweepAt(sweep, k / 100 * 4, 4)
			lo, hi = math.min(lo, a), math.max(hi, a)
		end
		expect(lo).toBe(-30)
		expect(hi).toBe(30)
		expect(Kit.beat(4)).toBe(2.4)
	end)
end)

describe("ObbyCourse rotation with the section registry", function()
	local function ids(picks: { ObbyCourse.Pick }): string
		local out = {}
		for _, p in picks do
			table.insert(out, `{p.id}#{p.variant}@{p.seed}`)
		end
		return table.concat(out, ",")
	end

	it("fills every tier slot with a variant of that tier (while the registry has one)", function()
		for slot = 4000, 4300 do
			local picks = ObbyCourse.pick(slot)
			expect(#picks).toBe(#OBBY.ORDER)
			for i, p in picks do
				local idea = ObbySections.byId[p.id]
				expect(idea ~= nil).toBe(true)
				expect(p.seed >= 1 and p.seed <= ObbyCourse.SEED_MAX).toBe(true)
				if p.variant == 0 then
					expect(table.find((idea.generator :: Kit.Generator).tiers, p.tier) ~= nil).toBe(true)
				else
					expect(idea.variants[p.variant].tier).toBe(p.tier)
				end
				if ideasWith(OBBY.ORDER[i]) > 0 then
					expect(p.tier).toBe(OBBY.ORDER[i])
				end
			end
		end
	end)

	it("builds a whole course even while some tiers have no idea yet", function()
		local course = ObbyCourse.build(4000)
		expect(#course.spans).toBe(#OBBY.ORDER)
	end)

	it("never uses an idea twice in a course, nor one of the course before inside a chain", function()
		local enough = #ObbySections.ALL >= #OBBY.ORDER
		for tier in TIERS do
			-- room for a fresh idea in every slot: not in this course, not in the one before
			enough = enough and ideasWith(tier) >= slotsOf(tier) + #OBBY.ORDER
		end
		for slot = 4000, 4400 do
			local picks = ObbyCourse.pick(slot)
			if #ObbySections.ALL >= #OBBY.ORDER then
				local seen = {}
				for _, p in picks do
					if ideasWith(p.tier) >= #OBBY.ORDER then
						expect(seen[p.id]).toBeNil()
					end
					seen[p.id] = true
				end
			end
			if enough and slot % OBBY.CHAIN_SLOTS ~= 0 then
				local before = {}
				for _, p in ObbyCourse.pick(slot - 1) do
					before[p.id] = true
				end
				for _, p in picks do
					expect(before[p.id]).toBeNil()
				end
			end
		end
	end)

	it("is the same course for the same slot", function()
		expect(ids(ObbyCourse.pick(4321))).toBe(ids(ObbyCourse.pick(4321)))
		expect(ids(ObbyCourse.build(4321).picks)).toBe(ids(ObbyCourse.pick(4321)))
		expect(ids(ObbyCourse.pick(4321)) ~= ids(ObbyCourse.pick(4322))).toBe(true)
	end)

	it("shows every variant (and every generator tier) within a week of rotations", function()
		local seen = {}
		local first = 4032
		local slot = first
		while slot < first + 7 * OBBY.CHAIN_SLOTS do
			for _, p in ObbyCourse.pick(slot) do
				seen[`{p.id}#{p.variant}#{p.tier}`] = true
			end
			slot += 1
		end
		local missing = {}
		for _, idea in ObbySections.ALL do
			for i, v in idea.variants do
				if ideasWith(v.tier) > 0 and not seen[`{idea.id}#{i}#{v.tier}`] then
					table.insert(missing, `{idea.id} #{i} {v.name}`)
				end
			end
			for _, tier in (idea.generator and idea.generator.tiers) or {} do
				if not seen[`{idea.id}#0#{tier}`] then
					table.insert(missing, `{idea.id} generator {tier}`)
				end
			end
		end
		expect(table.concat(missing, ", ")).toBe("")
	end)
end)
