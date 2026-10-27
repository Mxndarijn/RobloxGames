--!strict
--[[
	LuckyFx (client only, contract/lucky-charm.md)

	The Lucky Charm show on the pad, for every viewer near it, from Visuals.LuckyTimeline:
	  * Glow: while the server still shows the slime as it was caught (LuckyAt less than MORPH old), a gold
	    highlight pulses on it and clover sparkles rise.
	  * Burst: when the promoted slime's model arrives (the server rebuilt it as the new species), a gold flash, a
	    ring and a puff of sparkles; the highlight turns from gold to the new rarity colour and fades.
	  * Title: "🍀 LUCKY!" over "Legendary → Mythic" floats up above the pad and fades: a small sign in the world
	    (walls hide it, near only), for someone else's slime only from Epic up, like the hatch title.
	Everything it makes is local (never replicates) and decides nothing.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Timeline = require(ReplicatedStorage.Visuals.LuckyTimeline)

local LuckyFx = {}

LuckyFx.MAX_DISTANCE = 150 -- studs: a viewer further away sees no show
LuckyFx.FOLDER = "LuckyFx"

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local GOLD = rgb(Timeline.GOLD)
local CLOVER = rgb(Timeline.CLOVER)

local function rarityColor(tier: number): Color3
	return rgb(Config.RARITIES[math.clamp(tier, 1, Config.MAX_TIER)].color)
end

local function localPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Archivable = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function sparkles(parent: Instance, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK_TEXTURE
	e.Color = ColorSequence.new(GOLD, CLOVER)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(3, 7)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 4, 0)
	e.Rate = rate
	e.Parent = parent
	return e
end

local function highlight(model: Model, folder: Instance): Highlight
	local h = Instance.new("Highlight")
	h.Adornee = model
	h.FillColor = GOLD
	h.OutlineColor = GOLD
	h.FillTransparency = 1
	h.OutlineTransparency = 0.2
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Archivable = false
	h.Parent = folder
	return h
end

type Glow = { model: Model, at: number, holder: Folder, light: Highlight }

type Burst = {
	model: Model,
	startedAt: number, -- os.clock()
	pivot: Vector3,
	tier: number,
	holder: Folder,
	light: Highlight,
	ring: Part,
	flash: PointLight,
	title: Part?, -- nil when this viewer gets no title (LuckyTimeline.showsTitle)
	labels: { TextLabel },
	strokes: { UIStroke },
}

local function startGlow(model: Model, at: number, folder: Folder): Glow
	local holder = Instance.new("Folder")
	holder.Name = "Glow"
	holder.Archivable = false
	holder.Parent = folder
	local anchor = localPart({ CFrame = model:GetPivot() })
	anchor.Parent = holder
	sparkles(anchor, 12)
	return { model = model, at = at, holder = holder, light = highlight(model, holder) }
end

local function textLabel(
	gui: Instance,
	text: string,
	y: number,
	height: number,
	color: Color3,
	rich: boolean
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, y)
	label.Size = UDim2.fromScale(1, height)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = rich
	label.Text = text
	label.TextColor3 = color
	label.Parent = gui
	return label
end

local function startBurst(model: Model, fromTier: number, tier: number, owner: boolean, folder: Folder): Burst
	local holder = Instance.new("Folder")
	holder.Name = "Burst"
	holder.Archivable = false
	holder.Parent = folder
	local pivot = model:GetPivot().Position
	local center = localPart({ CFrame = CFrame.new(pivot) })
	center.Parent = holder
	sparkles(center, 0):Emit(Timeline.SPARKS)
	local flash = Instance.new("PointLight")
	flash.Color = GOLD
	flash.Range = 18
	flash.Brightness = 0
	flash.Parent = center
	local ring = localPart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 2, 2),
		Color = GOLD,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		CFrame = CFrame.new(pivot + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	ring.Parent = holder
	-- The title is a small sign in the world (walls hide it, near only), like the hatch title.
	local title: Part? = nil
	local labels, strokes = {}, {}
	if Timeline.showsTitle(owner, tier) then
		local anchor = localPart({ Name = "Title", CFrame = CFrame.new(pivot + Vector3.new(0, 5, 0)) })
		anchor.Parent = holder
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(Timeline.TITLE_STUDS[1], Timeline.TITLE_STUDS[2])
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.MaxDistance = Timeline.TITLE_DISTANCE
		gui.Parent = anchor
		local top, step = Timeline.title(fromTier, tier)
		labels = {
			textLabel(gui, top, 0, 0.55, GOLD, false),
			textLabel(gui, step, 0.55, 0.45, Color3.new(1, 1, 1), true),
		}
		for _, label in labels do
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = Color3.fromRGB(20, 14, 30)
			stroke.Parent = label
			table.insert(strokes, stroke)
		end
		title = anchor
	end
	return {
		model = model,
		startedAt = os.clock(),
		pivot = pivot,
		tier = tier,
		holder = holder,
		light = highlight(model, holder),
		ring = ring,
		flash = flash,
		title = title,
		labels = labels,
		strokes = strokes,
	}
end

-- Returns false once the burst and its title are over.
local function stepBurst(b: Burst): boolean
	local s = os.clock() - b.startedAt
	local look = Timeline.burst(s)
	if look then
		b.ring.Size = Vector3.new(0.2, look.ring, look.ring)
		b.ring.Transparency = look.ringFade
		b.flash.Brightness = look.light
		local color = GOLD:Lerp(rarityColor(b.tier), look.mix)
		b.light.FillColor = color
		b.light.OutlineColor = color
		b.light.FillTransparency = look.fill
		b.light.OutlineTransparency = 0.2 + 0.8 * s / Timeline.BURST_SECONDS
	else
		b.ring.Transparency = 1
		b.flash.Brightness = 0
		b.light.Enabled = false
	end
	local rise, fade = Timeline.titleLook(s)
	if not rise then
		b.holder:Destroy()
		return false
	end
	if b.title then
		b.title.CFrame = CFrame.new(b.pivot + Vector3.new(0, 5 + rise, 0))
	end
	for _, label in b.labels do
		label.TextTransparency = fade or 1
	end
	for _, stroke in b.strokes do
		stroke.Transparency = fade or 1
	end
	return true
end

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

-- Starts watching for Lucky Charm shows. Call `tick` once a frame from the client's frame loop.
function LuckyFx.start(): Controller
	local folder = Instance.new("Folder")
	folder.Name = LuckyFx.FOLDER
	folder.Archivable = false
	folder.Parent = workspace
	local player = Players.LocalPlayer
	local glows: { [Model]: Glow } = {}
	local bursts: { [Model]: Burst } = {}
	local burstDone: { [string]: number } = {} -- slime id -> os.clock() of its burst
	local watched: { [Instance]: RBXScriptConnection } = {}
	local conns: { RBXScriptConnection } = {}

	local function near(model: Model): boolean
		local camera = workspace.CurrentCamera
		return camera == nil or (camera.CFrame.Position - model:GetPivot().Position).Magnitude <= LuckyFx.MAX_DISTANCE
	end

	local function try(model: Model)
		if glows[model] or bursts[model] then
			return
		end
		local at = model:GetAttribute(Constants.LUCKY_AT_ATTRIBUTE)
		local id = model:GetAttribute("SlimeId")
		if type(at) ~= "number" or type(id) ~= "string" or burstDone[id] or not near(model) then
			return
		end
		local phase = Timeline.phase(workspace:GetServerTimeNow() - at)
		if phase == "glow" then
			glows[model] = startGlow(model, at, folder)
		elseif phase == "burst" then
			local from = model:GetAttribute(Constants.LUCKY_FROM_TIER_ATTRIBUTE)
			local tier = model:GetAttribute("Tier")
			tier = if type(tier) == "number" then tier else 1
			burstDone[id] = os.clock()
			local owner = player ~= nil and model:GetAttribute("OwnerUserId") == player.UserId
			bursts[model] = startBurst(model, if type(from) == "number" then from else tier - 1, tier, owner, folder)
		end
	end

	local function dropGlow(model: Model)
		local glow = glows[model]
		if glow then
			glow.holder:Destroy()
			glows[model] = nil
		end
	end

	local function added(instance: Instance)
		if not instance:IsA("Model") or watched[instance] then
			return
		end
		local model = instance :: Model
		watched[model] = model:GetAttributeChangedSignal(Constants.LUCKY_AT_ATTRIBUTE):Connect(function()
			try(model)
		end)
		if model.PrimaryPart or model:FindFirstChild("Body") then
			try(model)
		else
			task.spawn(function()
				if model:WaitForChild("Body", 5) then
					try(model)
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
		-- The caught model goes when the server rebuilds it as the new species: its glow ends here.
		dropGlow(instance :: Model)
		local burst = bursts[instance :: Model]
		if burst then
			burst.light.Enabled = false
		end
	end

	table.insert(conns, CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(added))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(removed))
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		added(model)
	end

	local function tick(_camera: Camera?)
		local now = workspace:GetServerTimeNow()
		for model, glow in glows do
			local t = now - glow.at
			if not model.Parent then
				dropGlow(model)
			elseif t >= Timeline.MORPH + Timeline.REBUILD_WAIT then
				-- No rebuild came (a slime without a species keeps its model): it bursts as it is.
				dropGlow(model)
				try(model)
			else
				glow.light.FillTransparency = Timeline.glow(t)
			end
		end
		for model, burst in bursts do
			if not stepBurst(burst) then
				bursts[model] = nil
			end
		end
		local clock = os.clock()
		for id, at in burstDone do
			if clock - at > 30 then
				burstDone[id] = nil
			end
		end
	end

	local function stop()
		for _, conn in conns do
			conn:Disconnect()
		end
		for _, conn in watched do
			conn:Disconnect()
		end
		table.clear(watched)
		table.clear(glows)
		table.clear(bursts)
		folder:Destroy()
	end

	return { tick = tick, stop = stop }
end

return LuckyFx
