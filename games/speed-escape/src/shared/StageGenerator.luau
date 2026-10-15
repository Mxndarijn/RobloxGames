--!strict
--[[
	StageGenerator

	Generates a linear obby course running along +Z.

	`layout` is pure and deterministic (own Park-Miller LCG, no Roblox APIs), so
	it runs under Lune for unit tests. `build` turns a layout into anchored Parts.

	Jump physics: with default Roblox JumpPower 50 and gravity 196.2 a character
	is airborne for 2 * 50 / 196.2 ≈ 0.51 s, so at WalkSpeed 16 it clears about
	8.2 studs. MAX_GAP_AT_BASE_SPEED (7) leaves margin at base speed. Each later
	stage allows 1 more stud (GAP_GROWTH_PER_STAGE), never exceeding
	ABSOLUTE_MAX_GAP (14), which needs WalkSpeed ≈ 27.5
	(see `requiredSpeedForGap`).

	Invalid stageCount (not an integer in 5..8) raises an error; it is not clamped.
]]

export type Vec3 = { x: number, y: number, z: number }

export type PartKind = "platform" | "checkpoint" | "finish"

export type PartSpec = {
	position: Vec3, -- centre of the part
	size: Vec3,
	kind: PartKind,
	stage: number, -- 0 for the spawn pad, 1..stageCount otherwise
}

export type LayoutConfig = {
	stageCount: number, -- must be an integer in 5..8
	seed: number?, -- defaults to DEFAULT_SEED
}

export type StageParams = {
	maxGap: number, -- largest Z gap leading into a part of this stage
	minGap: number, -- smallest Z gap leading into a part of this stage
	platformWidth: number, -- widest platform X size in this stage
	platformCount: number, -- obstacle platforms before the checkpoint
}

export type BuildResult = {
	spawn: BasePart,
	checkpoints: { BasePart },
	finish: BasePart,
}

local StageGenerator = {}

StageGenerator.MIN_STAGES = 5
StageGenerator.MAX_STAGES = 8
StageGenerator.DEFAULT_SEED = 1

-- Gap (studs, edge to edge along Z) allowed in stage 1.
StageGenerator.MAX_GAP_AT_BASE_SPEED = 7
StageGenerator.GAP_GROWTH_PER_STAGE = 1
-- Hard ceiling on any gap, whatever the stage.
StageGenerator.ABSOLUTE_MAX_GAP = 14
-- Gaps in a stage are drawn from [maxGap - GAP_JITTER, maxGap].
StageGenerator.GAP_JITTER = 1

StageGenerator.BASE_PLATFORM_WIDTH = 12
StageGenerator.MIN_PLATFORM_WIDTH = 5
StageGenerator.WIDTH_JITTER = 1
StageGenerator.PLATFORM_DEPTH = 6
StageGenerator.PLATFORM_HEIGHT = 1
-- Max sideways shift of a platform from the course centreline.
StageGenerator.MAX_LATERAL_OFFSET = 1.5

StageGenerator.SPAWN_SIZE = 16
StageGenerator.CHECKPOINT_SIZE = 8
StageGenerator.FINISH_SIZE = 16
-- Y of the course surface centre line, kept above a default baseplate.
StageGenerator.BASE_Y = 20

StageGenerator.DEFAULT_JUMP_POWER = 50
StageGenerator.DEFAULT_GRAVITY = 196.2

-- Seconds a character stays airborne on a flat jump.
function StageGenerator.airTime(jumpPower: number?, gravity: number?): number
	local jp = jumpPower or StageGenerator.DEFAULT_JUMP_POWER
	local g = gravity or StageGenerator.DEFAULT_GRAVITY
	return 2 * jp / g
end

-- Minimum WalkSpeed needed to clear `gap` studs on a flat jump.
function StageGenerator.requiredSpeedForGap(gap: number, jumpPower: number?, gravity: number?): number
	return gap / StageGenerator.airTime(jumpPower, gravity)
end

function StageGenerator.stageParams(stage: number): StageParams
	local maxGap = math.min(
		StageGenerator.MAX_GAP_AT_BASE_SPEED + (stage - 1) * StageGenerator.GAP_GROWTH_PER_STAGE,
		StageGenerator.ABSOLUTE_MAX_GAP
	)
	return {
		maxGap = maxGap,
		minGap = maxGap - StageGenerator.GAP_JITTER,
		platformWidth = math.max(StageGenerator.BASE_PLATFORM_WIDTH - (stage - 1), StageGenerator.MIN_PLATFORM_WIDTH),
		platformCount = 2 + stage // 2,
	}
