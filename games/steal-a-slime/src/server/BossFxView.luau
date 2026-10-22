--!strict
--[[
	BossFxView (Roblox adapter, contract/boss-event.md "Attacks")

	Makes workspace match the boss's attack state (world.boss): a guard model for every live guard (a mini copy of the
	boss built by the slime model factory; plain crowned balls without a factory), a goo puddle for
	every puddle, and attributes on the boss model that clients draw from: BossTargets (spit landing spots during the
	windup), BossSpits (spits in the air) and BossHitAt / BossHitBy / BossHitPoints (the latest counted bat hit).
	Holds no rules: BossEvent decides everything. Call from WorldView.reconcile.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local World = require(script.Parent.World)

local BOSS = Config.BOSS

local BossFxView = {}

local FOLDER = "BossFx"
local GOO = Color3.fromRGB(110, 210, 90)

local guards: { [string]: Model } = {}
local puddles: { [string]: BasePart } = {}

local function folder(): Folder
	local f = workspace:FindFirstChild(FOLDER)
	if f and f:IsA("Folder") then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = FOLDER
	made.Parent = workspace
	return made
end

local function part(name: string, shape: Enum.PartType, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- The slime model factory (WorldView's ModelFactory / SlimeMesh) and the boss's own slime data: guards are mini
-- copies of it. Either nil = the plain ball guards.
export type Look = { build: (slime: any) -> Model, slime: any }

-- A guard as a mini copy of its boss (the factory's look), facing the boss's players (away from the boss).
local function buildLookGuard(index: number, at: Vector3, face: Vector3, look: Look): Model?
	local slime = table.clone(look.slime)
	slime.id = `guard{index}`
	slime.size = BOSS.GUARD_SIZE / Config.SLIME_BASE_DIAMETER
	local ok, model = pcall(look.build, slime)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	model.Name = `BossGuard{index}`
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	for _, tag in CollectionService:GetTags(model) do
		CollectionService:RemoveTag(model, tag)
	end
	model:SetAttribute("SlimeId", nil)
	local away = Vector3.new(2 * at.X - face.X, at.Y, 2 * at.Z - face.Z)
	local base = CFrame.lookAt(at, away)
	model:PivotTo(base)
	model:SetAttribute(Constants.BOSS_GUARD_ATTRIBUTE, true)
	model:SetAttribute("GuardBaseY", at.Y)
	model.Parent = folder()
	return model
end

-- A guard: a small round slime in the boss's colour with two eyes and a little crown, facing the boss.
local function buildGuard(index: number, at: Vector3, face: Vector3, color: Color3, look: Look?): Model
	local fromLook = if look then buildLookGuard(index, at, face, look) else nil
	if fromLook then
		return fromLook
	end
	local model = Instance.new("Model")
	model.Name = `BossGuard{index}`
	local s = BOSS.GUARD_SIZE
	local cf = CFrame.lookAt(at + Vector3.new(0, s * 0.42, 0), Vector3.new(face.X, at.Y + s * 0.42, face.Z))
	local body = part("Body", Enum.PartType.Ball, Vector3.new(s, s * 0.85, s), color, model)
	body.CFrame = cf
	for side = -1, 1, 2 do
		local eye = part("Eye", Enum.PartType.Ball, Vector3.one * s * 0.22, Color3.fromRGB(25, 25, 35), model)
		eye.CFrame = cf * CFrame.new(side * s * 0.18, s * 0.08, -s * 0.42)
	end
	local crown = part(
		"Crown",
		Enum.PartType.Cylinder,
		Vector3.new(s * 0.18, s * 0.5, s * 0.5),
		Color3.fromRGB(255, 205, 70),
		model
	)
	crown.Material = Enum.Material.Neon
	crown.CFrame = cf * CFrame.new(0, s * 0.46, 0) * CFrame.Angles(0, 0, math.pi / 2)
	model.PrimaryPart = body
	model:SetAttribute(Constants.BOSS_GUARD_ATTRIBUTE, true)
	model:SetAttribute("GuardBaseY", at.Y)
	model.Parent = folder()
	return model
end

local function buildPuddle(at: Vector3): BasePart
	local r = BOSS.PUDDLE_RADIUS
	local p = part("GooPuddle", Enum.PartType.Cylinder, Vector3.new(0.25, r * 2, r * 2), GOO, folder())
	p.Material = Enum.Material.Neon
	p.Transparency = 0.35
	p.CFrame = CFrame.new(at + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	return p
end

local function setAttr(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function spotsText(list: { string }): string?
	return if #list > 0 then table.concat(list, ";") else nil
end

--[[
	`model` is the boss model (nil = none in the world), `origin` the plaza origin, `groundY` the plaza's ground
	height, `color` the boss's colour, `look` how to build its guards as mini copies of it (nil = plain balls).
]]
function BossFxView.sync(
	world: World.World,
	model: Model?,
	origin: Vector3,
	groundY: number,
	color: Color3?,
	look: Look?
)
	local event = world.boss
	local liveGuards: { [string]: boolean } = {}
	local livePuddles: { [string]: boolean } = {}
	if event then
		local bossAt = model and model:GetPivot().Position or origin
		for i, g in event.guards do
			if g.alive then
				local key = string.format("%.2f|%.2f", g.x, g.z) -- a new guard call never reuses an old model
				liveGuards[key] = true
				if not guards[key] or not guards[key].Parent then
					guards[key] =
						buildGuard(i, Vector3.new(g.x + origin.X, groundY, g.z + origin.Z), bossAt, color or GOO, look)
				end
			end
		end
		for _, p in event.puddles do
			local key = string.format("%.2f|%.2f|%.2f", p.x, p.z, p.untilAt)
			livePuddles[key] = true
			if not puddles[key] then
				puddles[key] = buildPuddle(Vector3.new(p.x + origin.X, groundY, p.z + origin.Z))
			end
		end
		if model then
			local targets = {}
			for _, t in event.targets do
				table.insert(targets, string.format("%.2f,%.2f", t[1] + origin.X, t[2] + origin.Z))
			end
			local spits = {}
			for _, s in event.spits do
				table.insert(spits, string.format("%.2f,%.2f,%.3f", s.x + origin.X, s.z + origin.Z, s.landAt))
			end
			setAttr(model, Constants.BOSS_TARGETS_ATTRIBUTE, spotsText(targets))
			setAttr(model, Constants.BOSS_SPITS_ATTRIBUTE, spotsText(spits))
			local runes = {}
			for _, p in event.puddles do
				local burst = p.burst
				if burst and p.burstAt then
					table.insert(
						runes,
						string.format(
							"%.2f,%.2f,%.3f,%.2f,%.2f",
							p.x + origin.X,
							p.z + origin.Z,
							p.burstAt,
							burst.radius or 10,
							burst.speed or 16
						)
					)
				end
			end
			setAttr(model, Constants.BOSS_RUNES_ATTRIBUTE, spotsText(runes))
			local bursts = {}
			for _, b in event.bursts do
				table.insert(
					bursts,
					string.format(
						"%.2f,%.2f,%.2f,%.2f,%.3f,%.3f",
						b.fromX + origin.X,
						b.fromZ + origin.Z,
						b.x + origin.X,
						b.z + origin.Z,
						b.at,
						b.landAt
					)
				)
			end
			setAttr(model, Constants.BOSS_BURSTS_ATTRIBUTE, spotsText(bursts))
			local hit = event.lastHit
			setAttr(model, Constants.BOSS_HIT_AT_ATTRIBUTE, hit and hit.at)
			setAttr(model, Constants.BOSS_HIT_BY_ATTRIBUTE, hit and hit.userId)
			setAttr(model, Constants.BOSS_HIT_POINTS_ATTRIBUTE, hit and hit.points)
		end
	end
	for key, m in guards do
		if not liveGuards[key] then
			m:Destroy()
			guards[key] = nil
		end
	end
	for key, p in puddles do
		if not livePuddles[key] then
			p:Destroy()
			puddles[key] = nil
		end
	end
end

return BossFxView
