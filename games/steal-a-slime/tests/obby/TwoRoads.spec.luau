--!strict
-- Two Roads (obby idea 11): every variant through ObbyCheck, plus what the shared checks can't see on a section with
-- several roads side by side: each road on its own is makeable, fair and blocks a straight walk (the shared runner and
-- walker may lean on the other road), the fast road really is quicker than the safe one, the bail-out plank and the
-- cracked-tile drop lead somewhere, and every branch is marked.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local TwoRoads = require("../../src/shared/ObbySections/TwoRoads")

type Part = Kit.Part
type Section = Kit.Section

local EPS = 0.01
-- Hazard windows a tier earns (contract §10); a window longer than STILL s is a still hazard (steer round it).
local BAND = {
	easy = { lo = 1.4, hi = 2.0 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}
local STILL = 5

local function variantNamed(name: string): Kit.Variant
	for _, v in TwoRoads.variants do
		if v.name == name then
			return v
		end
	end
	error(`no variant {name}`)
end

-- One road as a section of its own: the steps `keep` says yes to, in walking order (by where they start) and with
-- their route tags taken off, so the shared checks see one main path; every part that is not a step stays.
local function withSteps(section: Section, keep: (Part) -> boolean): Section
	local parts, steps = {}, {}
	for _, part in section.parts do
		if not part.step then
			table.insert(parts, part)
		elseif keep(part) then
			local copy = table.clone(part)
			copy.route = nil
			table.insert(steps, copy)
		end
	end
	table.sort(steps, function(a, b)
		return (Kit.bounds(a)) < (Kit.bounds(b))
	end)
	table.move(steps, 1, #steps, #parts + 1, parts)
	return { length = section.length, rise = section.rise, parts = parts }
end

local function xRange(part: Part): (number, number)
	local x0, x1 = Kit.bounds(part)
	return x0, x1
end

-- The shared pads every road starts and ends on.
local function isEnd(section: Section, part: Part): boolean
	local x0, x1 = xRange(part)
	return x1 <= 8 + EPS or x0 >= section.length - 8 - EPS
end

-- One road alone: "main" = the untagged steps; a route = its own steps between the shared entry and exit.
local function onlyRoute(section: Section, route: string): Section
	return withSteps(section, function(part)
		if route == "main" then
			return part.route == nil
		end
		return part.route == route or (part.route == nil and isEnd(section, part))
	end)
end

-- Roads that are not "own steps between entry and exit": the forks' fast pads come back to the join pad, the plank
-- leaves the fast road for the safe one, and the secret beam is reached by standing on the cracked tile.
local CUSTOM: { [string]: { [string]: (Section) -> Section } } = {
	["Two Forks"] = {
		fast1 = function(section: Section): Section
			return withSteps(section, function(part)
				return part.route == "fast1" or (part.route == nil and xRange(part) >= 42 - EPS)
			end)
		end,
		fast2 = function(section: Section): Section
			return withSteps(section, function(part)
				local _, x1 = xRange(part)
				return part.route == "fast2" or (part.route == nil and (x1 <= 52 + EPS or isEnd(section, part)))
			end)
		end,
	},
	["Bail Out"] = {
		bail = function(section: Section): Section
			local px = 0
			for _, part in section.parts do
				if part.route == "bail" then
					px = part.pos[1]
				end
			end
			return withSteps(section, function(part)
				local _, x1 = xRange(part)
				if part.route == "bail" then
					return true
				elseif part.route == "fast" then
					return xRange(part) < px -- the fast pads up to the plank
				end
				return part.route == nil and (x1 <= 8 + EPS or x1 > px) -- the entry, the safe pads past it, the exit
			end)
		end,
	},
	["Cracked Shortcut"] = {
		secret = function(section: Section): Section
			local beamFrom = math.huge
			for _, part in section.parts do
				if part.route == "secret" then
					beamFrom = math.min(beamFrom, (xRange(part)))
				end
			end
			return withSteps(section, function(part)
				local _, x1 = xRange(part)
				if part.route == "secret" or (part.motion and part.motion.kind == "melt") then
					return true -- the beam, and the cracked tile over it
				end
				return part.route == nil and (x1 <= beamFrom - 5 or isEnd(section, part)) -- entry, first pad, exit
			end)
		end,
	},
}

local function roadsOf(name: string, section: Section): { [string]: Section }
	local out = {}
	for _, route in ObbyCheck.routes(section) do
		local custom = CUSTOM[name] and CUSTOM[name][route]
		out[route] = if custom then custom(section) else onlyRoute(section, route)
	end
	return out
end

-- True when two parts overlap seen from above (at rest).
local function overlapXZ(a: Part, b: Part): boolean
	local ax0, ax1, _, _, az0, az1 = Kit.bounds(a)
	local bx0, bx1, _, _, bz0, bz1 = Kit.bounds(b)
	return ax0 < bx1 and bx0 < ax1 and az0 < bz1 and bz0 < az1
end

-- The average wait at a flip for a runner arriving at a random time: a blinking pad while it is away, a beat gate
-- while it is shut (a fraction f of a period p away: f * f * p / 2).
local function waitAt(part: Part): number
	local m = part.motion
	if not m or m.kind ~= "flip" or m.solid then
		return 0
	end
	local duty = m.duty or 0.5
	local away = if part.step then 1 - duty else duty
	return away * away * Kit.periodOf(part) / 2
end

-- A runner's time along a road's steps: centre to centre at walking speed, the time lost per jump (a hole to cross
-- or a ledge to climb; dropping down a ledge is no jump) and the average wait at its blinking pads and beat gates.
local function estimate(road: Section): (number, number)
	local time, jumps, last = 0, 0, nil
	local steps = {}
	for _, part in road.parts do
		if part.step then
			table.insert(steps, part)
			time += waitAt(part)
			if last then
				local dx, dy, dz = part.pos[1] - last.pos[1], part.pos[2] - last.pos[2], part.pos[3] - last.pos[3]
				time += math.sqrt(dx * dx + dy * dy + dz * dz) / Kit.WALK
				local _, a1, _, topA = Kit.bounds(last)
				local b0, _, _, topB = Kit.bounds(part)
				if b0 - a1 > 0.5 or topB - topA > 0.5 then
					jumps += 1
					time += Kit.JUMP_LOSS
				end
			end
			last = part
		end
	end
	for _, part in road.parts do
		if not part.step and not part.hazard and waitAt(part) > 0 then
			for _, step in steps do
				if overlapXZ(part, step) then
					time += waitAt(part)
					break
				end
			end
		end
	end
	return time, jumps
end

describe("TwoRoads", function()
	it("is idea 11 with every variant of the design file, hand-made", function()
		expect(TwoRoads.id).toBe("TwoRoads")
		expect(TwoRoads.name).toBe("Two Roads")
		expect(TwoRoads.idea).toBe(11)
		expect(#TwoRoads.variants).toBe(19)
		expect(TwoRoads.generator).toBeNil()
		local tiers = { easy = 0, medium = 0, hard = 0 }
		for _, v in TwoRoads.variants do
			tiers[v.tier] += 1
		end
		expect(tiers.easy).toBe(6)
		expect(tiers.medium).toBe(8)
		expect(tiers.hard).toBe(5)
	end)

	it("passes every shared check", function()
		local problems = {}
		for _, case in ObbyCheck.cases(TwoRoads) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("has at least two roads in every variant, each road with its own marker", function()
		local problems = {}
		for _, v in TwoRoads.variants do
			local section = v.build(1)
			local routes = ObbyCheck.routes(section)
			if #routes < 2 then
				table.insert(problems, `{v.name}: one road`)
			end
			for _, route in routes do
				local marked = false
				for _, part in section.parts do
					local mine = if route == "main" then part.route == nil else part.route == route
					if mine and part.step and (part.marker or (part.motion and part.motion.kind == "melt")) then
						marked = true
					end
				end
				if not marked then
					table.insert(problems, `{v.name}: road {route} has no marker`)
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("makes every road on its own: makeable, fair for its tier, and no straight walk clears it", function()
		local problems = {}
		for _, v in TwoRoads.variants do
			local section = v.build(1)
			for route, road in roadsOf(v.name, section) do
				local label = `{v.name} road {route}`
				local made = ObbyCheck.makeable(road)
				if made then
					table.insert(problems, `{label}: makeable: {made}`)
				end
				local fair = ObbyCheck.fairness(road, v.tier)
				if fair then
					table.insert(problems, `{label}: fairness: {fair}`)
				end
				local walk = ObbyCheck.straightWalk(road)
				if walk then
					table.insert(problems, `{label}: straightWalk: {walk}`)
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("keeps every road's moving-hazard windows in its tier's band (contract §10)", function()
		local problems = {}
		for _, v in TwoRoads.variants do
			local band = BAND[v.tier]
			for route, road in roadsOf(v.name, v.build(1)) do
				for _, w in ObbyCheck.windows(road) do
					if w.slack < STILL and (w.slack < band.lo - EPS or w.slack > band.hi + EPS) then
						table.insert(
							problems,
							`{v.name} road {route}: x {w.from}..{w.to} open {w.slack} s ({band.lo}..{band.hi})`
						)
					end
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("makes the short road pay: a fast road takes less time than the safe road, a top road fewer jumps", function()
		local problems = {}
		for _, v in TwoRoads.variants do
			local roads = roadsOf(v.name, v.build(1))
			local safeTime, safeJumps = estimate(roads.main)
			local quick = 0
			for route, road in roads do
				local fast = string.sub(route, 1, 4) == "fast"
				if fast or route == "top" then
					quick += 1
					local time, jumps = estimate(road)
					if (fast and time >= safeTime) or (not fast and jumps >= safeJumps) then
						table.insert(
							problems,
							`{v.name}: {route} takes {time} s / {jumps} jumps, the safe road {safeTime} s / {safeJumps}`
						)
					end
				end
			end
			if quick == 0 and v.name ~= "Cracked Shortcut" then
				table.insert(problems, `{v.name}: no short road`)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("lets the bail-out plank join the safe road and the cracked tile drop onto the secret beam", function()
		local bail = roadsOf("Bail Out", variantNamed("Bail Out").build(1)).bail
		local fastPads, plank = 0, false
		for _, part in bail.parts do
			if part.step and part.look == "goo" then
				fastPads += 1
			end
			plank = plank or part.look == "beam"
		end
		expect(fastPads).toBe(2) -- two fast pads, then the plank
		expect(plank).toBe(true)
		expect(ObbyCheck.makeable(bail)).toBeNil()

		local secret = roadsOf("Cracked Shortcut", variantNamed("Cracked Shortcut").build(1)).secret
		expect(ObbyCheck.makeable(secret)).toBeNil()
		-- The beam runs under the cracked tile, 5 studs down, so standing on the tile is how you reach it.
		local tile, beam
		for _, part in secret.parts do
			if part.motion and part.motion.kind == "melt" then
				tile = part
			elseif part.step and part.look == "beam" then
				beam = part
			end
		end
		local _, _, _, tileTop, tz0, tz1 = Kit.bounds(tile)
		local bx0, _, _, beamTop, bz0, bz1 = Kit.bounds(beam)
		expect(math.abs(tileTop - beamTop - 5) < EPS).toBe(true)
		expect(bx0 < tile.pos[1] and bz0 >= tz0 - EPS and bz1 <= tz1 + EPS).toBe(true)
	end)

	it("shuts the door of Door Behind You only after its trigger, and leaves time to reach it", function()
		local section = variantNamed("Door Behind You").build(1)
		local door, trigger
		for _, part in section.parts do
			if part.start == "door" then
				door = part
			elseif part.trigger == "door" then
				trigger = part
			end
		end
		expect(door ~= nil and trigger ~= nil).toBe(true)
		local m = door.motion :: Kit.Motion
		-- At rest (clock not started) the door hangs above head height over its pad; at the end it is down.
		local _, dyRest = Kit.offsetAt(door, nil)
		local _, dyEnd = Kit.offsetAt(door, (m.period :: number) + 1)
		local _, _, bottom = Kit.bounds(door)
		local padTop = -math.huge
		for _, part in section.parts do
			local x0, x1, _, top = Kit.bounds(part)
			if part.step and part.route == nil and x0 <= door.pos[1] and x1 >= door.pos[1] then
				padTop = top
			end
		end
		expect(bottom + dyRest > padTop + Kit.HEAD + Kit.JUMP_HEIGHT).toBe(true)
		expect(bottom + dyEnd <= padTop + EPS).toBe(true)
		-- A runner from the trigger, at walking speed and losing JUMP_LOSS per hop, passes it a second early.
		local reach = (door.pos[1] - trigger.pos[1]) / Kit.WALK + 4 * Kit.JUMP_LOSS
		expect(reach + 1 <= (m.hold :: number)).toBe(true)
	end)
end)
