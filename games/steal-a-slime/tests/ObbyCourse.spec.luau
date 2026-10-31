--!strict
-- The course around the sections: layout, ids, connectors, floors, falls, the finish and frames. Rotation and the
-- per-variant checks are in ObbySections.spec (with tests/ObbyCheck).
local T = require("./TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Config = require("../src/shared/Config")
local ObbyCourse = require("../src/shared/ObbyCourse")
local ObbySections = require("../src/shared/ObbySections")
local Kit = ObbySections.Kit

local OBBY = Config.OBBY

local function top(p: ObbyCourse.Part): number
	return p.pos[2] + p.size[2] / 2
end

-- Edge-to-edge distance between two parts' footprints, seen from above (at rest, unrotated).
local function gap(a: ObbyCourse.Part, b: ObbyCourse.Part): number
	local dx = math.max(0, math.abs(a.pos[1] - b.pos[1]) - (a.size[1] + b.size[1]) / 2)
	local dz = math.max(0, math.abs(a.pos[3] - b.pos[3]) - (a.size[3] + b.size[3]) / 2)
	return math.sqrt(dx * dx + dz * dz)
end

describe("ObbyCourse layout", function()
	it(
		"joins the sections with jelly blocks in line with the path, no checkpoint pads, and ends on the finish",
		function()
			local course = ObbyCourse.build(4100)
			expect(#course.spans).toBe(#OBBY.ORDER)
			local finishes, links = 0, 0
			for _, part in course.parts do
				if part.look == "finish" then
					finishes += 1
					expect(part.size[3]).toBe(ObbyCourse.WIDTH)
				elseif part.link then
					links += 1
					expect(part.look).toBe("jelly")
					expect(part.size[1]).toBe(ObbyCourse.LINK_LENGTH)
					expect(part.size[3] >= ObbyCourse.LINK_MIN_WIDTH).toBe(true)
					expect(part.size[3] <= ObbyCourse.WIDTH).toBe(true)
				end
				-- no checkpoint pads: the course itself adds only start, home, connectors and finish (section
				-- parts, ids "<section>.<index>", may use the light "pad" look as a material)
				if part.id and not string.find(part.id, ".", 1, true) then
					expect(part.look == "pad").toBe(false)
				end
			end
			expect(finishes).toBe(1)
			expect(links).toBe(#OBBY.ORDER - 1)
			expect(course.spans[1].from).toBe(ObbyCourse.START_LENGTH)
			for i = 2, #course.spans do
				expect(course.spans[i].from).toBe(course.spans[i - 1].to)
			end
			expect(course.finish.pos[1] - course.finish.size[1] / 2).toBe(course.spans[#course.spans].to)
		end
	)

	it("the lane is 24 studs wide", function()
		expect(ObbyCourse.WIDTH).toBe(24)
		expect(Kit.WIDTH).toBe(24)
	end)

	it("gives every part a unique id and turns melt `next` indices into ids", function()
		for slot = 4100, 4120 do
			local course = ObbyCourse.build(slot)
			local seen = {}
			for _, part in course.parts do
				local id = part.id :: string
				expect(type(id)).toBe("string")
				expect(seen[id]).toBeNil()
				seen[id] = true
			end
			expect(seen.s).toBe(true)
			expect(seen.h).toBe(true)
			expect(seen.f).toBe(true)
			expect(seen["l1"]).toBe(true)
			expect(seen["1.1"]).toBe(true)
			for _, part in course.parts do
				for _, n in (part.motion and part.motion.next) or {} do
					expect(type(n)).toBe("string")
					expect(seen[n :: string]).toBe(true)
				end
			end
		end
	end)

	it("connectors are within a jump of the sections next to them", function()
		for slot = 4100, 4140 do
			local course = ObbyCourse.build(slot)
			local prev: ObbyCourse.Part? = nil
			for _, part in course.parts do
				if part.step then
					if prev and (part.link or prev.link or part.look == "finish") then
						if gap(prev, part) > Kit.GAP_MAX then
							error(`slot {slot}: gap {gap(prev, part)} at {part.id}`)
						end
					end
					prev = part
				end
			end
		end
	end)

	it("builds the same course for the same slot", function()
		local a, b = ObbyCourse.build(4321), ObbyCourse.build(4321)
		expect(#a.parts).toBe(#b.parts)
		for i, part in a.parts do
			expect(part.id).toBe(b.parts[i].id)
			for k = 1, 3 do
				expect(part.pos[k]).toBe(b.parts[i].pos[k])
			end
		end
	end)

	it("names the sections from the registry", function()
		local picks = ObbyCourse.pick(4100)
		local names = ObbyCourse.names(picks)
		for i, p in picks do
			expect(names[i]).toBe(ObbySections.byId[p.id].name)
			expect(ObbyCourse.nameOf(p.id)).toBe(names[i])
		end
		expect(ObbyCourse.nameOf("NoSuchIdea")).toBe("NoSuchIdea")
	end)
end)

describe("ObbyCourse floors", function()
	local function part(size: ObbyCourse.Vec, pos: ObbyCourse.Vec, extra: { [string]: any }?): ObbyCourse.Part
		local p: { [string]: any } = { size = size, pos = pos, look = "goo", step = true }
		for k, v in extra or {} do
			p[k] = v
		end
		return p :: any
	end

	it("hazards, zones, keys, gates and rope ends are never floors", function()
		local floors = ObbyCourse.floorsOf({
			part({ 8, 1, 8 }, { 0, 0, 0 }, { hazard = true, look = "hazard" }),
			part({ 8, 1, 8 }, { 0, 0, 0 }, { zone = { kind = "moon", gravity = 0.4 }, ghost = true }),
			part({ 1, 1, 1 }, { 0, 0, 0 }, { key = "a", ghost = true }),
			part({ 8, 9, 1 }, { 0, 0, 0 }, { gate = { group = "a", need = 1 }, look = "gate" }),
			part({ 1, 1, 1 }, { 0, 0, 0 }, { vine = { reach = 2 } }),
		})
		expect(#floors).toBe(0)
	end)

	it("melting tiles and collapsing pieces still count", function()
		local floors = ObbyCourse.floorsOf({
			part({ 8, 1, 8 }, { 4, -0.5, 0 }, { motion = { kind = "melt", delay = 0.5, away = -1 } }),
			part({ 8, 1, 8 }, { 14, -0.5, 0 }, { motion = { kind = "drop", at = 2 }, start = "g" }),
		})
		expect(#floors).toBe(2)
	end)

	it("a ramp's footprint is its rotated length and its floor is the low end", function()
		local ramp = Kit.ramp(0, 0, 12, 4, 0, 8, "goo")
		local floor = ObbyCourse.floorsOf({ ramp })[1]
		expect(math.abs(floor.top - 0) < 0.6).toBe(true)
		expect(math.abs(floor.from - 0) < 0.6).toBe(true)
		expect(math.abs(floor.to - 12) < 0.6).toBe(true)
		local turned = ObbyCourse.floorsOf({ part({ 20, 1, 4 }, { 0, -0.5, 0 }, { yaw = 90 }) })[1]
		expect(math.abs(turned.to - turned.from - 4) < 1e-6).toBe(true)
	end)

	it("a path stretches the floor along its points and a sink lowers it", function()
		local ride = ObbyCourse.floorsOf({
			part({ 8, 1, 8 }, { 0, -0.5, 0 }, {
				motion = { kind = "path", points = { { 0, 0, 0 }, { 20, -3, 0 } }, period = 6 },
			}),
		})[1]
		expect(ride.from).toBe(-4)
		expect(ride.to).toBe(24)
		expect(ride.top).toBe(-3)
		local sink = ObbyCourse.floorsOf({
			part({ 8, 1, 8 }, { 0, -0.5, 0 }, { motion = { kind = "sink", depth = 2, speed = 1 } }),
		})[1]
		expect(sink.top).toBe(-2)
	end)
end)

describe("ObbyCourse sections, finish and frames", function()
	local course = ObbyCourse.build(4100)
	local zone = course.finish

	it("counts standing on the finish pad, not flying over it", function()
		expect(ObbyCourse.onFinish(course, { zone.pos[1], zone.pos[2] + 3, zone.pos[3] })).toBe(true)
		expect(ObbyCourse.onFinish(course, { zone.pos[1] + zone.size[1], zone.pos[2] + 3, zone.pos[3] })).toBe(false)
		expect(ObbyCourse.onFinish(course, { zone.pos[1], zone.pos[2] + 30, zone.pos[3] })).toBe(false)
		expect(ObbyCourse.onFinish(course, { zone.pos[1], zone.pos[2] - 5, zone.pos[3] })).toBe(false)
	end)

	it("knows which section a point is over", function()
		expect(ObbyCourse.sectionAt(course, course.start)).toBe(0)
		for _, span in course.spans do
			expect(ObbyCourse.sectionAt(course, { (span.from + span.to) / 2, 0, 0 })).toBe(span.index)
		end
		expect(ObbyCourse.sectionAt(course, zone.pos)).toBe(#course.spans + 1)
	end)

	it("falls are measured under the lowest platform a runner could still land on", function()
		expect(ObbyCourse.fallHeight(course, course.start)).toBe(-OBBY.FALL_DEPTH)
		expect(ObbyCourse.fallHeight(course, zone.pos)).toBe(zone.pos[2] - OBBY.FALL_DEPTH)
		expect(ObbyCourse.fallHeight(course, zone.pos, 20)).toBe(zone.pos[2] - 20)
	end)

	it("resets a runner soon after they drop off the course", function()
		for slot = 4100, 4110 do
			local c = ObbyCourse.build(slot)
			for _, span in c.spans do
				local p = { (span.from + span.to) / 2, 0, 0 }
				-- A fall resets within FALL_DEPTH under the lowest floor of this section (a section may dip below its
				-- entry and exit, e.g. a low road), never under the far lower end of the whole course.
				local low = span.floor
				for _, floor in c.floors do
					if floor.to >= span.from and floor.from <= span.to then
						low = math.min(low, floor.top)
					end
				end
				expect(ObbyCourse.fallHeight(c, p) >= low - OBBY.FALL_DEPTH - 1e-6).toBe(true)
			end
		end
	end)

	it("every step top stays above the fall height", function()
		for slot = 4100, 4110 do
			local c = ObbyCourse.build(slot)
			for _, part in c.parts do
				if part.step then
					local p = { part.pos[1], top(part), part.pos[3] }
					expect(top(part) >= ObbyCourse.fallHeight(c, p) + OBBY.FALL_DEPTH - 1e-6).toBe(true)
				end
			end
		end
	end)

	it("maps server time to the 10-minute slot", function()
		expect(ObbyCourse.slot(OBBY.ROTATION_SECONDS * 7 + 1)).toBe(7)
		expect(ObbyCourse.slotStart(7)).toBe(OBBY.ROTATION_SECONDS * 7)
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
