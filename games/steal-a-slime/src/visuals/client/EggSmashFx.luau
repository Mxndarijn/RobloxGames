--!strict
--[[
	EggSmashFx (client only, contract/mystery-egg.md 40.7)

	A wild Mystery Egg that was dropped smashes on the ground, for every viewer
	near it. The server marks the egg model with EggSmashedAt and keeps it for
	MYSTERY_EGG.SMASH_SECONDS; this hides the real egg locally and plays the
	show on a local copy, with the numbers from Visuals.EggSmashTimeline:
	  * fall: the copy drops from where the carrier held it to the ground with
	    gravity, tipping forward;
	  * squash: it flattens on impact;
	  * burst: the copy is gone; shell shards fly out, bounce and fade, a goo
	    splat in the kind's glow colour spreads, a jagged ring of shell stays a
	    moment, a dust ring rolls out, sparks, a flash and a crack sound.
	Everything it makes is local (never replicates) and decides nothing.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local EggModel = require(ReplicatedStorage.Visuals.EggModel)
local LocalCopy = require(script.Parent.LocalCopy)
local Timeline = require(ReplicatedStorage.Visuals.EggSmashTimeline)

local EggSmashFx = {}

EggSmashFx.MAX_DISTANCE = 160 -- studs: a viewer further away sees no show
EggSmashFx.FOLDER = "EggSmashFx"
EggSmashFx.SOUND_ID = "rbxassetid://9113959343" -- Pro Sound Effects "Crack Egg Crunchy 11" (1.1 s)
EggSmashFx.SOUND_VOLUME = 0.6

local DUST = Color3.fromRGB(235, 225, 205)
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type Piece = { part: BasePart, rel: CFrame, size: Vector3 }

type Show = {
	startedAt: number, -- os.clock()
	folder: Folder,
	copy: Model?,
	pieces: { Piece },
	from: CFrame, -- where the copy starts, at its bottom centre
	ground: Vector3, -- impact point on the ground
	drop: number,
	fallSeconds: number,
	shell: Color3,
	accent: Color3,
	goo: Color3,
	burst: boolean,
	shards: { BasePart },
	crown: { { part: BasePart, at: CFrame } },
	splat: BasePart?,
	ring: BasePart?,
	flash: PointLight?,
}

local function localPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Archivable = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- The ground under `from`: the first solid, queryable part that is not a character, a slime or our own FX.
local function groundBelow(from: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = false
	local result = workspace:Raycast(from + Vector3.new(0, 1, 0), Vector3.new(0, -60, 0), params)
	return if result then result.Position else from - Vector3.new(0, 3, 0)
end

local function ignoreList(folder: Folder): { Instance }
	local list: { Instance } = { folder }
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		table.insert(list, model)
	end
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

-- The splat in the kind's glow colour, saturated so it shows on snow and pale paths.
local function gooColor(glow: Color3): Color3
	local h, s, v = glow:ToHSV()
	return Color3.fromHSV(h, math.max(s, 0.65), v)
end

local function playSound(at: Vector3, folder: Folder)
	if EggSmashFx.SOUND_ID == "rbxassetid://0" then
		return
	end
	local holder = localPart({ Name = "Sound", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(at) })
	holder.Parent = folder
	local sound = Instance.new("Sound")
	sound.SoundId = EggSmashFx.SOUND_ID
	sound.Volume = EggSmashFx.SOUND_VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 90
	local sfx = SoundService:FindFirstChild("SFX")
	sound.SoundGroup = if sfx and sfx:IsA("SoundGroup") then sfx else nil
	sound.Parent = holder
	pcall(sound.Play, sound)
	task.delay(3, function()
		holder:Destroy()
	end)
end

-- Places every piece of the copy at `frame` (its bottom centre), scaled `wide` x `tall` around that point.
local function poseCopy(show: Show, frame: CFrame, wide: number, tall: number)
	local scale = Vector3.new(wide, tall, wide)
	for _, piece in show.pieces do
		piece.part.CFrame = frame * CFrame.new(piece.rel.Position * scale) * piece.rel.Rotation
		piece.part.Size = piece.size * scale
	end
end

local function startShow(model: Model, root: Folder): Show?
	local copy = LocalCopy.copyOf(model)
	if not copy then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Smash"
	folder.Archivable = false
	folder.Parent = root
	local pivot = model:GetPivot()
	local ground = groundBelow(pivot.Position, ignoreList(root))
	local drop = math.max(pivot.Position.Y - ground.Y, Timeline.MIN_DROP)
	local from = CFrame.new(ground.X, ground.Y, ground.Z) * pivot.Rotation
	local pieces: { Piece } = {}
	for _, d in copy:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Weld") then
			d:Destroy() -- every piece is posed on its own
		end
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(pieces, { part = d, rel = pivot:ToObjectSpace(d.CFrame), size = d.Size })
		end
	end
	local kind = model:GetAttribute(Constants.EGG_KIND_ATTRIBUTE)
	local shell, accent = EggModel.colors(if type(kind) == "string" then kind else "speckled")
	copy.Parent = folder
	LocalCopy.setHidden(model, true)
	local show: Show = {
		startedAt = os.clock(),
		folder = folder,
		copy = copy,
		pieces = pieces,
		from = from,
		ground = ground,
		drop = drop,
		fallSeconds = Timeline.fallSeconds(drop),
		shell = shell,
		accent = accent,
		goo = gooColor(if type(kind) == "string" then EggModel.glowColor(kind) else accent),
		burst = false,
		shards = {},
		crown = {},
	}
	poseCopy(show, from + Vector3.new(0, drop, 0), 1, 1)
	return show
end

local function startBurst(show: Show)
	show.burst = true
	if show.copy then
		show.copy:Destroy()
		show.copy = nil
	end
	local at = show.ground
	local folder = show.folder
	for i = 1, Timeline.SHARDS do
		local big = i % 3 == 0
		local shard = localPart({
			Name = `Shard{i}`,
			Shape = Enum.PartType.Block,
			Size = if big then Vector3.new(0.9, 0.7, 0.14) else Vector3.new(0.6, 0.45, 0.12),
			Color = if i % 3 == 1 then show.accent else show.shell,
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(at),
		})
		if i % 2 == 0 then
			local wedge = Instance.new("WedgePart")
			wedge.Anchored, wedge.CanCollide, wedge.CanTouch, wedge.CanQuery = true, false, false, false
			wedge.CastShadow, wedge.Archivable = false, false
			wedge.Size, wedge.Color, wedge.Material = shard.Size, shard.Color, shard.Material
			wedge.Name = shard.Name
			shard:Destroy()
			wedge.Parent = folder
			table.insert(show.shards, wedge)
		else
			shard.Parent = folder
			table.insert(show.shards, shard)
		end
	end
	-- The broken bottom of the shell: jagged pieces standing in a ring, tipped outwards.
	for i = 1, Timeline.CROWN do
		local a = (i / Timeline.CROWN) * math.pi * 2
		local r = EggModel.WIDTH * 0.42
		local h = 0.55 + 0.35 * ((i * 7) % 3) / 2
		local piece = Instance.new("WedgePart")
		piece.Name = `Crown{i}`
		piece.Anchored, piece.CanCollide, piece.CanTouch, piece.CanQuery = true, false, false, false
		piece.CastShadow, piece.Archivable = false, false
		piece.Size = Vector3.new(0.15, h, 0.9)
		piece.Color = show.shell
		piece.Material = Enum.Material.SmoothPlastic
		local cf = CFrame.new(at + Vector3.new(math.cos(a) * r, h / 2 - 0.05, math.sin(a) * r))
			* CFrame.Angles(0, -a, 0)
			* CFrame.Angles(0, 0, math.rad(-18))
		piece.CFrame = cf
		piece.Parent = folder
		table.insert(show.crown, { part = piece, at = cf })
	end
	local splat = localPart({
		Name = "Splat",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 0.2, 0.2),
		Color = show.goo,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
		Transparency = 0.1,
		CFrame = CFrame.new(at + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	splat.Parent = folder
	show.splat = splat
	local ring = localPart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 1.5, 1.5),
		Color = DUST,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35,
		CFrame = CFrame.new(at + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	ring.Parent = folder
	show.ring = ring
	local core = localPart({
		Name = "Core",
		Size = Vector3.one * 0.2,
		Transparency = 1,
		CFrame = CFrame.new(at + Vector3.new(0, 0.8, 0)),
	})
	core.Parent = folder
	local flash = Instance.new("PointLight")
	flash.Color = show.goo
	flash.Range = 14
	flash.Brightness = 4
	flash.Shadows = false
	flash.Parent = core
	show.flash = flash
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(show.goo, Color3.new(1, 1, 1))
	sparks.LightEmission = 0.8
	sparks.Texture = SPARK_TEXTURE
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Speed = NumberRange.new(10, 20)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Rate = 0
	sparks.Parent = core
	sparks:Emit(28)
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(DUST)
	dust.Texture = SMOKE_TEXTURE
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Speed = NumberRange.new(6, 11)
	dust.SpreadAngle = Vector2.new(85, 10)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Drag = 4
	dust.Rate = 0
	dust.Parent = core
	dust:Emit(14)
	playSound(at, folder)
end

-- Returns false once the show is over (its folder is gone).
local function stepShow(show: Show): boolean
	local s = os.clock() - show.startedAt
	local fallEnd = show.fallSeconds
	local squashEnd = fallEnd + Timeline.SQUASH_SECONDS
	if s < fallEnd then
		local height, tip = Timeline.fall(s, show.drop)
		poseCopy(show, (show.from + Vector3.new(0, height, 0)) * CFrame.Angles(tip, 0, tip * 0.35), 1, 1)
		return true
	elseif s < squashEnd then
		local wide, tall = Timeline.squash(s - fallEnd)
		local _, tip = Timeline.fall(fallEnd, show.drop)
		poseCopy(show, show.from * CFrame.Angles(tip * 0.3, 0, 0), wide, tall)
		return true
	end
	if not show.burst then
		startBurst(show)
	end
	local b = s - squashEnd
	if b >= Timeline.SHARD_SECONDS then
		show.folder:Destroy()
		return false
	end
	local at = show.ground
	for i, shard in show.shards do
		local x, y, z, spin, fade = Timeline.shard(i, #show.shards, b)
		shard.CFrame = CFrame.new(at + Vector3.new(x, y + shard.Size.Y / 2, z)) * CFrame.Angles(spin, spin * 0.6, 0)
		shard.Transparency = fade
	end
	local sink, fade = Timeline.crown(b)
	for _, piece in show.crown do
		piece.part.CFrame = piece.at - Vector3.new(0, sink * piece.part.Size.Y, 0)
		piece.part.Transparency = fade
	end
	local splat = show.splat
	if splat then
		local size, t = Timeline.splat(b)
		splat.Size = Vector3.new(0.12, math.max(size, 0.2), math.max(size, 0.2))
		splat.Transparency = t
	end
	local ring = show.ring
	if ring then
		local size, t = Timeline.ring(b)
		ring.Size = Vector3.new(0.1, size, size)
		ring.Transparency = t
	end
	local flash = show.flash
	if flash then
		flash.Brightness = math.max(0, 4 * (1 - b / 0.3))
	end
	return true
end

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

-- Starts watching for smashed eggs. Call `tick` once a frame from the client's frame loop.
function EggSmashFx.start(): Controller
	local folder = Instance.new("Folder")
	folder.Name = EggSmashFx.FOLDER
	folder.Archivable = false
	folder.Parent = workspace
	local shows: { Show } = {}
	local played: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local watched: { [Instance]: RBXScriptConnection } = {}
	local conns: { RBXScriptConnection } = {}

	local function check(model: Model)
		local at = model:GetAttribute(Constants.EGG_SMASHED_AT_ATTRIBUTE)
		if type(at) ~= "number" or played[model] then
			return
		end
		played[model] = true
		if workspace:GetServerTimeNow() - at > Timeline.LATE_SECONDS then
			LocalCopy.setHidden(model, true) -- too late for the show: just don't show the broken egg
			return
		end
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - model:GetPivot().Position).Magnitude > EggSmashFx.MAX_DISTANCE then
			LocalCopy.setHidden(model, true)
			return
		end
		local show = startShow(model, folder)
		if show then
			table.insert(shows, show)
		end
	end

	local function watch(inst: Instance)
		if not inst:IsA("Model") or watched[inst] or inst:GetAttribute(Constants.EGG_KIND_ATTRIBUTE) == nil then
			return
		end
		local model = inst :: Model
		watched[model] = model:GetAttributeChangedSignal(Constants.EGG_SMASHED_AT_ATTRIBUTE):Connect(function()
			check(model)
		end)
		check(model)
	end

	table.insert(conns, CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(watch))
	table.insert(
		conns,
		CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(function(inst)
			local conn = watched[inst]
			if conn then
				conn:Disconnect()
				watched[inst] = nil
			end
		end)
	)
	for _, inst in CollectionService:GetTagged(Constants.SLIME_TAG) do
		watch(inst)
	end

	return {
		tick = function(_camera: Camera?)
			for i = #shows, 1, -1 do
				local ok, alive = pcall(stepShow, shows[i])
				if not ok or not alive then
					if not ok then
						pcall(function()
							shows[i].folder:Destroy()
						end)
					end
					table.remove(shows, i)
				end
			end
		end,
		stop = function()
			for _, conn in conns do
				conn:Disconnect()
			end
			for _, conn in watched do
				conn:Disconnect()
			end
			table.clear(watched)
			table.clear(shows)
			folder:Destroy()
		end,
	}
end

return EggSmashFx
