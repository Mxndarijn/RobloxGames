--!strict
-- Slime fountain particle presets (Slime Ranch pass; the keys keep their
-- volcano names because the fountain still answers to Map.Volcano.Crater).
-- Locks the client emitters on the crown goo pool to
-- bounds relative to the 11-stud crown pool and the 40-stud fountain, and to
-- the THEME.md goo look (no grey smoke, no near-white puffs, no neon glare),
-- from the preset data alone (no ParticleEmitter needed).
local Effects = require("../src/visuals/shared/Effects")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local FOUNTAIN = { "CraterSmoke", "CraterEmbers", "Eruption" }
local CROWN_DIAMETER = 11 -- WorldLayout volcano(): disc("Crater", 0.6, 11, ...)

local LIMITS = {
	maxSize = CROWN_DIAMETER * 0.4, -- studs; a droplet never covers more than 40 % of the pool
	maxRise = WorldLayout.VOLCANO_HEIGHT * 0.5, -- studs above the crown
	maxAlive = 16, -- particles alive at once per static emitter (rate * max lifetime)
	maxBurst = 24, -- Eruption :Emit count
	maxLightEmission = 0.5, -- soft goo, not neon
	minTransparency = 0.2, -- every fountain particle starts see-through
	minChroma = 40, -- max - min rgb channel; below this a colour reads grey
	nearWhite = 235, -- all channels >= this is a near-white puff
	maxGlowBrightness = 1,
}

-- Highest point a particle reaches above its emitter (no drag on these presets).
local function rise(p: Effects.EmitterPreset): number
	local v, life, g = p.speed[2], p.lifetime[2], -(p.gravity or 0)
	if g <= 0 then
		return v * life
	end
	local t = math.min(v / g, life)
	return v * t - 0.5 * g * t * t
end

local function chroma(c: { number }): number
	return math.max(c[1], c[2], c[3]) - math.min(c[1], c[2], c[3])
end

describe("Effects fountain presets", function()
	for _, name in FOUNTAIN do
		local p = Effects.EMITTERS[name]
		it(`{name}: size <= {LIMITS.maxSize} studs`, function()
			expect(math.max(p.size[1], p.size[2]) <= LIMITS.maxSize).toBe(true)
		end)
		it(`{name}: rises <= {LIMITS.maxRise} studs above the crown`, function()
			expect(rise(p) <= LIMITS.maxRise).toBe(true)
		end)
		it(`{name}: <= {LIMITS.maxAlive} particles alive`, function()
			expect((p.rate or 0) * p.lifetime[2] <= LIMITS.maxAlive).toBe(true)
		end)
		it(`{name}: LightEmission <= {LIMITS.maxLightEmission}`, function()
			expect((p.lightEmission or 0) <= LIMITS.maxLightEmission).toBe(true)
		end)
		it(`{name}: starts >= {LIMITS.minTransparency} transparent`, function()
			local t = p.transparency or { 0, 1 }
			expect(t[1] >= LIMITS.minTransparency).toBe(true)
		end)
		it(`{name}: no grey or near-white colours`, function()
			for _, c in p.colors do
				expect(chroma(c) >= LIMITS.minChroma).toBe(true)
				expect(math.min(c[1], c[2], c[3]) < LIMITS.nearWhite).toBe(true)
			end
		end)
	end
	it(`Eruption bursts <= {LIMITS.maxBurst} particles`, function()
		expect((Effects.EMITTERS.Eruption.count or 0) <= LIMITS.maxBurst).toBe(true)
	end)
	it("crown spray stays see-through", function()
		local t = Effects.EMITTERS.CraterSmoke.transparency
		expect(t ~= nil and t[1] >= 0.5).toBe(true)
	end)
	it("CraterGlow is a soft goo green", function()
		local l = Effects.LIGHTS.CraterGlow
		expect(l.color[2] > l.color[1] and l.color[2] > l.color[3]).toBe(true)
		expect(chroma(l.color) >= LIMITS.minChroma).toBe(true)
	end)
end)
