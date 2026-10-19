--!strict
--[[
	PvpFunFx (client, FEATURES.PvP, CONTRACT.md §26.8): the look and sound of the Fun items.

	ui/PvpEffects hands over every PvpEvent whose itemId is a Fun item (`handles`): Effect payloads and the Bounce
	Pad's TrapPlaced / TrapCleared. Everything here is built from Roblox built-ins (Parts, ParticleEmitter, Highlight,
	PointLight, Sound, BillboardGui; rbxasset:// textures), lives in one client-only folder and is gone after its
	lifetime: effects are counted (`activeCount()`, 0 when idle) and at most PVP_FUN.FX_MAX play at once (the oldest
	ends early). Motion is tweens and client-only physics (lobbed balloons and bombs); there is no frame loop here.
	`tick(now)` runs on the client's 10 Hz loop and checks bubbles / pads against wild slimes.

	Squashes and floats of slimes and of a pancaked player use a proxy: a stripped, anchored clone of the model that
	is tweened instead of the original, while the original is hidden through LocalTransparencyModifier. The slime
	models, their life rigs and VisualsClient are never touched; at most PVP_FUN.PROXIES_MAX proxies exist at once.

	Use poses come from the ui/PvpAnim handle (`pop`, `blow`, `bonk`, `throw`, `blast` for another player's use; the
	local player's own use already played on the click), `dance` / `flip` / `hit` on the affected player.

	PvpFunFx.start(opts) -> Handle { handles, play, tick, activeCount, proxyCount, padCount, stop }
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local PvpFunRules = require(Shared:WaitForChild("PvpFunRules"))

local Logic = require(script.Parent.PvpFunFxLogic)
local PvpEffects = require(script.Parent.PvpEffects)

local FUN = Config.PVP_FUN
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local FOLDER_NAME = "PvpFunFx"

-- Sizes and colours of the props (studs, 0..1 colours); text pop-ups.
local LOOK = table.freeze({
	balloon = 1.7,
	bomb = 1.4,
	hatBrim = 1.8,
	hatCrown = 1.25,
	hatStack = 0.85, -- studs between stacked hats
	hatSlimeBody = 1.6,
	rocket = Vector3.new(0.45, 1.6, 0.45),
	padHeight = 1.1,
	padLegs = 4,
	discoBall = 1.5,
	discoHeight = 5,
	splatThickness = 0.12,
	rayDrop = 30, -- studs searched below a point for the ground
	bomb_color = { 0.35, 0.2, 0.5 },
	pad_frame = { 1, 0.4, 0.75 },
	pad_skin = { 0.2, 0.25, 0.45 },
	hat_colors = { { 0.45, 0.9, 0.4 }, { 1, 0.5, 0.75 }, { 0.4, 0.75, 1 }, { 1, 0.8, 0.25 }, { 0.75, 0.5, 1 } },
	text_size = UDim2.fromOffset(220, 60),
	text_rise = 3, -- studs a text pop-up floats up
	text_seconds = 0.9,
	text_color = { 1, 0.95, 0.4 },
	text_stroke = { 0.35, 0.15, 0.45 },
})

local PvpFunFx = {}

export type Options = {
	anim: any?, -- the ui/PvpAnim handle (nil = no poses)
	serverNow: () -> number, -- server time (the events' clock)
}
export type Handle = {
	handles: (payload: any) -> boolean,
	play: (payload: any) -> (),
	tick: (now: number) -> (),
	activeCount: () -> number,
	proxyCount: () -> number,
	padCount: () -> number,
	stop: () -> (),
}

type Record = { parts: { Instance }, done: boolean, cleanup: { () -> () } }
type Worn = { models: { Model }, untilAt: number, head: BasePart }
type Proxy = {
	model: Model,
	clone: Model,
	basis: CFrame,
	pieces: { { part: BasePart, rel: CFrame, size: Vector3, mesh: SpecialMesh?, meshScale: Vector3? } },
	hidden: { [Instance]: number },
	tweens: { Tween },
	released: boolean,
}

local function rgb(c: { number }): Color3
	return Color3.new(c[1], c[2], c[3])
end

local function vector(v: any): Vector3?
	local p = PvpFunRules.vec(v)
	return if p then Vector3.new(p.X, p.Y, p.Z) else nil
end

local function characterOf(userId: any): Model?
	local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	return player and player.Character
end

local function partOf(character: Model?, names: { string }): BasePart?
	if not character then
		return nil
	end
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function rootOf(character: Model?): BasePart?
	return partOf(character, { "HumanoidRootPart" })
end

local function handOf(character: Model?): BasePart?
	return partOf(character, { "RightHand", "Right Arm", "HumanoidRootPart" })
end

local function colorSequence(colors: { { number } }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(rgb(colors[1]))
	end
	local points = {}
	for i, c in colors do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), rgb(c)))
	end
	return ColorSequence.new(points)
end

type EmitSpec = {
	count: number,
	colors: { { number } },
	texture: string?,
	speed: { number },
	size: number,
	lifetime: { number },
	gravity: number?, -- downward acceleration (negative floats up)
	drag: number?,
	spread: number?, -- degrees (180 = all round)
	spin: number?, -- degrees/s
	light: number?,
	locked: boolean?,
	rate: number?, -- particles/s instead of one burst
}

function PvpFunFx.start(opts: Options): Handle
	local anim = opts.anim
	local localPlayer = Players.LocalPlayer
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	local effects = Logic.queue(FUN.FX_MAX) :: Logic.Queue<Record>
	local splats = Logic.queue(FUN.BALLOON.SPLATS_MAX) :: Logic.Queue<Record>
	local hatSlimes = Logic.queue(FUN.HATS.SLIMES_MAX) :: Logic.Queue<Record>
	local proxies: { [Model]: Proxy } = {}
	local proxyTotal = 0
	local pancakes: { [number]: { proxy: Proxy, combo: boolean } } = {}
	local streams: { [string]: { stream: PvpFunRules.Stream, bubbles: { [number]: BasePart } } } = {}
	local pads: { [string]: { model: Model, skin: BasePart, position: Vector3 } } = {}
	local padTotal = 0
	local hats: { [number]: Worn } = {}
	local paints: { [Model]: { highlight: Highlight, untilAt: number } } = {}
	local stopped = false

	local function lowQuality(): boolean
		return PvpEffects.lowQuality()
	end

	-- A record lives `seconds`, or until the queue evicts it. Its instances and cleanups go when it ends.
	local function finish(record: Record)
		if record.done then
			return
		end
		record.done = true
		effects.remove(record)
		splats.remove(record)
		hatSlimes.remove(record)
		for _, fn in record.cleanup do
			pcall(fn)
		end
		for _, instance in record.parts do
			instance:Destroy()
		end
	end

	local function newRecord(seconds: number, queue: Logic.Queue<Record>?): Record
		local record: Record = { parts = {}, done = false, cleanup = {} }
		local evicted = (queue or effects).push(record)
		if evicted then
			finish(evicted)
		end
		task.delay(seconds, finish, record)
		return record
	end

	local function own(record: Record, instance: Instance): any
		table.insert(record.parts, instance)
		return instance
	end

	local function part(record: Record?, props: { [string]: any }): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for key, value in props do
			(p :: any)[key] = value
		end
		if record then
			own(record, p)
		end
		if not props.Parent then
			p.Parent = folder
		end
		return p
	end

	-- An Attachment at a world point (under Terrain: no BasePart).
	local function anchorAt(record: Record, position: Vector3): Attachment
		local a = Instance.new("Attachment")
		a.Parent = workspace.Terrain
		a.WorldPosition = position
		return own(record, a)
	end

	local function emit(record: Record?, parent: Instance, spec: EmitSpec): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Texture = spec.texture or SPARK
		e.Color = colorSequence(spec.colors)
		e.LightEmission = spec.light or 0.3
		e.Lifetime = NumberRange.new(spec.lifetime[1], spec.lifetime[2])
		e.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
		e.SpreadAngle = Vector2.new(spec.spread or 180, spec.spread or 180)
		e.Acceleration = Vector3.new(0, -(spec.gravity or 0), 0)
		e.Drag = spec.drag or 0
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-(spec.spin or 0), spec.spin or 0)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, spec.size),
			NumberSequenceKeypoint.new(0.8, spec.size * 0.9),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.85, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.LockedToPart = spec.locked == true
		e.Rate = spec.rate or 0
		e.Parent = parent
		if record then
			own(record, e)
		end
		if not spec.rate then
			e:Emit(Logic.count(spec.count, lowQuality()))
		end
		return e
	end

	-- Confetti in several colours (one emitter per colour: a ParticleEmitter has one colour per lifetime).
	local function confettiAt(record: Record, parent: Instance, total: number, spec: EmitSpec)
		local colors = Logic.CONFETTI_COLORS
		for _, c in colors do
			local one = table.clone(spec)
			one.colors = { c }
			one.count = math.max(1, total // #colors)
			emit(record, parent, one)
		end
	end

	local function sound(name: string, parent: Instance?, involved: boolean, pitch: number?, volume: number?)
		if pitch == nil and volume == nil then
			PvpEffects.playSound(name, parent, involved, nil)
			return
		end
		PvpEffects.playSound(name, parent, false, { pitch = pitch, volume = volume })
	end

	local function light(
		record: Record,
		parent: Instance,
		color: Color3,
		range: number,
		brightness: number,
		fade: number?
	)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Parent = parent
		own(record, l)
		if fade then
			TweenService
				:Create(l, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 0 })
				:Play()
		end
		return l
	end

	-- A floating word ("SQUEAK!", "BOING!") that rises and fades.
	local function popText(record: Record, position: Vector3, text: string, scale: number)
		local holder = anchorAt(record, position + Vector3.new(0, 2.5, 0))
		local gui = Instance.new("BillboardGui")
		gui.Size =
			UDim2.new(LOOK.text_size.X.Scale, LOOK.text_size.X.Offset * scale, 0, LOOK.text_size.Y.Offset * scale)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = FUN.FX_RANGE
		gui.Adornee = holder
		gui.Parent = holder
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = rgb(LOOK.text_color)
		label.TextStrokeColor3 = rgb(LOOK.text_stroke)
		label.TextStrokeTransparency = 0
		label.Parent = gui
		local info = TweenInfo.new(LOOK.text_seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, LOOK.text_rise, 0) }):Play()
		TweenService:Create(
			label,
			TweenInfo.new(LOOK.text_seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		):Play()
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	-- The ground under `position` (characters, slimes and our own props ignored), else `position` itself.
	local function groundAt(position: Vector3): Vector3
		local ignore: { Instance } = { folder }
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		for _, slime in CollectionService:GetTagged(Constants.SLIME_TAG) do
			table.insert(ignore, slime)
		end
		rayParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -LOOK.rayDrop, 0), rayParams)
		return if hit then hit.Position else position
	end

	local function inRange(position: Vector3): boolean
		local camera = workspace.CurrentCamera
		return camera == nil or (camera.CFrame.Position - position).Magnitude <= FUN.FX_RANGE
	end

	local function playAnim(userId: any, kind: string?)
		if anim and kind and type(userId) == "number" then
			anim.play(userId, kind)
		end
	end

	---------------------------------------------------------------------------
	-- Proxies: an anchored clone that is squashed / floated while the original is hidden.
	---------------------------------------------------------------------------

	local function hideOriginal(model: Model): { [Instance]: number }
		local hidden: { [Instance]: number } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				hidden[d] = (d :: any).LocalTransparencyModifier;
				(d :: any).LocalTransparencyModifier = 1
			end
		end
		return hidden
	end

	local STRIP = {
		"JointInstance",
		"Constraint",
		"WeldConstraint",
		"LuaSourceContainer",
		"ProximityPrompt",
		"ClickDetector",
		"BillboardGui",
		"Sound",
		"ParticleEmitter",
		"Attachment",
	}
	local function stripped(model: Model): Model?
		local archivable = model.Archivable
		model.Archivable = true
		local ok, clone = pcall(function()
			return model:Clone()
		end)
		model.Archivable = archivable
		if not ok or not clone then
			return nil
		end
		for _, d in clone:GetDescendants() do
			for _, tag in d:GetTags() do
				d:RemoveTag(tag)
			end
			local drop = false
			for _, class in STRIP do
				if d:IsA(class) then
					drop = true
					break
				end
			end
			if drop then
				d:Destroy()
			elseif d:IsA("Humanoid") then
				d.RequiresNeck = false
				d.BreakJointsOnDeath = false
				d.EvaluateStateMachine = false
				d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end
		end
		for _, tag in clone:GetTags() do
			clone:RemoveTag(tag)
		end
		for name in clone:GetAttributes() do
			clone:SetAttribute(name, nil)
		end
		return clone
	end

	-- The upright frame at the bottom centre of `model` (proxy scaling happens about it).
	local function basisOf(model: Model): CFrame
		local box, size = model:GetBoundingBox()
		local pivot = model:GetPivot()
		local look = pivot.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local yaw = if flat.Magnitude > 1e-3 then math.atan2(-flat.X, -flat.Z) else 0
		return CFrame.new(box.Position - Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, yaw, 0)
	end

	local function makeProxy(model: Model): Proxy?
		if proxies[model] or proxyTotal >= FUN.PROXIES_MAX or not model:IsDescendantOf(workspace) then
			return nil
		end
		local clone = stripped(model)
		if not clone then
			return nil
		end
		local basis = basisOf(model)
		local proxy: Proxy = {
			model = model,
			clone = clone,
			basis = basis,
			pieces = {},
			hidden = {},
			tweens = {},
			released = false,
		}
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				local mesh = d:FindFirstChildOfClass("SpecialMesh")
				if d:IsA("Part") and d.Shape ~= Enum.PartType.Block and not mesh then
					-- a Ball / Cylinder keeps its proportions: a SpecialMesh lets it squash
					local m = Instance.new("SpecialMesh")
					m.MeshType = if d.Shape == Enum.PartType.Ball then Enum.MeshType.Sphere else Enum.MeshType.Cylinder
					d.Shape = Enum.PartType.Block
					m.Parent = d
				end
				local fileMesh = if mesh and mesh.MeshType == Enum.MeshType.FileMesh then mesh else nil
				table.insert(proxy.pieces, {
					part = d,
					rel = basis:ToObjectSpace(d.CFrame),
					size = d.Size,
					mesh = fileMesh,
					meshScale = if fileMesh then fileMesh.Scale else nil,
				})
			end
		end
		proxy.hidden = hideOriginal(model)
		clone.Parent = folder
		proxies[model] = proxy
		proxyTotal += 1
		return proxy
	end

	local function releaseProxy(proxy: Proxy)
		if proxy.released then
			return
		end
		proxy.released = true
		for _, tween in proxy.tweens do
			tween:Cancel()
		end
		for instance, value in proxy.hidden do
			if instance.Parent then
				(instance :: any).LocalTransparencyModifier = value
			end
		end
		proxy.clone:Destroy()
		if proxies[proxy.model] == proxy then
			proxies[proxy.model] = nil
			proxyTotal -= 1
		end
	end

	-- Tweens every proxy piece to the pose `key` (scale about the basis, then offset).
	local function poseTo(proxy: Proxy, key: Logic.Key)
		if proxy.released then
			return
		end
		local s, o = key.scale, key.offset
		local info = TweenInfo.new(
			math.max(key.seconds, 0.01),
			(Enum.EasingStyle :: any)[key.style] or Enum.EasingStyle.Quad,
			(Enum.EasingDirection :: any)[key.dir] or Enum.EasingDirection.Out
		)
		table.clear(proxy.tweens)
		local shift = proxy.basis * CFrame.new(o[1], o[2], o[3])
		for _, piece in proxy.pieces do
			local rel = piece.rel
			local p = rel.Position
			local rot = rel - p
			local target = shift * CFrame.new(p.X * s[1], p.Y * s[2], p.Z * s[3]) * rot
			local axes = {
				{ rel.XVector.X, rel.XVector.Y, rel.XVector.Z },
				{ rel.YVector.X, rel.YVector.Y, rel.YVector.Z },
				{ rel.ZVector.X, rel.ZVector.Y, rel.ZVector.Z },
			}
			local f = Logic.axisScale(axes, s)
			local size = piece.size * Vector3.new(f[1], f[2], f[3])
			local tween = TweenService:Create(piece.part, info, { CFrame = target, Size = size })
			tween:Play()
			table.insert(proxy.tweens, tween)
			if piece.mesh and piece.meshScale then
				local mt =
					TweenService:Create(piece.mesh, info, { Scale = piece.meshScale * Vector3.new(f[1], f[2], f[3]) })
				mt:Play()
				table.insert(proxy.tweens, mt)
			end
		end
	end

	-- Plays `keys` on the proxy one after the other; `done` runs after the last one.
	local function playKeys(proxy: Proxy, keys: { Logic.Key }, done: (() -> ())?)
		local i = 0
		local function nextKey()
			i += 1
			if proxy.released or stopped then
				return
			end
			local key = keys[i]
			if not key then
				if done then
					done()
				end
				return
			end
			poseTo(proxy, key)
			task.delay(key.seconds, nextKey)
		end
		nextKey()
	end

	local function slimeById(id: any): Model?
		if type(id) ~= "string" then
			return nil
		end
		for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
			if model:IsA("Model") and model:GetAttribute("SlimeId") == id then
				return model
			end
		end
		return nil
	end

	local function bodyPosition(model: Model): Vector3
		local body = model.PrimaryPart or model:FindFirstChild("Body")
		return if body and body:IsA("BasePart") then body.Position else model:GetPivot().Position
	end

	-- Plays a key list on a slime / character proxy, then puts the original back.
	local function proxyPlay(model: Model?, keys: { Logic.Key }, after: (() -> ())?): boolean
		local proxy = if model then makeProxy(model) else nil
		if not proxy then
			return false
		end
		playKeys(proxy, keys, function()
			releaseProxy(proxy)
			if after then
				after()
			end
		end)
		task.delay(Logic.seconds(keys) + 1, releaseProxy, proxy) -- backstop
		return true
	end

	local function floatSlime(model: Model)
		local proxy = makeProxy(model)
		if not proxy then
			return
		end
		local seconds = FUN.BUBBLES.SLIME_FLOAT_SECONDS
		-- the wild slime keeps walking its lane underneath: land where it will be (measured at the end)
		local keys = Logic.float(FUN.BUBBLES.LIFT * 0.7, seconds, { 0, 0 })
		local i = 0
		local function step()
			i += 1
			if proxy.released or stopped then
				return
			end
			local key = keys[i]
			if not key then
				releaseProxy(proxy)
				return
			end
			if i >= 2 and model.Parent then
				local here = proxy.basis:PointToObjectSpace(basisOf(model).Position)
				key = table.clone(key)
				key.offset = { here.X, key.offset[2], here.Z }
			end
			poseTo(proxy, key)
			task.delay(key.seconds, step)
		end
		step()
		task.delay(seconds + 1.5, releaseProxy, proxy)
	end

	---------------------------------------------------------------------------
	-- Effects
	---------------------------------------------------------------------------

	local function confetti(payload: any)
		local center = vector(payload.position)
		if not center or not inRange(center) then
			return
		end
		local mega = payload.mega == true
		local stick = math.clamp(tonumber(payload.duration) or 0, 0, FUN.CONFETTI.STICK_SECONDS)
		local record = newRecord(4.5)
		local at = anchorAt(record, center)
		local radius = tonumber(payload.radius) or FUN.CONFETTI.RADIUS
		sound("PvpPop", at, payload.attacker == localPlayer.UserId, if mega then 0.75 else 1.1, if mega then 1.4 else 1)
		confettiAt(record, at, if mega then 360 else 200, {
			count = 0,
			colors = {},
			speed = { radius * 0.8, radius * 1.7 },
			size = if mega then 0.9 else 0.7,
			lifetime = { 2.4, 4 },
			gravity = 7,
			drag = 2.2,
			spin = 260,
			light = 0.5,
		})
		-- the pop itself: a bright star burst at the centre
		emit(record, at, {
			count = if mega then 40 else 24,
			colors = { { 1, 1, 0.85 }, { 1, 0.85, 0.3 } },
			speed = { 20, 34 },
			size = if mega then 2.4 else 1.6,
			lifetime = { 0.2, 0.45 },
			drag = 4,
			light = 1,
		})
		light(record, at, Color3.new(1, 0.95, 0.8), radius * 2, if mega then 6 else 3, 0.5)
		for _, userId in (if type(payload.targets) == "table" then payload.targets else {}) :: { any } do
			local torso = partOf(characterOf(userId), { "UpperTorso", "Torso", "Head" })
			if torso then
				local e = emit(record, torso, {
					count = 0,
					colors = Logic.CONFETTI_COLORS,
					speed = { 0.3, 1 },
					size = 0.28,
					lifetime = { 0.6, 1.1 },
					gravity = 3,
					spin = 180,
					locked = true,
					rate = 0,
				})
				task.delay(0.7, function()
					e.Rate = if lowQuality() then 6 else 12
					task.delay(stick, function()
						e.Rate = 0
					end)
				end)
			end
		end
	end

	-- A ball thrown under client physics so it lands at `to` when the server says it does.
	local function lobbed(record: Record, from: Vector3, to: Vector3, landAt: number, props: { [string]: any })
		local flight = math.max(0.15, landAt - opts.serverNow())
		local ball = part(record, props)
		ball.Anchored = false
		ball.Massless = true
		ball.CFrame = CFrame.new(from)
		local v = Logic.ballistic(
			{ X = from.X, Y = from.Y, Z = from.Z },
			{ X = to.X, Y = to.Y, Z = to.Z },
			flight,
			workspace.Gravity
		)
		ball.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z)
		ball.AssemblyAngularVelocity = Vector3.new(4, 7, 2)
		return ball, flight
	end

	local function throwOrigin(payload: any): Vector3?
		local hand = handOf(characterOf(payload.attacker))
		return if hand then hand.Position else vector(payload.origin)
	end

	local function balloon(payload: any)
		local to = vector(payload.position)
		local from = throwOrigin(payload)
		if not to or not from or not inRange(to) then
			return
		end
		local record = newRecord(FUN.THROW_MAX_SECONDS + 1.5)
		local ball, flight = lobbed(record, from, to, tonumber(payload.landAt) or 0, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * LOOK.balloon,
			Color = rgb(Logic.GOO),
			Material = Enum.Material.Glass,
			Transparency = 0.15,
		})
		task.delay(flight, function()
			if record.done then
				return
			end
			ball:Destroy()
			local ground = groundAt(to)
			local at = anchorAt(record, ground + Vector3.new(0, 0.5, 0))
			sound("PvpGoo", at, payload.attacker == localPlayer.UserId)
			emit(record, at, {
				count = 40,
				colors = { Logic.GOO, { 0.2, 0.7, 0.2 } },
				texture = SMOKE,
				speed = { 10, 22 },
				size = 1.1,
				lifetime = { 0.4, 0.9 },
				gravity = 40,
				spread = 70,
			})
			-- the ground splat fades over the paint time
			local splat = newRecord(FUN.BALLOON.PAINT_SECONDS, splats)
			local d = FUN.BALLOON.SPLASH_RADIUS * 1.5
			local disc = part(splat, {
				Name = "GooSplat",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(LOOK.splatThickness, d, d),
				CFrame = CFrame.new(ground + Vector3.new(0, LOOK.splatThickness / 2 + 0.02, 0))
					* CFrame.Angles(0, 0, math.pi / 2),
				Color = rgb(Logic.GOO),
				Material = Enum.Material.Glass,
				Transparency = 0.1,
			})
			TweenService:Create(
				disc,
				TweenInfo.new(FUN.BALLOON.PAINT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Transparency = 1 }
			):Play()
		end)
	end

	local PAINT_CAP = 8
	local paintCount = 0
	local function paint(payload: any)
		local character = characterOf(payload.target)
		local root = rootOf(character)
		if not character or not root or not inRange(root.Position) then
			return
		end
		local seconds = math.clamp(tonumber(payload.duration) or 0, 0.1, FUN.BALLOON.PAINT_SECONDS)
		local record = newRecord(2.5)
		emit(record, root, {
			count = 0,
			colors = { Logic.GOO },
			texture = SMOKE,
			speed = { 0.5, 2 },
			size = 0.6,
			lifetime = { 0.5, 1 },
			gravity = 20,
			rate = if payload.slowed then 24 else 12,
			locked = false,
		})
		local entry = paints[character]
		if entry then
			entry.untilAt = math.max(entry.untilAt, os.clock() + seconds)
			return
		end
		if paintCount >= PAINT_CAP then
			return
		end
		local highlight = Instance.new("Highlight")
		highlight.FillColor = rgb(Logic.GOO)
		highlight.OutlineColor = Color3.new(0.15, 0.55, 0.15)
		highlight.FillTransparency = 0.3
		highlight.OutlineTransparency = 0.4
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = character
		highlight.Parent = character
		paintCount += 1
		local newEntry = { highlight = highlight, untilAt = os.clock() + seconds }
		paints[character] = newEntry
		local paintRecord = newRecord(FUN.BALLOON.PAINT_SECONDS + 1)
		own(paintRecord, highlight)
		table.insert(paintRecord.cleanup, function()
			if paints[character] == newEntry then
				paints[character] = nil
			end
			paintCount -= 1
		end)
		local function check()
			local left = newEntry.untilAt - os.clock()
			if paintRecord.done then
				return
			end
			if left > 1.2 then
				task.delay(left - 1.2, check)
				return
			end
			TweenService:Create(highlight, TweenInfo.new(1.1), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
			task.delay(1.15, finish, paintRecord)
		end
		task.delay(math.max(0, seconds - 1.2), check)
	end

	local function popBubble(record: Record?, bubble: BasePart?, quiet: boolean?)
		if not bubble or not bubble.Parent then
			return
		end
		local r = record or newRecord(1)
		local at = anchorAt(r, bubble.Position)
		emit(r, at, {
			count = 10,
			colors = { Logic.BUBBLE, { 1, 1, 1 } },
			speed = { 4, 9 },
			size = 0.35,
			lifetime = { 0.2, 0.45 },
		})
		if not quiet then
			sound("PvpBubble", at, false, 1.4 + math.random() * 0.3, 0.6)
		end
		bubble:Destroy()
	end

	local function bubbles(payload: any)
		local origin = PvpFunRules.vec(payload.origin)
		local direction = PvpFunRules.vec(payload.direction)
		local startedAt = tonumber(payload.startedAt)
		local id = payload.streamId
		if not origin or not direction or not startedAt or type(id) ~= "string" then
			return
		end
		if not inRange(Vector3.new(origin.X, origin.Y, origin.Z)) then
			return
		end
		local stream: PvpFunRules.Stream = { origin = origin, direction = direction, startedAt = startedAt }
		local live = { stream = stream, bubbles = {} :: { [number]: BasePart } }
		streams[id] = live
		local record = newRecord(PvpFunRules.streamEnds(stream) - opts.serverNow() + 0.5)
		table.insert(record.cleanup, function()
			if streams[id] == live then
				streams[id] = nil
			end
		end)
		local cfg = FUN.BUBBLES
		local hand = handOf(characterOf(payload.attacker))
		sound(
			"PvpBubble",
			hand or anchorAt(record, Vector3.new(origin.X, origin.Y, origin.Z)),
			payload.attacker == localPlayer.UserId
		)
		for index = 1, cfg.COUNT do
			local born = PvpFunRules.bubbleBorn(stream, index)
			task.delay(math.max(0, born - opts.serverNow()), function()
				if record.done then
					return
				end
				local now = opts.serverNow()
				local here = PvpFunRules.bubbleAt(stream, index, math.max(now, born))
				local last = PvpFunRules.bubbleAt(stream, index, born + cfg.LIFETIME)
				if not here or not last then
					return
				end
				local size = cfg.SIZE * (0.8 + 0.4 * ((index * 37) % 10) / 10)
				local bubble = part(record, {
					Name = "FunBubble",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * size,
					CFrame = CFrame.new(here.X, here.Y, here.Z),
					Color = rgb(Logic.BUBBLE),
					Material = Enum.Material.Glass,
					Transparency = 0.55,
					Reflectance = 0.25,
				})
				live.bubbles[index] = bubble
				local left = born + cfg.LIFETIME - math.max(now, born)
				TweenService:Create(
					bubble,
					TweenInfo.new(math.max(0.05, left), Enum.EasingStyle.Linear),
					{ CFrame = CFrame.new(last.X, last.Y, last.Z) }
				):Play()
				task.delay(left, function()
					if live.bubbles[index] == bubble then
						live.bubbles[index] = nil
						popBubble(nil, bubble, true)
					end
				end)
			end)
		end
	end

	local function bubbleHit(payload: any)
		local live = if type(payload.streamId) == "string" then streams[payload.streamId] else nil
		local index = tonumber(payload.index)
		if live and index then
			local bubble = live.bubbles[index]
			live.bubbles[index] = nil
			popBubble(nil, bubble)
		end
		local root = rootOf(characterOf(payload.target))
		if root and (tonumber(payload.duration) or 0) > 0 then
			local record = newRecord(math.min(tonumber(payload.duration) or 0, Config.PVP.CONTROL_MAX_SECONDS) + 0.5)
			sound("PvpBubble", root, payload.target == localPlayer.UserId, 0.8)
			emit(record, root, {
				count = 0,
				colors = { Logic.BUBBLE, { 1, 1, 1 } },
				speed = { 0.5, 1.5 },
				size = 0.4,
				lifetime = { 0.6, 1.2 },
				gravity = -4,
				rate = 10,
			})
		end
	end

	local function bubblePopped(payload: any)
		local root = rootOf(characterOf(payload.target))
		if not root then
			return
		end
		local record = newRecord(1)
		local at = anchorAt(record, root.Position + Vector3.new(0, 1, 0))
		emit(record, at, {
			count = 30,
			colors = { Logic.BUBBLE, { 1, 1, 1 } },
			speed = { 10, 20 },
			size = 0.5,
			lifetime = { 0.25, 0.5 },
		})
		sound("PvpBubble", at, payload.target == localPlayer.UserId, 1.6, 1.2)
		popText(record, root.Position, "POP!", 0.8)
	end

	-- The trampoline of a placed Bounce Pad (client only, no collisions: the server detects the steps).
	local function placePad(payload: any)
		local id, position = payload.trapId, vector(payload.position)
		if type(id) ~= "string" or not position then
			return
		end
		if payload.owner ~= localPlayer.UserId then
			playAnim(payload.owner, "throw")
		end
		local old = pads[id]
		if old then
			old.model:Destroy()
		end
		local ground = groundAt(position)
		local d = FUN.BOUNCE_PAD.RADIUS * 2
		local model = Instance.new("Model")
		model.Name = "FunBouncePad"
		local h = LOOK.padHeight
		local frame = part(nil, {
			Name = "Frame",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, d, d),
			CFrame = CFrame.new(ground + Vector3.new(0, h, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = rgb(LOOK.pad_frame),
			Parent = model,
		})
		local skin = part(nil, {
			Name = "Skin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, d - 0.7, d - 0.7),
			CFrame = frame.CFrame * CFrame.new(0.12, 0, 0),
			Color = rgb(LOOK.pad_skin),
			Material = Enum.Material.Fabric,
			Parent = model,
		})
		for i = 1, LOOK.padLegs do
			local a = (i / LOOK.padLegs) * math.pi * 2
			part(nil, {
				Name = "Leg",
				Size = Vector3.new(0.3, h, 0.3),
				CFrame = CFrame.new(
					ground + Vector3.new(math.cos(a) * (d / 2 - 0.4), h / 2, math.sin(a) * (d / 2 - 0.4))
				),
				Color = rgb(LOOK.pad_frame),
				Parent = model,
			})
		end
		model.Parent = folder
		pads[id] = { model = model, skin = skin, position = ground }
		padTotal += 1
		model.Destroying:Connect(function()
			if pads[id] and pads[id].model == model then
				pads[id] = nil
			end
			padTotal -= 1
		end)
		task.delay(FUN.BOUNCE_PAD.SECONDS + 2, function()
			if model.Parent then
				model:Destroy()
			end
		end)
		local record = newRecord(1)
		emit(record, anchorAt(record, ground + Vector3.new(0, h, 0)), {
			count = 20,
			colors = { LOOK.pad_frame, { 1, 1, 1 } },
			speed = { 6, 12 },
			size = 0.5,
			lifetime = { 0.3, 0.6 },
			spread = 85,
		})
	end

	local function clearPad(payload: any)
		local pad = if type(payload.trapId) == "string" then pads[payload.trapId] else nil
		if not pad then
			return
		end
		local record = newRecord(1)
		emit(record, anchorAt(record, pad.position + Vector3.new(0, 1, 0)), {
			count = 16,
			colors = { { 1, 1, 1 } },
			texture = SMOKE,
			speed = { 3, 6 },
			size = 1.2,
			lifetime = { 0.3, 0.6 },
		})
		pad.model:Destroy()
	end

	local function squishPad(trapId: any)
		local pad = if type(trapId) == "string" then pads[trapId] else nil
		if not pad then
			return
		end
		local rest = pad.skin.CFrame
		local down = TweenService:Create(
			pad.skin,
			TweenInfo.new(0.08, Enum.EasingStyle.Quad),
			{ CFrame = rest - Vector3.new(0, 0.7, 0) }
		)
		down.Completed:Connect(function()
			if pad.skin.Parent then
				TweenService:Create(pad.skin, TweenInfo.new(0.5, Enum.EasingStyle.Elastic), { CFrame = rest }):Play()
			end
		end)
		down:Play()
	end

	local function bounce(payload: any)
		squishPad(payload.trapId)
		local character = characterOf(payload.target)
		local isMe = payload.target == localPlayer.UserId
		if isMe and payload.velocity then
			PvpEffects.applyLaunch(character, payload.velocity)
		end
		local root = rootOf(character)
		local position = vector(payload.position) or (root and root.Position)
		if not position or not inRange(position) then
			return
		end
		local record = newRecord(1)
		local at = anchorAt(record, position + Vector3.new(0, LOOK.padHeight, 0))
		sound("PvpBoing", at, isMe, 0.9 + math.random() * 0.2)
		emit(record, at, {
			count = 18,
			colors = { { 1, 1, 1 }, LOOK.pad_frame },
			texture = SMOKE,
			speed = { 10, 16 },
			size = 0.9,
			lifetime = { 0.2, 0.45 },
			spread = 85,
		})
		if payload.flip then
			task.delay(0.12, playAnim, payload.target, "flip")
		else
			playAnim(payload.target, "hit")
		end
	end

	local function squash(payload: any)
		local position = vector(payload.position)
		if not position or not inRange(position) then
			return
		end
		local combo = payload.combo == true
		local record = newRecord(1.2)
		local at = anchorAt(record, position)
		local mine = payload.attacker == localPlayer.UserId or payload.target == localPlayer.UserId
		sound("PvpSqueak", at, mine, if combo then 0.7 else 0.95 + math.random() * 0.25, if combo then 1.6 else 1)
		emit(record, at, {
			count = if combo then 30 else 12,
			colors = { { 1, 0.95, 0.4 }, { 1, 1, 1 } },
			speed = { 8, if combo then 22 else 14 },
			size = if combo then 0.8 else 0.5,
			lifetime = { 0.25, 0.5 },
			spread = 80,
		})
		local duration = tonumber(payload.duration) or 0
		if payload.slimeId ~= nil then
			popText(record, position, if combo then "MEGA SQUEAK!" else "SQUEAK!", if combo then 1.4 else 1)
			proxyPlay(slimeById(payload.slimeId), Logic.slimeSquash(combo))
			return
		end
		local target = payload.target
		if type(target) ~= "number" then
			popText(record, position, "squeak", 0.7)
			return
		end
		popText(record, position, if combo then "MEGA SQUEAK!" else "SQUEAK!", if combo then 1.4 else 1)
		local character = characterOf(target)
		if duration <= 0 or not character then
			playAnim(target, "hit")
			return
		end
		local proxy = makeProxy(character)
		if not proxy then
			playAnim(target, "hit")
			return
		end
		pancakes[target] = { proxy = proxy, combo = combo }
		playKeys(proxy, Logic.pancake(combo))
		-- backstop: spring back on our own if the Boing never arrives
		task.delay(math.min(duration, Config.PVP.CONTROL_MAX_SECONDS) + 0.6, function()
			local entry = pancakes[target]
			if entry and entry.proxy == proxy then
				pancakes[target] = nil
				playKeys(proxy, Logic.spring(combo), function()
					releaseProxy(proxy)
				end)
			end
		end)
	end

	local function boing(payload: any)
		local target = payload.target
		local character = characterOf(target)
		if target == localPlayer.UserId and payload.velocity then
			PvpEffects.applyLaunch(character, payload.velocity)
		end
		local entry = if type(target) == "number" then pancakes[target] else nil
		if entry then
			pancakes[target] = nil
			playKeys(entry.proxy, Logic.spring(entry.combo), function()
				releaseProxy(entry.proxy)
			end)
		end
		local root = rootOf(character)
		if root and inRange(root.Position) then
			local record = newRecord(1.2)
			sound("PvpBoing", root, target == localPlayer.UserId, 1.15)
			popText(record, root.Position, "BOING!", 1.1)
		end
	end

	-- A slime hat: a squishy blob with a brim, eyes and a little shine (root = the brim).
	local function hatModel(record: Record?, color: Color3, scale: number): (Model, BasePart)
		local model = Instance.new("Model")
		model.Name = "SlimeHat"
		local brim = part(nil, {
			Name = "Brim",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.18, LOOK.hatBrim * scale, LOOK.hatBrim * scale),
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.1,
			Parent = model,
		})
		brim.CFrame = CFrame.Angles(0, 0, math.pi / 2)
		local crown = part(nil, {
			Name = "Crown",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * LOOK.hatCrown * scale,
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.05,
			CFrame = CFrame.new(0, 0.45 * scale, 0),
			Parent = model,
		})
		for _, side in { -1, 1 } do
			part(nil, {
				Name = "Eye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.22 * scale,
				Color = Color3.new(0.05, 0.05, 0.08),
				CFrame = crown.CFrame * CFrame.new(side * 0.22 * scale, 0.1 * scale, -0.52 * scale),
				Parent = model,
			})
		end
		for _, p in model:GetChildren() do
			if p ~= brim and p:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = brim, p
				weld.Parent = p
				p.Anchored = false
				p.Massless = true
			end
		end
		model.PrimaryPart = brim
		if record then
			own(record, model)
		end
		model.Parent = folder
		return model, brim
	end

	local function clearHats(userId: number)
		local worn = hats[userId]
		hats[userId] = nil
		if worn then
			for _, model in worn.models do
				model:Destroy()
			end
		end
	end

	-- `userId` wears `stack` hats (the stack only grows while the last hat is still on) for `seconds`.
	local function wearHat(userId: number, color: Color3, stack: number, seconds: number)
		local character = characterOf(userId)
		local head = partOf(character, { "Head" })
		if not character or not head then
			return
		end
		local worn = hats[userId]
		if not worn or os.clock() >= worn.untilAt or worn.head ~= head then
			clearHats(userId)
			worn = { models = {}, untilAt = 0, head = head }
			hats[userId] = worn
		end
		local wearing = worn :: Worn
		while #wearing.models < math.clamp(stack, 1, FUN.HATS.MAX_STACK) do
			local model, brim = hatModel(nil, color, 1)
			brim.Anchored = false
			brim.Massless = true
			local lift = head.Size.Y / 2 + 0.1 + #wearing.models * LOOK.hatStack
			brim.CFrame = head.CFrame * CFrame.new(0, lift, 0) * CFrame.Angles(0, 0, math.pi / 2)
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = head, brim
			weld.Parent = brim
			model.Parent = character
			table.insert(wearing.models, model)
		end
		wearing.untilAt = os.clock() + seconds
		task.delay(seconds + 0.05, function()
			if hats[userId] == wearing and os.clock() >= wearing.untilAt then
				clearHats(userId)
			end
		end)
	end

	-- A missed hat hops around as a little hat-slime for SLIME_SECONDS.
	local function hatSlime(position: Vector3, color: Color3, seed: number)
		local seconds = FUN.HATS.SLIME_SECONDS
		local record = newRecord(seconds, hatSlimes)
		local ground = groundAt(position)
		local model, brim = hatModel(record, color, 0.8)
		local body = part(nil, {
			Name = "Blob",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * LOOK.hatSlimeBody,
			Color = rgb(Logic.GOO),
			Material = Enum.Material.Glass,
			Transparency = 0.15,
			CFrame = brim.CFrame * CFrame.new(-LOOK.hatSlimeBody / 2, 0, 0),
			Parent = model,
		})
		body.Anchored = false
		body.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = brim, body
		weld.Parent = body
		local height = LOOK.hatSlimeBody + 0.1
		local hop = 0.55
		local path = Logic.hatPath(seed, { X = ground.X, Y = ground.Y, Z = ground.Z }, math.floor(seconds / hop), 2.2)
		brim.CFrame = CFrame.new(ground + Vector3.new(0, height, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		local i = 0
		local function step()
			i += 1
			local point = path[i]
			if record.done or not point or not brim.Parent then
				return
			end
			local to = groundAt(Vector3.new(point.X, ground.Y + 2, point.Z)) + Vector3.new(0, height, 0)
			local from = brim.Position
			local face = CFrame.lookAt(from, Vector3.new(to.X, from.Y, to.Z) + Vector3.new(0, 0, 1e-3))
			local mid = (from + to) / 2 + Vector3.new(0, 1.6, 0)
			local turn = face.Rotation * CFrame.Angles(0, 0, math.pi / 2)
			local up = TweenService:Create(
				brim,
				TweenInfo.new(hop * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = CFrame.new(mid) * turn }
			)
			up.Completed:Connect(function()
				if record.done or not brim.Parent then
					return
				end
				TweenService:Create(
					brim,
					TweenInfo.new(hop * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = CFrame.new(to) * turn }
				):Play()
			end)
			up:Play()
			task.delay(hop, step)
		end
		step()
		table.insert(record.cleanup, function()
			local poof = newRecord(0.8)
			emit(poof, anchorAt(poof, brim.Position), {
				count = 10,
				colors = { Logic.GOO, { 1, 1, 1 } },
				texture = SMOKE,
				speed = { 2, 5 },
				size = 0.8,
				lifetime = { 0.3, 0.6 },
			})
		end)
	end

	local function hat(payload: any)
		local to = vector(payload.position)
		local from = throwOrigin(payload)
		if not to or not from or not inRange(to) then
			return
		end
		local seed = tonumber(payload.seed) or 1
		local color = rgb(LOOK.hat_colors[(seed % #LOOK.hat_colors) + 1])
		local flight = math.clamp((to - from).Magnitude / FUN.HATS.SPEED, 0.1, 1)
		local record = newRecord(flight + 0.3)
		sound(
			"PvpSquirt",
			handOf(characterOf(payload.attacker)) or anchorAt(record, from),
			payload.attacker == localPlayer.UserId,
			1.3
		)
		local _, brim = hatModel(record, color, 1)
		brim.CFrame = CFrame.new(from) * CFrame.Angles(0, 0, math.pi / 2)
		TweenService:Create(
			brim,
			TweenInfo.new(flight, Enum.EasingStyle.Linear),
			{ CFrame = CFrame.new(to) * CFrame.Angles(0, math.pi * 3, math.pi / 2) }
		):Play()
		task.delay(flight, function()
			finish(record)
			local target = payload.target
			if type(target) == "number" then
				local head = partOf(characterOf(target), { "Head" })
				if head then
					local pop = newRecord(0.8)
					sound("PvpPop", head, target == localPlayer.UserId, 1.4, 0.8)
					emit(pop, head, {
						count = 12,
						colors = { { 1, 0.85, 0.2 }, { 1, 1, 1 } },
						speed = { 6, 12 },
						size = 0.5,
						lifetime = { 0.3, 0.5 },
					})
				end
				wearHat(target, color, tonumber(payload.stack) or 1, math.clamp(tonumber(payload.duration) or 0, 0, 60))
			else
				hatSlime(to, color, seed)
			end
		end)
	end

	local function disco(payload: any)
		local to = vector(payload.position)
		local from = throwOrigin(payload)
		if not to or not from or not inRange(to) then
			return
		end
		local seconds = math.clamp(tonumber(payload.duration) or 0, 0.5, FUN.DANCE.SECONDS)
		local landAt = tonumber(payload.landAt) or 0
		local throw = newRecord(FUN.THROW_MAX_SECONDS + 0.5)
		local bomb, flight = lobbed(throw, from, to, landAt, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * LOOK.bomb,
			Color = rgb(LOOK.bomb_color),
			Material = Enum.Material.Neon,
		})
		emit(throw, bomb, {
			count = 0,
			colors = Logic.DISCO_COLORS,
			speed = { 1, 3 },
			size = 0.3,
			lifetime = { 0.3, 0.5 },
			rate = 30,
		})
		task.delay(flight, function()
			finish(throw)
			local record = newRecord(seconds + 0.6)
			local ground = groundAt(to)
			local r = FUN.DANCE.RADIUS
			local dome = part(record, {
				Name = "DiscoBubble",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * r * 2,
				CFrame = CFrame.new(ground),
				Color = rgb(Logic.DISCO_COLORS[1]),
				Material = Enum.Material.Glass,
				Transparency = 0.72,
				Reflectance = 0.15,
			})
			local cycle = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true)
			TweenService:Create(dome, cycle, { Color = rgb(Logic.DISCO_COLORS[2]) }):Play()
			local ball = part(record, {
				Name = "DiscoBall",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * LOOK.discoBall,
				CFrame = CFrame.new(ground + Vector3.new(0, LOOK.discoHeight, 0)),
				Color = Color3.new(0.85, 0.85, 0.9),
				Material = Enum.Material.Foil,
				Reflectance = 0.5,
			})
			TweenService:Create(
				ball,
				TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
				{ Orientation = Vector3.new(0, 360, 0) }
			):Play()
			local glow = light(record, ball, rgb(Logic.DISCO_COLORS[1]), r * 4, 4, nil)
			TweenService:Create(glow, cycle, { Color = rgb(Logic.DISCO_COLORS[3]) }):Play()
			for i, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
				local spot = Instance.new("SpotLight")
				spot.Face = face
				spot.Angle = 50
				spot.Range = r * 3
				spot.Brightness = 6
				spot.Color = rgb(Logic.DISCO_COLORS[i])
				spot.Parent = ball
			end
			emit(record, ball, {
				count = 0,
				colors = Logic.DISCO_COLORS,
				speed = { 2, 5 },
				size = 0.35,
				lifetime = { 0.6, 1.2 },
				rate = 20,
				light = 0.8,
			})
			local music = PvpEffects.playSound("PvpDisco", ball, false, { looped = true, volume = 0.7 })
			if not music then
				sound("PvpPop", ball, false, 0.6, 1.2)
			end
			table.insert(record.cleanup, function()
				local poof = newRecord(1)
				local at = anchorAt(poof, ground + Vector3.new(0, 1, 0))
				confettiAt(poof, at, 60, {
					count = 0,
					colors = {},
					speed = { 8, 16 },
					size = 0.35,
					lifetime = { 0.6, 1.2 },
					gravity = 10,
					spin = 200,
				})
			end)
		end)
	end

	local function dance(payload: any)
		local head = partOf(characterOf(payload.target), { "Head" })
		local seconds = math.clamp(tonumber(payload.duration) or 0, 0.1, Config.PVP.CONTROL_MAX_SECONDS)
		playAnim(payload.target, "dance")
		if not head or not inRange(head.Position) then
			return
		end
		local record = newRecord(seconds + 0.5)
		local e = emit(record, head, {
			count = 0,
			colors = Logic.DISCO_COLORS,
			speed = { 1.5, 3 },
			size = 0.45,
			lifetime = { 0.6, 1 },
			gravity = -2,
			rate = 10,
			light = 0.8,
		})
		task.delay(seconds, function()
			e.Rate = 0
		end)
	end

	local function rocket(position: Vector3, color: { number }, height: number, seconds: number, attacker: any)
		local record = newRecord(FUN.FIREWORKS.FLIGHT + seconds + 0.5)
		local cfg = FUN.FIREWORKS
		local body = part(record, {
			Name = "Rocket",
			Size = LOOK.rocket,
			CFrame = CFrame.new(position + Vector3.new(0, 1, 0)),
			Color = rgb(color),
			Material = Enum.Material.Neon,
		})
		emit(record, body, {
			count = 0,
			colors = { { 1, 0.9, 0.5 }, { 1, 0.5, 0.2 } },
			texture = FIRE,
			speed = { 4, 8 },
			size = 0.7,
			lifetime = { 0.2, 0.4 },
			spread = 15,
			gravity = 30,
			rate = 60,
			light = 1,
		}).EmissionDirection =
			Enum.NormalId.Bottom
		sound("PvpFirework", body, attacker == localPlayer.UserId)
		local top = position + Vector3.new(0, height, 0)
		TweenService:Create(
			body,
			TweenInfo.new(cfg.FLIGHT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(top) }
		):Play()
		task.delay(cfg.FLIGHT, function()
			if record.done then
				return
			end
			body:Destroy()
			local at = anchorAt(record, top)
			local shades = {
				color,
				{ math.min(1, color[1] + 0.35), math.min(1, color[2] + 0.35), math.min(1, color[3] + 0.35) },
				{ 1, 1, 1 },
			}
			emit(record, at, {
				count = 220,
				colors = { color, shades[2] },
				texture = SPARK,
				speed = { 45, 70 },
				size = 3,
				lifetime = { 1.3, 2.2 },
				gravity = 10,
				drag = 1.3,
				light = 0.5,
			})
			-- a second, rainbow ring makes every burst colourful whatever the slime colour
			confettiAt(record, at, 120, {
				count = 0,
				colors = {},
				texture = SPARK,
				speed = { 25, 40 },
				size = 1.8,
				lifetime = { 0.9, 1.5 },
				gravity = 6,
				drag = 1.6,
				spin = 0,
				light = 0.7,
			})
			emit(record, at, {
				count = 60,
				colors = { shades[2], shades[3] },
				texture = SPARK,
				speed = { 15, 30 },
				size = 1.4,
				lifetime = { 0.6, 1.1 },
				drag = 2,
				light = 1,
			})
			-- goo sparkles rain down
			emit(record, at, {
				count = 80,
				colors = { color, shades[2] },
				texture = SMOKE,
				speed = { 5, 14 },
				size = 0.7,
				lifetime = { 2.2, seconds },
				gravity = 18,
				drag = 0.5,
				light = 0.6,
			})
			light(record, at, rgb(shades[2]), 90, 10, 1.4)
			sound("PvpPop", at, false, 0.55, 1.6)
		end)
	end

	local function cheer(position: Vector3)
		local radius = FUN.FIREWORKS.CHEER_RADIUS
		for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
			if proxyTotal >= FUN.PROXIES_MAX then
				return
			end
			if model:IsA("Model") and model:GetAttribute("State") == "Wild" and not proxies[model] then
				local p = bodyPosition(model)
				if (p - position).Magnitude <= radius then
					task.delay(FUN.FIREWORKS.FLIGHT + math.random() * 0.4, function()
						if model.Parent then
							proxyPlay(model, Logic.hop(2.5, 3))
						end
					end)
				end
			end
		end
	end

	local function firework(payload: any)
		local position = vector(payload.position)
		if not position then
			return
		end
		local cfg = FUN.FIREWORKS
		local color = if type(payload.color) == "table" and #payload.color >= 3 then payload.color else Logic.GOO
		local count = math.clamp(tonumber(payload.count) or 1, 1, cfg.VOLLEY)
		local height = math.clamp(tonumber(payload.height) or cfg.HEIGHT, 5, cfg.HEIGHT)
		local seconds = math.clamp(tonumber(payload.duration) or cfg.SECONDS, 1, cfg.SECONDS)
		local ground = groundAt(position)
		for k = 1, count do
			local a = (k - 1) / count * math.pi * 2
			local offset = if k == 1
				then Vector3.zero
				else Vector3.new(math.cos(a) * cfg.SPREAD, 0, math.sin(a) * cfg.SPREAD)
			task.delay(
				(k - 1) * cfg.VOLLEY_GAP,
				rocket,
				ground + offset,
				color,
				height + (k - 1) * 6,
				seconds,
				payload.attacker
			)
		end
		if inRange(ground) then
			cheer(ground)
		end
	end

	local USE: { [string]: (payload: any) -> () } = {
		Confetti = confetti,
		Balloon = balloon,
		Paint = paint,
		Bubbles = bubbles,
		Bubble = bubbleHit,
		Pop = bubblePopped,
		Bounce = bounce,
		Squash = squash,
		Boing = boing,
		Hat = hat,
		Disco = disco,
		Dance = dance,
		Firework = firework,
	}

	local handle = {}

	function handle.handles(payload: any): boolean
		return type(payload) == "table" and Logic.isFun(payload.itemId)
	end

	function handle.play(payload: any)
		if stopped or type(payload) ~= "table" then
			return
		end
		local kind = payload.kind
		if kind == "TrapPlaced" then
			placePad(payload)
			return
		elseif kind == "TrapCleared" then
			clearPad(payload)
			return
		end
		local run = USE[payload.effect]
		if not run then
			return
		end
		if payload.attacker ~= localPlayer.UserId then
			playAnim(payload.attacker, Logic.useAnim(payload.effect))
		end
		run(payload)
	end

	-- 10 Hz (init.client's loop, server time): bubbles and pads against nearby wild slimes.
	function handle.tick(now: number)
		if stopped or (next(streams) == nil and next(pads) == nil) then
			return
		end
		local camera = workspace.CurrentCamera
		local wild = {}
		for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
			if model:IsA("Model") and model:GetAttribute("State") == "Wild" and not proxies[model] then
				local p = bodyPosition(model)
				if not camera or (camera.CFrame.Position - p).Magnitude <= FUN.FX_RANGE then
					table.insert(wild, { model = model, position = p })
				end
			end
		end
		if #wild == 0 then
			return
		end
		local touch = FUN.BUBBLES.RADIUS + 1
		for _, live in streams do
			for index, bubble in live.bubbles do
				local at = PvpFunRules.bubbleAt(live.stream, index, now)
				if at and bubble.Parent then
					local here = Vector3.new(at.X, at.Y, at.Z)
					for _, slime in wild do
						if not proxies[slime.model] and (slime.position - here).Magnitude <= touch then
							live.bubbles[index] = nil
							popBubble(nil, bubble)
							floatSlime(slime.model)
							break
						end
					end
				end
			end
		end
		for id, pad in pads do
			for _, slime in wild do
				local d = slime.position - pad.position
				if
					not proxies[slime.model]
					and Vector3.new(d.X, 0, d.Z).Magnitude <= FUN.BOUNCE_PAD.RADIUS
					and math.abs(d.Y) <= 6
				then
					squishPad(id)
					proxyPlay(slime.model, Logic.hop(8, 1))
				end
			end
		end
	end

	function handle.activeCount(): number
		return effects.count() + splats.count() + hatSlimes.count() + proxyTotal
	end

	function handle.proxyCount(): number
		return proxyTotal
	end

	function handle.padCount(): number
		return padTotal
	end

	function handle.stop()
		stopped = true
		for _, queue in { effects, splats, hatSlimes } do
			for _, record in queue.items() do
				finish(record)
			end
		end
		for _, proxy in table.clone(proxies) do
			releaseProxy(proxy)
		end
		for userId in table.clone(hats) do
			clearHats(userId)
		end
		folder:Destroy()
	end

	return handle :: Handle
end

return PvpFunFx
