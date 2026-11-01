--!strict
-- Geyser Field (obby idea 21): every variant through ObbyCheck, plus what the shared checks can't see: the geysers are
-- the only way up (take them away and nothing can be made, and no climb is a plain jump), and every geyser window
-- sits in its tier's band (contract §10): arriving at a vent under a red column, a one-shot's fuse, catching a pit
-- column and walking from one into the next, a red pool's dry spell past its crossing. Chains that the design asks
-- for (Chain Reaction, Summit Spouts, Third Time's puffs) are checked against the real flight times.
local T = require("../TestRunner")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local describe, it, expect = T.describe, T.it, T.expect
local GeyserField = require("../../src/shared/ObbySections/GeyserField")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

local idea: Kit.Idea = GeyserField :: any

local BAND = {
	easy = { lo = 1.4, hi = 2.0 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}
local DT = 0.01
local HORIZON = 40 -- seconds sampled for a window (several periods of every beat used)
local EPS = 0.02
local ROOT = 3 -- a lift holds the root, about 3 over the feet (ObbyFx)
local HOVER_GAIN = 4 -- ObbyFx.LIFT_HOVER_GAIN
local DESCEND = 0.1 -- seconds you spend dropping through a red column's height before you land under it
local CLEAR = 0.25 -- seconds after a throw before you are over a red column's top
local JUMP_IN = 0.2 -- seconds of air jumping off an edge into a column
local STEP_OFF = 0.3 -- seconds to step out of a column onto the ledge beside it

local function onAt(p: Kit.Part, t: number): boolean
	local _, _, _, _, _, on = Kit.offsetAt(p, t)
	return on
end

local function isVent(p: Kit.Part): boolean
	return p.step == true and p.motion ~= nil and p.motion.kind == "bounce"
end

local function isColumn(p: Kit.Part): boolean
	return p.step == true and p.motion ~= nil and p.motion.kind == "lift"
end

local function isRed(p: Kit.Part): boolean
	return p.hazard == true and p.motion ~= nil and p.motion.kind == "flip"
end

-- A red curtain across the whole lane in a gap between islands (you fly through it, you never walk past it).
local function isCurtain(p: Kit.Part): boolean
	return isRed(p) and p.shape ~= "disc" and p.size[3] >= Kit.WIDTH
end

local function top(p: Kit.Part): number
	local _, _, _, y1 = Kit.bounds(p)
	return y1
end

-- Edge-to-edge distance between two parts' boxes seen from above.
local function gapOf(a: Kit.Part, b: Kit.Part): number
	local ax0, ax1, _, _, az0, az1 = Kit.bounds(a)
	local bx0, bx1, _, _, bz0, bz1 = Kit.bounds(b)
	local gx = math.max(0, bx0 - ax1, ax0 - bx1)
	local gz = math.max(0, bz0 - az1, az0 - bz1)
	return math.sqrt(gx * gx + gz * gz)
end

local function overlaps(a: Kit.Part, b: Kit.Part): boolean
	local ax0, ax1, ay0, ay1, az0, az1 = Kit.bounds(a)
	local bx0, bx1, by0, by1, bz0, bz1 = Kit.bounds(b)
	return ax0 < bx1 and bx0 < ax1 and az0 < bz1 and bz0 < az1 and ay0 < by1 + Kit.HEAD and by0 < ay1 + Kit.HEAD
end

-- The longest stretch of start times t in [0, HORIZON] for which good(t) holds.
local function longestRun(good: (number) -> boolean): number
	local best, run = 0, 0
	for k = 0, math.floor(HORIZON / DT) do
		if good(k * DT) then
			run += DT
			best = math.max(best, run)
		else
			run = 0
		end
	end
	return best
end

-- Seconds a lift (gain HOVER_GAIN, top speed `power`) takes to bring you within a stud of a hover `d` studs over you.
local function riseTime(d: number, power: number): number
	if d <= 1 then
		return 0
	end
	local k = power / HOVER_GAIN -- under this far it eases in
	if d > k then
		return (d - k) / power + math.log(k) / HOVER_GAIN
	end
	return math.log(d) / HOVER_GAIN
end

-- Feet height a capped column holds you at.
local function hoverOf(c: Kit.Part): number
	local _, _, y0 = Kit.bounds(c)
	return y0 + (c.motion :: Kit.Motion).cap :: number - ROOT
end

-- Air time of a throw at `v` up landing `rise` studs higher.
local function flight(v: number, rise: number): number
	return (v + math.sqrt(v * v - 2 * Kit.GRAVITY * rise)) / Kit.GRAVITY
end

-- The red columns over a vent.
local function guardsOf(section: Kit.Section, v: Kit.Part): { Kit.Part }
	local out = {}
	for _, p in section.parts do
		if isRed(p) and overlaps(p, v) then
			table.insert(out, p)
		end
	end
	return out
end

-- Can you step onto vent `v` at time t and be thrown before a red column over it blows again?
local function arrivesAt(v: Kit.Part, guards: { Kit.Part }, t: number): boolean
	local period = Kit.periodOf(v)
	local launch: number? = nil
	local s = t
	while s <= t + period + EPS do
		if onAt(v, s) then
			launch = s
			break
		end
		s += DT
	end
	if launch == nil then
		return false
	end
	local u = t - DESCEND
	while u <= launch + CLEAR do
		for _, g in guards do
			if onAt(g, u) then
				return false
			end
		end
		u += DT
	end
	return true
end

type Window = { what: string, seconds: number }

-- Every timing window of a section that its tier is held to.
local function windowsOf(section: Kit.Section): { Window }
	local out: { Window } = {}
	local steps = {}
	for _, p in section.parts do
		if p.step then
			table.insert(steps, p)
		end
	end
	local guarding: { [Kit.Part]: boolean } = {}
	for i, p in steps do
		if isVent(p) then
			local guards = guardsOf(section, p)
			if #guards > 0 then
				for _, g in guards do
					guarding[g] = true
				end
				table.insert(out, {
					what = `vent (step {i}) under a red column`,
					seconds = longestRun(function(t)
						return arrivesAt(p, guards, t)
					end),
				})
			end
			if p.start then
				-- a one-shot: the fuse from touching its bubbles to the blow
				local s = 0
				while not onAt(p, s) do
					s += DT
				end
				table.insert(out, { what = `one-shot vent (step {i}) fuse`, seconds = s })
			end
		elseif isColumn(p) then
			local m = p.motion :: Kit.Motion
			local prev = steps[i - 1]
			local hover = hoverOf(p)
			if isColumn(prev) then
				-- walk out of the last column at its hover and drop into this one
				local fall = gapOf(prev, p) / Kit.WALK
				local feet = hoverOf(prev) - Kit.GRAVITY * fall * fall / 2
				local rise = riseTime(hover - feet, m.power :: number)
				table.insert(out, {
					what = `column (step {i}) from the column before`,
					seconds = longestRun(function(t)
						if not onAt(prev, t) then
							return false
						end
						local u = t + fall
						while u <= t + fall + rise + 0.1 do
							if not onAt(p, u) then
								return false
							end
							u += DT
						end
						return true
					end),
				})
			else
				local rise = riseTime(hover - top(prev), m.power :: number)
				table.insert(out, {
					what = `column (step {i}) caught from a ledge`,
					seconds = longestRun(function(t)
						local u = t + JUMP_IN
						while u <= t + JUMP_IN + rise + STEP_OFF do
							if not onAt(p, u) then
								return false
							end
							u += DT
						end
						return true
					end),
				})
			end
		end
	end
	for i, p in section.parts do
		if isRed(p) and not guarding[p] and not isCurtain(p) then
			-- a red pool you walk past: its dry spell less the time to cross it with a body's width either side
			local x0, x1 = Kit.bounds(p)
			local cross = (x1 - x0 + 2 * ObbyCheck.BODY) / Kit.WALK
			local dry = longestRun(function(t)
				return not onAt(p, t)
			end)
			table.insert(out, { what = `red pool (part {i}) past its crossing`, seconds = dry - cross })
		end
	end
	return out
end

-- Every variant built at seed 1 (hand-made: the seed is ignored).
local function each(fn: (number, Kit.Variant, Kit.Section) -> ())
	for i, v in idea.variants do
		fn(i, v, v.build(1))
	end
end

describe("GeyserField", function()
	it("builds the 16 designed variants in the design file's order and tiers", function()
		local doc = serde.decode("json", fs.readFile("docs/obby-variants/21.json"))
		local design = doc.ideas[1].variants
		expect(#idea.variants).toBe(#design)
		for i, d in design do
			expect(idea.variants[i].name).toBe(d.name)
			expect(idea.variants[i].tier).toBe(d.tier)
		end
		expect(idea.generator).toBe(nil)
	end)

	it("passes every shared check", function()
		local problems = {}
		for _, case in ObbyCheck.cases(idea) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("needs its geysers: without them nothing can be made", function()
		each(function(_, v, section)
			local parts = {}
			for _, part in section.parts do
				local copy = table.clone(part)
				local m = copy.motion
				if m and (m.kind == "bounce" or m.kind == "lift") then
					copy.motion = nil
				end
				table.insert(parts, copy)
			end
			local why = ObbyCheck.makeable({ length = section.length, rise = section.rise, parts = parts })
			expect(if why then "needs geysers" else `{v.name} can be made without its geysers`).toBe("needs geysers")
		end)
	end)

	it("never lets a plain jump do a geyser's climb", function()
		-- A real jump (JumpHeight 7.2, WalkSpeed 16): over `rise` it carries 16 x its air time.
		local function jumpable(gap: number, rise: number): boolean
			if rise >= Kit.JUMP_HEIGHT then
				return false
			end
			return gap <= Kit.WALK * flight(Kit.JUMP_SPEED, rise)
		end
		each(function(_, v, section)
			local steps = {}
			for _, p in section.parts do
				if p.step then
					table.insert(steps, p)
				end
			end
			for k = 2, #steps - 1 do
				local a, b = steps[k], steps[k + 1]
				local climb = top(b) - top(a) > Kit.RISE_MAX or gapOf(a, b) > Kit.GAP_MAX
				if climb and (isVent(a) or isColumn(a)) then
					-- from the geyser itself (a vent), and from the floor you stood on before it
					local from = { steps[k - 1] }
					if isVent(a) then
						table.insert(from, a)
					end
					local j = k - 1
					while j > 1 and isColumn(steps[j]) do
						j -= 1
						from = { steps[j] }
					end
					for _, f in from do
						if not isColumn(f) then
							local bad = jumpable(gapOf(f, b), top(b) - top(f))
							expect(if bad then `{v.name}: step {k + 1} is a plain jump` else "ok").toBe("ok")
						end
					end
				end
			end
		end)
	end)

	it("holds every geyser window to its tier's band", function()
		local bad = {}
		each(function(_, v, section)
			local band = BAND[v.tier]
			for _, w in windowsOf(section) do
				if process.env.GEYSER_DEBUG then
					print(v.name, w.what, w.seconds)
				end
				if w.seconds < band.lo - EPS or w.seconds > band.hi + EPS then
					table.insert(bad, `{v.name} ({v.tier}): {w.what} is {w.seconds} s ({band.lo}..{band.hi})`)
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("gives every variant past the easy ones a timed window to hit, and every easy one a timing element", function()
		each(function(_, v, section)
			local n = #windowsOf(section)
			local timed = false
			for _, p in section.parts do
				local m = p.motion
				if m and m.duty then
					timed = true
				end
			end
			expect(timed).toBe(true)
			if v.tier ~= "easy" and v.name ~= "Off-Beat Row" and v.name ~= "Chain Reaction" then
				expect(if n > 0 then "windowed" else `{v.name} has no window`).toBe("windowed")
			end
		end)
	end)

	it("lights a one-shot's fuse before you stand on its vent", function()
		each(function(_, v, section)
			for _, p in section.parts do
				if isVent(p) and p.start then
					local cap: Kit.Part? = nil
					for _, q in section.parts do
						if q.trigger == p.start then
							cap = q
						end
					end
					expect(cap ~= nil).toBe(true)
					local c = cap :: Kit.Part
					local cx0, cx1, _, _, cz0, cz1 = Kit.bounds(c)
					local vx0, vx1, _, _, vz0, vz1 = Kit.bounds(p)
					local covers = cx0 <= vx0 + EPS and cx1 >= vx1 - EPS and cz0 <= vz0 + EPS and cz1 >= vz1 - EPS
					expect(if covers then "covers" else `{v.name}: bubbles miss the vent`).toBe("covers")
					-- not blowing at rest: the vent must not throw before its clock starts... it is on at cycle 0, so
					-- the bubbles have to be touched first (they are wider than the vent)
					expect(cx1 - cx0 > vx1 - vx0).toBe(true)
				end
			end
		end)
	end)

	it("Chain Reaction: every launch lands on the next island as it blows", function()
		local section = idea.variants[12].build(1)
		local vents = {}
		for _, p in section.parts do
			if isVent(p) then
				table.insert(vents, p)
			end
		end
		expect(#vents).toBe(4)
		for k = 1, #vents - 1 do
			local a, b = vents[k], vents[k + 1]
			local fly = flight((a.motion :: Kit.Motion).power :: number, top(b) - top(a))
			local s = 0
			while not onAt(a, s) do
				s += DT
			end
			while onAt(a, s) do
				-- landing at s + fly: b is blowing then, or starts within a beat's breath
				local land = s + fly
				local u, caught = land, false
				while u <= land + 0.3 do
					if onAt(b, u) then
						caught = true
						break
					end
					u += DT
				end
				expect(caught).toBe(true)
				s += DT
			end
		end
	end)

	it("Summit Spouts: a launch can chain on, landing in the next vent's gap between red blows", function()
		local section = idea.variants[15].build(1)
		local vents = {}
		for _, p in section.parts do
			if isVent(p) then
				table.insert(vents, p)
			end
		end
		expect(#vents).toBe(4)
		for k = 1, #vents - 1 do
			local a, b = vents[k], vents[k + 1]
			local guards = guardsOf(section, b)
			expect(#guards).toBe(1)
			local fly = flight((a.motion :: Kit.Motion).power :: number, top(b) - top(a))
			local s = 0
			while not onAt(a, s) do
				s += DT
			end
			while onAt(a, s) do
				expect(arrivesAt(b, guards, s + fly)).toBe(true)
				s += DT
			end
		end
	end)

	it("Third Time: the puffs never lift you off the vent as the big blow comes", function()
		local section = idea.variants[10].build(1)
		local checked = 0
		for _, vent in section.parts do
			if isVent(vent) then
				local puffs = {}
				for _, p in section.parts do
					if not p.step and p.motion and p.motion.kind == "lift" and overlaps(p, vent) then
						table.insert(puffs, p)
					end
				end
				expect(#puffs).toBe(2)
				for k = 0, math.floor(HORIZON / DT) do
					local t = k * DT
					if onAt(vent, t) then
						for _, p in puffs do
							-- you fall PUFF back onto the vent in about 0.2 s: no puff in the 0.3 s before
							expect(onAt(p, t) or onAt(p, t - 0.3)).toBe(false)
						end
					end
				end
				checked += 1
			end
		end
		expect(checked).toBe(3)
	end)

	-- The blows of the vent before a curtain, each with the seconds of it whose throw flies through the curtain dry.
	local function curtainBlows(section: Kit.Section, c: Kit.Part): { { at: number, safe: number } }
		local cx0 = Kit.bounds(c)
		local steps = {}
		for _, p in section.parts do
			if p.step then
				table.insert(steps, p)
			end
		end
		local k = 0
		for i, p in steps do
			local _, x1 = Kit.bounds(p)
			if isVent(p) and x1 <= cx0 then
				k = i
			end
		end
		expect(k > 0 and k < #steps).toBe(true)
		local a, b = steps[k], steps[k + 1]
		local fly = flight((a.motion :: Kit.Motion).power :: number, top(b) - top(a))
		local blows = {}
		local was = false
		for n = 0, math.floor(HORIZON / DT) do
			local s = n * DT
			local on = onAt(a, s)
			if on and not was then
				table.insert(blows, { at = s, safe = 0 })
			end
			if on and #blows > 0 then
				local dry = true
				local u = s
				while u <= s + fly do
					if onAt(c, u) then
						dry = false
						break
					end
					u += DT
				end
				if dry then
					blows[#blows].safe += DT
				end
			end
			was = on
		end
		return blows
	end

	it("Off-Beat Row and Chain Reaction: each red curtain shuts some throws and lets others through", function()
		for _, n in { 6, 12 } do
			local v = idea.variants[n]
			local section = v.build(1)
			local count = 0
			for _, c in section.parts do
				if isCurtain(c) then
					count += 1
					local blows = curtainBlows(section, c)
					local safe, shut, lastSafe, longest = 0, 0, nil, 0
					for _, b in blows do
						if b.safe >= 0.15 then
							safe += 1
							if lastSafe then
								longest = math.max(longest, b.at - lastSafe)
							end
							lastSafe = b.at
						elseif b.safe == 0 then
							shut += 1
						end
					end
					expect(if safe > 0 then "ok" else `{v.name}: a curtain lets no throw through`).toBe("ok")
					expect(if shut > 0 then "ok" else `{v.name}: a curtain never shuts a throw`).toBe("ok")
					-- never more than about three beats of waiting for a dry throw
					expect(if longest <= 11 then "ok" else `{v.name}: {longest} s between dry throws`).toBe("ok")
					if n == 12 then
						-- the chain's beat is dry for the whole blow, the beat after is shut
						for i, b in blows do
							local want = if i % 2 == 1 then "dry" else "shut"
							local got = if b.safe >= 0.5 - EPS then "dry" elseif b.safe == 0 then "shut" else "part"
							expect(got).toBe(want)
						end
					end
				end
			end
			expect(count).toBe(3)
		end
	end)
end)
