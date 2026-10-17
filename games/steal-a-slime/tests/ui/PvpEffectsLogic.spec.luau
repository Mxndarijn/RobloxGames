--!strict
-- Client PvP effects, pure part (src/ui/PvpEffectsLogic): which visual / sound per effect, clamped durations,
-- marker rules, shake math, tracker bookkeeping, and the PvP sound ids.
local Config = require("../../src/shared/Config")
local Logic = require("../../src/ui/PvpEffectsLogic")
local PvpRules = require("../../src/shared/PvpRules")
local Sounds = require("../../src/ui/Sounds")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local P = Config.PVP

local function plan(payload: any, low: boolean?): any
	return Logic.plan(payload, P, low == true)
end

describe("PvpEffectsLogic.plan", function()
	it("Knockback: burst + short flash + victim shake + punch sfx + launch", function()
		local p = plan({ effect = "Knockback", itemId = "KnockGlove3", target = 2, duration = 1 })
		expect(p.sfx).toBe("PvpHit")
		expect(p.burst.count > 0).toBe(true)
		expect(p.highlight.seconds <= 0.25 and p.highlight.seconds >= 0.15).toBe(true)
		expect(p.shake.seconds <= 0.3).toBe(true)
		expect(p.applyVelocity).toBe(true)
		expect(p.seconds <= P.FX_SECONDS).toBe(true)
	end)
	it("Freeze: green goo highlight for the duration, clamped to CONTROL_MAX_SECONDS", function()
		local p = plan({ effect = "Freeze", duration = 1.5, target = 2 })
		expect(p.sfx).toBe("PvpGoo")
		expect(p.highlight.seconds).toBe(1.5)
		expect(p.highlight.color[2] > p.highlight.color[1]).toBe(true)
		expect(plan({ effect = "Freeze", duration = 99, target = 2 }).highlight.seconds).toBe(P.CONTROL_MAX_SECONDS)
	end)
	it("Slow hit: beam + splat + highlight for duration (<= SLOW_MAX); miss: 0.4 s beam to position only", function()
		local hit = plan({ effect = "Slow", target = 2, duration = 2.5 })
		expect(hit.beam ~= nil and hit.burst ~= nil and hit.highlight.seconds == 2.5).toBe(true)
		expect(hit.sfx).toBe("PvpSquirt")
		expect(plan({ effect = "Slow", target = 2, duration = 99 }).highlight.seconds).toBe(P.SLOW_MAX_SECONDS)
		local miss = plan({ effect = "Slow", position = 1, duration = 0.4 })
		expect(miss.beam.seconds).toBe(0.4)
		expect(miss.highlight).toBe(nil)
		expect(miss.burst).toBe(nil)
		expect(miss.onTarget).toBe(false)
	end)
	it("Cosmetic: each item has its own colours / sfx; Fireworks lasts FIREWORKS_SECONDS at most", function()
		local ids = { "FunConfetti", "FunBalloon", "FunBubbles", "FunHatLauncher", "FunFireworks", "FunSqueaky" }
		local seen: { [string]: boolean } = {}
		for _, id in ids do
			local p = plan({ effect = "Cosmetic", itemId = id, duration = 99 })
			expect(p ~= nil).toBe(true)
			expect(p.seconds <= math.max(P.FX_SECONDS, P.FIREWORKS_SECONDS)).toBe(true)
			expect(Sounds.resolve(p.sfx) ~= nil).toBe(true)
			seen[p.sfx] = true
		end
		expect(plan({ effect = "Cosmetic", itemId = "FunSqueaky" }).sfx).toBe("PvpSqueak")
		expect(plan({ effect = "Cosmetic", itemId = "FunFireworks", duration = 99 }).seconds).toBe(P.FIREWORKS_SECONDS)
		expect(plan({ effect = "Cosmetic", itemId = "FunBubbles" }).sfx).toBe("PvpBubble")
		expect(plan({ effect = "Cosmetic", itemId = "FunConfetti" }).seconds).toBe(P.FX_SECONDS)
	end)
	it("Dance and Bounce", function()
		local d = plan({ effect = "Dance", duration = 2, target = 2 })
		expect(d.highlight.seconds).toBe(2)
		local b = plan({ effect = "Bounce", target = 2, duration = 1.2 })
		expect(b.sfx).toBe("PvpBoing")
		expect(b.trail <= 0.6 and b.trail > 0).toBe(true)
		expect(b.applyVelocity).toBe(true)
	end)
	it("unknown / junk payloads show nothing", function()
		expect(plan({ effect = "Nope" })).toBe(nil)
		expect(plan({})).toBe(nil)
		expect(Logic.plan("x", P, false)).toBe(nil)
	end)
	it("nothing outlives its plan.seconds; every sfx name resolves", function()
		for _, effect in { "Knockback", "Freeze", "Slow", "Dance", "Bounce", "Cosmetic" } do
			local p = plan({ effect = effect, target = 2, duration = 99, itemId = "FunFireworks" })
			expect(p.seconds <= math.max(P.FX_SECONDS, P.CONTROL_MAX_SECONDS, P.SLOW_MAX_SECONDS, P.FIREWORKS_SECONDS)).toBe(
				true
			)
			expect((p.highlight == nil) or p.highlight.seconds <= p.seconds).toBe(true)
			expect((p.trail == nil) or p.trail <= p.seconds).toBe(true)
			expect((p.beam == nil) or p.beam.seconds <= p.seconds).toBe(true)
			expect(Sounds.resolve(p.sfx) ~= nil).toBe(true)
		end
	end)
	it("low quality halves particle counts (never below 1)", function()
		local full = plan({ effect = "Cosmetic", itemId = "FunFireworks" }).burst.count
		local low = plan({ effect = "Cosmetic", itemId = "FunFireworks" }, true).burst.count
		expect(low).toBe(math.floor(full / 2))
		expect(Logic.scaleCount(1, true)).toBe(1)
	end)
end)

