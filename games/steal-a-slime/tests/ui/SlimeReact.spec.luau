--!strict
-- Reactions and beat poses (src/ui/SlimeReact.luau, src/ui/SlimeBeats.luau, contract/slime-life.md): "pick me" only
-- for a slime you can afford and reach, the other reactions by temperament, nerves before the drain, and a pose for
-- every lane beat.
local ParadeChoreo = require("../../src/shared/ParadeChoreo")
local ParadeLane = require("../../src/shared/ParadeLane")
local SlimeBeats = require("../../src/ui/SlimeBeats")
local SlimeBones = require("../../src/ui/SlimeBones")
local SlimeReact = require("../../src/ui/SlimeReact")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("SlimeReact.toPlayer", function()
	it("ignores a player outside REACT_DISTANCE", function()
		local p = SlimeReact.toPlayer("Bouncy", SlimeReact.REACT_DISTANCE + 1, 0, true, 0)
		expect(p.weight).toBe(0)
		expect(p.emote).toBeNil()
	end)
	it("pick me: an affordable slime in reach turns to you, bounces and shows a heart", function()
		local p = SlimeReact.toPlayer("Shy", 5, 0.7, true, 0.2)
		expect(p.yaw).toBe(0.7)
		expect(p.weight > 0.5).toBe(true)
		expect(p.lift > 0).toBe(true)
		expect(p.emote).toBe("love")
		expect(p.face).toBe("happy")
	end)
	it("without the cash it reacts by temperament", function()
		local shy = SlimeReact.toPlayer("Shy", 5, 0, false, 0)
		expect(shy.sy < 1 and shy.face == "worried").toBe(true)
		local feisty = SlimeReact.toPlayer("Feisty", 5, 0, false, 0)
		expect(feisty.face == "angry" and feisty.emote == "angry").toBe(true)
		local showoff = SlimeReact.toPlayer("Showoff", 5, 0, false, 0)
		expect(math.abs(showoff.yaw) > 1.5 and showoff.emote == "star").toBe(true)
		local lazy = SlimeReact.toPlayer("Lazy", 5, 0, false, 0)
		expect(lazy.weight < 0.3).toBe(true)
	end)
	it("a Curious slime leans towards you, a Shy one away", function()
		local left = math.pi / 2 -- the player stands to the slime's left: lean < 0
		expect(SlimeReact.toPlayer("Curious", 5, left, true, 0).lean < 0).toBe(true)
		expect(SlimeReact.toPlayer("Shy", 5, left, false, 0).lean > 0).toBe(true)
	end)
	it("nerves grow in the last NERVES_SECONDS before the telegraph", function()
		expect(SlimeReact.nerves(SlimeReact.NERVES_SECONDS + 1)).toBe(0)
		expect(SlimeReact.nerves(0)).toBeCloseTo(1, 1e-9)
	end)
	it("a startle is a short jump", function()
		expect(SlimeReact.startle(-0.1)).toBe(0)
		expect(SlimeReact.startle(SlimeReact.STARTLE_SECONDS / 2) > 0.5).toBe(true)
		expect(SlimeReact.startle(SlimeReact.STARTLE_SECONDS)).toBe(0)
	end)
end)

describe("SlimeBeats.pose", function()
	it("has a pose for every beat kind and phase, inside sane bounds", function()
		for _, kind in ParadeChoreo.KINDS do
			local any = false
			for _, phase in { "pre", "stop", "post" } do
				for u = 0, 1, 0.05 do
					local p = SlimeBeats.pose(kind, phase, u, 1, u * 3)
					expect(p.sy >= 0.55 and p.sy <= 1.45).toBe(true)
					expect(p.lift >= 0 and p.lift <= 2.5).toBe(true)
					expect(math.abs(p.lean) <= ParadeLane.ROOM).toBe(true) -- stays on the lane from the outermost line
					if p.face or p.emote or p.yaw or p.lift > 0 or p.sy ~= 1 then
						any = true
					end
				end
			end
			expect(any).toBe(true)
		end
	end)
	it("stands still with no beat", function()
		local p = SlimeBeats.pose("look", "none", 0.5, 1, 0)
		expect(p.yaw).toBeNil()
		expect(p.lift == 0 and p.sy == 1 and p.emote == nil).toBe(true)
	end)
	it("a nap sleeps, then wakes with a start", function()
		expect(SlimeBeats.pose("nap", "stop", 0.5, 1, 0).emote).toBe("sleep")
		expect(SlimeBeats.pose("nap", "stop", 0.93, 1, 0).face).toBe("surprised")
	end)
end)

describe("SlimeBones face and ears", function()
	it("ears fly up while the slime falls, droop a little while it rises", function()
		expect(SlimeBones.earFlop(-10) > 0.3).toBe(true)
		expect(SlimeBones.earFlop(-1000)).toBe(SlimeBones.EAR_FLOP_MAX)
		expect(SlimeBones.earFlop(10) < 0).toBe(true)
		expect(SlimeBones.earFlop(1000)).toBe(-0.3)
	end)
end)
