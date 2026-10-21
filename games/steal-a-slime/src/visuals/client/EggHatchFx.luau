--!strict
--[[
	EggHatchFx (client only, contract/mystery-egg.md §40.6)

	The Mystery Egg hatch show on the pad, for every viewer near it. The
	server tags the new slime model with HatchedAt / HatchedFrom / HatchLucky
	for a few seconds after a hatch; this module plays Visuals.EggHatchTimeline
	from those attributes and the server clock:
	  * a local copy of the egg (a clone of the ready egg taken before the
	    hatch, else EggModel.build) rocks three times while its glow climbs the
	    rarity colours, shivers, and bursts into shards with a flash, a ring and
	    sparks in the hatch's rarity colour;
	  * the slime model, kept tiny until the burst (Model:ScaleTo, local only),
	    pops up with an overshoot; Epic and up get a light pillar;
	  * a rarity title ("LEGENDARY!", "LUCKY! MYTHIC!") floats up; the hatching
	    owner's camera eases in a little over the hold.
	Everything it makes is local (never replicates), decides nothing and is
	gone by EggHatchTimeline.END or when the model goes.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local EggKind = require(ReplicatedStorage.Shared.EggKind)
local EggModel = require(ReplicatedStorage.Visuals.EggModel)
local Timeline = require(ReplicatedStorage.Visuals.EggHatchTimeline)

local EggHatchFx = {}

EggHatchFx.MAX_DISTANCE = 150 -- studs: a viewer further away sees no show
EggHatchFx.FOLDER = "EggHatchFx"

local GOLD = Color3.fromRGB(255, 214, 90)
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

type Cached = { copy: Model, pivot: CFrame }

type Show = {
	model: Model,
	hatchedAt: number,
	tier: number,
	lucky: boolean,
	steps: { number },
	pivot: CFrame, -- the pad spot: the slime's (and the egg's) bottom centre
	baseScale: number?, -- the slime's own scale, nil if it could not be scaled
	egg: Model?,
	eggBody: BasePart?,
	glow: PointLight?,
	sparks: ParticleEmitter?,
	burst: Folder?,
	shards: { BasePart },
	ring: BasePart?,
	flash: PointLight?,
	beam: BasePart?,
	title: BasePart?,
	label: TextLabel?,
	popped: boolean, -- the slime is back at its own scale
	owner: boolean, -- the local player hatched it
	fov: number?, -- the camera's field of view before the zoom, while zoomed
}

local function rarityColor(tier: number): Color3
	local c = Config.RARITIES[math.clamp(tier, 1, Config.MAX_TIER)].color
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function lowestDrop(kindId: string): number
	local kind = EggKind.get(kindId)
	local low = Config.MAX_TIER
	if kind then
		for _, drop in kind.drops do
			low = math.min(low, drop.tier)
		end
	end
	return low
end

local function localPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Archivable = false
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- A copy of an egg model that nothing else treats as a slime: no tags, prompts, labels, scripts or nest.
local function strip(copy: Model)
	for _, tag in copy:GetTags() do
		copy:RemoveTag(tag)
	end
	for name in copy:GetAttributes() do
		copy:SetAttribute(name, nil)
	end
	for _, d in copy:GetDescendants() do
		for _, tag in d:GetTags() do
			d:RemoveTag(tag)
		end
		if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	local nest = copy:FindFirstChild("Nest")
	if nest then
		nest:Destroy()
	end
	copy.Archivable = false
end

local function cloneEgg(model: Model): Model?
	local wasArchivable = model.Archivable
	model.Archivable = true
	local ok, copy = pcall(model.Clone, model)
	model.Archivable = wasArchivable
	if not ok or not copy then
		return nil
	end
	strip(copy :: Model)
	return copy :: Model
end

local function buildEgg(id: string, kindId: string): Model?
	local ok, copy = pcall(EggModel.build, id, kindId, nil)
	if not ok or typeof(copy) ~= "Instance" then
		return nil
	end
	strip(copy :: Model)
	return copy :: Model
end

local function scaleTo(show: Show, factor: number)
	local base = show.baseScale
	if base then
		pcall(show.model.ScaleTo, show.model, math.max(base * factor, 0.01))
	end
end

local function cleanup(show: Show)
	if show.egg then
		show.egg:Destroy()
	end
	if show.burst then
		show.burst:Destroy()
	end
	if not show.popped and show.model.Parent then
		scaleTo(show, 1)
	end
	show.popped = true
	local camera = workspace.CurrentCamera
	if show.fov and camera then
		camera.FieldOfView = show.fov
	end
	show.fov = nil
end

local function makeBurst(show: Show, folder: Instance)
	local burst = Instance.new("Folder")
	burst.Name = "Burst"
	burst.Archivable = false
	burst.Parent = folder
	show.burst = burst
	local color = rarityColor(show.tier)
	local shellColor = if show.eggBody then show.eggBody.Color else Color3.fromRGB(255, 240, 205)
	local centre = show.pivot.Position + Vector3.new(0, EggModel.HEIGHT / 2, 0)
	for i = 1, Timeline.SHARDS do
		local shard = localPart({
			Name = `Shard{i}`,
			Size = Vector3.new(0.9, 0.7, 0.22),
			Color = shellColor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(centre),
		})
		shard.Parent = burst
		table.insert(show.shards, shard)
	end
	local ring = localPart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 2, 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CFrame = CFrame.new(show.pivot.Position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	ring.Parent = burst
	show.ring = ring
	local core =
		localPart({ Name = "Core", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(centre) })
	core.Parent = burst
	local flash = Instance.new("PointLight")
	flash.Color = color
	flash.Range = 18
	flash.Brightness = 8
	flash.Shadows = false
	flash.Parent = core
	show.flash = flash
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.Texture = SPARK_TEXTURE
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(0.5, 1.2)
	sparks.Speed = NumberRange.new(8, 18)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -12, 0)
	sparks.Rate = 0
	sparks.Parent = core
	sparks:Emit(if show.tier >= Timeline.BEAM_TIER then 60 else 36)
	if show.tier >= Timeline.BEAM_TIER then
		local beam = localPart({
			Name = "Beam",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(40, 2, 2),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			CFrame = CFrame.new(show.pivot.Position + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		})
		beam.Parent = burst
		show.beam = beam
	end
	local anchor = localPart({
		Name = "Title",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(show.pivot.Position + Vector3.new(0, EggModel.HEIGHT + 3, 0)),
	})
	anchor.Parent = burst
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(340, 64)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = EggHatchFx.MAX_DISTANCE
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = Timeline.title(show.tier, show.lucky)
	label.TextColor3 = color
	label.TextTransparency = 1
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 14, 30)
	stroke.Parent = label
	show.title = anchor
	show.label = label
end

local function step(show: Show, t: number, camera: Camera?, folder: Instance)
	-- Egg: rock, glow, shiver until the burst.
	if t < Timeline.BURST then
		local egg = show.egg
		if egg then
			local tilt = Timeline.tilt(t)
			egg:PivotTo(show.pivot * CFrame.Angles(tilt, 0, tilt * 0.4))
		end
		local glow = show.glow
		if glow then
			glow.Color = if show.lucky and Timeline.luckyFlash(t)
				then GOLD
				else rarityColor(Timeline.glowTier(t, show.steps))
			glow.Brightness = Timeline.glow(t)
		end
		local sparks = show.sparks
		if sparks then
			sparks.Color = ColorSequence.new(rarityColor(Timeline.glowTier(t, show.steps)))
			sparks.Rate = if t >= Timeline.WOBBLE_END then 40 else 10
		end
	elseif not show.burst then
		if show.egg then
			show.egg:Destroy()
			show.egg = nil
		end
		makeBurst(show, folder)
	end
	-- Burst pieces.
	if show.burst then
		local s = t - Timeline.BURST
		for i, shard in show.shards do
			if s < Timeline.SHARD_SECONDS then
				local x, y, z = Timeline.shard(i, #show.shards, s)
				shard.CFrame = CFrame.new(show.pivot.Position + Vector3.new(x, y, z))
					* CFrame.Angles(s * (3 + i), s * (2 + i * 0.5), 0)
				shard.Transparency = math.clamp((s - 0.6) / 0.3, 0, 1)
			else
				shard.Transparency = 1
			end
		end
		local ring = show.ring
		if ring then
			local u = math.clamp(s / 0.5, 0, 1)
			ring.Size = Vector3.new(0.2, 2 + 14 * u, 2 + 14 * u)
			ring.Transparency = 0.2 + 0.8 * u
		end
		local flash = show.flash
		if flash then
			flash.Brightness = math.max(0, 8 * (1 - s / 0.6))
		end
		local beam = show.beam
		if beam then
			beam.Transparency = Timeline.beam(t, show.tier) or 1
		end
		local rise, fade = Timeline.titleLook(t)
		local label = show.label
		local title = show.title
		if label and title then
			label.TextTransparency = fade or 1
			if rise then
				title.CFrame = CFrame.new(show.pivot.Position + Vector3.new(0, EggModel.HEIGHT + 3 + rise, 0))
			end
		end
	end
	-- Slime: tiny, then the pop.
	if not show.popped then
		if t >= Timeline.REVEAL then
			scaleTo(show, 1)
			show.popped = true
		elseif t >= Timeline.BURST then
			scaleTo(show, Timeline.slimeScale(t))
		end
	end
	-- The hatching owner's camera eases in over the hold.
	if show.owner and camera then
		local zoom = Timeline.zoom(t)
		if zoom > 0 then
			show.fov = show.fov or camera.FieldOfView
			camera.FieldOfView = (show.fov :: number) - zoom
		elseif show.fov then
			camera.FieldOfView = show.fov
			show.fov = nil
		end
	end
end

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

-- Starts watching for hatches. Call `tick` once a frame from the client's frame loop.
function EggHatchFx.start(): Controller
	local folder = Instance.new("Folder")
	folder.Name = EggHatchFx.FOLDER
	folder.Archivable = false
	folder.Parent = workspace
	local eggs: { [Model]: true } = {} -- egg models on this client
	local cache: { [string]: Cached } = {} -- slime id -> a copy of its ready egg, taken before the hatch
	local shows: { [Model]: Show } = {}
	local conns: { RBXScriptConnection } = {}
	local player = Players.LocalPlayer

	local function begin(model: Model)
		if shows[model] then
			return
		end
		local hatchedAt = model:GetAttribute(Constants.HATCHED_AT_ATTRIBUTE)
		local kindId = model:GetAttribute(Constants.HATCHED_FROM_ATTRIBUTE)
		if type(hatchedAt) ~= "number" or type(kindId) ~= "string" then
			return
		end
		local t = workspace:GetServerTimeNow() - hatchedAt
		if t >= Timeline.REVEAL or t < -1 then
			return
		end
		local camera = workspace.CurrentCamera
		local pivot = model:GetPivot()
		if camera and (camera.CFrame.Position - pivot.Position).Magnitude > EggHatchFx.MAX_DISTANCE then
			return
		end
		local id = model:GetAttribute("SlimeId")
		local tier = model:GetAttribute("Tier") or model:GetAttribute(Constants.LABEL_TIER_ATTRIBUTE)
		tier = if type(tier) == "number" then tier else 1
		local cached = if type(id) == "string" then cache[id] else nil
		if cached and type(id) == "string" then
			cache[id] = nil
		end
		local okScale, scale = pcall(model.GetScale, model)
		local show: Show = {
			model = model,
			hatchedAt = hatchedAt,
			tier = tier,
			lucky = model:GetAttribute(Constants.HATCH_LUCKY_ATTRIBUTE) == true,
			steps = Timeline.steps(lowestDrop(kindId), tier),
			pivot = if cached then cached.pivot else pivot,
			baseScale = if okScale and type(scale) == "number" then scale else nil,
			shards = {},
			popped = false,
			owner = player ~= nil and model:GetAttribute("OwnerUserId") == player.UserId,
		}
		shows[model] = show
		if t < Timeline.BURST then
			local egg = if cached then cached.copy else buildEgg(if type(id) == "string" then id else "hatch", kindId)
			if egg then
				egg:PivotTo(show.pivot)
				egg.Parent = folder
				show.egg = egg
				local body = egg:FindFirstChild("Body")
				if body and body:IsA("BasePart") then
					show.eggBody = body
					local old = body:FindFirstChildOfClass("PointLight")
					if old then
						old:Destroy()
					end
					local glow = Instance.new("PointLight")
					glow.Range = 12
					glow.Shadows = false
					glow.Parent = body
					show.glow = glow
					local sparks = body:FindFirstChildOfClass("ParticleEmitter") or Instance.new("ParticleEmitter")
					sparks.Texture = SPARK_TEXTURE
					sparks.LightEmission = 1
					sparks.Lifetime = NumberRange.new(0.4, 0.8)
					sparks.Speed = NumberRange.new(2, 5)
					sparks.SpreadAngle = Vector2.new(180, 180)
					sparks.Parent = body
					show.sparks = sparks
				end
			end
		elseif cached then
			cached.copy:Destroy()
		end
		if not show.popped then
			scaleTo(show, if t >= Timeline.BURST then Timeline.slimeScale(t) else Timeline.HIDDEN_SCALE)
		end
	end

	local function added(instance: Instance)
		if not instance:IsA("Model") then
			return
		end
		if instance:GetAttribute(Constants.EGG_KIND_ATTRIBUTE) ~= nil then
			eggs[instance] = true
		elseif instance:GetAttribute(Constants.HATCHED_AT_ATTRIBUTE) ~= nil then
			-- Scale before the first frame draws it, if its parts are here; else once they stream in.
			if instance.PrimaryPart or instance:FindFirstChild("Body") then
				begin(instance)
			else
				task.spawn(function()
					if instance:WaitForChild("Body", 5) then
						begin(instance)
					end
				end)
			end
		end
	end
	local function removed(instance: Instance)
		eggs[instance :: Model] = nil
		local show = shows[instance :: Model]
		if show then
			shows[instance :: Model] = nil
			cleanup(show)
		end
	end

	table.insert(conns, CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(added))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(removed))
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		added(model)
	end

	-- Keeps a copy of every ready egg resting on a pad near the camera (re-taken if it moved).
	local function refreshCache(now: number, eye: Vector3?)
		for model in eggs do
			local id = model:GetAttribute("SlimeId")
			local hatchAt = model:GetAttribute(Constants.EGG_HATCH_AT_ATTRIBUTE)
			if
				type(id) ~= "string"
				or not model.Parent
				or model:GetAttribute("State") ~= "Pad"
				or type(hatchAt) ~= "number"
				or hatchAt > now
			then
				continue
			end
			local pivot = model:GetPivot()
			if eye and (pivot.Position - eye).Magnitude > EggHatchFx.MAX_DISTANCE then
				continue
			end
			local cached = cache[id]
			if cached and (cached.pivot.Position - pivot.Position).Magnitude < 0.5 then
				continue
			end
			if cached then
				cached.copy:Destroy()
			end
			local copy = cloneEgg(model)
			cache[id] = if copy then { copy = copy, pivot = pivot } else nil
		end
		for id, cached in cache do
			local alive = false
			for model in eggs do
				if model:GetAttribute("SlimeId") == id then
					alive = true
					break
				end
			end
			-- Kept a moment after its egg goes: the hatched slime's model may replicate just after.
			if not alive and not cached.copy:GetAttribute("GoneAt") then
				cached.copy:SetAttribute("GoneAt", now)
			elseif not alive and now - (cached.copy:GetAttribute("GoneAt") :: number) > 3 then
				cached.copy:Destroy()
				cache[id] = nil
			end
		end
	end

	local lastCache = 0
	local function tick(camera: Camera?)
		local now = workspace:GetServerTimeNow()
		if os.clock() - lastCache > 0.5 then
			lastCache = os.clock()
			refreshCache(now, camera and camera.CFrame.Position)
		end
		for model, show in shows do
			local t = now - show.hatchedAt
			if not model.Parent or t >= Timeline.END then
				shows[model] = nil
				cleanup(show)
			else
				step(show, t, camera, folder)
			end
		end
	end

	return {
		tick = tick,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			for model, show in shows do
				shows[model] = nil
				cleanup(show)
			end
			for _, cached in cache do
				cached.copy:Destroy()
			end
			folder:Destroy()
		end,
	}
end

return EggHatchFx
