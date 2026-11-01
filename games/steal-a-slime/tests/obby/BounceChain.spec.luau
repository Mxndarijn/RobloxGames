--!strict
-- Bounce Chain (obby idea 4): every variant through ObbyCheck, plus what the shared checks don't ask:
--   * every variant needs its pads (take the bounces away and it can't be made);
--   * every pad is readable (spring look with rings, an arrow or a star);
--   * a straight pad walked onto at its near edge still lands on the next step holding forward and steering (the
--     check measures from the pad's best edge; a player who walks on is thrown at the near one);
--   * holding forward doesn't clear the bounces either: the walker also fails when it starts past the opening hole.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local BounceChain = require("../../src/shared/ObbySections/BounceChain")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

-- The section with every bounce taken off its pad.
local function flat(section: Kit.Section): Kit.Section
	local parts = {}
	for _, part in section.parts do
		local copy = table.clone(part)
		if copy.motion and copy.motion.kind == "bounce" then
			copy.motion = nil
		end
		table.insert(parts, copy)
	end
	return { length = section.length, rise = section.rise, parts = parts }
end

-- The section without its entry pad: the walker starts on the island past the opening hole.
local function pastTheHole(section: Kit.Section): Kit.Section
	local parts, dropped = {}, false
	for _, part in section.parts do
		if part.step and not dropped then
			dropped = true
		else
			table.insert(parts, part)
		end
	end
	return { length = section.length, rise = section.rise, parts = parts }
end

-- Studs a throw at `power` carries you at walking speed until you come down `rise` higher.
local function carry(power: number, rise: number): number
	local disc = power * power - 2 * Kit.GRAVITY * rise
	return Kit.WALK * (power + math.sqrt(math.max(disc, 0))) / Kit.GRAVITY
end

local function steps(section: Kit.Section): { Kit.Part }
	local out = {}
	for _, part in section.parts do
		if part.step then
			table.insert(out, part)
		end
	end
	return out
end

describe("BounceChain", function()
	it("passes every shared check for every variant", function()
		local problems = {}
		for _, case in ObbyCheck.cases(BounceChain) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		expect(#problems).toBe(0)
	end)

	it("has every variant of the design file, in its order", function()
		local names = {}
		for _, v in BounceChain.variants do
			table.insert(names, v.name)
		end
		expect(table.concat(names, ", ")).toBe(
			"Step Up, Hop Line, Over the Wall, Long Spring, Ring Count, Side Throw, Zig-zag Tilt, Low Ceiling, "
				.. "Pad on Rails, Star Bounce, Bounce Back, Spent Springs, Ring Swap, Spring Relay, "
				.. "Tilt Through Pillars, Star Tower, Sliding Chain, Swap Climb"
		)
	end)

	it("can't be made without its pads", function()
		local bad = {}
		for _, case in ObbyCheck.cases(BounceChain) do
			if ObbyCheck.makeable(flat(case.build(1))) == nil then
				table.insert(bad, case.name)
			end
		end
		expect(table.concat(bad, ", ")).toBe("")
	end)

	it("can't be cleared holding forward from past the opening hole", function()
		local bad = {}
		for _, case in ObbyCheck.cases(BounceChain) do
			local why = ObbyCheck.straightWalk(pastTheHole(case.build(1)))
			if why then
				table.insert(bad, `{case.name}: {why}`)
			end
		end
		expect(table.concat(bad, "; ")).toBe("")
	end)

	it("marks every pad with rings, an arrow or a star", function()
		for _, case in ObbyCheck.cases(BounceChain) do
			for _, part in case.build(1).parts do
				local m = part.motion
				if m and m.kind == "bounce" then
					expect(part.look).toBe("spring")
					local mark = part.marker or ""
					local ok = string.match(mark, "^rings[123]$") ~= nil or mark == "star" or mark == "arrows"
					expect(ok).toBe(true)
					expect(mark == "arrows").toBe(m.throw ~= nil)
				end
			end
		end
	end)

	it("lands a near-edge throw from a straight pad on the next still step", function()
		local bad = {}
		for _, case in ObbyCheck.cases(BounceChain) do
			local path = steps(case.build(1))
			for i = 1, #path - 1 do
				local a, b = path[i], path[i + 1]
				local m, bm = a.motion, b.motion
				local still = bm == nil or bm.kind == "bounce" or bm.kind == "melt"
				if m and m.kind == "bounce" and m.throw == nil and still then
					local ax0, _, _, _, az0, az1 = Kit.bounds(a)
					local bx0, _, _, _, bz0, bz1 = Kit.bounds(b)
					local _, aTop = Kit.endTops(a)
					local bTop = Kit.endTops(b)
					-- from the near edge at the best z on the pad to half a stud onto the next step
					local dx = bx0 - ax0 + 0.5
					local dz = math.max(bz0 - az1, az0 - bz1, 0)
					dz = if dz > 0 then dz + 0.5 else 0
					local need = math.sqrt(dx * dx + dz * dz)
					local reach = carry(m.power :: number, bTop - aTop)
					if need > reach then
						table.insert(
							bad,
							`{case.name} step {i + 1}: {need} from the near edge, the throw carries {reach}`
						)
					end
				end
			end
		end
		expect(table.concat(bad, "; ")).toBe("")
	end)

	-- A throw from (x, z) on a pad whose top is `top`, flying with horizontal speed (vx, vz): does the body (1 stud
	-- round, feet to head) touch any of `boxes` before it comes back down to `top`?
	local function hits(part: Kit.Part, x: number, z: number, vx: number, vz: number, boxes: { Kit.Part }): boolean
		local m = part.motion :: Kit.Motion
		local _, top = Kit.endTops(part)
		local vy = (m.power :: number) + (if m.throw then m.throw[2] else 0)
		local tl = 2 * vy / Kit.GRAVITY
		for k = 1, 60 do
			local t = tl * k / 60
			local px, pz = x + vx * t, z + vz * t
			local feet = top + vy * t - Kit.GRAVITY * t * t / 2
			for _, b in boxes do
				local x0, x1, y0, y1, z0, z1 = Kit.bounds(b)
				if
					px > x0 - 1
					and px < x1 + 1
					and pz > z0 - 1
					and pz < z1 + 1
					and feet < y1
					and feet + Kit.HEAD > y0
				then
					return true
				end
			end
		end
		return false
	end

	local function variant(name: string): Kit.Section
		for _, v in BounceChain.variants do
			if v.name == name then
				return v.build(1)
			end
		end
		error(name)
	end

	it(
		"Over the Wall: a throw from each pad's near edge clears its wall, one from its middle or far edge does not",
		function()
			local s = variant("Over the Wall")
			local pads, walls = {}, {}
			for _, part in s.parts do
				if part.motion and part.motion.kind == "bounce" then
					table.insert(pads, part)
				elseif not part.step and not part.hazard then
					table.insert(walls, part)
				end
			end
			expect(#pads).toBe(2)
			expect(#walls).toBe(2)
			for i, p in pads do
				local x0, x1 = Kit.bounds(p)
				local wall = { walls[i] }
				expect(Kit.bounds(walls[i]) > x1).toBe(true)
				expect(hits(p, x0, 0, Kit.WALK, 0, wall)).toBe(false)
				expect(hits(p, (x0 + x1) / 2, 0, Kit.WALK, 0, wall)).toBe(true)
				expect(hits(p, x1, 0, Kit.WALK, 0, wall)).toBe(true)
				-- no plain jump gets over it either
				local _, _, _, top = Kit.bounds(walls[i])
				local _, padTop = Kit.endTops(p)
				expect(top - padTop > Kit.JUMP_HEIGHT).toBe(true)
			end
		end
	)

	it("Low Ceiling: the one-ring pads pass under the goo, the three-ring pads under it hit it", function()
		local s = variant("Low Ceiling")
		local ceilings = {}
		for _, part in s.parts do
			if part.hazard and part.pos[2] > 5 then
				table.insert(ceilings, part)
			end
		end
		expect(#ceilings).toBe(2)
		local low, high = 0, 0
		for _, part in s.parts do
			local m = part.motion
			if m and m.kind == "bounce" then
				local x0 = Kit.bounds(part)
				local under = hits(part, x0, part.pos[3], Kit.WALK, 0, ceilings)
				if m.power == 45 and part.step then
					low += 1
					expect(under).toBe(false)
				elseif m.power == 75 and part.step == nil then
					high += 1
					expect(under).toBe(true) -- the high decoys sit under the ceilings
				end
			end
		end
		expect(low).toBe(2)
		expect(high).toBe(2)
	end)

	it(
		"Tilt Through Pillars: middle to middle misses every pillar within walking steer, a corner throw hits",
		function()
			local s = variant("Tilt Through Pillars")
			local pads, pillars = {}, {}
			for _, part in s.parts do
				if part.motion and part.motion.kind == "bounce" then
					table.insert(pads, part)
				elseif part.hazard and part.size[2] > 10 then
					table.insert(pillars, part)
				end
			end
			expect(#pads).toBe(5)
			local corners = 0
			for i = 1, #pads - 1 do
				local a, b = pads[i], pads[i + 1]
				local m = a.motion :: Kit.Motion
				local throw = m.throw :: Kit.Vec
				local tl = 2 * (m.power :: number) / Kit.GRAVITY
				local vx, vz = (b.pos[1] - a.pos[1]) / tl, (b.pos[3] - a.pos[3]) / tl
				-- the steer it takes on top of the throw is within walking speed
				expect(math.sqrt(vx * vx + (vz - throw[3]) ^ 2) <= Kit.WALK).toBe(true)
				expect(hits(a, a.pos[1], a.pos[3], vx, vz, pillars)).toBe(false)
				-- from the pad's back inner corner to the same spot
				local x0 = Kit.bounds(a)
				local zc = a.pos[3] + (if throw[3] > 0 then 3.5 else -3.5)
				local cx, cz = (b.pos[1] - x0) / tl, (b.pos[3] - zc) / tl
				if hits(a, x0, zc, cx, cz, pillars) then
					corners += 1
				end
			end
			expect(corners >= 3).toBe(true)
		end
	)

	-- A blade is a goo hazard on a `path` over a timed pad's x (sweptPad). Open = the pad glows and the blade is off
	-- a body standing on the pad's edge; dark spells must each see the blade cross the pad's middle (no waiting).
	it("every blade leaves its pad an open window for its tier and sweeps it in every dark spell", function()
		local bad, count = {}, 0
		for _, case in ObbyCheck.cases(BounceChain) do
			local s = case.build(1)
			for _, blade in s.parts do
				local bm = blade.motion
				if blade.hazard and bm and bm.kind == "path" then
					local thePad: Kit.Part? = nil
					for _, part in s.parts do
						local m = part.motion
						if m and m.kind == "bounce" and m.duty and part.step and part.pos[1] == blade.pos[1] then
							thePad = part
						end
					end
					expect(thePad ~= nil).toBe(true)
					local p = thePad :: Kit.Part
					count += 1
					local _, _, _, _, z0, z1 = Kit.bounds(p)
					local dt = 0.005
					local n = math.floor(Kit.periodOf(blade) / dt + 0.5)
					local open, dark, middle = {}, {}, {}
					for k = 0, n - 1 do
						local t = k * dt
						local _, _, _, _, _, on = Kit.offsetAt(p, t)
						local _, _, dz = Kit.offsetAt(blade, t)
						local bz = blade.pos[3] + dz
						open[k] = on and (bz + 0.5 < z0 - 1 or bz - 0.5 > z1 + 1)
						dark[k] = not on
						middle[k] = math.abs(bz - p.pos[3]) < 0.5
					end
					-- longest open run (the clock wraps), and every dark spell crosses the middle
					local best, run = 0, 0
					local spells, crossed, swept, inSpell = 0, 0, false, false
					for k = 0, 2 * n - 1 do
						local i = k % n
						run = if open[i] then run + 1 else 0
						best = math.max(best, run)
						if dark[i] and not inSpell then
							swept = false
						end
						if dark[i] and middle[i] then
							swept = true
						end
						if inSpell and not dark[i] and k >= n then
							spells += 1
							crossed += if swept then 1 else 0
						end
						inSpell = dark[i]
					end
					local window = math.min(best, n) * dt
					local need = ObbyCheck.WINDOW[case.tier]
					if window < need then
						table.insert(bad, `{case.name}: open {window} s (at least {need})`)
					end
					if spells < 2 or crossed < spells then
						table.insert(bad, `{case.name}: {crossed} of {spells} dark spells swept`)
					end
				end
			end
		end
		expect(table.concat(bad, "; ")).toBe("")
		expect(count).toBe(10)
	end)
end)
