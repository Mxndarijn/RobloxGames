--!strict
-- Key Run (obby idea 20): every variant and the Scatter generator through ObbyCheck, plus what the shared checks
-- don't ask: walking forward fails even with every gate open, a gate can't be jumped or walked round, every key
-- branch's own hazards sit in the tier's band (the shared runner may dodge them on another lane), the ring doors
-- of Hazard Guard open for the tier's window, and the generator keeps its rules and stays solvable over many seeds.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local KeyRun = require("../../src/shared/ObbySections/KeyRun")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

local idea: Kit.Idea = KeyRun :: any

local NAMES = {
	"Key Line",
	"Three Islands",
	"Up and Back",
	"Spare Key",
	"Scatter: Both Sides",
	"Under the Bridge",
	"Hazard Guard",
	"Bounce Key",
	"Drifting Keys",
	"Ride for It",
	"Out and Back",
	"Two Gates",
	"Keys in the Dark",
	"Scatter: Far Pair",
	"Scatter: One Drifts",
	"Countdown Lock",
	"Four Corners",
	"Next Key Glows",
	"Scatter: Four Wide",
	"Scatter: Four and Drift",
}

-- Hazard windows a tier earns (contract §10); a window longer than STILL s is a still hazard you steer round.
local BAND = {
	easy = { lo = 1.4, hi = 2.0 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}
local STILL = 5
local GEN_SEEDS = 200

local function withParts(section: Kit.Section, keep: (Kit.Part, number) -> boolean): Kit.Section
	local parts = {}
	for i, part in section.parts do
		if keep(part, i) then
			table.insert(parts, part)
		end
	end
	return { length = section.length, rise = section.rise, parts = parts }
end

describe("KeyRun", function()
	it("is idea 20 with every variant of the design file, in order, and a generator", function()
		expect(idea.id).toBe("KeyRun")
		expect(idea.idea).toBe(20)
		expect(#idea.variants).toBe(#NAMES)
		for i, name in NAMES do
			expect(idea.variants[i].name).toBe(name)
		end
		local gen = idea.generator :: Kit.Generator
		expect(gen ~= nil).toBe(true)
		expect(table.concat(gen.tiers, ",")).toBe("easy,medium,hard")
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

	it("can't be walked forward even with every gate open", function()
		for _, case in ObbyCheck.cases(idea) do
			for seed = 1, 5 do
				local open = withParts(case.build(seed), function(part)
					return part.gate == nil
				end)
				local why = ObbyCheck.straightWalk(open)
				if why then
					error(`{case.name} seed {seed} without gates: {why}`)
				end
			end
		end
	end)

	it("has a gate you can't jump over or walk round", function()
		for _, case in ObbyCheck.cases(idea) do
			local section = case.build(1)
			local gates = {}
			for _, part in section.parts do
				if part.gate and part.size[1] < 2 then
					table.insert(gates, part)
				end
			end
			if #gates == 0 then
				error(`{case.name}: no gate`)
			end
			for _, g in gates do
				local gx = g.pos[1]
				local bottom = g.pos[2] - g.size[2] / 2
				local z0, z1 = g.pos[3] - g.size[3] / 2, g.pos[3] + g.size[3] / 2
				if g.size[2] < 9 then
					error(`{case.name}: gate only {g.size[2]} tall`)
				end
				for _, part in section.parts do
					if part.step then
						local x0, x1, _, top, pz0, pz1 = Kit.bounds(part)
						-- A floor under the gate: the gate covers it across, with 2 studs past an edge that isn't the lane's.
						if x0 < gx and x1 > gx and pz1 > z0 and pz0 < z1 then
							local okLeft = z0 <= pz0 + 1e-6 and (z0 <= -Kit.HALF + 1e-6 or z0 <= pz0 - 2 + 1e-6)
							local okRight = z1 >= pz1 - 1e-6 and (z1 >= Kit.HALF - 1e-6 or z1 >= pz1 + 2 - 1e-6)
							if not (okLeft and okRight) then
								error(`{case.name}: the gate at x {gx} doesn't close the floor z {pz0}..{pz1}`)
							end
						end
						-- No running jump off a floor before it clears its top (feet over the top as they reach it).
						if x1 <= gx and pz1 > z0 and pz0 < z1 then
							local t = math.max(gx - g.size[1] / 2 - x1, 0) / Kit.WALK
							local v = Kit.JUMP_SPEED
							local peakAt = v / Kit.GRAVITY
							local rise = if t < peakAt then Kit.JUMP_HEIGHT else v * t - Kit.GRAVITY * t * t / 2
							if top + rise >= bottom + g.size[2] then
								error(
									`{case.name}: a jump off a floor {top} high {gx - x1} studs before the gate clears it`
								)
							end
						end
					end
				end
			end
		end
	end)

	it("times every hazard on whichever lane it guards to the tier", function()
		-- One hazard at a time, with only the floors under it at its x (the shared runner may dodge onto another lane,
		-- a player fetching a key there can't).
		for _, case in ObbyCheck.cases(idea) do
			local band = BAND[case.tier]
			for seed = 1, (if case.variant == 0 then 5 else 1) do
				local section = case.build(seed)
				for hi, h in section.parts do
					if h.hazard and h.motion and h.motion.kind ~= "rise" then
						local hx0, hx1, _, _, hz0, hz1 = Kit.bounds(h)
						local view = withParts(section, function(part, i)
							if part.hazard then
								return i == hi
							elseif not part.step then
								return true
							end
							local x0, x1, _, _, z0, z1 = Kit.bounds(part)
							local beside = x1 > hx0 - 2 and x0 < hx1 + 2
							return not beside or (z1 > hz0 and z0 < hz1)
						end)
						for _, w in ObbyCheck.windows(view) do
							if w.slack < band.lo - 1e-6 or (w.slack < STILL and w.slack > band.hi + 1e-6) then
								error(
									`{case.name} seed {seed} hazard {hi}: window {w.slack} s at x {w.from}..{w.to} (band {band.lo}..{band.hi})`
								)
							end
						end
					end
				end
			end
		end
	end)

	it("opens Hazard Guard's ring doors for a medium window", function()
		local section = idea.variants[7].build(1)
		local doors = 0
		for _, part in section.parts do
			local m = part.motion
			if part.hazard and m and m.kind == "punch" and part.size[1] < 6 and part.size[3] < 6 then
				doors += 1
				local period = Kit.periodOf(part)
				local bottomRest = part.pos[2] - part.size[2] / 2
				-- open while the door's bottom is over a head; the crossing is the door's thickness plus a body
				local open, best, n = 0, 0, 2000
				for k = 0, 2 * n do
					local _, dy = Kit.offsetAt(part, k / n * period)
					if bottomRest + dy >= Kit.HEAD then
						open += period / n
						best = math.max(best, open)
					else
						open = 0
					end
				end
				local window = best - (math.min(part.size[1], part.size[3]) + 2) / Kit.WALK
				if window < BAND.medium.lo or window > BAND.medium.hi then
					error(`door window {window} s (band {BAND.medium.lo}..{BAND.medium.hi})`)
				end
			end
		end
		expect(doors).toBe(3)
	end)

	it("keeps the generator's rules and stays solvable over many seeds", function()
		local gen = idea.generator :: Kit.Generator
		local spots = (KeyRun :: any).SPOTS
		for _, tier in gen.tiers do
			for seed = 1, GEN_SEEDS do
				local section = gen.build(seed, tier)
				if ObbyCheck.encode(section) ~= ObbyCheck.encode(gen.build(seed, tier)) then
					error(`{tier} seed {seed}: not deterministic`)
				end
				for _, check in { ObbyCheck.makeable, ObbyCheck.fields, ObbyCheck.budget, ObbyCheck.widths } do
					local why = check(section)
					if why then
						error(`{tier} seed {seed}: {why}`)
					end
				end
				local keys, far, drifting, need = 0, 0, 0, 0
				for _, part in section.parts do
					if part.key then
						keys += 1
						if part.start then
							drifting += 1
						end
						for _, s in spots do
							if math.abs(part.pos[1] - (s.x + 4)) < 1e-6 then
								far += if s.far then 1 else 0
							end
						end
					end
					if part.gate then
						need = part.gate.need
					end
				end
				expect(need).toBe(keys)
				expect(drifting <= 1).toBe(true)
				if tier == "easy" then
					expect(keys >= 2 and keys <= 3).toBe(true)
					expect(far).toBe(0)
					expect(drifting).toBe(0)
				elseif tier == "medium" then
					expect(keys).toBe(3)
				else
					expect(keys).toBe(4)
					expect(far >= 2).toBe(true)
				end
				if seed <= 20 then
					local why = ObbyCheck.straightWalk(section)
					if why then
						error(`{tier} seed {seed}: {why}`)
					end
				end
			end
		end
	end)
end)
