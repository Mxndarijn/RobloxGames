--!strict
-- SlimeAttention (src/ui/SlimeAttention.luau, contract/slime-life.md "Alive attention"): a watching slime's look
-- darts in small quick glances and its head tilts now and then; an idle slime does neither.
local SlimeAttention = require("../../src/ui/SlimeAttention")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function lcg(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local FPS = 60

describe("SlimeAttention", function()
	it("an engaged slime glances round and tilts its head, within the limits", function()
		local rand = lcg(3)
		local st = SlimeAttention.new(0, rand)
		local yaws, rolls = {}, {}
		local maxYaw, maxRoll = 0, 0
		for f = 1, 12 * FPS do
			local yaw, roll = SlimeAttention.step(st, f / FPS, rand, 1)
			yaws[math.floor(yaw * 50)] = true
			rolls[math.floor(roll * 50)] = true
			maxYaw, maxRoll = math.max(maxYaw, math.abs(yaw)), math.max(maxRoll, math.abs(roll))
		end
		local nYaw, nRoll = 0, 0
		for _ in yaws do
			nYaw += 1
		end
		for _ in rolls do
			nRoll += 1
		end
		expect(nYaw > 5).toBe(true) -- it does not hold one look
		expect(nRoll > 3).toBe(true)
		expect(maxYaw <= SlimeAttention.SACCADE + 1e-9).toBe(true)
		expect(maxRoll <= SlimeAttention.TILT + 1e-9).toBe(true)
	end)

	it("a glance is quick but never a snap", function()
		local rand = lcg(5)
		local st = SlimeAttention.new(0, rand)
		local last = 0
		local fastest = 0
		for f = 1, 10 * FPS do
			local yaw = SlimeAttention.step(st, f / FPS, rand, 1)
			fastest = math.max(fastest, math.abs(yaw - last))
			last = yaw
		end
		-- a full glance (2 x SACCADE) over SACCADE_TIME, smoothstep peak 1.5x the mean speed
		local limit = 2 * SlimeAttention.SACCADE / SlimeAttention.SACCADE_TIME * 1.6 / FPS
		expect(fastest <= limit).toBe(true)
		expect(fastest > 0.01).toBe(true)
	end)

	it("an idle slime neither glances nor tilts", function()
		local rand = lcg(7)
		local st = SlimeAttention.new(0, rand)
		for f = 1, 5 * FPS do
			local yaw, roll = SlimeAttention.step(st, f / FPS, rand, 0)
			expect(yaw).toBe(0)
			expect(roll).toBe(0)
		end
	end)
end)
