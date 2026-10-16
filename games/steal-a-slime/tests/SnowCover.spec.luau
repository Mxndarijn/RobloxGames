--!strict
local Config = require("../src/shared/Config")
local SnowCover = require("../src/visuals/shared/SnowCover")
local TestRunner = require("./TestRunner")
local WeatherLook = require("../src/visuals/shared/WeatherLook")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function run(level: number, seconds: number, snowing: boolean, dt: number): number
	local t = 0
	while t < seconds do
		level = SnowCover.step(level, dt, snowing)
		t += dt
	end
	return level
end

describe("SnowCover (F2)", function()
	it("builds from bare to full over BUILD_SECONDS while it snows", function()
		expect(run(0, SnowCover.BUILD_SECONDS / 2, true, 0.1) > 0.45).toBe(true)
		expect(run(0, SnowCover.BUILD_SECONDS / 2, true, 0.1) < 0.55).toBe(true)
		expect(run(0, SnowCover.BUILD_SECONDS + 1, true, 0.1)).toBe(1)
	end)
	it("melts from full to bare over MELT_SECONDS once the snow stops", function()
		expect(run(1, SnowCover.MELT_SECONDS / 2, false, 0.1) > 0.45).toBe(true)
		expect(run(1, SnowCover.MELT_SECONDS + 1, false, 0.1)).toBe(0)
	end)
	it("is independent of the frame rate and never leaves 0..1", function()
		local a, b = run(0, 20, true, 1 / 60), run(0, 20, true, 1 / 20)
		expect(math.abs(a - b) < 0.01).toBe(true)
		expect(SnowCover.step(0.99, 100, true)).toBe(1)
		expect(SnowCover.step(0.01, 100, false)).toBe(0)
	end)
	it("a short snow shower leaves a partial cover that melts from where it was", function()
		local partial = run(0, 10, true, 0.1)
		expect(partial > 0 and partial < 1).toBe(true)
		local later = run(partial, 5, false, 0.1)
		expect(later < partial).toBe(true)
	end)
	it("transparency eases from clear to the full-cover value, monotonic and clamped", function()
		expect(SnowCover.transparency(0)).toBe(SnowCover.CLEAR_TRANSPARENCY)
		expect(math.abs(SnowCover.transparency(1) - SnowCover.FULL_TRANSPARENCY) < 1e-9).toBe(true)
		expect(SnowCover.transparency(-5)).toBe(SnowCover.CLEAR_TRANSPARENCY)
		local last = 2
		for i = 0, 20 do
			local v = SnowCover.transparency(i / 20)
			expect(v <= last).toBe(true)
			last = v
		end
		expect(SnowCover.FULL_TRANSPARENCY > 0).toBe(true) -- the ground and paths still show through
	end)
	it("visible / settled", function()
		expect(SnowCover.visible(0)).toBe(false)
		expect(SnowCover.visible(0.2)).toBe(true)
		expect(SnowCover.settled(1, true)).toBe(true)
		expect(SnowCover.settled(0, false)).toBe(true)
		expect(SnowCover.settled(0.5, true)).toBe(false)
		expect(SnowCover.settled(0.5, false)).toBe(false)
	end)
	it("sits flush above the paths and under the pads, covering the whole ground", function()
		local top = 0
		for _, y in WorldLayout.PATH_TOPS do
			top = math.max(top, y)
		end
		expect(SnowCover.TOP > top).toBe(true)
		expect(SnowCover.TOP < 0.2).toBe(true)
		expect(SnowCover.SIZE[1] >= 640 and SnowCover.SIZE[3] >= 640).toBe(true)
	end)
	it("costs one runtime part and no mesh slot, inside the world budgets", function()
		expect(SnowCover.PART_COUNT).toBe(1)
		expect(SnowCover.MESH_SLOTS).toBe(0)
		expect(SnowCover.MESH_SLOTS <= WorldLayout.RUNTIME_SLOT_ALLOWANCE).toBe(true)
		expect(WorldLayout.PART_BUDGET > 0).toBe(true)
	end)
	it("snow flakes reach the ground: speed x lifetime beats the emitter height at the steepest spread", function()
		local flakes = WeatherLook.EMITTERS.Flakes
		local minSpeed, spreadDeg, height = 7, 15, 42 -- WeatherFx makeEmitter / SNOW_EMITTER_Y
		local down = minSpeed * flakes.lifetime * math.cos(math.rad(spreadDeg * 1.5))
		expect(down >= height).toBe(true)
		expect(Config.WEATHER_PARTICLE_CAP >= 1).toBe(true)
	end)
end)
