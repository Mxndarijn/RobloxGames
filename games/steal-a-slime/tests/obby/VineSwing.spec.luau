--!strict
-- Vine Swing (obby idea 15): every variant through ObbyCheck, plus what the shared checks don't size, all on the
-- rope physics the game runs (src/shared/ObbySections/Vine, ObbyMoves' vine controller):
--   * the let-go window: in one full (pumped) swing, the longest stretch a let go lands on the next step sits in
--     the tier's band (contract §10: wide on easy, tight on hard, never the whole swing);
--   * a player bot (pumps, lets go when the flight gets it on) clears every variant from nearly every start time;
--   * a masher bot (holds forward, jumps on every landing, lets go as soon as it can) almost never does;
--   * Snapping Vine's flood leaves the bot a second or two.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local Vine = require("../../src/shared/ObbySections/Vine")
local VineSwing = require("../../src/shared/ObbySections/VineSwing")

type Part = Kit.Part

-- Seconds of one pumped swing a let go lands on the next step (contract §10): at least `lo`, at most `hi`.
local BAND = {
	easy = { lo = 0.3, hi = 0.8 },
	medium = { lo = 0.2, hi = 0.45 },
	hard = { lo = 0.15, hi = 0.3 },
}
local BOT_SHARE = 0.9 -- the player bot clears every variant from at least this share of start times
local MASHER_SHARE = 0.2 -- the masher bot from at most this share (ObbyCheck.MASHER_SHARE)
local STARTS = 40 -- start times tried, STARTS_STEP s apart
local STARTS_STEP = 0.29
local DT = 1 / 120
local JUMP = math.sqrt(2 * Kit.GRAVITY * Kit.JUMP_HEIGHT)
local REGRAB = 1.2 -- seconds before the rope you let go of grabs you again (ObbyMoves.REGRAB_SAME)

local function steps(section: Kit.Section): { Part }
	local out = {}
	for _, p in section.parts do
		if p.step then
			table.insert(out, p)
		end
	end
	return out
end

local function hazardsOf(section: Kit.Section): { Part }
	local out = {}
	for _, p in section.parts do
		if p.hazard and not (p.motion and (p.motion.kind == "rise" or p.motion.kind == "flood")) then
			table.insert(out, p)
		end
	end
	return out
end

-- The longest stretch (s) of one swing at AMP_MAX in which letting go of rope `a` lands on step `b`, at the best
-- time for the moving hazards (VINE_PHASES points over their longest period).
local function releaseWindow(a: Part, b: Part, hazards: { Part }): number
	local rope = ObbyCheck.ropeOf(a)
	local amp = Vine.ampMax()
	local d = math.rad(0.25)
	local n = math.floor(2 * amp / d)
	local period = 0
	for _, h in hazards do
		if h.motion then
			period = math.max(period, Kit.periodOf(h))
		end
	end
	local times: { number } = { -1 }
	if period > 0 then
		times = {}
		for k = 0, ObbyCheck.VINE_PHASES - 1 do
			table.insert(times, k / ObbyCheck.VINE_PHASES * period)
		end
	end
	local best = 0
	for _, t in times do
		for _, sign in { 1, -1 } do
			local run, clock = 0, 0
			for k = 0, n - 1 do
				local th = sign * (-amp + (k + 0.5) * d)
				local w = sign * Vine.speedAt(rope.arm, th, amp)
				local dt = d / math.max(math.abs(w), 1e-3)
				if ObbyCheck.vineLands(rope, th, w, b, hazards, if t >= 0 then t + clock else nil) then
					run += dt
					best = math.max(best, run)
				else
					run = 0
				end
				clock += dt
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- The bots: a box body (feet to head) on the course, the ropes and hazards on server time
---------------------------------------------------------------------------

type Entry = { part: Part, index: number }
type World = {
	list: { Part },
	floors: { Entry },
	ropes: { Entry },
	ladders: { Entry },
	hazards: { Part },
	lowest: number,
	phi: number, -- the server time the run starts at
}

local function worldOf(section: Kit.Section, phi: number): World
	local w: World = {
		list = steps(section),
		floors = {},
		ropes = {},
		ladders = {},
		hazards = hazardsOf(section),
		lowest = math.huge,
		phi = phi,
	}
	for i, p in w.list do
		local e = { part = p, index = i }
		if p.vine then
			table.insert(w.ropes, e)
		elseif p.shape == "truss" then
			table.insert(w.ladders, e)
		else
			table.insert(w.floors, e)
		end
		local _, _, y0 = Kit.bounds(p)
		w.lowest = math.min(w.lowest, y0)
	end
	return w
end

local function knobAt(w: World, p: Part, t: number): (number, number, number)
	local dx, dy, dz = Kit.offsetAt(p, w.phi + t)
	return p.pos[1] + dx, p.pos[2] + dy, p.pos[3] + dz
end

-- The idle rope's angular speed (radians/s) at time t.
local function idleSpeed(w: World, p: Part, t: number): number
	local m = p.motion :: Kit.Motion
	local period = Kit.periodOf(p)
	local cycle = (w.phi + t) / period + (m.phase or 0)
	return math.rad(m.amp or 0) * 2 * math.pi / period * math.cos(2 * math.pi * cycle)
end

type Body = { x: number, y: number, z: number, vx: number, vy: number, vz: number }
type Last = { part: Part?, at: number }

-- What the body meets at time t: "dead", "rope" or "ladder" (with its entry), or nil.
local function meet(w: World, b: Body, t: number, last: Last): (string?, Entry?)
	for _, h in w.hazards do
		local x0, x1, y0, y1, z0, z1 = Kit.bounds(h)
		if h.motion then
			local dx, dy, dz = Kit.offsetAt(h, w.phi + t)
			x0, x1, y0, y1, z0, z1 = x0 + dx, x1 + dx, y0 + dy, y1 + dy, z0 + dz, z1 + dz
		end
		if
			b.x >= x0 - 0.5
			and b.x <= x1 + 0.5
			and b.z >= z0 - 0.5
			and b.z <= z1 + 0.5
			and b.y - Vine.FEET <= y1
			and b.y + Vine.HEAD >= y0
		then
			return "dead", nil
		end
	end
	if b.y < w.lowest - 20 then
		return "dead", nil
	end
	for _, r in w.ropes do
		if r.part == last.part and t - last.at < REGRAB then
			continue
		end
		local kx, ky, kz = knobAt(w, r.part, t)
		if Vine.touches(b.x, b.y, b.z, kx, ky, kz, (r.part.vine :: any).reach) then
			return "rope", r
		end
	end
	for _, l in w.ladders do
		local x0, x1, y0, y1, z0, z1 = Kit.bounds(l.part)
		local gx = math.max(x0 - b.x, b.x - x1, 0)
		local gz = math.max(z0 - b.z, b.z - z1, 0)
		if math.sqrt(gx * gx + gz * gz) <= 1.5 and b.y - Vine.FEET <= y1 and b.y + Vine.HEAD >= y0 then
			return "ladder", l
		end
	end
	return nil, nil
end

-- The floor under (x, z) whose top the feet come down onto (from `before` to `feet`), or nil.
local function floorAt(w: World, x: number, z: number, before: number, feet: number): Entry?
	for _, f in w.floors do
		local x0, x1, _, y1, z0, z1 = Kit.bounds(f.part)
		if before >= y1 - 1e-6 and feet <= y1 + 1e-6 and x >= x0 and x <= x1 and z >= z0 and z <= z1 then
			return f
		end
	end
	return nil
end

-- Flies a body, steering along (ux, uz) up to walk speed, until it meets something. Returns what and when.
local function fly(
	w: World,
	b: Body,
	t: number,
	last: Last,
	limit: number,
	ux: number,
	uz: number
): (string, Entry?, number)
	local g = Kit.GRAVITY
	local stop = t + limit
	while t < stop do
		local before = b.y - Vine.FEET
		local along = b.vx * ux + b.vz * uz
		if along < Kit.WALK then
			local add = math.min(Kit.WALK - along, Vine.STEER * DT)
			b.vx += ux * add
			b.vz += uz * add
		end
		b.x += b.vx * DT
		b.z += b.vz * DT
		b.y += b.vy * DT - 0.5 * g * DT * DT
		b.vy -= g * DT
		t += DT
		local what, e = meet(w, b, t, last)
		if what then
			return what, e, t
		end
		local f = floorAt(w, b.x, b.z, before, b.y - Vine.FEET)
		if f then
			local _, _, _, y1 = Kit.bounds(f.part)
			b.y = y1 + Vine.FEET
			b.vy = 0
			return "floor", f, t
		end
	end
	return "dead", nil, t
end

--[[
	Runs a bot through the section from the start of the entry pad at server time `phi`. "player": walks at the next
	step and jumps as soon as a jump gets it on; on a rope pumps with the swing and lets go as soon as the flight gets
	it on. "masher": holds forward (+x) on its line, jumps on every landing, lets go once the grace is over. Returns
	whether it reached the last step and the time it took.
]]
local function run(section: Kit.Section, phi: number, kind: string): (boolean, number)
	local w = worldOf(section, phi)
	local final = #w.list
	local entry = w.list[1]
	local ex0, _, _, ey1 = Kit.bounds(entry)
	local b: Body = { x = ex0 + 1, y = ey1 + Vine.FEET, z = entry.pos[3], vx = 0, vy = 0, vz = 0 }
	local t = 0
	local at = 1
	local floor: Part? = entry
	local last: Last = { part = nil, at = -math.huge }
	local LIMIT = 45
	-- the way the bot holds the stick: the masher straight on, the player at the next step
	local function aim(): (number, number)
		if kind == "masher" then
			return 1, 0
		end
		local nxt = w.list[math.min(at + 1, final)]
		local dx, dz = nxt.pos[1] - b.x, nxt.pos[3] - b.z
		local n = math.sqrt(dx * dx + dz * dz)
		if n < 1e-6 then
			return 1, 0
		end
		return dx / n, dz / n
	end
	local grabbed: Entry? = nil
	while t < LIMIT do
		if floor then
			if at == final then
				return true, t
			end
			local ux, uz = aim()
			local jump = kind == "masher"
			if not jump then
				local probe = { x = b.x, y = b.y, z = b.z, vx = ux * Kit.WALK, vy = JUMP, vz = uz * Kit.WALK }
				local what, e = fly(w, probe, t, last, 2, ux, uz)
				jump = what ~= "dead" and e ~= nil and e.index > at
			end
			if jump then
				b.vx, b.vy, b.vz = ux * Kit.WALK, JUMP, uz * Kit.WALK
				floor = nil
			else
				-- walk on, but never off the floor's edge (the player waits there)
				local x0, x1, _, y1, z0, z1 = Kit.bounds(floor)
				b.x = math.clamp(b.x + ux * Kit.WALK * DT, x0 + 0.5, x1 - 0.5)
				b.z = math.clamp(b.z + uz * Kit.WALK * DT, z0 + 0.5, z1 - 0.5)
				b.y = y1 + Vine.FEET
				t += DT
				local what, e = meet(w, b, t, last)
				if what == "dead" then
					return false, t
				elseif what == "rope" and e and e.index > at then
					grabbed = e
				end
				if not grabbed then
					continue
				end
			end
		end
		local what: string, e: Entry? = "rope", grabbed
		if not grabbed then
			local ux, uz = aim()
			local t2
			what, e, t2 = fly(w, b, t, last, 3, ux, uz)
			t = t2
		end
		grabbed = nil
		if what == "dead" or e == nil then
			return false, t
		elseif what == "floor" then
			floor = e.part
			at = math.max(at, e.index)
			b.vx, b.vz = 0, 0
			continue
		elseif what == "ladder" then
			-- climbs it: out onto the step after it
			at = math.max(at, e.index + 1)
			local top = w.list[math.min(e.index + 1, final)]
			local tx0, _, _, ty1 = Kit.bounds(top)
			b.x, b.y, b.vy, b.vx, b.vz = tx0 + 1, ty1 + Vine.FEET, 0, 0, 0
			floor = top
			t += 1
			continue
		end
		-- a rope: hold it
		local rope = e.part
		at = math.max(at, e.index)
		local r = ObbyCheck.ropeOf(rope)
		local s = (b.x - r.px) * r.ux + (b.z - r.pz) * r.uz
		local vs = b.vx * r.ux + b.vz * r.uz
		local th, om = Vine.grab(r.arm, s, b.y - r.py, vs, b.vy, idleSpeed(w, rope, t))
		local held = t
		local released = false
		local ux, uz = aim()
		while t - held < 20 do
			local push = if kind == "masher" then r.ux elseif om >= 0 then 1 else -1
			th, om = Vine.step(r.arm, th, om, push, DT)
			t += DT
			if t - held >= Vine.GRACE then
				local x, y, z, vx, vy, vz = ObbyCheck.letGo(r, th, om)
				local go = kind == "masher"
				if not go then
					local probe = { x = x, y = y, z = z, vx = vx, vy = vy, vz = vz }
					local pw, pe = fly(w, probe, t, { part = rope, at = t }, 2, ux, uz)
					go = pw ~= "dead" and pe ~= nil and pe.index > at
				end
				if go then
					b = { x = x, y = y, z = z, vx = vx, vy = vy, vz = vz }
					last = { part = rope, at = t }
					released = true
					break
				end
			end
		end
		if not released then
			return false, t
		end
	end
	return false, t
end

local function shareOf(section: Kit.Section, kind: string): (number, number)
	local wins, worst = 0, 0
	for k = 0, STARTS - 1 do
		local ok, took = run(section, k * STARTS_STEP, kind)
		if ok then
			wins += 1
			worst = math.max(worst, took)
		end
	end
	return wins / STARTS, worst
end

describe("VineSwing", function()
	it("every variant passes ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(VineSwing) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("every let go has the tier's window in a full swing, and no more", function()
		local problems = {}
		for _, v in VineSwing.variants do
			local section = v.build(1)
			local list = steps(section)
			local hazards = hazardsOf(section)
			local band = BAND[v.tier]
			for i = 2, #list do
				local a = list[i - 1]
				if a.vine then
					local s = releaseWindow(a, list[i], hazards)
					if s < band.lo - 1e-6 or s > band.hi + 1e-6 then
						local shown = math.floor(s * 100 + 0.5) / 100
						table.insert(problems, `{v.name} ({v.tier}) step {i}: {shown} s ({band.lo}..{band.hi})`)
					end
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("a player bot clears every variant, a masher bot almost never does", function()
		local problems = {}
		for _, v in VineSwing.variants do
			local section = v.build(1)
			local good = shareOf(section, "player")
			local mash = shareOf(section, "masher")
			if good < BOT_SHARE then
				table.insert(problems, `{v.name}: the player bot clears it from {good * 100}% of start times`)
			end
			if mash > MASHER_SHARE then
				table.insert(problems, `{v.name}: the masher bot clears it from {mash * 100}% of start times`)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("Snapping Vine's flood reaches a hanging player 1..3 s after the player bot's slowest run", function()
		local section: Kit.Section? = nil
		for _, v in VineSwing.variants do
			if v.name == "Snapping Vine" then
				section = v.build(1)
			end
		end
		assert(section, "Snapping Vine is a variant")
		local flood, lowest = nil, math.huge
		for _, p in section.parts do
			if p.motion and p.motion.kind == "rise" then
				flood = p
			elseif p.vine then
				lowest = math.min(lowest, p.pos[2])
			end
		end
		assert(flood and flood.motion, "Snapping Vine has a flood")
		local m = flood.motion :: Kit.Motion
		-- a hanging player's feet at rest: the knob's centre in the hands, the root GRIP under it, then the legs
		local feet = lowest - Vine.GRIP - Vine.FEET
		local restTop = flood.pos[2] + flood.size[2] / 2
		expect(restTop + (m.stop :: number) >= feet - 1e-6).toBe(true)
		local touch = (m.delay or 0) + (feet - restTop) / (m.speed :: number)
		local share, worst = shareOf(section, "player")
		expect(share >= BOT_SHARE).toBe(true)
		expect(touch >= worst + 1 - 1e-6).toBe(true)
		expect(touch <= worst + 3 + 1e-6).toBe(true)
	end)
end)
