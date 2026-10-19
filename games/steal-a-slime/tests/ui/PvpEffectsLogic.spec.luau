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
	it("unknown / junk payloads show nothing; Fun effects are not planned here (ui/PvpFunFx)", function()
		expect(plan({ effect = "Nope" })).toBe(nil)
		expect(plan({ effect = "Cosmetic", itemId = "FunConfetti" })).toBe(nil)
		expect(plan({ effect = "Bounce", itemId = "FunBouncePad", target = 2 })).toBe(nil)
		expect(plan({})).toBe(nil)
		expect(Logic.plan("x", P, false)).toBe(nil)
	end)
	it("nothing outlives its plan.seconds; every sfx name resolves", function()
		for _, effect in { "Knockback", "Freeze", "Slow" } do
			local p = plan({ effect = effect, target = 2, duration = 99, itemId = "GooTrap1" })
			expect(p.seconds <= math.max(P.FX_SECONDS, P.CONTROL_MAX_SECONDS, P.SLOW_MAX_SECONDS)).toBe(true)
			expect((p.highlight == nil) or p.highlight.seconds <= p.seconds).toBe(true)
			expect((p.beam == nil) or p.beam.seconds <= p.seconds).toBe(true)
			expect(Sounds.resolve(p.sfx) ~= nil).toBe(true)
		end
	end)
	it("low quality halves particle counts (never below 1)", function()
		local full = plan({ effect = "Knockback", itemId = "KnockGlove1", target = 2 }).burst.count
		local low = plan({ effect = "Knockback", itemId = "KnockGlove1", target = 2 }, true).burst.count
		expect(low).toBe(math.floor(full / 2))
		expect(Logic.scaleCount(1, true)).toBe(1)
	end)
end)

describe("PvpEffectsLogic hit feel and animation cues", function()
	it("a push opens with a white impact flash, a shock ring and the victim's recoil", function()
		local p = plan({ effect = "Knockback", itemId = "KnockGlove2", target = 2 })
		expect(p.highlight.impact).toEqual({ 1, 1, 1 })
		expect(p.ring.ring).toBe(true)
		expect(p.ring.count > 0).toBe(true)
		expect(p.attackerAnim).toBe(true)
		expect(p.targetHit).toBe(true)
	end)
	it("a trap freeze splashes a goo ring at the feet; the trap owner plays nothing (it sprang by itself)", function()
		local p = plan({ effect = "Freeze", duration = 1, target = 2 })
		expect(p.ring.height < 0).toBe(true)
		expect(p.attackerAnim).toBe(false)
		expect(p.targetHit).toBe(false)
	end)
	it("a blaster hit is a wider beam plus a splat ring; a miss still animates the shooter", function()
		local hit = plan({ effect = "Slow", target = 2, duration = 2 })
		local miss = plan({ effect = "Slow", position = 1, duration = 0.4 })
		expect(hit.beam.width > miss.beam.width).toBe(true)
		expect(hit.ring ~= nil).toBe(true)
		expect(miss.ring).toBeNil()
		expect(hit.attackerAnim and miss.attackerAnim).toBe(true)
	end)
	it("low quality halves the ring too", function()
		local high = plan({ effect = "Knockback", itemId = "KnockGlove1", target = 2 }, false)
		local low = plan({ effect = "Knockback", itemId = "KnockGlove1", target = 2 }, true)
		expect(low.ring.count < high.ring.count).toBe(true)
	end)
end)

