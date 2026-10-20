--!strict
-- The ritual circle's look (Visuals.RitualLook) and its particle presets (Visuals.Effects Ritual*):
-- the ring fill follows the charge and the rest, only a finished ritual bursts, and the effects stay
-- small (the circle sits beside plot 1's entrance).
local Config = require("../src/shared/Config")
local Effects = require("../src/visuals/shared/Effects")
local RitualLook = require("../src/visuals/shared/RitualLook")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local R = Config.RITUAL
local NOW = 1000

describe("RitualLook ring and charge", function()
	it("is empty while Idle", function()
		local fill, tint = RitualLook.ring("Idle", nil, nil, NOW)
		expect(fill).toBe(0)
		expect(tint).toBe("idle")
	end)
	it("fills with the hold countdown while Charging", function()
		expect(RitualLook.charge("Charging", NOW + R.HOLD_SECONDS, NOW)).toBe(0)
		expect(RitualLook.charge("Charging", NOW + R.HOLD_SECONDS / 2, NOW)).toBe(0.5)
		expect(RitualLook.charge("Charging", NOW - 1, NOW)).toBe(1)
		local fill, tint = RitualLook.ring("Charging", NOW + R.HOLD_SECONDS / 2, nil, NOW)
		expect(fill).toBe(0.5)
		expect(tint).toBe("charge")
	end)
	it("refills while resting", function()
		local fill, tint = RitualLook.ring("Cooldown", nil, NOW + R.SERVER_COOLDOWN, NOW)
		expect(fill).toBe(0)
		expect(tint).toBe("recharge")
		expect((RitualLook.ring("Cooldown", nil, NOW + R.SERVER_COOLDOWN / 4, NOW))).toBe(0.75)
	end)
	it("charge is 0 outside Charging or without a time", function()
		expect(RitualLook.charge("Idle", NOW + 1, NOW)).toBe(0)
		expect(RitualLook.charge("Charging", nil, NOW)).toBe(0)
	end)
	it("lights every dash at full and none at empty", function()
		local n = RitualLook.RING_SEGMENTS
		expect(RitualLook.dashLevel(0, 1)).toBe(0)
		expect(RitualLook.dashLevel(1, 1)).toBe(1)
		expect(RitualLook.dashLevel(1, n)).toBe(1)
		expect(RitualLook.dashLevel(2, n)).toBe(1)
	end)
	it("fades the dash being filled in instead of popping it", function()
		local n = RitualLook.RING_SEGMENTS
		local fill = 2.5 / n -- two dashes lit, the third half way
		expect(RitualLook.dashLevel(fill, 2)).toBe(1)
		expect(math.abs(RitualLook.dashLevel(fill, 3) - 0.5) < 1e-9).toBe(true)
		expect(RitualLook.dashLevel(fill, 4)).toBe(0)
	end)
	it("shows the unlit dashes as a faint track only while recharging", function()
		expect(RitualLook.dashTransparency(0, "recharge")).toBe(RitualLook.DASH_TRACK)
		expect(RitualLook.dashTransparency(0, "charge")).toBe(1)
		expect(RitualLook.dashTransparency(0, "idle")).toBe(1)
		expect(math.abs(RitualLook.dashTransparency(1, "recharge") - RitualLook.DASH_LIT) < 1e-9).toBe(true)
		expect(RitualLook.DASH_TRACK < 1 and RitualLook.DASH_LIT < 0.3).toBe(true)
	end)
end)

describe("RitualLook motion and burst", function()
	it("only Charging -> Cooldown is a finished ritual", function()
		expect(RitualLook.completed("Charging", "Cooldown")).toBe(true)
		expect(RitualLook.completed("Charging", "Idle")).toBe(false)
		expect(RitualLook.completed("Cooldown", "Idle")).toBe(false)
		expect(RitualLook.completed(nil, "Cooldown")).toBe(false)
	end)
	it("the orb grows and spins faster with the charge, and slows while resting", function()
		local _, idleSpin, idleScale = RitualLook.orb("Idle", 0, 0)
		local _, fullSpin, fullScale = RitualLook.orb("Charging", 1, 0)
		local _, restSpin = RitualLook.orb("Cooldown", 0, 0)
		expect(idleScale).toBe(1)
		expect(fullScale > 1 and fullScale <= 1.5).toBe(true)
		expect(fullSpin > idleSpin).toBe(true)
		expect(restSpin < idleSpin).toBe(true)
	end)
	it("beams widen with the charge", function()
		expect(RitualLook.beamWidth(1) > RitualLook.beamWidth(0)).toBe(true)
	end)
	it("the shockwave grows and fades out, and stays near the circle", function()
		local r0, t0 = RitualLook.shock(0)
		local r1, t1 = RitualLook.shock(1)
		expect(r1 > r0).toBe(true)
		expect(t1).toBe(1)
		expect(t0 < 0.5).toBe(true)
		expect(r1 <= R.CIRCLE_RADIUS * 3).toBe(true)
	end)
	it("has a colour for every tint", function()
		for _, tint in { "idle", "taken", "charge", "rest", "recharge" } do
			expect(#RitualLook.color(tint :: RitualLook.Tint)).toBe(3)
		end
	end)
end)

describe("Ritual particle presets stay quiet", function()
	local STATIC = { "RitualMote", "RitualSwirl", "RitualRest" }
	local BURSTS = { "RitualJoin", "RitualShower" }
	for _, name in STATIC do
		it(`{name}: <= 15 particles alive`, function()
			local p = Effects.EMITTERS[name]
			expect((p.rate or 0) * p.lifetime[2] <= 15).toBe(true)
		end)
	end
	for _, name in BURSTS do
		it(`{name}: bursts <= 30 particles`, function()
			local p = Effects.EMITTERS[name]
			expect(p.count ~= nil and (p.count :: number) <= 30).toBe(true)
		end)
	end
	for _, name in { "RitualMote", "RitualSwirl", "RitualRest", "RitualJoin", "RitualShower" } do
		it(`{name}: particles <= 1.5 studs`, function()
			local p = Effects.EMITTERS[name]
			expect(math.max(p.size[1], p.size[2]) <= 1.5).toBe(true)
		end)
	end
	it("the orb glow is soft", function()
		expect(Effects.LIGHTS.RitualGlow.brightness <= 1).toBe(true)
	end)
end)
