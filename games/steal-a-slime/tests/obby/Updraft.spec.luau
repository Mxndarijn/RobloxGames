--!strict
-- Updraft (obby idea 5): every variant through ObbyCheck, plus what the shared checks don't measure about wind
-- columns: every variant needs its wind, the first column can't be walked into (a standing root is about ROOT over
-- the floor), every exit ledge is under where a rider's feet really get to (ObbyFx lifts the root, ObbyCheck measures
-- from the column's top or cap), a column you hand off into can't be jumped into from a floor, and every timed column
-- leaves the tier's window past the ride (contract §10).
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local Updraft = require("../../src/shared/ObbySections/Updraft")

local ROOT = 3 -- feet to the root part (HipHeight 2 + half the root)
local HOP = Kit.RISE_MAX
-- The tightest window a variant of each tier may have at most: it has to earn its tier (§10).
local MAX = { easy = 2.0, medium = 1.4, hard = 1.0 }

local function isLift(p: Kit.Part): boolean
	return p.motion ~= nil and p.motion.kind == "lift"
end

local function bottomOf(p: Kit.Part): number
	local _, _, y0 = Kit.bounds(p)
	return y0
end

local function topOf(p: Kit.Part): number
	local _, _, _, y1 = Kit.bounds(p)
	return y1
end

-- The steps of a section in order.
local function steps(section: Kit.Section): { Kit.Part }
	local out = {}
	for _, p in section.parts do
		if p.step then
			table.insert(out, p)
		end
	end
	return out
end

-- Edge gap between two parts seen from above (axis-aligned boxes).
local function gap(a: Kit.Part, b: Kit.Part): number
	local ax0, ax1, _, _, az0, az1 = Kit.bounds(a)
	local bx0, bx1, _, _, bz0, bz1 = Kit.bounds(b)
	local dx = math.max(0, bx0 - ax1, ax0 - bx1)
	local dz = math.max(0, bz0 - az1, az0 - bz1)
	return math.sqrt(dx * dx + dz * dz)
end

-- Where a rider's feet get to in a column: the hover height, or the top plus the throw past it.
local function feetTop(p: Kit.Part): number
	local m = p.motion :: Kit.Motion
	if m.cap then
		return bottomOf(p) + m.cap - ROOT
	end
	local power = m.power or 50
	return topOf(p) - ROOT + power * power / (2 * Kit.GRAVITY)
end

-- Seconds a timed column is on in each cycle, and the share of the period it starts at (0 = cycle start).
local function onSpan(p: Kit.Part): (number, number)
	local m = p.motion :: Kit.Motion
	local period = Kit.periodOf(p)
	-- on while (t / period + phase) % 1 < duty: it comes on at t = (1 - phase) * period
	return (m.duty or 1) * period, ((1 - (m.phase or 0)) % 1) * period
end

-- The forward gust over the same box as `p`, if any.
local function gustOver(section: Kit.Section, p: Kit.Part): number?
	for _, q in section.parts do
		if q.motion and q.motion.kind == "gust" and q.pos[1] == p.pos[1] and q.pos[2] == p.pos[2] then
			return q.motion.power
		end
	end
	return nil
end

-- Seconds a ride in column `p` takes: up to its exit height, or a tunnel's length at its gust.
local function rideTime(section: Kit.Section, p: Kit.Part): number
	local m = p.motion :: Kit.Motion
	local height = p.size[2]
	if p.size[1] > height then
		return p.size[1] / math.max(Kit.WALK, gustOver(section, p) or 0)
	end
	local rise = if m.cap then m.cap else height
	return rise / (m.power or 50)
end

-- Seconds two timed columns run together each cycle (same period).
local function overlap(a: Kit.Part, b: Kit.Part): number
	local onA, fromA = onSpan(a)
	local onB, fromB = onSpan(b)
	local period = Kit.periodOf(a)
	local best = 0
	for k = -1, 1 do
		local lo = math.max(fromA, fromB + k * period)
		local hi = math.min(fromA + onA, fromB + k * period + onB)
		best = math.max(best, hi - lo)
	end
	return best
end

