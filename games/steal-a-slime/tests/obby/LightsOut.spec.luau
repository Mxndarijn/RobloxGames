--!strict
-- Lights Out (obby idea 17): every variant through ObbyCheck, plus the idea's own rules (every variant is dark, the
-- lights that guide you are wired to real triggers, and hazards keep their tier's window).
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local LightsOut = require("../../src/shared/ObbySections/LightsOut")
local ObbyCheck = require("../ObbyCheck")

describe("LightsOut", function()
	it("every variant passes ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(LightsOut :: any) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("builds all 18 designed variants in the design file's order", function()
		local names = {}
		for _, v in LightsOut.variants do
			table.insert(names, v.name)
		end
		expect(table.concat(names, ",")).toBe(
			"Night Walk,Lantern Zigzag,Glow Edges,Light the Way,Glow Stairs,Firefly Friend,Blink,Firefly Pace,"
				.. "Feel the Way,Lighthouse,Dark Movers,Red in the Dark,Dark Shortcut,Campfire Hop,Thunder Flash,"
				.. "Night Shift,Beam Over Goo,Fading Lantern"
		)
	end)

	it("every variant is night over its whole length and has a hazard or a timed part", function()
		for _, v in LightsOut.variants do
			local s = v.build(1)
			local covered, hazard = 0, false
			for _, p in s.parts do
				if p.zone and p.zone.kind == "dark" then
					covered += p.size[1]
					expect(p.zone.light ~= nil and p.zone.light >= 3 and p.zone.light <= 16).toBe(true)
				end
				if p.hazard or (p.motion and p.motion.kind ~= "path") then
					hazard = true
				end
			end
			expect(math.abs(covered - s.length) < 1e-6).toBe(true)
			expect(hazard).toBe(true)
		end
	end)

	it("a light that waits for you is set off by a platform before the one it shows", function()
		for _, v in LightsOut.variants do
			local s = v.build(1)
			local triggerX: { [string]: number } = {}
			for _, p in s.parts do
				if p.trigger then
					expect(p.step).toBe(true)
					triggerX[p.trigger] = p.pos[1]
				end
			end
			for _, p in s.parts do
				if p.start then
					local tx = triggerX[p.start]
					expect(tx ~= nil).toBe(true)
					-- the light sits in (or over) a later platform than the one you stand on to set it off
					local m = p.motion :: any
					local points = m.points
					local last = points[#points]
					expect(p.pos[1] + last[1] > (tx :: number) + 1).toBe(true)
				end
			end
		end
	end)

	-- Dark Shortcut's two roads are measured one at a time: ObbyCheck.windows runs over both floors at once, and
	-- while one road's red light is on the other road is usually open, so the joint window says nothing.
	local function mainRoad(s: any): any
		local parts = {}
		for _, p in s.parts do
			local onDarkRoad = p.route == "dark" or (p.hazard and p.pos[3] > 2)
			if not onDarkRoad then
				table.insert(parts, p)
			end
		end
		return { length = s.length, rise = s.rise, parts = parts }
	end
	local function darkRoad(s: any): any
		local parts = {}
		for _, p in s.parts do
			local onLitRoad = (p.step and p.route == nil and p.size[3] < 10) or (p.hazard and p.pos[3] < -2)
			if not onLitRoad then
				table.insert(parts, p)
			end
		end
		return { length = s.length, rise = s.rise, parts = parts }
	end

	it("every variant has a timed hazard and keeps its windows inside the tier's band", function()
		-- Only stretches with moving or blinking goo have a real window (static goo leaves the whole horizon open).
		local band = { easy = { 1.4, 2.0 }, medium = { 1.0, 1.4 }, hard = { 0.75, 1.0 } }
		for _, v in LightsOut.variants do
			local b = band[v.tier]
			local s = v.build(1)
			local sections = if v.name == "Dark Shortcut" then { mainRoad(s), darkRoad(s) } else { s }
			for _, section in sections do
				local timed = 0
				for _, w in ObbyCheck.windows(section) do
					if w.slack < 5 then
						timed += 1
						if not (w.slack >= b[1] - 1e-6 and w.slack <= b[2] + 1e-6) then
							error(`{v.name}: window {w.slack} s at x {w.from}..{w.to} is outside {b[1]}..{b[2]}`)
						end
					end
				end
				if timed == 0 then
					local ws = {}
					for _, w in ObbyCheck.windows(section) do
						table.insert(ws, `{w.from}-{w.to}:{w.slack}`)
					end
					error(`{v.name}: no timed hazard {table.concat(ws, " ")} {#section.parts}`)
				end
			end
		end
	end)

	it("moving and blinking goo is taller than a jump, so you can't hop over it", function()
		for _, v in LightsOut.variants do
			for _, p in v.build(1).parts do
				local m = p.motion :: any
				local riding = m and m.kind == "slide" and p.size[2] < 3 -- dim goo riding on a moving platform
				if p.hazard and m and not riding then
					expect(p.size[2] > 7.2).toBe(true)
				end
			end
		end
	end)
end)
