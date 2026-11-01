--!strict
-- Moon Jump (obby idea 28): every variant through ObbyCheck, the variant list against its design file, that every
-- variant has a jump only a moon bubble makes, the sinking walls' windows in their tier's band (contract §10), and
-- the real moon arcs the shared checks don't model: walls and bars that really block the float, the overshoots, the
-- gravity edge of Bubble Edge, the roof and ceiling bars of Skylights and Goo Sandwich, the blobs in Last Leap's arc
-- and the beat of Moon Pulse.
local T = require("../TestRunner")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local MoonJump = require("../../src/shared/ObbySections/MoonJump")
local ObbyCheck = require("../ObbyCheck")

type Part = Kit.Part

-- The tightest hazard window of a variant with timed hazards (contract §10; easy up to 2.2 like Crusher Alley).
local BAND = {
	easy = { lo = 1.4, hi = 2.2 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}

local function variantNamed(name: string): Kit.Variant
	for _, v in MoonJump.variants do
		if v.name == name then
			return v
		end
	end
	error(`no Moon Jump variant {name}`)
end

local function steps(section: Kit.Section): { Part }
	local out = {}
	for _, p in section.parts do
		if p.step then
			table.insert(out, p)
		end
	end
	return out
end

local function box(p: Part): (number, number, number, number, number, number)
	return Kit.bounds(p)
end

-- The moon gravity over a step's middle (1 outside every bubble).
local function gravityOver(section: Kit.Section, s: Part): number
	local top = s.pos[2] + s.size[2] / 2
	for _, p in section.parts do
		if p.zone and p.zone.kind == "moon" then
			local x0, x1, y0, y1, z0, z1 = box(p)
			if s.pos[1] >= x0 and s.pos[1] <= x1 and s.pos[3] >= z0 and s.pos[3] <= z1 and top >= y0 and top <= y1 then
				return p.zone.gravity or 1
			end
		end
	end
	return 1
end

--[[
	A real moon arc along the line z = 0: take off from height `top` at x `x0` at `speed` studs / s forward, jump speed
	Kit.JUMP_SPEED, gravity `grav` x workspace gravity (one bubble the whole way). The body is 2 wide and 5 tall over
	the feet. Returns "land" when it comes down on `target`'s top, "hit" when it touches a static hazard first, else
	"miss".
]]
local function arc(section: Kit.Section, x0: number, top: number, speed: number, grav: number, target: Part): string
	local g = Kit.GRAVITY * grav
	local tx0, tx1, _, ty1 = box(target)
	local dt = 1 / 240
	local t = 0
	while t < 6 do
		t += dt
		local x = x0 + speed * t
		local feet = top + Kit.JUMP_SPEED * t - g * t * t / 2
		local vy = Kit.JUMP_SPEED - g * t
		for _, p in section.parts do
			if p.hazard and not p.motion then
				local hx0, hx1, hy0, hy1, hz0, hz1 = box(p)
				if
					x + ObbyCheck.BODY > hx0
					and x - ObbyCheck.BODY < hx1
					and feet + Kit.HEAD > hy0
					and feet < hy1
					and hz0 < ObbyCheck.BODY
					and hz1 > -ObbyCheck.BODY
				then
					return "hit"
				end
			end
		end
		if vy < 0 and feet <= ty1 then
			return if x >= tx0 and x <= tx1 then "land" else "miss"
		end
	end
	return "miss"
end

-- The take-off points (0.1 studs apart, full speed) on step `from` whose arc lands on step `to`.
local function goodTakeoffs(section: Kit.Section, from: Part, to: Part, grav: number): (number, number, number)
	local x0, x1, _, top = box(from)
	local good, first, last = 0, math.huge, -math.huge
	local x = x0
	while x <= x1 + 1e-9 do
		if arc(section, x, top, Kit.WALK, grav, to) == "land" then
			good += 1
			first, last = math.min(first, x), math.max(last, x)
		end
		x += 0.1
	end
	return good * 0.1, first, last
end

--[[
	A real flight with moving hazards and gravity from the bubble the body is in at each moment (Bubble Edge changes
	gravity mid-air): take off at x `x0`, line z `z`, height `top`, `speed` forward, at clock `t0` (server time of the
	motions). Returns "land" on `target`, "hit" on any hazard (where it is at that moment), else "miss".
]]
local function fly(
	section: Kit.Section,
	x0: number,
	z: number,
	top: number,
	speed: number,
	t0: number,
	target: Part
): string
	local tx0, tx1, _, ty1 = box(target)
	local dt = 1 / 240
	local x, feet, vy, t = x0, top, Kit.JUMP_SPEED, 0
	while t < 8 do
		local g = 1
		for _, p in section.parts do
			if p.zone and p.zone.kind == "moon" then
				local zx0, zx1, zy0, zy1 = box(p)
				if x >= zx0 and x <= zx1 and feet + 1 >= zy0 and feet + 1 <= zy1 then
					g = p.zone.gravity or 1
				end
			end
		end
		t += dt
		x += speed * dt
		vy -= Kit.GRAVITY * g * dt
		feet += vy * dt
		for _, p in section.parts do
			if p.hazard then
				local dx, dy, dz, _, _, on = Kit.offsetAt(p, t0 + t)
				local hx0, hx1, hy0, hy1, hz0, hz1 = box(p)
				if
					on
					and x + ObbyCheck.BODY > hx0 + dx
					and x - ObbyCheck.BODY < hx1 + dx
					and feet + Kit.HEAD > hy0 + dy
					and feet < hy1 + dy
					and hz0 + dz < z + ObbyCheck.BODY
					and hz1 + dz > z - ObbyCheck.BODY
				then
					return "hit"
				end
			end
		end
		if vy < 0 and feet <= ty1 then
			return if x >= tx0 and x <= tx1 then "land" else "miss"
		end
	end
	return "miss"
end

-- The longest run of start times (over two of its periods) at which a full-speed flight from `x0` on any of the lines
-- `zs` lands on `to`.
local function bestWindow(
	section: Kit.Section,
	x0: number,
	zs: { number },
	top: number,
	period: number,
	to: Part
): number
	local best, run, dt = 0, 0, 0.02
	for k = 0, math.floor(2 * period / dt) do
		local ok = false
		for _, z in zs do
			if fly(section, x0, z, top, Kit.WALK, k * dt, to) == "land" then
				ok = true
				break
			end
		end
		run = if ok then run + 1 else 0
		best = math.max(best, run)
	end
	return best * dt
end

-- The lowest period of a section's moving hazards.
local function hazardPeriod(section: Kit.Section): number
	local period = 0
	for _, p in section.parts do
		if p.hazard and p.motion then
			period = math.max(period, Kit.periodOf(p))
		end
	end
	return period
end

describe("Moon Jump", function()
	it("passes every shared check for every variant, seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(MoonJump) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("builds every variant of docs/obby-variants/28.json, in its order and tiers", function()
		local doc = serde.decode("json", fs.readFile("docs/obby-variants/28.json"))
		local design = doc.ideas[1]
		expect(MoonJump.id).toBe("MoonJump")
		expect(MoonJump.name).toBe(design.name)
		expect(MoonJump.idea).toBe(design.id)
		expect(#MoonJump.variants).toBe(#design.variants)
		for i, v in design.variants do
			expect(MoonJump.variants[i].name).toBe(v.name)
			expect(MoonJump.variants[i].tier).toBe(v.tier)
		end
		expect(MoonJump.generator).toBeNil()
	end)

	it("gives every variant a jump a normal jump can't make, from inside a bubble", function()
		local off = {}
		for _, case in ObbyCheck.cases(MoonJump) do
			local section = case.build(1)
			local list = steps(section)
			local moonOnly = 0
			for i = 2, #list do
				local a, b = list[i - 1], list[i]
				local _, ax1, _, atop = box(a)
				local bx0, _, _, btop = box(b)
				if bx0 - ax1 > Kit.GAP_MAX or btop - atop > Kit.RISE_MAX then
					moonOnly += 1
					if gravityOver(section, a) >= 1 then
						table.insert(off, `{case.name}: the big jump onto step {i} starts outside a bubble`)
					end
				end
			end
			if moonOnly == 0 then
				table.insert(off, `{case.name}: no jump needs the bubble`)
			end
		end
		expect(table.concat(off, "\n")).toBe("")
	end)

	it("keeps the sinking walls' tightest window in their tier's band", function()
		local off, seen = {}, 0
		for _, case in ObbyCheck.cases(MoonJump) do
			local section = case.build(1)
			local timed = false
			for _, p in section.parts do
				timed = timed or (p.hazard == true and p.motion ~= nil and p.motion.kind == "path")
			end
			if timed then
				seen += 1
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
		expect(seen).toBe(2) -- Goo Hedge, Over and Back
	end)

	it("never lets a straight walk through, on any line or start time", function()
		for _, case in ObbyCheck.cases(MoonJump) do
			expect(ObbyCheck.straightWalk(case.build(1))).toBeNil()
		end
	end)
end)

describe("Moon Jump real arcs", function()
	it("Skylights: a jump from the last few studs of each island clears the roof; an early one hits it", function()
		local section = variantNamed("Skylights").build(1)
		local list = steps(section)
		for i = 2, #list do
			local a, b = list[i - 1], list[i]
			local grav = gravityOver(section, a)
			local spare, first = goodTakeoffs(section, a, b, grav)
			local ax0, ax1, _, top = box(a)
			-- a 3..6-stud take-off strip at the far end: about a quarter of a second at a run
			expect(spare >= 3 and spare <= 6).toBe(true)
			expect(first > ax1 - 6).toBe(true)
			-- jumping from the near half goes into the roof
			expect(arc(section, (ax0 + ax1) / 2 - 2, top, Kit.WALK, grav, b)).toBe("hit")
		end
	end)

	it("Goo Sandwich: a full-speed jump from the edge overshoots; one from mid-island flies over the bar", function()
		local section = variantNamed("Goo Sandwich").build(1)
		local list = steps(section)
		for i = 2, #list do
			local a, b = list[i - 1], list[i]
			local grav = gravityOver(section, a)
			local _, ax1, _, top = box(a)
			expect(arc(section, ax1, top, Kit.WALK, grav, b)).toBe("miss")
			local spare = goodTakeoffs(section, a, b, grav)
			expect(spare >= 2).toBe(true)
			-- a slow, short float runs into the ceiling bar
			expect(arc(section, ax1, top, Kit.WALK / 2, grav, b)).toBe("hit")
		end
	end)

	it("Last Leap: each goo blob crosses the arc of a jump that lands on the pad", function()
		local section = variantNamed("Last Leap").build(1)
		local list = steps(section)
		local a, b = list[1], list[2]
		local grav = gravityOver(section, a)
		local _, _, _, top = box(a)
		local _, first, last = goodTakeoffs(section, a, b, grav)
		expect(first < last).toBe(true)
		local takeoff = (first + last) / 2
		for _, p in section.parts do
			if p.hazard and p.motion and p.motion.kind == "slide" then
				-- where the middle arc is when it passes the blob's x
				local t = (p.pos[1] - takeoff) / Kit.WALK
				local feet = top + Kit.JUMP_SPEED * t - Kit.GRAVITY * grav * t * t / 2
				local r = p.size[1] / 2
				expect(feet < p.pos[2] + r and feet + Kit.HEAD > p.pos[2] - r).toBe(true)
				-- and it sweeps across the middle line of the lane
				expect((p.motion.amp :: number) > r).toBe(true)
			end
		end
	end)

	it("Moon Pulse: off the first blinking island in a ~1 s window, the float lands while the second is lit", function()
		local section = variantNamed("Moon Pulse").build(1)
		local blink = {}
		for _, s in steps(section) do
			if s.motion and s.motion.kind == "flip" then
				table.insert(blink, s)
			end
		end
		expect(#blink).toBe(2)
		local grav = gravityOver(section, blink[1])
		local flight = 2 * Kit.JUMP_SPEED / (Kit.GRAVITY * grav)
		local period = Kit.periodOf(blink[1])
		expect(period).toBeCloseTo(3.6, 1e-6)
		local function lit(p: Part, t: number): boolean
			local _, _, _, _, _, on = Kit.offsetAt(p, t)
			return on
		end
		-- Seconds of a bar you can leave the first and still land on the second (lit for 0.3 s after you land).
		local ok, dt = 0, 0.01
		for k = 0, math.floor(period / dt) - 1 do
			local t = k * dt
			if lit(blink[1], t) and lit(blink[2], t + flight) and lit(blink[2], t + flight + 0.3) then
				ok += dt
			end
		end
		expect(ok >= BAND.hard.lo - 1e-6 and ok <= BAND.hard.hi + 1e-6).toBe(true)
		-- and the pad to the first: you can always time it (it is lit 2.4 s a bar)
		local fromPad = 0
		for k = 0, math.floor(period / dt) - 1 do
			if lit(blink[1], k * dt + flight) then
				fromPad += dt
			end
		end
		expect(fromPad > 2).toBe(true)
	end)

	it("Goo Hedge and Over and Back: a wall that is up stops every float; one that is down lets one through", function()
		for _, name in { "Goo Hedge", "Over and Back" } do
			local section = variantNamed(name).build(1)
			local list = steps(section)
			local period = hazardPeriod(section)
			for i = 2, #list do
				local a, b = list[i - 1], list[i]
				local ax0, ax1, _, top = box(a)
				local wall: Part? = nil
				for _, p in section.parts do
					if p.hazard and p.motion and p.pos[1] > ax1 and p.pos[1] < box(b) then
						wall = p
					end
				end
				if wall then
					-- take off just before the wall stands up (its rest point, held `hold` s): no take-off from the last
					-- 6 studs of the island lands (each reaches the wall while it is still up)
					local up = (1 - ((wall.motion :: any).phase or 0)) % 1 * period
					local x = math.max(ax0, ax1 - 6)
					while x <= ax1 + 1e-9 do
						expect(fly(section, x, 0, top, Kit.WALK, up - 0.2, b) ~= "land").toBe(true)
						x += 0.5
					end
					-- and some take-off and time lands
					expect(bestWindow(section, ax1 - 3, { 0 }, top, period, b) > 0).toBe(true)
				end
			end
		end
	end)

	it("Over and Back and Two Moons: a full-speed float from the edge overshoots; an earlier one lands", function()
		for _, name in { "Over and Back", "Two Moons" } do
			local section = variantNamed(name).build(1)
			local list = steps(section)
			local a, b = list[#list - 1], list[#list]
			local _, ax1, _, top = box(a)
			-- at a clock where any wall is down all through the flight, so only the landing decides
			local t0 = 0
			for _, p in section.parts do
				local m = p.motion
				if p.hazard and m and m.kind == "path" and p.pos[1] > ax1 then
					local period = Kit.periodOf(p)
					local hold = m.hold or 0
					-- rest (up) at cycle 0, held `hold`, then one leg down: the down hold starts here
					local down = hold + (period - 2 * hold) / 2
					t0 = ((1 - (m.phase or 0)) % 1) * period + down - 0.2
				end
			end
			expect(fly(section, ax1, 0, top, Kit.WALK, t0, b)).toBe("miss")
			expect(fly(section, ax1 - 4, 0, top, Kit.WALK, t0 - 0.25, b)).toBe("land")
		end
	end)

	it("Bobbing Goo: the bar crosses the float's path; the real window over or under it is a medium one", function()
		local section = variantNamed("Bobbing Goo").build(1)
		local list = steps(section)
		local period = hazardPeriod(section)
		for i = 2, 3 do
			local a, b = list[i - 1], list[i]
			local _, ax1, _, top = box(a)
			local w = bestWindow(section, ax1 - 2, { 0 }, top, period, b)
			expect(w >= BAND.medium.lo and w <= BAND.medium.hi).toBe(true)
		end
	end)

	it("Bubble Edge: only a take-off from the last few studs floats far enough before gravity comes back", function()
		local section = variantNamed("Bubble Edge").build(1)
		local list = steps(section)
		for i = 2, #list do
			local a, b = list[i - 1], list[i]
			local ax0, ax1, _, top = box(a)
			local good, x = 0, ax0
			while x <= ax1 + 1e-9 do
				if fly(section, x, 0, top, Kit.WALK, 0, b) == "land" then
					good += 0.5
					expect(x > ax1 - 5).toBe(true)
				end
				x += 0.5
			end
			expect(good >= 2 and good <= 5).toBe(true)
		end
	end)

	it("Last Leap: picking a line between the blobs leaves a hard window", function()
		local section = variantNamed("Last Leap").build(1)
		local list = steps(section)
		local a, b = list[1], list[2]
		local _, _, _, top = box(a)
		local lines = {}
		for z = -4, 4, 0.5 do
			table.insert(lines, z)
		end
		local w = bestWindow(section, 6, lines, top, hazardPeriod(section), b) -- 8 short of the 14-long pad's edge
		expect(w >= BAND.hard.lo and w <= BAND.hard.hi).toBe(true)
	end)
end)
