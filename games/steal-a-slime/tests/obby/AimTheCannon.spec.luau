--!strict
-- Aim the Cannon (obby idea 26): every variant through ObbyCheck, the variant list against its design file, and the
-- fire windows the shared checks don't measure. ObbyCheck only asks that some sampled aim lands within 2 studs of the
-- next step; here every cannon's shot is flown as the check flies it (from the barrel's centre, fixed power and arc)
-- every 5 ms, and a moment counts as a hit only when the landing spot is 1 stud inside a target (clear of a barrel
-- standing on it), the target is measured where it is when you land (drifting and breathing islands move during the
-- flight), and the arc stays clear of every goo box (padded 1 stud, as ObbyMoves' trace) at the time it passes.
-- The longest such run is the cannon's fire window; the tier bands are contract §10's shift applied to the design's
-- fire-window floors (easy 0.8, medium 0.45, hard 0.3 s in the draft), tightened in review: the median pass of a tier
-- stays under its ceiling, so no variant sits at the soft end.
local T = require("../TestRunner")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local describe, it, expect = T.describe, T.it, T.expect
local AimTheCannon = require("../../src/shared/ObbySections/AimTheCannon")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

local BAND = {
	easy = { lo = 0.55, hi = 0.9 },
	medium = { lo = 0.38, hi = 0.6 },
	hard = { lo = 0.25, hi = 0.4 },
}
local DT = 0.005 -- seconds between fire times tried
local MARGIN = 1 -- studs in from a target's edge (half a body)
local HAZARD_PAD = 1 -- ObbyMoves.HAZARD_PAD: the arc hits goo this close to its box
local FEET = 3 -- the game hands the root back when the feet (3 under it) meet the floor: hazards count until then

local function variantNamed(name: string): Kit.Variant
	for _, v in AimTheCannon.variants do
		if v.name == name then
			return v
		end
	end
	error(`no Aim the Cannon variant {name}`)
end

-- Is (x, z) inside part `p` at time t (its motion offset, turn and scale), shrunk by `margin` studs?
local function inside(p: Kit.Part, t: number, x: number, z: number, margin: number): boolean
	local dx, _, dz, dyaw, scale = Kit.offsetAt(p, t)
	local a = math.rad((p.yaw or 0) + dyaw)
	local c, s = math.cos(a), math.sin(a)
	local px, pz = x - p.pos[1] - dx, z - p.pos[3] - dz
	local lx, lz = px * c - pz * s, px * s + pz * c
	return math.abs(lx) <= p.size[1] * scale / 2 - margin and math.abs(lz) <= p.size[3] * scale / 2 - margin
end

-- Is (x, y, z) inside hazard `h` (axis-aligned, moved by its motion at t) grown by `pad`?
local function inGoo(h: Kit.Part, t: number, x: number, y: number, z: number, pad: number): boolean
	local dx, dy, dz = Kit.offsetAt(h, t)
	return math.abs(x - h.pos[1] - dx) <= h.size[1] / 2 + pad
		and math.abs(y - h.pos[2] - dy) <= h.size[2] / 2 + pad
		and math.abs(z - h.pos[3] - dz) <= h.size[3] / 2 + pad
end

type Shot = { index: number, cannon: Kit.Part, targets: { Kit.Part }, period: number }

-- Every cannon of a section with its targets: the non-cannon steps after it up to the next cannon.
local function shots(section: Kit.Section): { Shot }
	local out: { Shot } = {}
	local current: Shot? = nil
	for i, part in section.parts do
		if part.step and part.cannon then
			current = { index = i, cannon = part, targets = {}, period = Kit.periodOf(part) }
			table.insert(out, current :: Shot)
		elseif part.step and current then
			table.insert(current.targets, part)
		end
	end
	return out
end

-- Whether firing cannon `shot` at time t hits a target cleanly.
local function hits(section: Kit.Section, shot: Shot, t: number): boolean
	local c = shot.cannon
	local spec = c.cannon :: { power: number, arc: number }
	local dx, _, dz, dyaw = Kit.offsetAt(c, t)
	local ox, oy, oz = c.pos[1] + dx, c.pos[2], c.pos[3] + dz
	local aim = math.rad((c.yaw or 0) + dyaw)
	local arc = math.rad(spec.arc)
	local vh, vy = spec.power * math.cos(arc), spec.power * math.sin(arc)
	local ux, uz = math.cos(aim), -math.sin(aim)
	for _, target in shot.targets do
		local top = target.pos[2] + target.size[2] / 2
		local disc = vy * vy + 2 * Kit.GRAVITY * (oy - top)
		if disc >= 0 then
			local tl = (vy + math.sqrt(disc)) / Kit.GRAVITY
			local lx, lz = ox + ux * vh * tl, oz + uz * vh * tl
			local landed = inside(target, t + tl, lx, lz, MARGIN)
			-- not on top of a barrel standing on the target
			for _, other in section.parts do
				if landed and other.cannon and other ~= c and inside(other, t + tl, lx, lz, -MARGIN) then
					landed = false
				end
			end
			if landed then
				local d3 = vy * vy + 2 * Kit.GRAVITY * (oy - top - FEET)
				local tHit = if d3 >= 0 then (vy + math.sqrt(d3)) / Kit.GRAVITY else tl
				local clear = true
				local s = 0
				while clear and s <= tHit do
					local x, y, z = ox + ux * vh * s, oy + vy * s - Kit.GRAVITY * s * s / 2, oz + uz * vh * s
					for _, h in section.parts do
						-- (a flood runs on your own clock from its trigger: the Hot Seat test times it)
						local flood = h.motion ~= nil and h.motion.kind == "rise"
						if h.hazard and not flood and inGoo(h, t + s, x, y, z, HAZARD_PAD) then
							clear = false
							break
						end
					end
					s += 0.01
				end
				if clear then
					return true
				end
			end
		end
	end
	return false
end

-- The good fire times of a shot over `horizon` seconds: a list of { from, to } runs.
local function runs(section: Kit.Section, shot: Shot, horizon: number): { { number } }
	local out = {}
	local from: number? = nil
	local t = 0
	while t <= horizon do
		local good = hits(section, shot, t)
		if good and from == nil then
			from = t
		elseif not good and from ~= nil then
			table.insert(out, { from :: number, t })
			from = nil
		end
		t += DT
	end
	if from ~= nil then
		table.insert(out, { from :: number, horizon })
	end
	return out
end

-- Seconds to look over: long enough for a cannon and its moving targets to line up in every way they do.
local function horizonOf(section: Kit.Section, shot: Shot): number
	local longest = shot.period
	for _, target in shot.targets do
		if target.motion then
			longest = math.max(longest, Kit.periodOf(target))
		end
	end
	for _, h in section.parts do
		if h.hazard and h.motion and h.motion.kind ~= "rise" then
			longest = math.max(longest, Kit.periodOf(h))
		end
	end
	return math.max(4 * longest, 24)
end

-- Each cannon of a section: its longest run of good fire times (the best shot you can wait for) and its median run
-- (the shot a typical pass gives you; a drifting island moving with the aim now and then gives a long one).
local function windows(section: Kit.Section): { { number } }
	local out = {}
	for _, shot in shots(section) do
		local lengths = {}
		for _, r in runs(section, shot, horizonOf(section, shot)) do
			table.insert(lengths, r[2] - r[1])
		end
		table.sort(lengths)
		local n = #lengths
		local median = if n == 0 then 0 else lengths[math.floor((n + 1) / 2)]
		table.insert(out, { if n == 0 then 0 else lengths[n], median })
	end
	return out
end

describe("Aim the Cannon", function()
	it("passes every shared check for every variant, seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(AimTheCannon) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("builds every variant of docs/obby-variants/26.json, in its order and tiers", function()
		local doc = serde.decode("json", fs.readFile("docs/obby-variants/26.json"))
		local design = doc.ideas[1]
		expect(AimTheCannon.id).toBe("AimTheCannon")
		expect(AimTheCannon.name).toBe(design.name)
		expect(AimTheCannon.idea).toBe(design.id)
		expect(#AimTheCannon.variants).toBe(#design.variants)
		for i, v in design.variants do
			expect(AimTheCannon.variants[i].name).toBe(v.name)
			expect(AimTheCannon.variants[i].tier).toBe(v.tier)
		end
		expect(AimTheCannon.generator).toBeNil()
	end)

	it("keeps every cannon's fire window in its tier's band", function()
		-- The longest window is at least the band's floor (there is a fair shot to wait for); the median window is at
		-- most its ceiling (typical passes are not too easy).
		local off, report = {}, {}
		for _, case in ObbyCheck.cases(AimTheCannon) do
			local section = case.build(1)
			local shown = {}
			local band = BAND[case.tier]
			for k, w in windows(section) do
				shown[k] = string.format("%.2f (median %.2f)", w[1], w[2])
				if w[1] < band.lo - 1e-6 or w[2] > band.hi + 1e-6 then
					table.insert(off, `{case.name} cannon {k}: fire window {shown[k]} s ({band.lo}..{band.hi})`)
				end
			end
			table.insert(report, `{case.name} [{case.tier}]: {table.concat(shown, " / ")}`)
		end
		if process.env.CANNON_REPORT then
			print(table.concat(report, "\n"))
		end
		expect(table.concat(off, "\n")).toBe("")
	end)

	it("every cannon has at least one clean hit each sweep it is fired on a still target", function()
		-- Static targets: a good run inside every full sweep period (no dead sweeps).
		for _, case in ObbyCheck.cases(AimTheCannon) do
			local section = case.build(1)
			for _, shot in shots(section) do
				local still = true
				for _, target in shot.targets do
					still = still and target.motion == nil
				end
				for _, h in section.parts do
					still = still and not (h.hazard and h.motion and h.motion.kind ~= "rise")
				end
				if still then
					local list = runs(section, shot, 3 * shot.period)
					local gapMax = 0
					for k = 2, #list do
						gapMax = math.max(gapMax, list[k][1] - list[k - 1][2])
					end
					expect(#list >= 2).toBe(true)
					expect(gapMax < shot.period).toBe(true)
				end
			end
		end
	end)

	it("never lets a straight walk through, on any line or start time", function()
		for _, case in ObbyCheck.cases(AimTheCannon) do
			expect(ObbyCheck.straightWalk(case.build(1))).toBeNil()
		end
	end)
end)

describe("Aim the Cannon twists", function()
	it(
		"Hole in the Wall, Sliding Hole, Four Fast Shots: the wall blocks part of the aims that reach the island",
		function()
			for _, name in { "Hole in the Wall", "Sliding Hole", "Four Fast Shots" } do
				local section = variantNamed(name).build(1)
				local list = shots(section)
				local shot = list[#list]
				-- the same shot with the goo taken away hits for longer: the wall really is in the way
				local bare = table.clone(section)
				bare.parts = {}
				for _, p in section.parts do
					if not p.hazard then
						table.insert(bare.parts, p)
					end
				end
				local horizon = horizonOf(section, shot)
				local function total(s: Kit.Section): number
					local sum = 0
					for _, r in runs(s, shot, horizon) do
						sum += r[2] - r[1]
					end
					return sum
				end
				local with, without = total(section), total(bare)
				expect(with > 0).toBe(true)
				expect(with < without * 0.85).toBe(true)
			end
		end
	)

	-- A hot seat (a cannon that is a trigger, red goo rising under it on that clock): from any moment you climb in, a
	-- run of at least 0.2 s of good fire times starts after the 0.2 s seat grace and ends before the goo arrives.
	-- Returns the longest wait from climbing in to the start of that shot.
	local function hotSeat(section: Kit.Section, shot: Shot): number
		local group = shot.cannon.trigger
		assert(group, "not a hot seat")
		local flood: Kit.Part? = nil
		for _, p in section.parts do
			if p.motion and p.motion.kind == "rise" and p.start == group then
				flood = p
			end
		end
		assert(flood, `hot seat {group} has no flood`)
		-- the flood sits under the barrel
		expect(math.abs(flood.pos[1] - shot.cannon.pos[1]) < 0.01).toBe(true)
		expect(math.abs(flood.pos[3] - shot.cannon.pos[3]) < 0.01).toBe(true)
		-- When the goo's top reaches a seated character's feet (3 under the barrel's centre: 1.5 under the floor top)
		-- with ObbyFx's 0.5-stud hazard pad.
		local floor = shot.cannon.pos[2] - shot.cannon.size[2] / 2
		local reach = math.huge
		for k = 0, 600 do
			local t = k / 100
			local _, dy = Kit.offsetAt(flood, t)
			if flood.pos[2] + flood.size[2] / 2 + dy >= floor - 2 then
				reach = t
				break
			end
		end
		expect(reach > 2.8 and reach < 3.3).toBe(true)
		local list = runs(section, shot, 4 * shot.period)
		local worst = 0
		local sit = 0
		while sit < shot.period do
			local ok = false
			for _, r in list do
				local from = math.max(r[1], sit + 0.2)
				local to = math.min(r[2], sit + reach)
				if to - from >= 0.2 then
					ok = true
					worst = math.max(worst, from - sit)
					break
				end
			end
			expect(ok).toBe(true)
			sit += 0.05
		end
		return worst
	end

	it("Four Fast Shots: every seat is hot, and each one still gives a clean shot before its goo arrives", function()
		local section = variantNamed("Four Fast Shots").build(1)
		local list = shots(section)
		expect(#list).toBe(4)
		for _, shot in list do
			hotSeat(section, shot)
		end
	end)

	it("Hot Seat: from any moment you climb in, a clean shot comes before the goo reaches you", function()
		local section = variantNamed("Hot Seat").build(1)
		local shot = shots(section)[1]
		expect(shot.cannon.trigger).toBe("seat")
		local worst = hotSeat(section, shot)
		-- but you do have to take an early one: waiting out a second full pass is not always possible
		expect(worst > 1.5).toBe(true)
	end)

	it("Pick a Side: the hits are in the pause at the sweep's left end", function()
		local section = variantNamed("Pick a Side").build(1)
		local shot = shots(section)[1]
		for _, r in runs(section, shot, 2 * shot.period) do
			local mid = (r[1] + r[2]) / 2
			local _, _, _, dyaw = Kit.offsetAt(shot.cannon, mid)
			expect(dyaw).toBeCloseTo((shot.cannon.motion :: Kit.Motion).amp :: number, 1e-6)
		end
	end)

	it("Near or Far: firing too early lands in the goo pool, too late flies past the island", function()
		local section = variantNamed("Near or Far").build(1)
		local shot = shots(section)[1]
		local c = shot.cannon
		local spec = c.cannon :: { power: number, arc: number }
		local arc = math.rad(spec.arc)
		local vh, vy = spec.power * math.cos(arc), spec.power * math.sin(arc)
		local tl = (vy + math.sqrt(vy * vy + 2 * Kit.GRAVITY * c.pos[2])) / Kit.GRAVITY
		local pool: Kit.Part? = nil
		for _, p in section.parts do
			if p.hazard then
				pool = p
			end
		end
		assert(pool, "Near or Far has no pool")
		local target = shot.targets[1]
		local _, ix1 = Kit.bounds(target)
		local px0, px1 = Kit.bounds(pool)
		local amp = (c.motion :: Kit.Motion).amp :: number
		local nearest, farthest = c.pos[1] - amp + vh * tl, c.pos[1] + amp + vh * tl
		expect(nearest >= px0 and nearest <= px1).toBe(true)
		expect(farthest > ix1 + 2).toBe(true)
	end)
end)
