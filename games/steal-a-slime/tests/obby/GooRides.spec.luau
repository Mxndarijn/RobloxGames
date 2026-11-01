--!strict
-- Goo Rides (obby idea 3): every variant through ObbyCheck, plus the idea's own rules. ObbyCheck measures a moving
-- ride at its closest point of a period; here every handoff between rides (and docks) is timed for real: how long a
-- runner can step or jump across, before goo or a cap reaches them, and how long a ride stands still at a stop.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local GooRides = require("../../src/shared/ObbySections/GooRides")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

local idea: Kit.Idea = GooRides :: any

-- GOO_RIDES_DEBUG=1 prints every handoff's windows (Lune only).
local okProcess, lprocess = pcall(require, "@lune/process")
local DEBUG = okProcess and (lprocess :: any).env.GOO_RIDES_DEBUG ~= nil

local DT = 0.01 -- seconds between samples
local BODY = ObbyCheck.BODY
-- The longest a ride may stand still at a stop you step across from, per tier (contract §10: easy <= 2.0 s).
local HOLD_MAX = { easy = 2.0, medium = 1.4, hard = 1.0 }
-- Handoffs whose deck hazards you dodge by walking about the deck (Walk the Deck's gates): no "killed spot" model.
local DODGE = { ["Walk the Deck"] = true }

type Box = { x0: number, x1: number, z0: number, z1: number, y0: number, y1: number }

-- A part's box at clock `t` (nil = at rest).
local function boxAt(part: Kit.Part, t: number?): Box
	local dx, dy, dz = Kit.offsetAt(part, t)
	local p, s = part.pos, part.size
	return {
		x0 = p[1] - s[1] / 2 + dx,
		x1 = p[1] + s[1] / 2 + dx,
		z0 = p[3] - s[3] / 2 + dz,
		z1 = p[3] + s[3] / 2 + dz,
		y0 = p[2] - s[2] / 2 + dy,
		y1 = p[2] + s[2] / 2 + dy,
	}
end

-- Edge-to-edge gap seen from above and the rise from a's top to b's.
local function gapRise(a: Box, b: Box): (number, number)
	local gx = math.max(0, b.x0 - a.x1, a.x0 - b.x1)
	local gz = math.max(0, b.z0 - a.z1, a.z0 - b.z1)
	return math.sqrt(gx * gx + gz * gz), b.y1 - a.y1
end

-- The clock a part reads at time t when its start group (if any) began at `started`.
local function clock(part: Kit.Part, t: number, started: number): number?
	if part.start then
		return if t >= started then t - started else nil
	end
	return t
end

-- The 1-stud spots on a ride's deck (offsets from its centre).
local function spots(part: Kit.Part): { { number } }
	local out = {}
	local hx, hz = part.size[1] / 2, part.size[3] / 2
	for x = -hx + 0.5, hx - 0.5 + 1e-6, 1 do
		for z = -hz + 0.5, hz - 0.5 + 1e-6, 1 do
			table.insert(out, { x, z })
		end
	end
	return out
end

-- Is a runner standing on `deck` (box) at spot (x, z) touching a hazard (box)?
local function hit(deck: Box, x: number, z: number, h: Box): boolean
	local cx, cz = (deck.x0 + deck.x1) / 2 + x, (deck.z0 + deck.z1) / 2 + z
	return cx >= h.x0 - BODY
		and cx <= h.x1 + BODY
		and cz >= h.z0 - BODY
		and cz <= h.z1 + BODY
		and h.y0 < deck.y1 + Kit.HEAD
		and h.y1 > deck.y1
end

export type Handoff = { from: number, to: number, jump: number, hold: number, board: number? }

--[[
	Every handoff along the steps: from step a to step b, over two periods of the slower one. `jump` is the longest
	stretch in which b is within a jump of a (gap <= GAP_MAX, rise <= RISE_MAX) while a runner still lives on a (a
	deck spot no hazard has touched since the ride last stood at rest, or since the runner got on it) and b has a spot
	no hazard touches; `hold` the longest stretch both stand still edge to edge, level (a stop you step across). A ride
	on a per-player clock (`start`) is tried for every start time over the other's period: `board` is the longest
	stretch of start times that leave a jump, `jump` the best jump over them.
]]
local function handoffs(section: Kit.Section, dodge: boolean): { Handoff }
	local steps, hazards = {}, {}
	for _, part in section.parts do
		if part.step then
			table.insert(steps, part)
		elseif part.hazard then
			table.insert(hazards, part)
		end
	end
	local out = {}
	for i = 2, #steps do
		local a, b = steps[i - 1], steps[i]
		if a.motion or b.motion then
			local period = math.max(Kit.periodOf(a), Kit.periodOf(b))
			local deckA = spots(a)
			-- one run of the pair with a's start group (if any) started at `started`: (longest jump, longest hold)
			local function run(started: number, from: number, to: number): (number, number)
				local killed: { [number]: boolean } = {}
				local bestJ, bestH, runJ, runH = 0, 0, 0, 0
				local t = from
				local last: { number }? = nil
				while t <= to do
					local ta, tb = clock(a, t, started), clock(b, t, started)
					local ba, bb = boxAt(a, ta), boxAt(b, tb)
					local dx, dy, dz = Kit.offsetAt(a, ta)
					if dx == 0 and dy == 0 and dz == 0 and not (a.start and ta) then
						killed = {} -- standing at rest: a runner gets on fresh
					end
					local hz = {}
					for _, h in hazards do
						table.insert(hz, boxAt(h, t))
					end
					local alive = false
					for k, s in deckA do
						for _, h in hz do
							if hit(ba, s[1], s[2], h) then
								killed[k] = true
							end
						end
						if dodge or not killed[k] then
							alive = true
						end
					end
					local landing = #hz == 0
					if not landing then
						for _, s in spots(b) do
							local free = true
							for _, h in hz do
								if hit(bb, s[1], s[2], h) then
									free = false
									break
								end
							end
							if free then
								landing = true
								break
							end
						end
					end
					local gap, rise = gapRise(ba, bb)
					if alive and landing and gap <= Kit.GAP_MAX and rise <= Kit.RISE_MAX then
						runJ += DT
						bestJ = math.max(bestJ, runJ)
					else
						runJ = 0
					end
					-- standing still: neither part moved since the last sample
					local now = { ba.x0, ba.y0, ba.z0, bb.x0, bb.y0, bb.z0 }
					local still = last ~= nil
					if last then
						for k = 1, 6 do
							still = still and math.abs(now[k] - last[k]) < 1e-9
						end
					end
					last = now
					if still and gap <= 0.5 and math.abs(rise) <= 0.5 then
						runH += DT
						bestH = math.max(bestH, runH)
					else
						runH = 0
					end
					t += DT
				end
				return bestJ, bestH
			end
			if a.start then
				-- try every start time over b's period
				local bestJ, bestH, board, runB = 0, 0, 0, 0
				local pa = Kit.periodOf(a)
				local s = 0
				while s < 2 * Kit.periodOf(b) do
					local j, h = run(s, s, s + pa)
					bestJ, bestH = math.max(bestJ, j), math.max(bestH, h)
					if j > 0 then
						runB += 0.05
						board = math.max(board, runB)
					else
						runB = 0
					end
					s += 0.05
				end
				table.insert(out, { from = i - 1, to = i, jump = bestJ, hold = bestH, board = board })
			else
				local j, h = run(0, 0, 2 * period)
				table.insert(out, { from = i - 1, to = i, jump = j, hold = h })
			end
		end
	end
	return out
end

local function round(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

describe("GooRides", function()
	it("builds all 18 designed variants in the design's order", function()
		expect(#idea.variants).toBe(18)
		expect(idea.variants[1].name).toBe("First Ferry")
		expect(idea.variants[18].name).toBe("Shaft Rush")
		expect(idea.generator).toBeNil()
	end)

	it("passes every ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(idea) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it(
		"every handoff leaves the tier's window to jump, and no stop stands still longer than the tier allows",
		function()
			local problems = {}
			for i, v in idea.variants do
				local section = v.build(1)
				local need = ObbyCheck.WINDOW[v.tier]
				local rows = {}
				for _, h in handoffs(section, DODGE[v.name] == true) do
					table.insert(
						rows,
						`{h.from}->{h.to} jump {round(h.jump)} hold {round(h.hold)}`
							.. (if h.board then ` board {round(h.board)}` else "")
					)
					if h.jump < need - 1e-6 then
						table.insert(
							problems,
							`#{i} {v.name} step {h.from}->{h.to}: jump window {round(h.jump)} s < {need}`
						)
					end
					if h.board and h.board < need - 1e-6 then
						table.insert(
							problems,
							`#{i} {v.name} step {h.from}->{h.to}: start window {round(h.board)} s < {need}`
						)
					end
					if h.hold > HOLD_MAX[v.tier] + 0.02 then
						table.insert(
							problems,
							`#{i} {v.name} step {h.from}->{h.to}: stands still {round(h.hold)} s > {HOLD_MAX[v.tier]}`
						)
					end
				end
				if DEBUG then
					print(`  #{i} {v.name} ({v.tier}): {table.concat(rows, ", ")}`)
				end
			end
			expect(table.concat(problems, "\n")).toBe("")
		end
	)

	it("rides heading into goo or a cap kill whoever stays on, wherever they stand", function()
		-- variant name -> the steps (in path order) that are rides you must leave in time
		local deadly = {
			["Into the Goo"] = { 2 },
			["Wrong Stop"] = { 2 },
			["Sink and Swap"] = { 2 },
			["Triple Transfer"] = { 2, 3 },
			["Express"] = { 2 },
			["Shaft Rush"] = { 2, 3 },
		}
		local seen = 0
		for _, v in idea.variants do
			local list = deadly[v.name]
			if list then
				seen += 1
				local section = v.build(1)
				local steps, hazards = {}, {}
				for _, part in section.parts do
					if part.step then
						table.insert(steps, part)
					elseif part.hazard then
						table.insert(hazards, part)
					end
				end
				for _, index in list do
					local ride = steps[index]
					local deck = spots(ride)
					local killed, n = {}, 0
					-- from the ride's rest (its clock at 0) over one period: every deck spot meets goo
					local t = 0
					while t <= Kit.periodOf(ride) do
						local box = boxAt(ride, t)
						for k, s in deck do
							if not killed[k] then
								for _, h in hazards do
									if hit(box, s[1], s[2], boxAt(h, t)) then
										killed[k] = true
										n += 1
										break
									end
								end
							end
						end
						t += DT
					end
					if n ~= #deck then
						print(`  {v.name} step {index}: {#deck - n} deck spots never meet goo`)
					end
					expect(n).toBe(#deck)
				end
			end
		end
		expect(seen).toBe(6)
	end)

	it("Wrong Stop: the trip to the exit stop never touches the goo over the other stop", function()
		local section = idea.variants[14].build(1)
		local ride = section.parts[2]
		local m = ride.motion :: Kit.Motion
		local hazards = {}
		for _, part in section.parts do
			if part.hazard then
				table.insert(hazards, part)
			end
		end
		expect(#hazards).toBe(1)
		-- the first two legs (out to the exit stop and back) take half the period
		local t, touched = 0, 0
		while t <= Kit.periodOf(ride) / 2 do
			local box = boxAt(ride, t)
			for _, s in spots(ride) do
				if hit(box, s[1], s[2], boxAt(hazards[1], t)) then
					touched += 1
				end
			end
			t += DT
		end
		expect(touched).toBe(0)
		expect((m.points :: any)[2][3] < 0).toBe(true)
	end)

	it("Quick Stop: whenever you get off onto a melting pad, the next ferry comes before the pad melts", function()
		local section = idea.variants[13].build(1)
		local steps = {}
		for _, part in section.parts do
			if part.step then
				table.insert(steps, part)
			end
		end
		local function reach(a: Kit.Part, b: Kit.Part, t: number): boolean
			local gap, rise = gapRise(boxAt(a, t), boxAt(b, t))
			return gap <= Kit.GAP_MAX and rise <= Kit.RISE_MAX
		end
		local pads = 0
		local worst = math.huge
		for i, pad in steps do
			local m = pad.motion
			if m and m.kind == "melt" then
				pads += 1
				local before, after = steps[i - 1], steps[i + 1]
				expect(before.motion and before.motion.kind).toBe("path")
				expect(after.motion and after.motion.kind).toBe("path")
				-- land at any moment the ferry before is in reach; cross the 6-stud pad (0.4 s) and count how long
				-- the next ferry is in reach before the pad melts under you
				local period = Kit.periodOf(before)
				local t = 0
				while t < 2 * period do
					if reach(before, pad, t) then
						local open, s = 0, t + 0.4
						while s <= t + (m.delay or 0) do
							if reach(pad, after, s) then
								open += DT
							end
							s += DT
						end
						worst = math.min(worst, open)
					end
					t += DT
				end
			end
		end
		if DEBUG then
			print(`  Quick Stop: worst time to board the next ferry before the pad melts {round(worst)} s`)
		end
		expect(pads).toBe(2)
		expect(worst >= ObbyCheck.WINDOW.medium - DT).toBe(true)
	end)

	it("Walk the Deck: between two gates there is the medium window to cross to the open half", function()
		local section = idea.variants[10].build(1)
		local deck = section.parts[2]
		local m = deck.motion :: Kit.Motion
		local speed = (m.points :: any)[2][1] / ((Kit.periodOf(deck) - 2 * (m.hold or 0)) / 2)
		local gates = {}
		for _, part in section.parts do
			if part.hazard then
				table.insert(gates, part)
			end
		end
		expect(#gates).toBe(3)
		for k = 2, #gates do
			local spacing = gates[k].pos[1] - gates[k - 1].pos[1]
			-- a spot on the deck is under a gate for (gate thickness + body) / speed; the rest is the time to switch
			local switch = (spacing - gates[k].size[1] - 2 * BODY) / speed
			expect(switch >= ObbyCheck.WINDOW.medium - 1e-6).toBe(true)
			expect(switch <= 1.4 + 1e-6).toBe(true)
			-- the gates take turns: one half, then the other
			expect(gates[k].pos[3] * gates[k - 1].pos[3] < 0).toBe(true)
		end
	end)
end)
