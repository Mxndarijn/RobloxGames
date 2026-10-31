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
local GRAVITY = 196.2 -- workspace.Gravity
local WALK = 16 -- studs / s while airborne after a launch (the walk speed steers you)

-- How a step is reached: "climb" (a ladder), "lift" (a wind column) or nil (walk / jump).
local function special(p: ObbyCourse.Part): string?
	if p.shape == "truss" then
		return "climb"
	end
	return if p.motion and p.motion.kind == "lift" then "lift" else nil
end

-- Launched straight up at `power`: can you land `rise` studs higher, `g` studs away? (20 % spare on the walk)
local function launchReaches(power: number, rise: number, g: number): (boolean, string)
	local peak = power * power / (2 * GRAVITY)
	if rise > peak - 1.5 then
		return false, `rise {rise} over a {peak}-stud launch`
	end
	local t = (power + math.sqrt(power * power - 2 * GRAVITY * rise)) / GRAVITY
	local reach = WALK * t * 0.8
	return g <= reach, `gap {g} past a {reach}-stud launch`
end

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

local function bottom(p: ObbyCourse.Part): number
	return p.pos[2] - p.size[2] / 2
end

local JUMP_SPEED = math.sqrt(2 * GRAVITY * 7.2) -- JumpHeight 7.2
local HEAD = 5 -- feet to the top of the head

-- How far a running jump carries on the flat when a roof `room` studs over the floor stops the head.
local function jumpUnderRoof(room: number): number
	local headroom = room - HEAD
	local peak = JUMP_SPEED * JUMP_SPEED / (2 * GRAVITY)
	if headroom >= peak then
		return WALK * 2 * JUMP_SPEED / GRAVITY
	end
	local disc = JUMP_SPEED * JUMP_SPEED - 2 * GRAVITY * headroom
	local up = (JUMP_SPEED - math.sqrt(disc)) / GRAVITY
	local down = math.sqrt(2 * headroom / GRAVITY)
	return WALK * (up + down)
end

-- The lowest solid roof over the middle of two steps, as studs over the higher one, or nil.
local function roofOver(parts: { ObbyCourse.Part }, a: ObbyCourse.Part, b: ObbyCourse.Part): number?
	local mx, mz = (a.pos[1] + b.pos[1]) / 2, (a.pos[3] + b.pos[3]) / 2
	local floor = math.max(top(a), top(b))
	local best: number? = nil
	for _, p in parts do
		if not p.step and not p.ghost and bottom(p) > floor + 0.01 then
			if math.abs(mx - p.pos[1]) <= p.size[1] / 2 and math.abs(mz - p.pos[3]) <= p.size[3] / 2 then
				local room = bottom(p) - floor
				if best == nil or room < best then
					best = room
				end
			end
		end
	end
	return best
end

-- Every motion kind visuals/client/ObbyFx plays.
local KINDS = {
	slide = true,
	spin = true,
	melt = true,
	flip = true,
	shrink = true,
	bounce = true,
	lift = true,
	swing = true,
	rock = true,
	roll = true,
	punch = true,
	gust = true,
}

---------------------------------------------------------------------------
-- The straight walk: can you hold "forward" along z = 0 and get across without jumping or steering?
---------------------------------------------------------------------------

local SAMPLE = 0.25 -- studs between samples along x
local WALK_OVER = 2 -- a hole up to this long is walked over (or stumbled over)
local STEP_UP = 1 -- a ledge up to this high is walked up
local FEET = 0.75 -- a part counts on the line while it comes within this far of z = 0
local MOVING_HAZARDS = { slide = true, spin = true, swing = true, punch = true, gust = true }

type Section = { length: number, rise: number, parts: { ObbyCourse.Part } }

local function covers(p: ObbyCourse.Part, x: number, grow: number): boolean
	if p.shape == "disc" then
		local r = p.size[1] / 2 + grow
		return (x - p.pos[1]) ^ 2 + p.pos[3] ^ 2 <= r * r
	end
	return math.abs(x - p.pos[1]) <= p.size[1] / 2 and math.abs(p.pos[3]) <= p.size[3] / 2 + grow
end