describe("PvpEffectsLogic glove specials and goo blobs", function()
	it("Bonk pops BONK!, Royal throws gold confetti, a power punch is bigger", function()
		local bonk = plan({ effect = "Knockback", itemId = "KnockGlove1", special = "bonk", target = 2 })
		expect(bonk.popup.text).toBe("BONK!")
		local royal = plan({ effect = "Knockback", itemId = "KnockGlove5", special = "royal", target = 2 })
		expect(royal.burst.count >= 40).toBe(true)
		local tap = plan({ effect = "Knockback", itemId = "KnockGlove1", target = 2 })
		local power = plan({ effect = "Knockback", itemId = "KnockGlove1", target = 2, charged = true })
		expect(power.burst.count > tap.burst.count).toBe(true)
		expect(power.shake.amplitude > tap.shake.amplitude).toBe(true)
	end)
	it("Bounce keeps at most 3 pogo heights within the arc cap; Thunder draws a bolt to a chained player", function()
		local bounce =
			plan({ effect = "Knockback", itemId = "KnockGlove2", special = "bounce", pogo = { 6, 4, 2, 9, 99 } })
		expect(bounce.pogo).toEqual({ 6, 4, 2 })
		local junk = plan({ effect = "Knockback", itemId = "KnockGlove2", special = "bounce", pogo = { "x", -1 } })
		expect(junk.pogo).toBe(nil)
		local chained = plan({ effect = "Knockback", itemId = "KnockGlove4", special = "thunder", chained = true })
		expect(chained.bolt ~= nil).toBe(true)
		expect(chained.attackerAnim).toBe(false) -- the attacker already punched once
		local boom = plan({ effect = "Knockback", itemId = "KnockGlove3", special = "boom" })
		expect(boom.ring.count >= 24).toBe(true)
	end)
	it("a goo blob flies its flight, then splats the victim's screen or leaves a ground splat", function()
		local hit = plan({ effect = "Slow", itemId = "GooBlaster2", target = 2, from = 1, flight = 0.5, duration = 2 })
		expect(hit.blob.size).toBe(Logic.BLOB_SIZES[2])
		expect(hit.delay).toBe(0.5)
		expect(hit.screenSplat).toBe(2)
		expect(hit.beam).toBe(nil)
		expect(hit.seconds >= 0.5 + 2).toBe(true)
		local miss = plan({
			effect = "Slow",
			itemId = "GooBlaster3",
			from = 1,
			flight = 99,
			splat = { radius = 6, seconds = 4 },
		})
		expect(miss.delay).toBe(Logic.MAX_FLIGHT)
		expect(miss.screenSplat).toBe(nil)
		expect(miss.splat.radius).toBe(6)
		expect(miss.splat.seconds).toBe(4)
		expect(miss.seconds >= Logic.MAX_FLIGHT + 4).toBe(true)
	end)
	it("the blob velocity lands on `to` after `t` under gravity", function()
		local from, to, t, g = { X = 0, Y = 3, Z = 0 }, { X = 30, Y = 3, Z = 0 }, 0.5, P.BLOB_GRAVITY
		local v = Logic.blobVelocity(from, to, t, g)
		expect(math.abs(from.X + v.X * t - 30) < 1e-9).toBe(true)
		expect(math.abs(from.Y + v.Y * t - 0.5 * g * t * t - 3) < 1e-9).toBe(true)
	end)
	it("each pogo bounce starts when the one before lands", function()
		local times = Logic.pogoTimes({ 6, 4, 2 }, 196.2)
		expect(#times).toBe(2)
		expect(math.abs(times[1] - 2 * math.sqrt(12 / 196.2)) < 1e-9).toBe(true)
		expect(times[2] > times[1]).toBe(true)
	end)
	it("a Mega Trap chomps; a Puddle only goos the feet", function()
		expect(plan({ effect = "Freeze", itemId = "GooTrap3", target = 2, duration = 2, hold = 2 }).popup.text).toBe(
			"CHOMP!"
		)
		local puddle = plan({ effect = "Freeze", itemId = "GooTrap1", target = 2, duration = 2, hold = 0 })
		expect(puddle.burst).toBe(nil)
		expect(puddle.ring ~= nil).toBe(true)
	end)
end)

describe("PvpEffectsLogic markers", function()
	local function tool(id: string): any
		return PvpRules.tool(id)
	end
	it(
		"a Goo Trap puddle is sized by its radius and seen by everyone: glowing for its owner, a shimmer for others",
		function()
			local m = Logic.marker("GooTrap2", tool("GooTrap2"), P)
			expect(m ~= nil and m.shape == "puddle" and m.diameter == tool("GooTrap2").radius * 2).toBe(true)
			expect(Logic.markerVisible(m :: any, 1, 1)).toBe(true)
			expect(Logic.markerVisible(m :: any, 1, 2)).toBe(true)
			local mine, theirs = Logic.markerLook(m :: any, true), Logic.markerLook(m :: any, false)
			expect(mine.material).toBe("Neon")
			expect(theirs.transparency > 0.8 and theirs.transparency > mine.transparency).toBe(true)
			expect((m :: any).seconds >= P.TRAP_LIFETIME_SECONDS).toBe(true)
		end
	)
	it("a TrapPlaced finds its tool by id in the PVP_TOOLS list", function()
		local m = Logic.markerFor("GooTrap3", Config.PVP_TOOLS, P)
		expect(m ~= nil and m.shape == "puddle" and m.diameter == tool("GooTrap3").radius * 2).toBe(true)
		expect(Logic.markerFor("FunBouncePad", Config.PVP_TOOLS, P)).toBe(nil) -- the trampoline is ui/PvpFunFx's
		expect(Logic.markerFor("KnockGlove1", Config.PVP_TOOLS, P)).toBe(nil)
		expect(Logic.markerFor("Nope", Config.PVP_TOOLS, P)).toBe(nil)
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
	local PVP_NAMES = {
		"PvpHit",
		"PvpCollide",
		"PvpGoo",
		"PvpSquirt",
		"PvpBoing",
		"PvpPop",
		"PvpSqueak",
		"PvpFirework",
		"PvpBubble",
		"PvpDisco",
	}
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
