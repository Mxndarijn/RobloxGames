--!strict
--[[
	Effects (owner: Archer)

	Effects.play(kind: string, target: Vector3 | CFrame | BasePart): Instance?

	Short particle bursts for "Collect", "Steal", "Merge" and "Rebirth".
	Callable from server or client:
	  * target is a BasePart: an Attachment named "Effect_<kind>" goes inside
	    it, so the burst follows the part.
	  * target is a Vector3 / CFrame: an invisible, anchored, non-colliding
	    Part "Effect_<kind>" goes into workspace.
	On the client the emitters fire once with :Emit(count). On the server
	:Emit doesn't replicate, so the emitters run at count / BURST_TIME for
	BURST_TIME seconds instead. Either way the holder is handed to Debris and
	cleans itself up. Unknown kinds return nil (never error).

	Effects.emitter(name) / Effects.light(name) build the configured
	ParticleEmitter / PointLight presets. WorldBuilder places the static lights
	(only Color3 needed); VisualsClient adds the static emitters (crater
	smoke / embers / "Eruption", lava-crack bubbles) and bursts "Eruption".

	No services or Roblox APIs are touched at load time; the preset tables are
	plain data (rgb arrays), so the render proof can read them under Lune.
]]

export type EmitterPreset = {
	colors: { { number } }, -- rgb keypoints, evenly spaced over the lifetime
	size: { number }, -- { start, finish } studs
	lifetime: { number }, -- { min, max } seconds
	speed: { number }, -- { min, max } studs/s
	spread: number?, -- SpreadAngle degrees (both axes), default 180
	count: number?, -- particles per burst (bursts only)
	rate: number?, -- particles/s for static emitters (0 = burst only)
	lightEmission: number?,
	drag: number?,
	gravity: number?, -- Acceleration Y
	rotSpeed: number?, -- RotSpeed +- degrees/s
	transparency: { number }?, -- { start, finish }, default { 0, 1 }
	direction: string?, -- Enum.NormalId name, default "Top"
	texture: string?,
}

export type LightPreset = { color: { number }, brightness: number, range: number }

local Effects = {}

Effects.BURST_TIME = 0.15
Effects.KINDS = { "Collect", "Steal", "Merge", "Rebirth" }

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

