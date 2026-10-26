--!strict
-- Ground-matched footsteps (src/ui/FootstepsLogic.luau, ui/Footsteps): the floor picks the step set, ground snow
-- turns grass into snow, and steps fall once per stride whether the loop runs every frame or every 0.1 s.
local Config = require("../../src/shared/Config")
local FootstepsLogic = require("../../src/ui/FootstepsLogic")
local Sounds = require("../../src/ui/Sounds")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local cfg = Config.AUDIO.SLIME

-- Runs a walker at `speed` for `seconds` with calls every `dt`; returns the absolute times of every step.
local function walk(speed: number, seconds: number, dt: number): { number }
	local stride = FootstepsLogic.stride(16, cfg)
	local w = FootstepsLogic.new(stride, cfg)
	local times = {}
	local t = 0
	while t < seconds - 1e-9 do
		for _, d in FootstepsLogic.advance(w, speed, dt, stride, cfg) do
			table.insert(times, t + d)
		end
		t += dt
	end
	return times
end

describe("FootstepsLogic floors", function()
	it("maps grass and snow floors to their sets and leaves other floors alone", function()
		expect(FootstepsLogic.setFor("Grass", 0, cfg)).toBe("StepGrass")
		expect(FootstepsLogic.setFor("LeafyGrass", 0, cfg)).toBe("StepGrass")
		expect(FootstepsLogic.setFor("Mud", 0, cfg)).toBe("StepGrass")
		expect(FootstepsLogic.setFor("Snow", 0, cfg)).toBe("StepSnow")
		expect(FootstepsLogic.setFor("Ice", 0, cfg)).toBe("StepSnow")
		expect(FootstepsLogic.setFor("Wood", 0, cfg)).toBeNil()
		expect(FootstepsLogic.setFor("Air", 0, cfg)).toBeNil()
		expect(FootstepsLogic.setFor(nil, 0, cfg)).toBeNil()
	end)

	it("steps on snow over grass once the snow cover settles", function()
		expect(FootstepsLogic.setFor("Grass", cfg.SNOW_COVER_MIN - 0.01, cfg)).toBe("StepGrass")
		expect(FootstepsLogic.setFor("Grass", cfg.SNOW_COVER_MIN, cfg)).toBe("StepSnow")
		expect(FootstepsLogic.setFor("Wood", 1, cfg)).toBeNil()
	end)

	it("every set is a Sounds variant group", function()
		for _, set in cfg.STEP_MATERIALS do
			expect(Sounds.VARIANTS[set] ~= nil).toBe(true)
		end
		for _, set in cfg.SNOW_STEPS do
			expect(Sounds.VARIANTS[set] ~= nil).toBe(true)
		end
	end)
end)

describe("FootstepsLogic timing", function()
	it("takes longer strides at a higher WalkSpeed, inside STRIDE_MIN..STRIDE_MAX", function()
		expect(FootstepsLogic.stride(cfg.STRIDE_WALK_SPEED, cfg)).toBeCloseTo(cfg.STRIDE_STUDS)
		expect(FootstepsLogic.stride(32, cfg) > FootstepsLogic.stride(16, cfg)).toBe(true)
		expect(FootstepsLogic.stride(1000, cfg)).toBe(cfg.STRIDE_MAX)
		expect(FootstepsLogic.stride(0.1, cfg)).toBe(cfg.STRIDE_MIN)
		expect(FootstepsLogic.stride(nil, cfg)).toBeCloseTo(cfg.STRIDE_STUDS)
	end)

	it("one step per stride walked", function()
		local stride = FootstepsLogic.stride(16, cfg)
		local times = walk(16, 10, 1 / 60)
		local expected = math.floor((16 * 10 - stride * cfg.FIRST_STEP_SHARE) / stride) + 1
		expect(math.abs(#times - expected) <= 1).toBe(true)
	end)

	it("spaces steps evenly from a 0.1 s loop as from a frame loop", function()
		local stride = FootstepsLogic.stride(16, cfg)
		local slow, fast = walk(16, 5, 0.1), walk(16, 5, 1 / 60)
		expect(math.abs(#slow - #fast) <= 1).toBe(true)
		for i = 2, #slow do
			expect(slow[i] - slow[i - 1]).toBeCloseTo(stride / 16, 1e-6)
		end
		for i = 1, math.min(#slow, #fast) do
			expect(math.abs(slow[i] - fast[i]) < 0.02).toBe(true)
		end
	end)

	it("the first step comes soon after setting off; standing still makes none", function()
		local stride = FootstepsLogic.stride(16, cfg)
		local w = FootstepsLogic.new(stride, cfg)
		expect(#FootstepsLogic.advance(w, 0, 0.1, stride, cfg)).toBe(0)
		local times = walk(16, 1, 0.1)
		expect(times[1]).toBeCloseTo(stride * cfg.FIRST_STEP_SHARE / 16, 1e-6)
	end)

	it("never schedules a burst after a long hitch", function()
		local stride = FootstepsLogic.stride(16, cfg)
		local w = FootstepsLogic.new(stride, cfg)
		expect(#FootstepsLogic.advance(w, 16, 5, stride, cfg) <= FootstepsLogic.MAX_PER_CALL).toBe(true)
	end)
end)
