--!strict
-- Visuals.EffectPrefs: the Visuals settings as client effects read them (reduced motion, Goo effects Low,
-- camera shake, other players' effects) and the Low maths for bursts and the server-emitter dimmer.
local EffectPrefs = require("../src/visuals/shared/EffectPrefs")
local PlayerSettings = require("../src/shared/PlayerSettings")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- A LocalPlayer stand-in: each setting on the attribute the Settings card mirrors it onto.
local function player(values: { [string]: any }): any
	local attributes = {}
	for id, value in values do
		local entry = PlayerSettings.entry(id)
		assert(entry, id)
		attributes[entry.attribute] = value
	end
	return {
		GetAttribute = function(_, name: string)
			return attributes[name]
		end,
	}
end

describe("EffectPrefs reads", function()
	it("uses the defaults with no attributes or no player", function()
		for _, p in { player({}), nil :: any } do
			expect(EffectPrefs.isLow(p)).toBe(false)
			expect(EffectPrefs.reducedMotion(p, nil)).toBe(false)
			expect(EffectPrefs.cameraMoves(p, nil)).toBe(true)
			expect(EffectPrefs.showOthers(p)).toBe(true)
		end
	end)
	it("is low on the Low setting or the caller's low graphics quality", function()
		expect(EffectPrefs.isLow(player({ effects = "low" }))).toBe(true)
		expect(EffectPrefs.isLow(player({ effects = "full" }), true)).toBe(true)
		expect(EffectPrefs.isLow(player({ effects = "full" }), false)).toBe(false)
	end)
	it("reduces motion for Roblox's Reduced Motion or the game setting", function()
		local off = { ReducedMotionEnabled = false }
		local on = { ReducedMotionEnabled = true }
		expect(EffectPrefs.reducedMotion(player({}), on)).toBe(true)
		expect(EffectPrefs.reducedMotion(player({ reducedMotion = true }), off)).toBe(true)
		expect(EffectPrefs.reducedMotion(player({}), off)).toBe(false)
	end)
	it("reads a GuiService without ReducedMotionEnabled as off", function()
		local broken = setmetatable({}, {
			__index = function()
				error("no such property")
			end,
		})
		expect(EffectPrefs.reducedMotion(player({}), broken)).toBe(false)
	end)
	it("keeps the camera still with shake off or reduced motion on", function()
		expect(EffectPrefs.cameraMoves(player({ cameraShake = false }), nil)).toBe(false)
		expect(EffectPrefs.cameraMoves(player({}), { ReducedMotionEnabled = true })).toBe(false)
		expect(EffectPrefs.cameraMoves(player({ reducedMotion = true }), nil)).toBe(false)
	end)
	it("hides other players' effects only when that setting is off", function()
		expect(EffectPrefs.showOthers(player({ othersEffects = false }))).toBe(false)
	end)
end)

describe("EffectPrefs.count", function()
	it("keeps Full counts and scales Low counts down to at least 1", function()
		expect(EffectPrefs.count(24, false)).toBe(24)
		expect(EffectPrefs.count(20, true) < 20).toBe(true)
		expect(EffectPrefs.count(20, true)).toBe(math.floor(20 * EffectPrefs.LOW_SCALE + 0.5))
		expect(EffectPrefs.count(1, true)).toBe(1)
		expect(EffectPrefs.count(0, true)).toBe(0)
	end)
end)

describe("EffectPrefs dimmer rules", function()
	it("dims the server's Effects.play holders, the drain splash and shine sparkles", function()
		expect(EffectPrefs.dimmable("CollectSparkle", "Effect_Collect")).toBe(true)
		expect(EffectPrefs.dimmable("ParadeSplash", "DrainSplash")).toBe(true)
		expect(EffectPrefs.dimmable("ShineFx", "Body")).toBe(true)
	end)
	it("leaves every other emitter alone", function()
		expect(EffectPrefs.dimmable("Trail", "BossCarry")).toBe(false)
		expect(EffectPrefs.dimmable("ParticleEmitter", "HumanoidRootPart")).toBe(false)
		expect(EffectPrefs.dimmable("ParticleEmitter", nil)).toBe(false)
	end)
	it("lowers the rate on Low and keeps the full rate to restore", function()
		local rate, saved = EffectPrefs.dim(40, nil, true)
		expect(rate).toBeCloseTo(40 * EffectPrefs.LOW_SCALE)
		expect(saved).toBe(40)
		-- Applying Low again scales the saved full rate, not the dimmed one.
		local again, keep = EffectPrefs.dim(rate, saved, true)
		expect(again).toBeCloseTo(rate)
		expect(keep).toBe(40)
		local back, cleared = EffectPrefs.dim(rate, saved, false)
		expect(back).toBe(40)
		expect(cleared).toBeNil()
	end)
	it("leaves an undimmed emitter as it is on Full", function()
		local rate, saved = EffectPrefs.dim(12, nil, false)
		expect(rate).toBe(12)
		expect(saved).toBeNil()
	end)
end)