-- A floor you can walk straight over: always there, and it doesn't carry you off its side before you are across.
local function steadyFloor(p: ObbyCourse.Part): boolean
	local m = p.motion
	if m and (m.kind == "flip" or m.kind == "shrink") then
		return false
	end
	local sideways, along = 0, 0
	if p.conveyor then
		along, sideways = p.conveyor[1], math.abs(p.conveyor[3])
	elseif m and m.kind == "roll" then
		sideways = math.abs(2 * math.pi / (m.period or 1)) * p.size[2] / 2
	end
	if sideways > 0 then
		local speed = WALK + along
		if speed <= 0 then
			return false
		end
		local drift = sideways * p.size[1] / speed
		if drift > p.size[3] / 2 - 0.5 then
			return false
		end
	end
	return true
end

-- The box a moving hazard sweeps: centre x, half x, centre z, half z, bottom, top.
local function swept(p: ObbyCourse.Part): (number, number, number, number, number, number)
	local m = p.motion :: ObbyCourse.Motion
	local hx, hz = p.size[1] / 2, p.size[3] / 2
	local cx, cz = p.pos[1], p.pos[3]
	local y0, y1 = bottom(p), top(p)
	if m.kind == "slide" or m.kind == "punch" then
		local amp = m.amp or 0
		if m.axis == "x" then
			hx += math.abs(amp)
		elseif m.axis == "y" then
			y0 -= math.abs(amp)
			y1 += math.abs(amp)
		elseif m.kind == "punch" then
			-- a punch goes one way only
			cz += amp / 2
			hz += math.abs(amp) / 2
		else
			hz += math.abs(amp)
		end
	elseif m.kind == "spin" then
		local r = math.sqrt(hx * hx + hz * hz)
		hx, hz = r, r
	elseif m.kind == "swing" then
		local a = math.rad(m.amp or 0)
		hz += (m.arm or 0) * math.sin(a)
		y1 += (m.arm or 0) * (1 - math.cos(a))
	end
	return cx, hx, cz, hz, y0, y1
end

