--!strict
-- Rolling Blobs (obby idea 14): every variant through the shared section checks, plus the idea's own rules: every
-- ball is a red hazard that comes out of a launcher you can see, and drains out of reach under the floor.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local RollingBlobs = require("../../src/shared/ObbySections/RollingBlobs")

-- Seconds into a ball's period when it leaves the launcher (its path's cycle 0).
local function fireTime(part: Kit.Part): number
	local m = part.motion :: Kit.Motion
	local period = Kit.periodOf(part)
	return ((1 - (m.phase or 0)) % 1) * period
end

local function inside(p: Kit.Vec, box: Kit.Part, dx: number, dy: number, dz: number): boolean
	for i, d in { dx, dy, dz } do
		if math.abs(p[i] - (box.pos[i] + d)) > box.size[i] / 2 + 1e-6 then
			return false
		end
	end
	return true
end

describe("Rolling Blobs", function()
	it("has every variant of the design file in order", function()
		local names = {}
		for _, v in RollingBlobs.variants do
			table.insert(names, v.name)
		end
		expect(table.concat(names, ",")).toBe(
			"Lane Watch,Pebble Hop,Wall Pockets,Two Lanes Swap,Slow Giants,Burst and Lull,Bouncers,Switchback,"
				.. "Big and Small,Road Crossing,Funnel,Roaming Launcher,Zigzag Grooves,Odd One Out,Full Sweep,"
				.. "Stair Bounce,Storm Ramp"
		)
		expect(RollingBlobs.id).toBe("RollingBlobs")
		expect(RollingBlobs.idea).toBe(14)
	end)

	for _, case in ObbyCheck.cases(RollingBlobs :: any) do
		it(`{case.name} ({case.tier}) passes every section check`, function()
			local problems = ObbyCheck.run(case)
			expect(table.concat(problems, "\n")).toBe("")
		end)
	end

	-- Not too easy (contract §10): the runner never finds a line that stays open (an edge strip, a lane no ball
	-- takes). Such a line shows as a window as long as the runner's whole horizon; tuned ones sit near the tier floor.
	it("leaves no line that is always open", function()
		for _, v in RollingBlobs.variants do
			for _, w in ObbyCheck.windows(v.build(1)) do
				if w.slack > 3 then
					error(`{v.name}: hazards at x {w.from}..{w.to} open {w.slack} s: a line nothing ever crosses`)
				end
			end
		end
	end)

	it("fires every ball from inside a launcher housing, and drains it under the floor", function()
		for _, v in RollingBlobs.variants do
			local s = v.build(1)
			local houses = {}
			for _, p in s.parts do
				if p.look == "post" and not p.ghost then
					table.insert(houses, p)
				end
			end
			for i, p in s.parts do
				if p.hazard then
					local m = p.motion :: Kit.Motion
					expect(m.kind).toBe("path")
					expect(m.loop == true and m.jump == true and m.spinRoll == true).toBe(true)
					local t = fireTime(p)
					local found = false
					for _, h in houses do
						local dx, dy, dz = Kit.offsetAt(h, t)
						if inside(p.pos, h, dx, dy, dz) then
							found = true
						end
					end
					if not found then
						error(`{v.name}: ball {i} does not start inside a launcher`)
					end
					-- Somewhere on its way it sinks fully under the floor top it rolled on (the drain).
					local lowest, at = math.huge, p.pos
					for _, q in m.points or {} do
						local top = p.pos[2] + q[2] + p.size[2] / 2
						if top < lowest then
							lowest, at = top, { p.pos[1] + q[1], 0, p.pos[3] + q[3] }
						end
					end
					local floor = -math.huge
					for _, f in s.parts do
						if f.step then
							local x0, x1, _, y1 = Kit.bounds(f)
							if x1 >= at[1] - 6 and x0 <= at[1] + 6 then
								floor = math.max(floor, y1)
							end
						end
					end
					if lowest > floor - 2 then
						error(`{v.name}: ball {i} never drains (top {lowest}, floor {floor})`)
					end
				end
			end
		end
	end)
end)
