--!strict
-- Sticky Walls (obby idea 22): every variant through ObbyCheck, plus what the shared checks don't ask: the variants
-- are the design file's, in its order and tiers; every one needs its goo (turn the walls into plain stone and it
-- can't be made); every goo wall shows its handprints; and the slide gets faster with the tier (contract §10).
local T = require("../TestRunner")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local StickyWalls = require("../../src/shared/ObbySections/StickyWalls")

-- The slowest slide a tier's walls may have (studs / s): faster walls leave less time to aim.
local MIN_FALL = { easy = 2, medium = 2, hard = 2.5 }
-- A character is 2 studs wide: drops in a sheet must leave less than that between them.
local BODY_WIDTH = 2
-- A jump off throws you 30 studs / s across and you steer forward at about walking speed, so a hop of about 10
-- across carries you about 5 forward: the most open air along x between a wall and the next step.
local HOP_AIR = 5
-- ObbyMoves.STICK_REACH: studs past the root's side a goo face still grips; stone over goo must be deeper.
local GRIP_REACH = 1.2

-- The section with every goo wall turned into a plain wall.
local function dry(section: Kit.Section): Kit.Section
	local parts = {}
	for _, part in section.parts do
		local copy = table.clone(part)
		copy.sticky = nil
		table.insert(parts, copy)
	end
	return { length = section.length, rise = section.rise, parts = parts }
end

describe("StickyWalls", function()
	it("is idea 22 with every variant of the design file, in its order and tiers", function()
		expect(StickyWalls.id).toBe("StickyWalls")
		expect(StickyWalls.name).toBe("Sticky Walls")
		expect(StickyWalls.idea).toBe(22)
		expect((StickyWalls :: any).generator).toBeNil()
		local design = serde.decode("json", fs.readFile("docs/obby-variants/22.json")).ideas[1]
		expect(#StickyWalls.variants).toBe(#design.variants)
		for i, v in design.variants do
			expect(StickyWalls.variants[i].name).toBe(v.name)
			expect(StickyWalls.variants[i].tier).toBe(v.tier)
		end
	end)

	it("passes every shared check", function()
		local problems = {}
		for _, case in ObbyCheck.cases(StickyWalls) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("can't be made without the goo", function()
		for _, case in ObbyCheck.cases(StickyWalls) do
			if ObbyCheck.makeable(dry(case.build(1))) == nil then
				error(`{case.name} is makeable with plain walls`)
			end
		end
	end)

	it("marks every goo wall with handprints and slides faster with the tier", function()
		for _, case in ObbyCheck.cases(StickyWalls) do
			local walls = 0
			for _, part in case.build(1).parts do
				if part.sticky then
					walls += 1
					expect(part.look).toBe("sticky")
					expect(part.marker).toBe("handprints")
					expect(part.step).toBe(true)
					if part.sticky.fall < MIN_FALL[case.tier] then
						error(
							`{case.name}: a wall slides {part.sticky.fall} studs / s (a {case.tier} one at least {MIN_FALL[case.tier]})`
						)
					end
				end
			end
			if walls == 0 then
				error(`{case.name} has no goo wall`)
			end
		end
	end)

	it("leaves no more air along the course than a jump off carries you forward", function()
		for _, case in ObbyCheck.cases(StickyWalls) do
			local last: Kit.Part? = nil
			for _, part in case.build(1).parts do
				if part.step then
					if last and last.sticky then
						local _, x1 = Kit.bounds(last)
						local x0 = Kit.bounds(part)
						if x0 - x1 > HOP_AIR + 1e-6 then
							error(`{case.name}: {x0 - x1} studs of air along x after a wall (at most {HOP_AIR})`)
						end
					end
					last = part
				end
			end
		end
	end)

	it("covers goo with stone deeper than the grip reaches", function()
		for _, case in ObbyCheck.cases(StickyWalls) do
			for _, part in case.build(1).parts do
				if part.look == "pad" and not part.step then
					expect(part.size[3] > GRIP_REACH).toBe(true)
				end
			end
		end
	end)

	it("has red goo in every variant", function()
		for _, case in ObbyCheck.cases(StickyWalls) do
			local hazard = false
			for _, part in case.build(1).parts do
				hazard = hazard or part.hazard == true
			end
			if not hazard then
				error(`{case.name} has no red goo`)
			end
		end
	end)

	-- The sticky controller grips a goo part whatever its motion, so dry goo must be stone closing over the face.
	it("dries goo with moving stone over a goo face, never by moving the goo", function()
		local drying = { ["Drying Goo"] = "flip", ["Quick Dry"] = "path", ["Goo Gauntlet"] = "flip" }
		for _, case in ObbyCheck.cases(StickyWalls) do
			local parts = case.build(1).parts
			local covers = 0
			for _, part in parts do
				if part.sticky then
					expect(part.motion == nil or part.motion.kind == "path").toBe(true) -- only Breathing Wall moves
				end
				if part.look == "pad" and part.motion then
					covers += 1
					expect(part.motion.kind).toBe(drying[StickyWalls.variants[case.variant].name])
					expect(part.size[3] > GRIP_REACH).toBe(true)
					-- where it covers (a shutter at its lowest point), it overlaps a goo wall along x and y
					local dy = 0
					if part.motion.kind == "path" then
						for _, pt in part.motion.points :: { { number } } do
							dy = math.min(dy, pt[2])
						end
						local group = part.start
						expect(group ~= nil).toBe(true)
						local triggered = false
						for _, other in parts do
							triggered = triggered or (other.sticky ~= nil and other.trigger == group)
						end
						expect(triggered).toBe(true)
					end
					local x0, x1 = Kit.bounds(part)
					local covered = false
					for _, wall in parts do
						if wall.sticky then
							local w0, w1 = Kit.bounds(wall)
							local sameY = math.abs(wall.pos[2] - (part.pos[2] + dy)) < 0.01
							local nearZ = math.abs(wall.pos[3] - part.pos[3])
								<= (wall.size[3] + part.size[3]) / 2 + 0.01
							covered = covered or (x0 >= w0 - 0.01 and x1 <= w1 + 0.01 and sameY and nearZ)
						end
					end
					if not covered then
						error(`{case.name}: a drying stone at x {x0}..{x1} covers no goo face`)
					end
				end
			end
			if drying[StickyWalls.variants[case.variant].name] then
				if covers == 0 then
					error(`{case.name} has no drying stone`)
				end
			else
				expect(covers).toBe(0)
			end
		end
	end)

	it("leaves no gap a character fits through in Goo Drip's sheets of drops", function()
		for _, case in ObbyCheck.cases(StickyWalls) do
			if StickyWalls.variants[case.variant].name == "Goo Drip" then
				local rows: { [number]: { Kit.Part } } = {}
				for _, part in case.build(1).parts do
					if part.hazard and part.shape == "ball" then
						local key = math.floor(part.pos[3] * 10 + 0.5)
						rows[key] = rows[key] or {}
						table.insert(rows[key], part)
					end
				end
				local n = 0
				for _, row in rows do
					table.sort(row, function(a, b)
						return a.pos[1] < b.pos[1]
					end)
					for i = 2, #row do
						local a, b = row[i - 1], row[i]
						local gap = (b.pos[1] - b.size[1] / 2) - (a.pos[1] + a.size[1] / 2)
						-- drops of one wall share a beat; a jump to the next wall's row is a new sheet
						if a.motion and b.motion and a.motion.phase == b.motion.phase then
							n += 1
							expect(gap < BODY_WIDTH).toBe(true)
						end
					end
				end
				expect(n > 0).toBe(true)
			end
		end
	end)
end)
