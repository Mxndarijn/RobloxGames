--!strict
-- Ice Slide (obby idea 6): every variant through ObbyCheck, plus what the shared checks don't ask: every variant
-- has slide ice, every jump off a slide clears its gap at the slide's capped speed (a real ballistic flight, not the
-- walking GAP_MAX), the half-pipe's far side can be climbed at the cap, the timed hazards' windows sit in the
-- tier's band (contract §10), the goo layout can really be steered on ice (a planner with ObbyMoves' weak steering)
-- and no goo strip can simply be hopped at slide speed instead of steered round.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local IceSlide = require("../../src/shared/ObbySections/IceSlide")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

local DESIGN = {
	"First Slide",
	"Dodge Left, Dodge Right",
	"Bumper Bend",
	"Steer to the Green",
	"Ice Stairs",
	"Wide Sweep",
	"Hairpins",
	"Swiss Cheese",
	"Ice Bridge",
	"Ski Jump",
	"Slalom Posts",
	"Fork in the Ice",
	"Brake and Go",
	"Half-Pipe Hop",
	"Red Run",
	"Corkscrew",
	"Ice Islands",
	"Blind Crest",
}

-- Hazard windows a tier earns (contract §10); a window longer than STILL s is still goo (steer round it).
local BAND = {
	easy = { lo = 1.4, hi = 2.0 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}
local STILL = 5

-- The steering planner: ObbyMoves.STEER_ACCEL (16 studs/s²) with the checks' 20 % spare.
local STEER = 16 * 0.8
local GOO_UP = 1.2 -- a goo patch's top over the ice (IceSlide)
-- Variants the planner can't model: turned track (bends, arcs, the corkscrew) and a leg that runs back (hairpins).
local UNPLANNED = { ["Bumper Bend"] = true, ["Wide Sweep"] = true, ["Hairpins"] = true, ["Corkscrew"] = true }

-- Steps in order with their x range and the top at each end.
type Step = { part: Kit.Part, x0: number, x1: number, near: number, far: number }
local function steps(section: Kit.Section): { Step }
	local out = {}
	for _, part in section.parts do
		if part.step and part.route == nil then
			local near, far = Kit.endTops(part)
			local x0, x1 = Kit.bounds(part)
			table.insert(out, { part = part, x0 = x0, x1 = x1, near = near, far = far })
		end
	end
	return out
end

-- Studs a jump off a slide at `speed` carries before it comes down `drop` studs lower (negative: higher), with the
-- checks' 20 % steering spare.
local function flight(speed: number, drop: number): number
	local v = Kit.JUMP_SPEED
	local t = (v + math.sqrt(v * v + 2 * Kit.GRAVITY * drop)) / Kit.GRAVITY
	return speed * t * 0.8
end

--[[
	Can the static goo, posts and holes of `section` be steered through on ice, along `route`? A slider runs +x at
	the cap (the fastest, least time to steer); on slide ice the stick only adds STEER studs/s² sideways, and on a
	slope the downhill pull at the cap bleeds sideways speed (ObbyMoves.stepDrive rescales to the cap: a decay of
	pull / cap a second). In the air over a hole it steers the same, without the pull. On brake goo or jelly it can
	stop and walk off sideways. Its body must stay on a floor and a body's width off every goo patch, post and solid
	prop; blinking or spinning hazards are timing (the fairness checks) and left out. Returns nil when some line gets
	through, else the x where every line died.
]]
local function steerable(section: Kit.Section, route: string?): number?
	type Box = { x0: number, x1: number, z0: number, z1: number, slide: boolean, pull: number }
	local floors: { Box } = {}
	local blocks: { Box } = {}
	local cap, xs, xe = 0, math.huge, -math.huge
	for _, part in section.parts do
		local x0, x1, _, _, z0, z1 = Kit.bounds(part)
		if part.step and (part.route == nil or part.route == route) then
			local pull = if part.slide and math.abs(part.roll or 0) > 1 then part.slide.pull else 0
			table.insert(floors, { x0 = x0, x1 = x1, z0 = z0, z1 = z1, slide = part.slide ~= nil, pull = pull })
			if part.slide then
				cap = math.max(cap, part.slide.cap)
				xs, xe = math.min(xs, x0), math.max(xe, x1)
			end
		elseif not part.step and not part.ghost and not part.zone and not (part.hazard and part.motion) then
			local b = ObbyCheck.BODY
			table.insert(blocks, { x0 = x0 - b, x1 = x1 + b, z0 = z0 - b, z1 = z1 + b, slide = false, pull = 0 })
		end
	end
	local dx = 1
	local dt = dx / cap
	local dv = STEER * dt
	local vmax = cap * 0.7
	-- (allowed, can stop here, sideways decay a second)
	local function at(x: number, z: number): (boolean, boolean, number)
		if math.abs(z) > Kit.HALF then
			return false, false, 0
		end
		local any, inside, stop, decay = false, false, false, 0
		for _, f in floors do
			if x >= f.x0 and x <= f.x1 then
				any = true
				if z >= f.z0 + 0.3 and z <= f.z1 - 0.3 then
					inside = true
					stop = stop or not f.slide
					decay = math.max(decay, f.pull / cap)
				end
			end
		end
		if any and not inside then
			return false, false, 0
		end
		for _, b in blocks do
			if x >= b.x0 and x <= b.x1 and z >= b.z0 and z <= b.z1 then
				return false, false, 0
			end
		end
		return true, stop, decay
	end
	type State = { z: number, v: number, stop: boolean, decay: number }
	local states: { State } = {}
	for k = 0, 4 * Kit.WIDTH do
		local z = -Kit.HALF + k / 4
		local good, _, decay = at(xs, z)
		if good then
			table.insert(states, { z = z, v = 0, stop = false, decay = decay })
		end
	end
	local x = xs
	while x < xe - 1e-6 do
		x = math.min(x + dx, xe)
		local new: { State }, seen: { [number]: boolean } = {}, {}
		for _, s in states do
			local options = {}
			for u = -1, 1 do
				table.insert(options, s.v * (1 - s.decay * dt) + u * dv)
			end
			if s.stop then
				for _, v in { -8, -4, 0, 4, 8 } do
					table.insert(options, v)
				end
			end
			for _, option in options do
				local v = math.clamp(option, -vmax, vmax)
				local z = s.z + v * dt
				local key = math.round(z * 5) * 10000 + math.round(v * 8)
				if not seen[key] then
					local good, stop, decay = at(x, z)
					if good then
						seen[key] = true
						table.insert(new, { z = z, v = v, stop = stop, decay = decay })
					end
				end
			end
		end
		if #new == 0 then
			return x
		end
		states = new
	end
	return nil
end

-- Studs of goo (plus a body each side) a jump off a slide at `cap` on a slope of `deg` clears: the stretch of the
-- flight where the feet are over GOO_UP above the ice under them.
local function hopLength(cap: number, deg: number): number
	local v, g = Kit.JUMP_SPEED + cap * math.tan(math.rad(deg)), Kit.GRAVITY
	local d = v * v - 2 * g * GOO_UP
	return if d > 0 then cap * 2 * math.sqrt(d) / g else 0
end

describe("IceSlide", function()
	it("is idea 6 with every variant of the design file, in its order", function()
		expect(IceSlide.id).toBe("IceSlide")
		expect(IceSlide.name).toBe("Ice Slide")
		expect(IceSlide.idea).toBe(6)
		expect(#IceSlide.variants).toBe(#DESIGN)
		for i, name in DESIGN do
			expect(IceSlide.variants[i].name).toBe(name)
		end
		expect(IceSlide.generator).toBeNil()
	end)

	it("has at least 4 easy, 4 medium and 3 hard variants", function()
		local count = { easy = 0, medium = 0, hard = 0 }
		for _, v in IceSlide.variants do
			count[v.tier] += 1
		end
		expect(count.easy >= 4).toBe(true)
		expect(count.medium >= 4).toBe(true)
		expect(count.hard >= 3).toBe(true)
	end)

	it("passes every ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(IceSlide :: any) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("has slide ice and a hazard in every variant", function()
		for _, v in IceSlide.variants do
			local slides, hazards = 0, 0
			for _, part in v.build(1).parts do
				if part.slide then
					slides += 1
					expect(part.look).toBe("ice")
					expect(part.slide.cap >= Kit.WALK).toBe(true)
				end
				if part.hazard then
					hazards += 1
				end
			end
			expect(slides > 0).toBe(true)
			if hazards == 0 and v.name ~= "Ice Islands" then
				error(`{v.name}: no hazard (contract §10: no section is just sliding)`)
			end
		end
	end)

	it("clears every jump off a slide at the capped slide speed", function()
		for _, v in IceSlide.variants do
			local list = steps(v.build(1))
			for i = 2, #list do
				local a, b = list[i - 1], list[i]
				local gap = b.x0 - a.x1
				if a.part.slide and gap > 0.5 then
					local reach = flight(a.part.slide.cap, a.far - b.near)
					if reach < gap then
						error(`{v.name}: a {gap}-stud jump off the ice reaches only {reach}`)
					end
				end
			end
		end
	end)

	it("needs the slide for its longest jumps (Ski Jump, Red Run, Ice Islands)", function()
		local walkJump = flight(Kit.WALK, 2)
		for _, i in { 10, 15, 17 } do
			local list = steps(IceSlide.variants[i].build(1))
			local longest = 0
			for k = 2, #list do
				longest = math.max(longest, list[k].x0 - list[k - 1].x1)
			end
			expect(longest > walkJump).toBe(true)
		end
	end)

	it("can climb the half-pipe's far side at the cap, holding forward", function()
		local section = IceSlide.variants[14].build(1)
		local bottomX, bottomY, lastX, lastY, cap, pull = 0, math.huge, 0, 0, 0, 0
		for _, part in section.parts do
			if part.slide then
				local near, far, x0, x1 = Kit.endTops(part)
				if near < bottomY then
					bottomX, bottomY = x0, near
				end
				if far < bottomY then
					bottomX, bottomY = x1, far
				end
				lastX, lastY = x1, far
				cap, pull = part.slide.cap, part.slide.pull
			end
		end
		expect(lastY > bottomY).toBe(true)
		-- uphill the pull brakes you; holding forward steers against it at a quarter accel (ObbyMoves.STEER_ACCEL)
		local brake = pull - 16
		local reach = cap * cap / (2 * brake)
		expect(reach > lastX - bottomX).toBe(true)
	end)

	it("keeps every timed hazard's window in its tier's band", function()
		for _, case in ObbyCheck.cases(IceSlide :: any) do
			for _, w in ObbyCheck.windows(case.build(1)) do
				local band = BAND[case.tier]
				if w.slack < STILL then
					if w.slack < band.lo - 1e-6 or w.slack > band.hi + 1e-6 then
						error(`{case.name}: hazards at x {w.from}..{w.to} open {w.slack} s ({band.lo}..{band.hi})`)
					end
				end
			end
		end
	end)

	-- The checks' runner only goes +x, so a blinking patch on a leg that runs back (Hairpins) or in a lane beside a
	-- free one (Fork) is never measured there: time those patches here, as a runner setting off from where it
	-- waits at walking speed.
	it("gives the blinking goo patches their tier's window", function()
		for _, case in ObbyCheck.cases(IceSlide :: any) do
			for _, part in case.build(1).parts do
				local m = part.motion
				if part.hazard and m and m.kind == "flip" then
					local period = Kit.periodOf(part)
					local off = period * (1 - (m.duty :: number))
					local x0, x1 = Kit.bounds(part)
					local cross = (x1 - x0 + 2 * ObbyCheck.BODY) / Kit.WALK
					local window = off - cross
					local band = BAND[case.tier]
					if window < band.lo - 1e-6 or window > band.hi + 1e-6 then
						error(
							`{case.name}: a blinking patch is out for {window} s past its crossing ({band.lo}..{band.hi})`
						)
					end
				end
			end
		end
	end)

	-- On ice you can't stop and the stick only steers at a quarter of a normal start, so a goo layout the fairness
	-- runner (who sidesteps at 8 studs/s and can wait anywhere) clears may still be impossible on a slide.
	it("can be steered through on ice (every straight variant, every route)", function()
		for _, v in IceSlide.variants do
			if not UNPLANNED[v.name] then
				local section = v.build(1)
				for _, route in ObbyCheck.routes(section) do
					local died = steerable(section, if route == "main" then nil else route)
					if died then
						error(`{v.name} ({route}): no line steers through; every slider is stopped by x {died}`)
					end
				end
			end
		end
	end)

	-- Hopping a short goo patch at slide speed would skip the steering. A patch (with the goo touching it) must be
	-- longer than a slide jump clears, unless the ice before and after it is so far apart that the hop is a jump
	-- over holes too (Red Run's landings). Goo posts taller than a jump are walls, not patches; turned goo (the
	-- corkscrew's bites, the fork's nose) only narrows a line, and its box is not its shape.
	it("has no goo patch you can just hop at slide speed", function()
		for _, v in IceSlide.variants do
			local section = v.build(1)
			local patches = {}
			for _, part in section.parts do
				if part.hazard and not part.motion and not part.yaw and part.size[2] < Kit.JUMP_HEIGHT then
					local x0, x1, _, _, z0, z1 = Kit.bounds(part)
					table.insert(patches, { x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
				end
			end
			-- merge goo that touches into one patch
			local merged = true
			while merged do
				merged = false
				for i = 1, #patches do
					for j = i + 1, #patches do
						local a, b = patches[i], patches[j]
						if a.x0 <= b.x1 + 0.5 and b.x0 <= a.x1 + 0.5 and a.z0 <= b.z1 + 0.5 and b.z0 <= a.z1 + 0.5 then
							a.x0, a.x1 = math.min(a.x0, b.x0), math.max(a.x1, b.x1)
							a.z0, a.z1 = math.min(a.z0, b.z0), math.max(a.z1, b.z1)
							table.remove(patches, j)
							merged = true
							break
						end
					end
					if merged then
						break
					end
				end
			end
			for _, p in patches do
				-- the slide ice under the patch's middle: its cap and slope
				local mid, cap, deg = (p.x0 + p.x1) / 2, 0, 0
				for _, part in section.parts do
					if part.slide then
						local x0, x1 = Kit.bounds(part)
						if mid >= x0 and mid <= x1 then
							cap = math.max(cap, part.slide.cap)
							deg = math.max(deg, -(part.roll or 0))
						end
					end
				end
				if cap > 0 then
					local need = hopLength(cap, deg)
					-- the shortest take-off to landing over this patch along any line through it
					local best = math.huge
					local z = p.z0 + 0.25
					while z < p.z1 do
						local from, to = -math.huge, math.huge
						for _, part in section.parts do
							if part.step then
								local x0, x1, _, _, z0, z1 = Kit.bounds(part)
								if z >= z0 and z <= z1 then
									if x0 <= p.x0 - ObbyCheck.BODY then
										from = math.max(from, math.min(x1, p.x0 - ObbyCheck.BODY))
									end
									if x1 >= p.x1 + ObbyCheck.BODY then
										to = math.min(to, math.max(x0, p.x1 + ObbyCheck.BODY))
									end
								end
							end
						end
						best = math.min(best, to - from)
						z += 0.5
					end
					if best < need then
						error(
							`{v.name}: the goo at x {p.x0}..{p.x1} can be hopped ({best} studs, a slide jump clears {need})`
						)
					end
				end
			end
		end
	end)
end)