end

-- Park-Miller minimal standard LCG. 16807 * (2^31 - 2) < 2^53, so every
-- intermediate is an exact integer in a double and Lune/Roblox agree.
local LCG_MUL = 16807
local LCG_MOD = 2147483647

local function makeRng(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % (LCG_MOD - 1) + 1
	return function(): number
		state = (state * LCG_MUL) % LCG_MOD
		return (state - 1) / (LCG_MOD - 1) -- [0, 1]
	end
end

local function roundHalf(n: number): number
	return math.floor(n * 2 + 0.5) / 2
end

local function validate(config: LayoutConfig)
	local n = config.stageCount
	local lo, hi = StageGenerator.MIN_STAGES, StageGenerator.MAX_STAGES
	if type(n) ~= "number" or n ~= math.floor(n) or n < lo or n > hi then
		error(`StageGenerator: stageCount must be an integer in {lo}..{hi}, got {tostring(n)}`, 3)
	end
end

function StageGenerator.layout(config: LayoutConfig): { PartSpec }
	validate(config)
	local rand = makeRng(config.seed or StageGenerator.DEFAULT_SEED)
	local specs: { PartSpec } = {}
	local h = StageGenerator.PLATFORM_HEIGHT
	local y = StageGenerator.BASE_Y
	local cursorZ = 0 -- far (+Z) edge of the last placed part

	local function place(kind: PartKind, stage: number, gap: number, width: number, depth: number, x: number)
		local frontZ = cursorZ + gap
		table.insert(specs, {
			position = { x = x, y = y, z = frontZ + depth / 2 },
			size = { x = width, y = h, z = depth },
			kind = kind,
			stage = stage,
		})
		cursorZ = frontZ + depth
	end

	local spawnSize = StageGenerator.SPAWN_SIZE
	place("platform", 0, 0, spawnSize, spawnSize, 0)

	local lastParams = StageGenerator.stageParams(1)
	for stage = 1, config.stageCount do
		local params = StageGenerator.stageParams(stage)
		lastParams = params
		local function nextGap(): number
			return roundHalf(params.minGap + rand() * (params.maxGap - params.minGap))
		end

		for _ = 1, params.platformCount do
			local width = roundHalf(params.platformWidth - rand() * StageGenerator.WIDTH_JITTER)
			local x = roundHalf((rand() * 2 - 1) * StageGenerator.MAX_LATERAL_OFFSET)
			place("platform", stage, nextGap(), width, StageGenerator.PLATFORM_DEPTH, x)
		end

		local cp = StageGenerator.CHECKPOINT_SIZE
		place("checkpoint", stage, nextGap(), cp, cp, 0)
	end

	-- Finish uses the easiest gap of the final stage.
	local finishSize = StageGenerator.FINISH_SIZE
	place("finish", config.stageCount, lastParams.minGap, finishSize, finishSize, 0)

	return specs
end

-- RGB per kind; Color3 is built inside `build` so the module loads under Lune.
local KIND_RGB: { [PartKind]: { number } } = {
	platform = { 110, 130, 160 },
	checkpoint = { 60, 200, 90 },
	finish = { 255, 200, 40 },
}

-- Replaces any existing Model named "Course" under `parent`.
function StageGenerator.build(parent: Instance, config: LayoutConfig): BuildResult
	local specs = StageGenerator.layout(config)

	local existing = parent:FindFirstChild("Course")
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "Course"

	local spawn: BasePart? = nil
	local finish: BasePart? = nil
	local checkpoints: { BasePart } = {}
	local platformIndex = 0

	for _, spec in specs do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(spec.size.x, spec.size.y, spec.size.z)
		part.Position = Vector3.new(spec.position.x, spec.position.y, spec.position.z)
		local rgb = KIND_RGB[spec.kind]
		part.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])

		if spec.kind == "checkpoint" then
			local index = #checkpoints + 1
			part.Name = `Checkpoint_{index}`
			part.Material = Enum.Material.Neon
			part:SetAttribute("StageIndex", index)
			table.insert(checkpoints, part)
		elseif spec.kind == "finish" then
			part.Name = "WinPad"
			part.Material = Enum.Material.Neon
			finish = part
		elseif spawn == nil then
			part.Name = "Spawn"
			spawn = part
		else
			platformIndex += 1
			part.Name = `Platform_{platformIndex}`
		end

		part.Parent = model
	end

	model.Parent = parent
	assert(spawn and finish, "StageGenerator: layout missing spawn or finish")
	return { spawn = spawn, checkpoints = checkpoints, finish = finish }
end

return StageGenerator
