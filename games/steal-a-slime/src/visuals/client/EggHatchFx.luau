--!strict
--[[
	EggHatchFx (client only, contract/mystery-egg.md §40.6)

	The Mystery Egg hatch show on the pad, for every viewer near it, from
	Visuals.EggHatchTimeline:
	  * Egg: for HATCH_BURST_SECONDS after a hatch the server keeps the egg
	    model on the pad with HatchedAt / HatchedFrom / HatchLucky / HatchTier.
	    The real egg is hidden locally and a local copy plays the wobble: three
	    rocks with a hop, a new set of glowing cracks each time, a glow that
	    climbs the rarity colours to the tier inside, then a swelling shake.
	  * Burst (egg time BURST, or when the egg model goes): shards, the egg's top
	    flying off, a flash, a ring and sparks in the rarity colour.
	  * Pop: the hatched slime's model is hidden locally (LocalTransparencyModifier)
	    while a local copy of it springs up from tiny; then the real one shows
	    again. Nothing ever rescales the real model, so whatever the server adds
	    to it (a species mesh arriving late) keeps its size. A rarity title
	    floats up as a small sign in the world (walls hide it, near only; for
	    someone else's hatch only from Epic up); the owner's camera eases in.
	Everything it makes is local (never replicates) and decides nothing.
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

-- Glowing cracks, one set per rock: points on the shell as (yaw, height -1..1) joined into a zig-zag.
local CRACKS = {
	{ { 0.2, 0.75 }, { 0.45, 0.45 }, { 0.15, 0.2 }, { 0.5, -0.05 }, { 0.3, -0.3 } },
	{ { 2.3, 0.6 }, { 2.0, 0.3 }, { 2.4, 0.05 }, { 2.1, -0.25 }, { 2.5, -0.45 } },
	{ { 4.3, 0.8 }, { 4.0, 0.5 }, { 4.4, 0.25 }, { 4.1, 0 }, { 4.5, -0.3 }, { 4.2, -0.55 } },
}

type EggShow = {
	original: Model,
	id: string,
	hatchedAt: number,
	tier: number,
	lucky: boolean,
	steps: { number },
	pivot: CFrame,
	copy: Model?,
	body: BasePart?,
	glow: PointLight?,
	sparks: ParticleEmitter?,
	cracks: { { BasePart } },
	shellColor: Color3,
	owner: boolean,
	burst: boolean,
}

type Pop = {
	original: Model,
	startedAt: number, -- os.clock() when it began
	tier: number,
	lucky: boolean,
	pivot: CFrame,
	copy: Model?,
	baseScale: number,
	folder: Folder,
	title: BasePart?,
	label: TextLabel?,
	hiddenConn: RBXScriptConnection?,
	done: boolean, -- the copy is gone and the real slime shows again
}

type Burst = {
	startedAt: number,
	pivot: CFrame,
	folder: Folder,
	shards: { BasePart },
	lid: BasePart?,
	ring: BasePart?,
	flash: PointLight?,
}

local function rarityColor(tier: number): Color3
	local c = Config.RARITIES[math.clamp(tier, 1, Config.MAX_TIER)].color
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function lowestDrop(kindId: any): number
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

local function inNest(d: Instance, model: Instance): boolean
	local nest = model:FindFirstChild("Nest")
	return nest ~= nil and d:IsDescendantOf(nest)
end

-- Hides (or shows again) a model on this client only: parts, decals, and the lights and sparkles on it (EggFx's
-- ready glow). The egg's nest stays.
local function setHidden(model: Model, hidden: boolean)
	local value = if hidden then 1 else 0
	for _, d in model:GetDescendants() do
		if inNest(d, model) then
			continue
		elseif d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = value
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
			(d :: any).Enabled = not hidden
		end
	end
end

-- A local copy of a model that nothing else treats as a slime: no tags, attributes, prompts, guis, scripts or nest.
local function copyOf(model: Model): Model?
	local was = model.Archivable
	model.Archivable = true
	local ok, copy = pcall(model.Clone, model)
	model.Archivable = was
	if not ok or not copy then
		return nil
	end
	local c = copy :: Model
	for _, tag in c:GetTags() do
		c:RemoveTag(tag)
	end
	for name in c:GetAttributes() do
		c:SetAttribute(name, nil)
	end
	for _, d in c:GetDescendants() do
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
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	local nest = c:FindFirstChild("Nest")
	if nest then
		nest:Destroy()
	end
	c.Archivable = false
	return c
end

-- The glowing crack sets on the egg copy, hidden until their rock.
local function addCracks(show: EggShow)
	local body = show.body
	local copy = show.copy
	if not body or not copy then
		return
	end
	local rx, ry = EggModel.WIDTH / 2, EggModel.HEIGHT / 2
	local function onShell(yaw: number, h: number): (Vector3, Vector3)
		local ring = math.sqrt(math.max(0, 1 - h * h)) * rx
		local pos = Vector3.new(math.cos(yaw) * ring, h * ry, math.sin(yaw) * ring)
		local normal = Vector3.new(pos.X / (rx * rx), pos.Y / (ry * ry), pos.Z / (rx * rx)).Unit
		return pos + normal * 0.04, normal
	end
	for set, points in CRACKS do
		local parts = {}
		for i = 1, #points - 1 do
			local a, na = onShell(points[i][1], points[i][2])
			local b = onShell(points[i + 1][1], points[i + 1][2])
			local mid = (a + b) / 2
			local length = (b - a).Magnitude
			local crack = localPart({
				Name = `GlowCrack{set}_{i}`,
				Size = Vector3.new(0.24, length + 0.1, 0.08),
				Material = Enum.Material.Neon,
				Color = Color3.new(1, 1, 1),
				Transparency = 1,
			})
			-- Up along the segment, facing out of the shell.
			local up = (b - a).Unit
			local out = (na - up * na:Dot(up)).Unit
			crack.CFrame = body.CFrame * CFrame.fromMatrix(mid, up:Cross(out), up, -out)
			crack.Parent = copy
			table.insert(parts, crack)
		end
		show.cracks[set] = parts
	end
end

local function startEgg(egg: Model, folder: Folder, player: Player?): EggShow?
	local hatchedAt = egg:GetAttribute(Constants.HATCHED_AT_ATTRIBUTE)
	local id = egg:GetAttribute("SlimeId")
	if type(hatchedAt) ~= "number" or type(id) ~= "string" then
		return nil
	end
	local t = workspace:GetServerTimeNow() - hatchedAt
	if t >= Timeline.BURST then
		return nil
	end
	local tier = egg:GetAttribute(Constants.HATCH_TIER_ATTRIBUTE)
	-- Until HatchTier arrives the glow stays at the kind's lowest drop.
	tier = if type(tier) == "number" then tier else lowestDrop(egg:GetAttribute(Constants.HATCHED_FROM_ATTRIBUTE))
	local copy = copyOf(egg)
	local show: EggShow = {
		original = egg,
		id = id,
		hatchedAt = hatchedAt,
		tier = tier,
		lucky = egg:GetAttribute(Constants.HATCH_LUCKY_ATTRIBUTE) == true,
		steps = Timeline.steps(lowestDrop(egg:GetAttribute(Constants.HATCHED_FROM_ATTRIBUTE)), tier),
		pivot = egg:GetPivot(),
		copy = copy,
		cracks = {},
		shellColor = Color3.fromRGB(255, 240, 205),
		owner = player ~= nil and egg:GetAttribute("OwnerUserId") == player.UserId,
		burst = false,
	}
	if copy then
		local body = copy:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			show.body = body
			show.shellColor = body.Color
			for _, old in body:GetChildren() do
				if old:IsA("PointLight") or old:IsA("ParticleEmitter") then
					old:Destroy()
				end
			end
			local glow = Instance.new("PointLight")
			glow.Range = 14
			glow.Shadows = false
			glow.Parent = body
			show.glow = glow
			local sparks = Instance.new("ParticleEmitter")
			sparks.Texture = SPARK_TEXTURE
			sparks.LightEmission = 1
			sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
			sparks.Lifetime = NumberRange.new(0.4, 0.9)
			sparks.Speed = NumberRange.new(3, 7)
			sparks.SpreadAngle = Vector2.new(180, 180)
			sparks.Rate = 0
			sparks.Parent = body
			show.sparks = sparks
		end
		copy:PivotTo(show.pivot)
		copy.Parent = folder
		addCracks(show)
		setHidden(egg, true)
	end
	return show
end

local function stepEgg(show: EggShow, t: number)
	local copy = show.copy
	if not copy then
		return
	end
	-- HatchTier / HatchLucky can replicate a frame after HatchedAt: follow them while the egg is here.
	local egg = show.original
	local tier = egg:GetAttribute(Constants.HATCH_TIER_ATTRIBUTE)
	if type(tier) == "number" and tier ~= show.tier then
		show.tier = tier
		show.steps = Timeline.steps(lowestDrop(egg:GetAttribute(Constants.HATCHED_FROM_ATTRIBUTE)), tier)
	end
	if egg:GetAttribute(Constants.HATCH_LUCKY_ATTRIBUTE) == true then
		show.lucky = true
	end
	local tilt = Timeline.tilt(t)
	copy:PivotTo(show.pivot * CFrame.new(0, Timeline.hop(t), 0) * CFrame.Angles(tilt, 0, tilt * 0.45))
	pcall(copy.ScaleTo, copy, Timeline.swell(t))
	local color = if show.lucky and Timeline.luckyFlash(t) then GOLD else rarityColor(Timeline.glowTier(t, show.steps))
	local glow = show.glow
	if glow then
		glow.Color = color
		glow.Brightness = Timeline.glow(t)
	end
	local sparks = show.sparks
	if sparks then
		sparks.Color = ColorSequence.new(color)
		sparks.Rate = if t >= Timeline.WOBBLE_END then 60 else 8 * Timeline.crackSets(t)
	end
	local sets = Timeline.crackSets(t)
	for set, parts in show.cracks do
		for _, crack in parts do
			crack.Transparency = if set <= sets then 0 else 1
			crack.Color = color
		end
	end
end

local function startBurst(pivot: CFrame, tier: number, shellColor: Color3, folder: Folder): Burst
	local holder = Instance.new("Folder")
	holder.Name = "Burst"
	holder.Archivable = false
	holder.Parent = folder
	local color = rarityColor(tier)
	local centre = pivot.Position + Vector3.new(0, EggModel.HEIGHT / 2, 0)
	local burst: Burst = { startedAt = os.clock(), pivot = pivot, folder = holder, shards = {} }
	for i = 1, Timeline.SHARDS do
		local shard = localPart({
			Name = `Shard{i}`,
			Size = Vector3.new(1.1, 0.85, 0.25),
			Color = shellColor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(centre),
		})
		shard.Parent = holder
		table.insert(burst.shards, shard)
	end
	local lid = localPart({
		Name = "Lid",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(EggModel.WIDTH * 0.9, EggModel.HEIGHT * 0.45, EggModel.WIDTH * 0.9),
		Color = shellColor,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(pivot.Position + Vector3.new(0, EggModel.HEIGHT * 0.85, 0)),
	})
	lid.Parent = holder
	burst.lid = lid
	local ring = localPart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 2, 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CFrame = CFrame.new(pivot.Position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	ring.Parent = holder
	burst.ring = ring
	local core =
		localPart({ Name = "Core", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(centre) })
	core.Parent = holder
	local flash = Instance.new("PointLight")
	flash.Color = color
	flash.Range = 16
	flash.Brightness = 6
	flash.Shadows = false
	flash.Parent = core
	burst.flash = flash
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.Texture = SPARK_TEXTURE
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(0.6, 1.4)
	sparks.Speed = NumberRange.new(10, 22)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -14, 0)
	sparks.Rate = 0
	sparks.Parent = core
	sparks:Emit(if tier >= Timeline.BIG_BURST_TIER then 80 else 50)
	return burst
end

-- Returns false once the burst pieces are done.
local function stepBurst(burst: Burst): boolean
	local s = os.clock() - burst.startedAt
	if s >= Timeline.SHARD_SECONDS + 0.4 then
		burst.folder:Destroy()
		return false
	end
	for i, shard in burst.shards do
		local x, y, z = Timeline.shard(i, #burst.shards, s)
		shard.CFrame = CFrame.new(burst.pivot.Position + Vector3.new(x, y, z))
			* CFrame.Angles(s * (3 + i), s * (2 + i * 0.5), 0)
		shard.Transparency = math.clamp((s - Timeline.SHARD_SECONDS + 0.3) / 0.3, 0, 1)
	end
	local lid = burst.lid
	if lid then
		local height, spin = Timeline.lid(s)
		lid.CFrame = CFrame.new(burst.pivot.Position + Vector3.new(0.8 * s, height, 0))
			* CFrame.Angles(spin, 0, spin * 0.6)
		lid.Transparency = math.clamp((s - Timeline.SHARD_SECONDS + 0.3) / 0.3, 0, 1)
	end
	local ring = burst.ring
	if ring then
		local u = math.clamp(s / 0.5, 0, 1)
		ring.Size = Vector3.new(0.2, 2 + 16 * u, 2 + 16 * u)
		ring.Transparency = 0.15 + 0.85 * u
	end
	local flash = burst.flash
	if flash then
		flash.Brightness = math.max(0, 6 * (1 - s / 0.5))
	end
	return true
end

local function startPop(slime: Model, tier: number, lucky: boolean, owner: boolean, folder: Folder): Pop
	local holder = Instance.new("Folder")
	holder.Name = "Pop"
	holder.Archivable = false
	holder.Parent = folder
	local pivot = slime:GetPivot()
	local okScale, scale = pcall(slime.GetScale, slime)
	local pop: Pop = {
		original = slime,
		startedAt = os.clock(),
		tier = tier,
		lucky = lucky,
		pivot = pivot,
		baseScale = if okScale and type(scale) == "number" then scale else 1,
		folder = holder,
		done = false,
	}
	local copy = copyOf(slime)
	if copy then
		copy:PivotTo(pivot)
		pcall(copy.ScaleTo, copy, pop.baseScale * Timeline.HIDDEN_SCALE)
		copy.Parent = holder
		pop.copy = copy
		slime:SetAttribute(Constants.HATCH_POPPING_ATTRIBUTE, true)
		setHidden(slime, true)
		-- Parts the server adds while the copy plays (a species mesh arriving) stay hidden until the end.
		pop.hiddenConn = slime.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = 1
			end
		end)
	end
	local color = rarityColor(tier)
	if not Timeline.showsTitle(owner, tier) then
		return pop
	end
	local anchor = localPart({
		Name = "Title",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(pivot.Position + Vector3.new(0, 7, 0)),
	})
	anchor.Parent = holder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(Timeline.TITLE_STUDS[1], Timeline.TITLE_STUDS[2])
	gui.AlwaysOnTop = false
	gui.MaxDistance = Timeline.TITLE_DISTANCE
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = Timeline.title(tier, lucky)
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 14, 30)
	stroke.Parent = label
	pop.title = anchor
	pop.label = label
	return pop
end

local function finishPop(pop: Pop)
	if pop.done then
		return
	end
	pop.done = true
	if pop.copy then
		pop.copy:Destroy()
		pop.copy = nil
	end
	if pop.hiddenConn then
		pop.hiddenConn:Disconnect()
	end
	if pop.original.Parent then
		setHidden(pop.original, false)
		pop.original:SetAttribute(Constants.HATCH_POPPING_ATTRIBUTE, nil)
	end
end

-- Returns false once the pop and its title are over.
local function stepPop(pop: Pop): boolean
	local s = os.clock() - pop.startedAt
	if not pop.done then
		local copy = pop.copy
		if s >= Timeline.POP_SECONDS or not pop.original.Parent then
			finishPop(pop)
		elseif copy then
			pcall(copy.ScaleTo, copy, pop.baseScale * Timeline.popScale(s))
		end
	end
	local rise, fade = Timeline.titleLook(s)
	if pop.label and pop.title then
		pop.label.TextTransparency = fade or 1
		if pop.label:FindFirstChildOfClass("UIStroke") then
			(pop.label:FindFirstChildOfClass("UIStroke") :: UIStroke).Transparency = fade or 1
		end
		if rise then
			pop.title.CFrame = CFrame.new(pop.pivot.Position + Vector3.new(0, 7 + rise, 0))
		end
	end
	if s >= Timeline.TITLE_SECONDS then
		finishPop(pop)
		pop.folder:Destroy()
		return false
	end
	return true
end

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

-- Starts watching for hatches. Call `tick` once a frame from the client's frame loop.
function EggHatchFx.start(): Controller
	local folder = Instance.new("Folder")
	folder.Name = EggHatchFx.FOLDER
	folder.Archivable = false
	folder.Parent = workspace
	local player = Players.LocalPlayer
	local eggShows: { [Model]: EggShow } = {}
	local bursts: { Burst } = {}
	local pops: { [Model]: Pop } = {}
	local burstDone: { [string]: { at: number, tier: number, lucky: boolean } } = {} -- slime id -> its burst
	local watched: { [Instance]: RBXScriptConnection } = {}
	local conns: { RBXScriptConnection } = {}
	local fov: number? = nil

	local function near(model: Model): boolean
		local camera = workspace.CurrentCamera
		return camera == nil
			or (camera.CFrame.Position - model:GetPivot().Position).Magnitude <= EggHatchFx.MAX_DISTANCE
	end

	local function burstOf(show: EggShow)
		if show.burst then
			return
		end
		show.burst = true
		if show.copy then
			show.copy:Destroy()
			show.copy = nil
		end
		if show.original.Parent then
			setHidden(show.original, false)
		end
		table.insert(bursts, startBurst(show.pivot, show.tier, show.shellColor, folder))
		burstDone[show.id] = { at = os.clock(), tier = show.tier, lucky = show.lucky }
	end

	local function tryEgg(egg: Model)
		if eggShows[egg] or egg:GetAttribute(Constants.HATCHED_AT_ATTRIBUTE) == nil or not near(egg) then
			return
		end
		local show = startEgg(egg, folder, player)
		if show then
			eggShows[egg] = show
		end
	end

	local function trySlime(slime: Model)
		if pops[slime] then
			return
		end
		local hatchedAt = slime:GetAttribute(Constants.HATCHED_AT_ATTRIBUTE)
		local id = slime:GetAttribute("SlimeId")
		if type(hatchedAt) ~= "number" or type(id) ~= "string" or not near(slime) then
			return
		end
		if workspace:GetServerTimeNow() - hatchedAt > Timeline.BURST + Timeline.LATE then
			return
		end
		local tier = slime:GetAttribute("Tier")
		tier = if type(tier) == "number" then tier else 1
		local lucky = slime:GetAttribute(Constants.HATCH_LUCKY_ATTRIBUTE) == true
		-- The egg went in the same moment the slime came (or this client never saw the egg's show): burst here.
		if not burstDone[id] then
			for egg, show in eggShows do
				if show.id == id then
					burstOf(show)
					eggShows[egg] = nil
				end
			end
			if not burstDone[id] then
				table.insert(bursts, startBurst(slime:GetPivot(), tier, Color3.fromRGB(255, 240, 205), folder))
				burstDone[id] = { at = os.clock(), tier = tier, lucky = lucky }
			end
		end
		local owner = player ~= nil and slime:GetAttribute("OwnerUserId") == player.UserId
		pops[slime] = startPop(slime, tier, lucky, owner, folder)
	end

	local function added(instance: Instance)
		if not instance:IsA("Model") or watched[instance] then
			return
		end
		local model = instance :: Model
		local isEgg = model:GetAttribute(Constants.EGG_KIND_ATTRIBUTE) ~= nil
		-- HatchedAt can arrive on an egg already on the pad (the owner just hatched it).
		watched[model] = model:GetAttributeChangedSignal(Constants.HATCHED_AT_ATTRIBUTE):Connect(function()
			if isEgg then
				tryEgg(model)
			else
				trySlime(model)
			end
		end)
		if isEgg then
			tryEgg(model)
		elseif model.PrimaryPart or model:FindFirstChild("Body") then
			trySlime(model)
		else
			task.spawn(function()
				if model:WaitForChild("Body", 5) then
					trySlime(model)
				end
			end)
		end
	end

	local function removed(instance: Instance)
		local conn = watched[instance]
		if conn then
			conn:Disconnect()
			watched[instance] = nil
		end
		local show = eggShows[instance :: Model]
		if show then
			-- The server swapped the egg for the slime: the burst plays now.
			eggShows[instance :: Model] = nil
			burstOf(show)
		end
		local pop = pops[instance :: Model]
		if pop then
			finishPop(pop)
		end
	end

	table.insert(conns, CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(added))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(removed))
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		added(model)
	end

	local function tick(camera: Camera?)
		local now = workspace:GetServerTimeNow()
		local zoom = 0
		for egg, show in eggShows do
			local t = now - show.hatchedAt
			if t >= Timeline.BURST then
				eggShows[egg] = nil
				burstOf(show)
			else
				stepEgg(show, t)
			end
			if show.owner then
				zoom = math.max(zoom, Timeline.zoom(t))
			end
		end
		for i = #bursts, 1, -1 do
			if not stepBurst(bursts[i]) then
				table.remove(bursts, i)
			end
		end
		for slime, pop in pops do
			if not stepPop(pop) then
				pops[slime] = nil
			end
			local hatchedAt = slime:GetAttribute(Constants.HATCHED_AT_ATTRIBUTE)
			if player and slime:GetAttribute("OwnerUserId") == player.UserId and type(hatchedAt) == "number" then
				zoom = math.max(zoom, Timeline.zoom(now - hatchedAt))
			end
		end
		for id, b in burstDone do
			if os.clock() - b.at > 30 then
				burstDone[id] = nil
			end
		end
		if camera then
			if zoom > 0 then
				fov = fov or camera.FieldOfView
				camera.FieldOfView = (fov :: number) - zoom
			elseif fov then
				camera.FieldOfView = fov
				fov = nil
			end
		end
	end

	return {
		tick = tick,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			for _, c in watched do
				c:Disconnect()
			end
			for _, show in eggShows do
				if show.original.Parent then
					setHidden(show.original, false)
				end
			end
			for _, pop in pops do
				finishPop(pop)
			end
			local camera = workspace.CurrentCamera
			if fov and camera then
				camera.FieldOfView = fov
			end
			folder:Destroy()
		end,
	}
end

return EggHatchFx
