--!strict
local T = require("./TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Config = require("../src/shared/Config")
local ObbyCourse = require("../src/shared/ObbyCourse")

local OBBY = Config.OBBY

-- A default character (JumpHeight 7.2, WalkSpeed 16) jumps about 8.7 studs across and 7.2 up; these leave room.
local GAP_MAX = 6
local RISE_MAX = 3.5
local SECTION_MAX_LENGTH = 36 -- keeps a whole run near a minute

local function ids(picks: { ObbyCourse.Pick }): string
	local out = {}
	for _, p in picks do
		table.insert(out, `{p.id}#{p.layout}`)
	end
	return table.concat(out, ",")
end

-- Edge-to-edge distance between two parts' footprints, seen from above (at rest).
local function gap(a: ObbyCourse.Part, b: ObbyCourse.Part): number
	local dx = math.max(0, math.abs(a.pos[1] - b.pos[1]) - (a.size[1] + b.size[1]) / 2)
	local dz = math.max(0, math.abs(a.pos[3] - b.pos[3]) - (a.size[3] + b.size[3]) / 2)
	return math.sqrt(dx * dx + dz * dz)
end

local function top(p: ObbyCourse.Part): number
	return p.pos[2] + p.size[2] / 2
end

describe("ObbyCourse rotation", function()
	it("picks one section per tier slot, never the same one twice", function()
		for slot = 4000, 4300 do
			local picks = ObbyCourse.pick(slot)
			expect(#picks).toBe(#OBBY.ORDER)
			local seen = {}
			for i, p in picks do
				expect(p.tier).toBe(OBBY.ORDER[i])
				expect(table.find((OBBY.SECTIONS :: any)[p.tier], p.id) ~= nil).toBe(true)
				expect(seen[p.id]).toBeNil()
				seen[p.id] = true
				expect(p.layout >= 1 and p.layout <= OBBY.LAYOUTS).toBe(true)
			end
		end
	end)

	it("is the same course for the same slot", function()
		expect(ids(ObbyCourse.pick(4321))).toBe(ids(ObbyCourse.pick(4321)))
		expect(ids(ObbyCourse.build(4321).picks)).toBe(ids(ObbyCourse.pick(4321)))
	end)

	it("never repeats a section of the course before inside a chain", function()
		for slot = 4000, 4400 do
			if slot % OBBY.CHAIN_SLOTS ~= 0 then
				local before = {}
				for _, p in ObbyCourse.pick(slot - 1) do
					before[p.id] = true
				end
				for _, p in ObbyCourse.pick(slot) do
					expect(before[p.id]).toBeNil()
				end
			end
		end
	end)

	it("shows every section and every layout over a day", function()
		local seen = {}
		local first = 4032
		for slot = first, first + OBBY.CHAIN_SLOTS - 1 do
			for _, p in ObbyCourse.pick(slot) do
				seen[`{p.id}#{p.layout}`] = true
			end
		end
		for _, pool in OBBY.SECTIONS do
			for _, id in pool do
				for layout = 1, OBBY.LAYOUTS do
					expect(seen[`{id}#{layout}`]).toBe(true)
				end
			end
		end
	end)

	it("maps server time to the 10-minute slot", function()
		expect(ObbyCourse.slot(OBBY.ROTATION_SECONDS * 7 + 1)).toBe(7)
		expect(ObbyCourse.slotStart(7)).toBe(OBBY.ROTATION_SECONDS * 7)
	end)
end)

describe("ObbyCourse sections", function()
	it("every layout of every section is a makeable path", function()
		for id in ObbyCourse.BUILD do
			for layout = 1, OBBY.LAYOUTS do
				local course = ObbyCourse.build(1, { { id = id, tier = "easy", layout = layout } })
				local steps = {}
				for _, part in course.parts do
					if part.step then
						table.insert(steps, part)
					end
				end
				expect(#steps >= 3).toBe(true)
				for i = 2, #steps do
					local label = `{id} layout {layout} step {i}`
					local g = gap(steps[i - 1], steps[i])
					if g > GAP_MAX then
						error(`{label}: gap {g}`)
					end
					local rise = top(steps[i]) - top(steps[i - 1])
					if rise > RISE_MAX then
						error(`{label}: rise {rise}`)
					end
				end
			end
		end
	end)

	it("keeps sections short and every step at or above the lower of its two pads", function()
		for id in ObbyCourse.BUILD do
			for layout = 1, OBBY.LAYOUTS do
				local section = ObbyCourse.section(id, layout)
				expect(section.length <= SECTION_MAX_LENGTH).toBe(true)
				for _, part in section.parts do
					if part.step then
						expect(top(part) >= math.min(0, section.rise) - 0.01).toBe(true)
					end
				end
			end
		end
	end)

	it("lays a checkpoint pad after every section, the last one the finish", function()
		local course = ObbyCourse.build(4100)
		expect(#course.checkpoints).toBe(#OBBY.ORDER)
		local finishes = 0
		for _, part in course.parts do
			if part.look == "finish" then
				finishes += 1
			end
		end
		expect(finishes).toBe(1)
		for i = 2, #course.checkpoints do
			expect(course.checkpoints[i].pos[1] > course.checkpoints[i - 1].pos[1]).toBe(true)
		end
		expect(course.length <= ObbyCourse.START_LENGTH + #OBBY.ORDER * (SECTION_MAX_LENGTH + 12)).toBe(true)
	end)
end)

describe("ObbyCourse checkpoints and frames", function()
	local course = ObbyCourse.build(4100)
	local cp = course.checkpoints[2]

	it("counts standing on a pad, not walking past it", function()
		expect(ObbyCourse.onCheckpoint(cp, { cp.pos[1], cp.pos[2] + 3, cp.pos[3] })).toBe(true)
		expect(ObbyCourse.onCheckpoint(cp, { cp.pos[1] + cp.size[1], cp.pos[2] + 3, cp.pos[3] })).toBe(false)
		expect(ObbyCourse.onCheckpoint(cp, { cp.pos[1], cp.pos[2] + 30, cp.pos[3] })).toBe(false)
		expect(ObbyCourse.onCheckpoint(cp, { cp.pos[1], cp.pos[2] - 5, cp.pos[3] })).toBe(false)
	end)

	it("respawns above the last pad and falls below the lower pad", function()
		expect(ObbyCourse.respawn(course, 0)[1]).toBe(course.start[1])
		local r = ObbyCourse.respawn(course, 2)
		expect(r[1]).toBe(cp.pos[1])
		expect(r[2]).toBe(cp.pos[2] + OBBY.RESPAWN_LIFT)
		expect(ObbyCourse.fallHeight(course, 0)).toBe(-OBBY.FALL_DEPTH)
	end)

	it("toLocal undoes toWorld", function()
		local frame = { origin = { -90, 150, 220 }, yaw = 157.5 }
		local p = { 37, 4, -3 }
		local back = ObbyCourse.toLocal(frame, ObbyCourse.toWorld(frame, p))
		for i = 1, 3 do
			expect(math.abs(back[i] - p[i]) < 1e-6).toBe(true)
		end
		local ahead = ObbyCourse.toWorld(frame, { 10, 0, 0 })
		expect(math.abs(ahead[1] - (-90 + math.sin(math.rad(157.5)) * 10)) < 1e-6).toBe(true)
	end)
end)