Effects.EMITTERS = {
	-- bursts
	CollectSparkle = {
		colors = { { 140, 255, 150 }, { 255, 240, 120 } },
		size = { 0.6, 0.1 },
		lifetime = { 0.5, 0.9 },
		speed = { 8, 14 },
		count = 30,
		lightEmission = 0.8,
		drag = 3,
		gravity = -12,
		texture = SPARK,
	},
	CollectCoin = {
		colors = { { 255, 215, 60 }, { 255, 180, 30 } },
		size = { 0.5, 0.4 },
		lifetime = { 0.6, 1 },
		speed = { 10, 16 },
		spread = 35,
		count = 10,
		lightEmission = 0.4,
		gravity = -30,
		rotSpeed = 360,
		transparency = { 0, 0.3 },
	},
	StealPuff = {
		colors = { { 170, 60, 255 }, { 60, 20, 90 } },
		size = { 1.2, 2.6 },
		lifetime = { 0.5, 0.8 },
		speed = { 4, 8 },
		count = 18,
		lightEmission = 0.2,
		drag = 4,
		texture = SMOKE,
	},
	StealSpark = {
		colors = { { 255, 60, 80 }, { 255, 170, 60 } },
		size = { 0.5, 0.05 },
		lifetime = { 0.3, 0.6 },
		speed = { 14, 22 },
		count = 24,
		lightEmission = 1,
		drag = 5,
		texture = SPARK,
	},
	MergeSwirl = {
		colors = { { 120, 220, 255 }, { 255, 130, 230 }, { 180, 120, 255 } },
		size = { 0.9, 0.1 },
		lifetime = { 0.7, 1.1 },
		speed = { 5, 9 },
		count = 40,
		lightEmission = 1,
		drag = 2,
		gravity = 6,
		rotSpeed = 270,
		texture = SPARK,
	},
	MergeGoo = {
		colors = { { 120, 255, 140 }, { 70, 200, 110 } },
		size = { 0.7, 0.2 },
		lifetime = { 0.5, 0.8 },
		speed = { 10, 15 },
		spread = 60,
		count = 16,
		lightEmission = 0.3,
		gravity = -35,
		transparency = { 0.1, 0.6 },
	},
	RebirthRing = {
		colors = { { 255, 245, 180 }, { 255, 200, 60 }, { 255, 120, 40 } },
		size = { 1.4, 0.2 },
		lifetime = { 1, 1.6 },
		speed = { 18, 26 },
		spread = 180,
		count = 80,
		lightEmission = 1,
		drag = 3,
		texture = SPARK,
	},
	RebirthColumn = {
		colors = { { 255, 255, 220 }, { 255, 210, 90 } },
		size = { 1.8, 0.4 },
		lifetime = { 1.2, 1.8 },
		speed = { 20, 30 },
		spread = 12,
		count = 40,
		lightEmission = 1,
		texture = FIRE,
	},
	-- static, added to the Map by VisualsClient (client-only looks)
	CraterSmoke = {
		direction = "Right", -- the Crater cylinder's local +X is world up
		colors = { { 90, 80, 80 }, { 40, 36, 36 } },
		-- Kept small and thin so the volcano stays readable (tests/Effects.spec).
		size = { 2.5, 6 },
		lifetime = { 3, 5 },
		speed = { 2.5, 4 },
		spread = 15,
		rate = 2,
		lightEmission = 0,
		transparency = { 0.6, 1 },
		rotSpeed = 30,
		texture = SMOKE,
	},
	CraterEmbers = {
		direction = "Right", -- the Crater cylinder's local +X is world up
		colors = { { 255, 220, 120 }, { 255, 90, 20 } },
		size = { 0.5, 0.1 },
		lifetime = { 1.2, 2 },
		speed = { 8, 14 },
		spread = 25,
		rate = 6,
		lightEmission = 1,
		gravity = -10,
		texture = SPARK,
	},
	Eruption = { -- Rate 0: VisualsClient :Emit()s it every few seconds
		direction = "Right", -- the Crater cylinder's local +X is world up
		colors = { { 255, 240, 160 }, { 255, 120, 30 }, { 120, 40, 20 } },
		size = { 1.6, 0.5 },
		lifetime = { 1.2, 2 },
		speed = { 18, 26 },
		spread = 22,
		rate = 0,
		count = 24,
		lightEmission = 1,
		gravity = -40,
		rotSpeed = 120,
		texture = FIRE,
	},
	RareSparkle = { -- RareSpawn: Rate and Color set per tier
		colors = { { 255, 255, 255 } },
		size = { 0.5, 0.05 },
		lifetime = { 1, 1.6 },
		speed = { 2, 5 },
		rate = 4,
		lightEmission = 1,
		gravity = 3,
		rotSpeed = 120,
		texture = SPARK,
	},
	LavaBubbles = {
		colors = { { 255, 160, 60 }, { 255, 80, 20 } },
		size = { 0.6, 1.2 },
		lifetime = { 0.6, 1 },
		speed = { 1, 3 },
		spread = 10,
		rate = 3,
		lightEmission = 0.8,
		transparency = { 0.1, 1 },
		texture = SPARK,
	},
} :: { [string]: EmitterPreset }

Effects.LIGHTS = {
	CraterGlow = { color = { 255, 120, 40 }, brightness = 3, range = 40 },
	LavaGlow = { color = { 255, 110, 30 }, brightness = 1.5, range = 14 },
	TorchGlow = { color = { 255, 180, 90 }, brightness = 1.2, range = 16 },
	CrystalGlow = { color = { 120, 255, 200 }, brightness = 0.8, range = 10 },
	MergeFlash = { color = { 200, 150, 255 }, brightness = 4, range = 16 },
	RebirthFlash = { color = { 255, 220, 120 }, brightness = 6, range = 28 },
} :: { [string]: LightPreset }

