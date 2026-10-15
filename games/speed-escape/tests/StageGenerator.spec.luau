--!strict
local StageGenerator = require("../src/shared/StageGenerator")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type PartSpec = StageGenerator.PartSpec

local function countKind(specs: { PartSpec }, kind: string): number
	local n = 0
	for _, spec in specs do
		if spec.kind == kind then
			n += 1
		end
	end
	return n
end

-- Z gap between each part and the one before it, keyed by the later part's stage.
local function gapsByStage(specs: { PartSpec }): { [number]: { number } }
	local result: { [number]: { number } } = {}
	for i = 2, #specs do
		local prev, cur = specs[i - 1], specs[i]
		local gap = (cur.position.z - cur.size.z / 2) - (prev.position.z + prev.size.z / 2)
		result[cur.stage] = result[cur.stage] or {}
		table.insert(result[cur.stage], gap)
	end
	return result
end

local function overlaps(a: PartSpec, b: PartSpec): boolean
	for _, axis in { "x", "y", "z" } do
		local pa, pb = (a.position :: any)[axis], (b.position :: any)[axis]
		local sa, sb = (a.size :: any)[axis], (b.size :: any)[axis]
		if math.abs(pa - pb) >= (sa + sb) / 2 then
			return false
		end
	end
	return true
end

local function sameLayout(a: { PartSpec }, b: { PartSpec }): boolean
	if #a ~= #b then
		return false
	end
	for i, sa in a do
		local sb = b[i]
		if sa.kind ~= sb.kind or sa.stage ~= sb.stage then
			return false
		end
		for _, axis in { "x", "y", "z" } do
			if (sa.position :: any)[axis] ~= (sb.position :: any)[axis] then
				return false
			end
			if (sa.size :: any)[axis] ~= (sb.size :: any)[axis] then
				return false
			end
		end
	end
	return true
end

describe("StageGenerator.layout", function()
	it("is deterministic for the same seed and stageCount", function()
		for _, n in { 5, 6, 7, 8 } do
			local a = StageGenerator.layout({ stageCount = n, seed = 42 })
			local b = StageGenerator.layout({ stageCount = n, seed = 42 })
			expect(sameLayout(a, b)).toBe(true)
		end
	end)

	it("defaults to DEFAULT_SEED when seed is omitted", function()
		local a = StageGenerator.layout({ stageCount = 6 })
		local b = StageGenerator.layout({ stageCount = 6, seed = StageGenerator.DEFAULT_SEED })
		expect(sameLayout(a, b)).toBe(true)
	end)

	it("differs between seeds", function()
		local a = StageGenerator.layout({ stageCount = 6, seed = 1 })
		local b = StageGenerator.layout({ stageCount = 6, seed = 2 })
		expect(sameLayout(a, b)).toBe(false)
	end)

	it("supports 5 and 8 stages with one checkpoint per stage and one finish", function()
		for _, n in { 5, 8 } do
			local specs = StageGenerator.layout({ stageCount = n, seed = 7 })
			expect(countKind(specs, "checkpoint")).toBe(n)
			expect(countKind(specs, "finish")).toBe(1)
			expect(specs[1].kind).toBe("platform")
			expect(specs[1].stage).toBe(0)
			expect(specs[#specs].kind).toBe("finish")
		end
	end)

	it("ends every stage with its checkpoint", function()
		local specs = StageGenerator.layout({ stageCount = 8, seed = 3 })
		local checkpointStage = 0
		for i, spec in specs do
			if spec.kind == "checkpoint" then
				checkpointStage += 1
				expect(spec.stage).toBe(checkpointStage)
				local nextSpec = specs[i + 1]
				expect(nextSpec.kind == "finish" or nextSpec.stage == spec.stage + 1).toBeTruthy()
			end
		end
	end)

	it("progresses monotonically along +Z", function()
		local specs = StageGenerator.layout({ stageCount = 8, seed = 11 })
		for i = 2, #specs do
			expect(specs[i].position.z > specs[i - 1].position.z).toBeTruthy()
		end
	end)

	it("gets harder: bigger gaps, narrower platforms, more platforms", function()
		for seed = 1, 20 do
			local specs = StageGenerator.layout({ stageCount = 8, seed = seed })
			local gaps = gapsByStage(specs)
			local prevMaxGap, prevMinWidth, prevCount = -math.huge, math.huge, 0
			for stage = 1, 8 do
				local maxGap = math.max(table.unpack(gaps[stage]))
				local minWidth, count = math.huge, 0
				for _, spec in specs do
					if spec.stage == stage and spec.kind == "platform" then
						minWidth = math.min(minWidth, spec.size.x)
						count += 1
					end
				end
				expect(maxGap >= prevMaxGap).toBeTruthy()
				expect(minWidth <= prevMinWidth).toBeTruthy()
				expect(count >= prevCount).toBeTruthy()
				prevMaxGap, prevMinWidth, prevCount = maxGap, minWidth, count
			end
			expect(math.max(table.unpack(gaps[8])) > math.max(table.unpack(gaps[1]))).toBeTruthy()
		end
	end)

	it("keeps every gap positive and within the documented max", function()
		for seed = 1, 50 do
			for _, n in { 5, 8 } do
				local gaps = gapsByStage(StageGenerator.layout({ stageCount = n, seed = seed }))
				for stage, list in gaps do
					local limit = StageGenerator.stageParams(stage).maxGap
					for _, gap in list do
						expect(gap > 0).toBeTruthy()
						expect(gap <= limit).toBeTruthy()
						expect(gap <= StageGenerator.ABSOLUTE_MAX_GAP).toBeTruthy()
					end
				end
				for _, gap in gaps[1] do
					expect(gap <= StageGenerator.MAX_GAP_AT_BASE_SPEED).toBeTruthy()
				end
			end
		end
	end)

	it("stage 1 gaps are clearable at base WalkSpeed 16", function()
		expect(StageGenerator.requiredSpeedForGap(StageGenerator.MAX_GAP_AT_BASE_SPEED) < 16).toBeTruthy()
		expect(StageGenerator.requiredSpeedForGap(10)).toBeCloseTo(10 / StageGenerator.airTime())
	end)

	it("has no overlapping parts", function()
		for seed = 1, 20 do
			local specs = StageGenerator.layout({ stageCount = 8, seed = seed })
			for i = 1, #specs do
				for j = i + 1, #specs do
					expect(overlaps(specs[i], specs[j])).toBe(false)
				end
			end
		end
	end)

	it("rejects invalid stageCount", function()
		for _, n in { 4, 9, 0, -1, 5.5 } do
			expect(function()
				StageGenerator.layout({ stageCount = n })
			end).toThrow()
		end
	end)
end)
