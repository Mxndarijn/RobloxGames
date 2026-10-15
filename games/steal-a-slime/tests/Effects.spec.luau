--!strict
-- Volcano particle presets (v10: the crater smoke / Eruption were so big and
-- tall they hid the volcano). Locks the client emitters on Map.Volcano.Crater
-- and the lava cracks to bounds relative to the 15-stud crater and the
-- 40-stud volcano, from the preset data alone (no ParticleEmitter needed).
local Effects = require("../src/visuals/shared/Effects")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local VOLCANO = { "CraterSmoke", "CraterEmbers", "Eruption", "LavaBubbles" }
local CRATER_DIAMETER = 15 -- WorldLayout volcano(): disc("Crater", 0.6, 15, ...)

local LIMITS = {
	maxSize = CRATER_DIAMETER * 0.4, -- studs; a puff never covers more than 40 % of the crater
	maxRise = WorldLayout.VOLCANO_HEIGHT * 0.5, -- studs above the crater
	maxAlive = 16, -- particles alive at once per static emitter (rate * max lifetime)
	maxBurst = 30, -- Eruption :Emit count
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

describe("Effects volcano presets", function()
	for _, name in VOLCANO do
		local p = Effects.EMITTERS[name]
		it(`{name}: size <= {LIMITS.maxSize} studs`, function()
			expect(math.max(p.size[1], p.size[2]) <= LIMITS.maxSize).toBe(true)
		end)
		it(`{name}: rises <= {LIMITS.maxRise} studs above the crater`, function()
			expect(rise(p) <= LIMITS.maxRise).toBe(true)
		end)
		it(`{name}: <= {LIMITS.maxAlive} particles alive`, function()
			expect((p.rate or 0) * p.lifetime[2] <= LIMITS.maxAlive).toBe(true)
		end)
	end
	it(`Eruption bursts <= {LIMITS.maxBurst} particles`, function()
		expect((Effects.EMITTERS.Eruption.count or 0) <= LIMITS.maxBurst).toBe(true)
	end)
	it("smoke stays see-through", function()
		local t = Effects.EMITTERS.CraterSmoke.transparency
		expect(t ~= nil and t[1] >= 0.5).toBe(true)
	end)
end)