-- Burst kind -> emitter presets (+ optional light flash).
Effects.BURSTS = {
	Collect = { emitters = { "CollectSparkle", "CollectCoin" } },
	Steal = { emitters = { "StealPuff", "StealSpark" } },
	Merge = { emitters = { "MergeSwirl", "MergeGoo" }, light = "MergeFlash" },
	Rebirth = { emitters = { "RebirthRing", "RebirthColumn" }, light = "RebirthFlash" },
} :: { [string]: { emitters: { string }, light: string? } }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
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

function Effects.emitter(name: string): ParticleEmitter
	local p = Effects.EMITTERS[name]
	assert(p, `unknown emitter preset {name}`)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Color = colorSequence(p.colors)
	e.Size = NumberSequence.new(p.size[1], p.size[2])
	e.Lifetime = NumberRange.new(p.lifetime[1], p.lifetime[2])
	e.Speed = NumberRange.new(p.speed[1], p.speed[2])
	local spread = p.spread or 180
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Rate = p.rate or 0
	e.LightEmission = p.lightEmission or 0
	e.Drag = p.drag or 0
	e.Acceleration = Vector3.new(0, p.gravity or 0, 0)
	local rot = p.rotSpeed or 0
	e.RotSpeed = NumberRange.new(-rot, rot)
	e.Rotation = NumberRange.new(0, 360)
	local t = p.transparency or { 0, 1 }
	e.Transparency = NumberSequence.new(t[1], t[2])
	e.EmissionDirection = (Enum.NormalId :: any)[p.direction or "Top"]
	if p.texture then
		e.Texture = p.texture
	end
	return e
end

function Effects.light(name: string): PointLight
	local p = Effects.LIGHTS[name]
	assert(p, `unknown light preset {name}`)
	local l = Instance.new("PointLight")
	l.Name = name
	l.Color = rgb(p.color)
	l.Brightness = p.brightness
	l.Range = p.range
	l.Shadows = false
	return l
end

local function holderFor(kind: string, target: any): Instance?
	local name = `Effect_{kind}`
	if typeof(target) == "Instance" and target:IsA("BasePart") then
		local a = Instance.new("Attachment")
		a.Name = name
		a.Parent = target
		return a
	end
	local cf: CFrame
	if typeof(target) == "Vector3" then
		cf = CFrame.new(target)
	elseif typeof(target) == "CFrame" then
		cf = target
	else
		return nil
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = cf
	part.Parent = workspace
	return part
end

function Effects.play(kind: string, target: Vector3 | CFrame | BasePart): Instance?
	local burst = Effects.BURSTS[kind]
	if not burst then
		return nil
	end
	local holder = holderFor(kind, target)
	if not holder then
		return nil
	end
	local isClient = game:GetService("RunService"):IsClient()
	local longest = 0
	local emitters = {}
	for _, name in burst.emitters do
		local preset = Effects.EMITTERS[name]
		local e = Effects.emitter(name)
		local count = preset.count or 20
		longest = math.max(longest, preset.lifetime[2])
		if isClient then
			e.Rate = 0
			e.Parent = holder
			e:Emit(count)
		else
			e.Rate = count / Effects.BURST_TIME
			e.Parent = holder
			table.insert(emitters, e)
		end
	end
	if burst.light then
		local light = Effects.light(burst.light)
		light.Parent = holder
		task.delay(0.25, function()
			light.Enabled = false
		end)
	end
	if #emitters > 0 then
		task.delay(Effects.BURST_TIME, function()
			for _, e in emitters do
				e.Enabled = false
			end
		end)
	end
	game:GetService("Debris"):AddItem(holder, Effects.BURST_TIME + longest + 0.5)
	return holder
end

return Effects