-- nil when holding forward along z = 0 gets you across `section`; otherwise what stops you.
local function straightWalkStop(section: Section): string?
	local level, hole = 0, 0
	local x = 0
	while x <= section.length do
		local best: number? = nil
		for _, p in section.parts do
			local hazard = p.motion ~= nil and MOVING_HAZARDS[p.motion.kind] == true and not p.step
			if hazard then
				local cx, hx, cz, hz, y0, y1 = swept(p)
				if math.abs(x - cx) <= hx and math.abs(cz) <= hz + FEET and y1 > level + 0.5 and y0 < level + HEAD then
					return `{p.look} sweeps across at x {x}`
				end
			elseif not p.ghost and covers(p, x, FEET) then
				local t, b = top(p), bottom(p)
				if t > level + STEP_UP and b < level + HEAD and p.look ~= "post" then
					return `{p.look} blocks at x {x}`
				end
				if t <= level + STEP_UP and steadyFloor(p) and (best == nil or t > best) then
					best = t
				end
			end
		end
		if best then
			level, hole = best, 0
		else
			hole += SAMPLE
			if hole > WALK_OVER then
				return `hole at x {x}`
			end
		end
		x += SAMPLE
	end
	return nil
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

	it("shows every section and every layout within three days", function()
		local seen = {}
		local first = 4032
		for slot = first, first + 3 * OBBY.CHAIN_SLOTS - 1 do
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
					local prev, cur = steps[i - 1], steps[i]
					local g = gap(prev, cur)
					local rise = top(cur) - top(prev)
					local launch = prev.motion and prev.motion.kind == "bounce" and prev.motion.power
					local room = roofOver(course.parts, prev, cur)
					local gapMax = if room then math.min(GAP_MAX, jumpUnderRoof(room) * 0.8) else GAP_MAX
					if special(cur) then
						-- You walk into a ladder or a wind column from the step before.
						if g > 1.5 then
							error(`{label}: gap {g} to a {special(cur)}`)
						end
					elseif special(prev) then
						-- Off the top of a ladder or out of the wind: the next step is at or under its top, close by.
						if rise > 0.01 or g > 2 then
							error(`{label}: off a {special(prev)}: rise {rise}, gap {g}`)
						end
					elseif launch then
						local ok, why = launchReaches(launch, rise, g)
						if not ok then
							error(`{label}: {why}`)
						end
					else
						if g > gapMax then
							error(`{label}: gap {g} (at most {gapMax})`)
						end
						if rise > RISE_MAX then
							error(`{label}: rise {rise}`)
						end
					end
				end
			end
		end
	end)

	it("no section can be crossed by walking straight forward", function()
		local walkable = {}
		for id in ObbyCourse.BUILD do
			for layout = 1, OBBY.LAYOUTS do
				if straightWalkStop(ObbyCourse.section(id, layout)) == nil then
					table.insert(walkable, `{id}#{layout}`)
				end
			end
		end
		table.sort(walkable)
		expect(table.concat(walkable, ", ")).toBe("")
	end)

	it("the straight-walk check passes a plain bridge, a slow belt and a hole you step over", function()
		local function part(size: ObbyCourse.Vec, pos: ObbyCourse.Vec, extra: { [string]: any }?): ObbyCourse.Part
			local p: { [string]: any } = { size = size, pos = pos, look = "goo", step = true }
			for k, v in extra or {} do
				p[k] = v
			end
			return p :: any
		end
		local function section(parts: { ObbyCourse.Part }, length: number): Section
			return { length = length, rise = 0, parts = parts }
		end
		expect(straightWalkStop(section({ part({ 20, 1, 3 }, { 10, -0.5, 0 }) }, 20))).toBeNil()
		local stepOver =
			section({ part({ 9.5, 1, 3 }, { 4.75, -0.5, 0 }), part({ 9.5, 1, 3 }, { 15.25, -0.5, 0 }) }, 20)
		expect(straightWalkStop(stepOver)).toBeNil()
		local slowBelt = section({ part({ 8, 1, 8 }, { 4, -0.5, 0 }, { conveyor = { 0, 0, 4 } }) }, 8)
		expect(straightWalkStop(slowBelt)).toBeNil()
		local fastBelt = section({ part({ 8, 1, 4 }, { 4, -0.5, 0 }, { conveyor = { 0, 0, 10 } }) }, 8)
		expect(straightWalkStop(fastBelt) ~= nil).toBe(true)
		local gapped = section({ part({ 8, 1, 3 }, { 4, -0.5, 0 }), part({ 8, 1, 3 }, { 16, -0.5, 0 }) }, 20)
		expect(straightWalkStop(gapped) ~= nil).toBe(true)
		local wall =
			section({ part({ 20, 1, 3 }, { 10, -0.5, 0 }), part({ 20, 8, 1 }, { 10, 3, 0 }, { step = false }) }, 20)
		expect(straightWalkStop(wall) ~= nil).toBe(true)
	end)

	it("uses only motion kinds the client plays", function()
		for id in ObbyCourse.BUILD do
			for layout = 1, OBBY.LAYOUTS do
				for _, part in ObbyCourse.section(id, layout).parts do
					if part.motion and not KINDS[part.motion.kind] then
						error(`{id} layout {layout}: unknown motion {part.motion.kind}`)
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

	it("joins the sections with plain connectors, no checkpoint pads, and ends on the finish", function()
		local course = ObbyCourse.build(4100)
		expect(#course.spans).toBe(#OBBY.ORDER)
		local finishes, links = 0, 0
		for _, part in course.parts do
			if part.look == "finish" then
				finishes += 1
			elseif part.look == "pad" then
				links += 1
				expect(part.size[1]).toBe(ObbyCourse.LINK_LENGTH)
			end
		end
		expect(finishes).toBe(1)
		expect(links).toBe(#OBBY.ORDER - 1)
		expect(course.spans[1].from).toBe(ObbyCourse.START_LENGTH)
		for i = 2, #course.spans do
			expect(course.spans[i].from).toBe(course.spans[i - 1].to)
		end
		expect(course.finish.pos[1] - course.finish.size[1] / 2).toBe(course.spans[#course.spans].to)
		expect(course.length <= ObbyCourse.START_LENGTH + #OBBY.ORDER * (SECTION_MAX_LENGTH + 12)).toBe(true)
	end)

	it("a whole course with connectors is a makeable path", function()
		for slot = 4100, 4140 do
			local course = ObbyCourse.build(slot)
			local prev: ObbyCourse.Part? = nil
			for _, part in course.parts do
				if part.step then
					if prev and not special(part) and not special(prev) and not prev.motion then
						if gap(prev, part) > GAP_MAX then
							error(`slot {slot}: gap {gap(prev, part)} before a {part.look}`)
						end
					end
					prev = part
				end
			end
		end
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

	it("falls are measured below the section's lower end", function()
		expect(ObbyCourse.fallHeight(course, 0)).toBe(-OBBY.FALL_DEPTH)
		local span = course.spans[3]
		expect(ObbyCourse.fallHeight(course, 3)).toBe(span.floor - OBBY.FALL_DEPTH)
		expect(ObbyCourse.fallHeight(course, #course.spans + 1)).toBe(zone.pos[2] - OBBY.FALL_DEPTH)
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