--[[
	A rider in column `col` past the goo inside it: it hops in at the bottom at time `t0`, its root rises at the column's
	power, and it may steer at ObbyCheck.LATERAL (the fairness runner's sidestep). The body is ROOT under to 2 over the root and BODY + HAZARD_PAD (1.5)
	round it; a hazard touches when that box meets it. A grid of root positions inside the column is carried up step
	by step (what is reachable from what was reachable). True when some position gets to the exit height untouched.
	`still`: the rider can't steer (it keeps its spot).
]]
local REACH = 1.5 -- body half width plus ObbyFx.HAZARD_PAD
local GRID = 0.5

local function touches(h: Kit.Part, x: number, root: number, z: number, t: number): boolean
	local dx, dy, dz, dyaw = Kit.offsetAt(h, t)
	local bottom = h.pos[2] + dy - h.size[2] / 2
	local top = h.pos[2] + dy + h.size[2] / 2
	if root - ROOT - 0.5 > top or root + 2 + 0.5 < bottom then
		return false
	end
	local a = math.rad((h.yaw or 0) + dyaw)
	local c, s = math.cos(a), math.sin(a)
	local px, pz = x - h.pos[1] - dx, z - h.pos[3] - dz
	local lx, lz = px * c - pz * s, px * s + pz * c
	return math.abs(lx) <= h.size[1] / 2 + REACH and math.abs(lz) <= h.size[3] / 2 + REACH
end

local function riderPasses(col: Kit.Part, hazards: { Kit.Part }, t0: number, still: boolean?): boolean
	local m = col.motion :: Kit.Motion
	local power = m.power or 50
	local x0, x1, y0, y1, z0, z1 = Kit.bounds(col)
	local exit = if m.cap then y0 + m.cap else y1
	local nx, nz = math.floor((x1 - x0) / GRID), math.floor((z1 - z0) / GRID)
	-- one grid cell sideways per rise step, at the fairness runner's sidestep speed (ObbyCheck.LATERAL)
	local dh = GRID * power / ObbyCheck.LATERAL
	local dt = GRID / ObbyCheck.LATERAL
	local function free(i: number, k: number, root: number, t: number): boolean
		local x, z = x0 + (i - 0.5) * GRID, z0 + (k - 0.5) * GRID
		for _, h in hazards do
			if touches(h, x, root, z, t) then
				return false
			end
		end
		return true
	end
	local alive: { [number]: boolean } = {}
	local any = false
	for i = 1, nx do
		for k = 1, nz do
			if free(i, k, y0, t0) then
				alive[i * 1000 + k], any = true, true
			end
		end
	end
	local root, t = y0, t0
	while any and root < exit do
		root += dh
		t += dt
		local nextAlive: { [number]: boolean } = {}
		any = false
		for i = 1, nx do
			for k = 1, nz do
				local near = alive[i * 1000 + k] == true
				if not still then
					for di = -1, 1 do
						for dk = -1, 1 do
							if alive[(i + di) * 1000 + k + dk] then
								near = true
							end
						end
					end
				end
				if near and free(i, k, root, t) then
					nextAlive[i * 1000 + k], any = true, true
				end
			end
		end
		alive = nextAlive
	end
	return any
end

-- Longest run of hop-in times (seconds) a rider gets past the goo inside column `col`, over `horizon` seconds.
local function riderWindow(col: Kit.Part, hazards: { Kit.Part }, horizon: number): number
	local best, run = 0, 0
	local t0 = 0
	while t0 < horizon do
		if riderPasses(col, hazards, t0) then
			run += 1
			best = math.max(best, run)
		else
			run = 0
		end
		t0 += 0.05
	end
	return best * 0.05
end

describe("Updraft", function()
	it("every variant passes ObbyCheck, seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(Updraft) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("a rider gets past the goo inside every column for the tier's window", function()
		local checked = 0
		for _, v in Updraft.variants do
			local section = v.build(1)
			for _, col in steps(section) do
				if isLift(col) and col.size[2] >= col.size[1] then
					local cx0, cx1, cy0, cy1, cz0, cz1 = Kit.bounds(col)
					local inside, horizon = {}, 6
					for _, h in section.parts do
						if h.hazard then
							local hx0, hx1, hy0, hy1, hz0, hz1 = Kit.bounds(h)
							if hx1 > cx0 and hx0 < cx1 and hz1 > cz0 and hz0 < cz1 and hy1 > cy0 and hy0 < cy1 then
								table.insert(inside, h)
								if h.motion then
									horizon = math.max(horizon, 2 * Kit.periodOf(h))
								end
							end
						end
					end
					if #inside > 0 then
						checked += 1
						local window = riderWindow(col, inside, horizon)
						if window < ObbyCheck.WINDOW[v.tier] - 1e-6 then
							error(
								`{v.name}: a rider gets past the goo for {window} s (at least {ObbyCheck.WINDOW[v.tier]})`
							)
						end
					end
				end
			end
		end
		expect(checked >= 3).toBe(true)
	end)

	it("the moving goo in Spinner Shaft and Goo Ring Climb really blocks: a window in the tier's range", function()
		for _, name in { "Spinner Shaft", "Goo Ring Climb" } do
			for _, v in Updraft.variants do
				if v.name == name then
					local section = v.build(1)
					local col: Kit.Part? = nil
					local goo = {}
					for _, p in section.parts do
						if isLift(p) then
							col = p
						elseif p.hazard then
							table.insert(goo, p)
						end
					end
					assert(col, "no column")
					local hits = 0
					for k = 0, 59 do
						if not riderPasses(col, goo, k * 0.05) then
							hits += 1
						end
					end
					local window = riderWindow(col, goo, 12)
					expect(hits > 0).toBe(true)
					expect(window >= ObbyCheck.WINDOW[v.tier] - 1e-6).toBe(true)
					expect(window <= MAX[v.tier] + 1e-6).toBe(true)
				end
			end
		end
	end)

	it("the goo shelves make you weave: a rider who keeps its spot never gets past them", function()
		for _, name in { "Goo Ring Climb", "Storm Shaft" } do
			for _, v in Updraft.variants do
				if v.name == name then
					local section = v.build(1)
					local col: Kit.Part? = nil
					local shelves = {}
					for _, p in section.parts do
						if isLift(p) then
							col = p
						elseif p.hazard then
							table.insert(shelves, p)
						end
					end
					assert(col, "no column")
					expect(#shelves).toBe(3)
					-- over one cycle of the shelves (they slide in Goo Ring Climb): standing still never passes,
					-- steering does at some hop-in time
					local still, steer = false, false
					for k = 0, 39 do
						still = still or riderPasses(col, shelves, k * 0.05, true)
						steer = steer or riderPasses(col, shelves, k * 0.05)
					end
					expect(still).toBe(false)
					expect(steer).toBe(true)
				end
			end
		end
	end)

	-- The variant called `name`, built.
	local function built(name: string): Kit.Section
		for _, v in Updraft.variants do
			if v.name == name then
				return v.build(1)
			end
		end
		error(`no variant {name}`)
	end

	-- Longest stretch (s) in one period of `col` during which it is on, its rider is past the ride, and `ok(t)`.
	local function exitWindow(section: Kit.Section, col: Kit.Part, ok: (number) -> boolean): number
		local period = Kit.periodOf(col)
		local on, from = onSpan(col)
		local ride = rideTime(section, col)
		local best, run, dt = 0, 0, 0.02
		local t = from + ride
		while t < from + on do
			if ok(t) then
				run += dt
				best = math.max(best, run)
			else
				run = 0
			end
			t += dt
		end
		expect(period > 0).toBe(true)
		return best
	end

	it("Drifting Column: the column runs while the drifting ledge lines up with it, for a medium window", function()
		local section = built("Drifting Column")
		local list = steps(section)
		local col, drift = list[2], list[3]
		expect(isLift(col)).toBe(true)
		expect(Kit.periodOf(drift)).toBe(Kit.periodOf(col))
		local _, _, _, _, cz0, cz1 = Kit.bounds(col)
		local window = exitWindow(section, col, function(t)
			local _, _, dz = Kit.offsetAt(drift, t)
			local _, _, _, _, z0, z1 = Kit.bounds(drift)
			return math.min(cz1, z1 + dz) - math.max(cz0, z0 + dz) >= 3
		end)
		expect(window >= ObbyCheck.WINDOW.medium - 1e-6).toBe(true)
		expect(window <= MAX.medium + 1e-6).toBe(true)
	end)

	it(
		"Moving Exit: the column runs while the moving ledge is low, and the far ledge is only in reach at the top",
		function()
			local section = built("Moving Exit")
			local list = steps(section)
			local col, lift, far = list[2], list[3], list[4]
			expect(Kit.periodOf(lift)).toBe(Kit.periodOf(col))
			local feet = feetTop(col)
			local window = exitWindow(section, col, function(t)
				local _, dy = Kit.offsetAt(lift, t)
				return topOf(lift) + dy <= feet - 0.5
			end)
			expect(window >= ObbyCheck.WINDOW.medium - 1e-6).toBe(true)
			expect(window <= MAX.medium + 1e-6).toBe(true)
			-- from the moving ledge the far ledge is a jump only near the top of its trip
			local reach = 0
			for k = 0, 599 do
				local _, dy = Kit.offsetAt(lift, k * 0.01)
				if topOf(far) - (topOf(lift) + dy) <= Kit.RISE_MAX then
					reach += 0.01
				end
			end
			expect(reach > 0).toBe(true)
			expect(reach <= 2).toBe(true)
		end
	)

	it("Hover Shelf: the goo bar is down below your feet for an easy window, then back up", function()
		local section = built("Hover Shelf")
		local list = steps(section)
		local col = list[2]
		local feet = feetTop(col)
		local bar: Kit.Part? = nil
		for _, p in section.parts do
			if p.hazard then
				bar = p
			end
		end
		assert(bar, "no bar")
		local period = Kit.periodOf(bar)
		local best, run, open = 0, 0, 0
		for k = 0, math.floor(2 * period / 0.02) do
			local _, dy = Kit.offsetAt(bar, k * 0.02)
			if topOf(bar) + dy < feet - 0.5 then
				run += 0.02
				open += 0.02
				best = math.max(best, run)
			else
				run = 0
			end
		end
		expect(best >= ObbyCheck.WINDOW.easy - 1e-6).toBe(true)
		expect(best <= MAX.easy + 1e-6).toBe(true)
		expect(open < period * 2).toBe(true)
	end)

	it("every variant needs its wind: without the lifts it can't be made", function()
		for _, v in Updraft.variants do
			local section = v.build(1)
			local parts = {}
			for _, p in section.parts do
				local copy = table.clone(p)
				if copy.motion and copy.motion.kind == "lift" then
					-- a column is see-through air: without its wind it is no step at all
					copy.motion = nil
					copy.step = nil
				end
				table.insert(parts, copy)
			end
			local why = ObbyCheck.makeable({ length = section.length, rise = section.rise, parts = parts })
			expect(why ~= nil).toBe(true)
		end
	end)

	it("the first column can't be walked into: it floats a hop over the pad, or you drop into it", function()
		for _, v in Updraft.variants do
			local list = steps(v.build(1))
			for i = 2, #list do
				local p = list[i]
				if isLift(p) then
					local from = list[i - 1]
					local floorTop = topOf(from)
					local floats = bottomOf(p) >= floorTop + HOP - 1e-6
					local below = topOf(p) <= floorTop + 1 + 1e-6 and gap(from, p) >= 4 - 1e-6
					if not (floats or below) then
						error(`{v.name}: column {i} can be walked into from the pad`)
					end
					break
				end
			end
		end
	end)

	it("every exit ledge is at least a stud under where a rider's feet get to", function()
		for _, v in Updraft.variants do
			local list = steps(v.build(1))
			for i = 1, #list - 1 do
				local p, nxt = list[i], list[i + 1]
				if isLift(p) and not isLift(nxt) then
					local short = topOf(nxt) + 1 - feetTop(p)
					if short > 1e-6 then
						error(`{v.name}: step {i + 1} is {short} studs too high for the ride`)
					end
				end
			end
		end
	end)

	it("a column you hand off into is out of jumping reach from every floor near it", function()
		for _, v in Updraft.variants do
			local list = steps(v.build(1))
			for i = 2, #list do
				local p = list[i]
				if isLift(p) and isLift(list[i - 1]) then
					for j = 1, i - 1 do
						local f = list[j]
						if not isLift(f) and gap(f, p) <= Kit.GAP_MAX + 2 then
							local reach = topOf(f) + ROOT + Kit.JUMP_HEIGHT
							if bottomOf(p) <= reach then
								error(`{v.name}: column {i} can be jumped into from step {j}`)
							end
						end
					end
				end
			end
		end
	end)

	it("every timed column leaves the tier's window past the ride, and the tightest one earns the tier", function()
		for _, v in Updraft.variants do
			local section = v.build(1)
			local list = steps(section)
			local need = ObbyCheck.WINDOW[v.tier]
			local tightest = math.huge
			for i, p in list do
				local m = p.motion
				if m and m.kind == "lift" and m.duty then
					local prev = list[i - 1]
					local window
					if prev and isLift(prev) and (prev.motion :: Kit.Motion).duty then
						-- a hand-off: both run together this long
						window = overlap(prev, p)
					else
						local on = onSpan(p)
						window = on - rideTime(section, p)
					end
					if window < need - 1e-6 then
						error(`{v.name}: column {i} leaves {window} s (at least {need})`)
					end
					tightest = math.min(tightest, window)
				end
			end
			if tightest < math.huge and tightest > MAX[v.tier] + 1e-6 then
				error(`{v.name}: its tightest window is {tightest} s, too easy for {v.tier} (at most {MAX[v.tier]})`)
			end
		end
	end)
end)