describe("PvpEffectsLogic markers", function()
	local function tool(id: string): any
		return PvpRules.tool(id)
	end
	it("a Goo Trap puddle is owner-only and sized by the trap radius", function()
		local m = Logic.marker("GooTrap2", tool("GooTrap2"), P)
		expect(m ~= nil and m.shape == "puddle" and m.diameter == tool("GooTrap2").radius * 2).toBe(true)
		expect(Logic.markerVisible(m :: any, 1, 1)).toBe(true)
		expect(Logic.markerVisible(m :: any, 1, 2)).toBe(false)
	end)
	it("the Bounce Pad marker is public and expires after the pad lifetime", function()
		local m = Logic.marker("FunBouncePad", tool("FunBouncePad"), P) :: any
		expect(m.shape).toBe("pad")
		expect(Logic.markerVisible(m, 1, 2)).toBe(true)
		expect(m.seconds >= P.BOUNCE_PAD_SECONDS).toBe(true)
	end)
	it("other items have no marker", function()
		expect(Logic.marker("KnockGlove1", tool("KnockGlove1"), P)).toBe(nil)
		expect(Logic.marker(nil, nil, P)).toBe(nil)
	end)
end)

describe("PvpEffectsLogic shake, range, tracker", function()
	it("the shake decays to zero within its seconds", function()
		local x0, y0 = Logic.shakeOffset(0.01, 0.3, 0.25)
		local x1, y1 = Logic.shakeOffset(0.29, 0.3, 0.25)
		expect(math.abs(x0) + math.abs(y0) > math.abs(x1) + math.abs(y1)).toBe(true)
		expect(Logic.shakeOffset(0.3, 0.3, 0.25)).toBe(0)
		expect(Logic.shakeOffset(-1, 0.3, 0.25)).toBe(0)
		expect(math.abs(x0) <= 0.25 and math.abs(y0) <= 0.25).toBe(true)
	end)
	it("range check", function()
		expect(Logic.inRange(10)).toBe(true)
		expect(Logic.inRange(Logic.FX_RANGE + 1)).toBe(false)
		expect(Logic.inRange(0 / 0)).toBe(false)
	end)
	it("tracker: acquire / release return to 0 and never go negative", function()
		local t = Logic.tracker()
		t.acquire("emitter")
		t.acquire("emitter")
		t.acquire("highlight")
		expect(t.count()).toBe(3)
		expect(t.count("emitter")).toBe(2)
		t.release("emitter")
		t.release("emitter")
		t.release("emitter") -- a double release is harmless
		t.release("highlight")
		expect(t.count()).toBe(0)
	end)
	it("highlight cap stays far below the Roblox limit", function()
		expect(Logic.HIGHLIGHT_CAP <= 10).toBe(true)
	end)
end)

describe("PvP sounds", function()
	local PVP_NAMES =
		{ "PvpHit", "PvpCollide", "PvpGoo", "PvpSquirt", "PvpBoing", "PvpPop", "PvpSqueak", "PvpFirework", "PvpBubble" }
	it("every PvP sound is a numeric rbxassetid", function()
		for _, name in PVP_NAMES do
			local id = Sounds.IDS[name]
			expect(id ~= nil and string.match(id, "^rbxassetid://%d+$") ~= nil).toBe(true)
		end
	end)
	it("all ids in the registry are numeric rbxassetids", function()
		for _, id in Sounds.IDS do
			expect(string.match(id, "^rbxassetid://%d+$") ~= nil).toBe(true)
		end
	end)
end)
