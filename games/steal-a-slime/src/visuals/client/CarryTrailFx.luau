--!strict
--[[
	CarryTrailFx (VisualsClient module, contract/exclusive-shop.md §9)

	Draws every player's equipped carry trail while they carry a slime: Player attribute CarryTrail (the trail id,
	Constants.CARRY_TRAIL_ATTRIBUTE, set by the server only with the flag on) plus Player attribute Carrying (the
	carried slime's id, Constants.CARRYING_ATTRIBUTE: set from pickup, wild or stolen, until the slime leaves the
	hands). The local player gets theirs too. Look and rules (visible, behind the back, below the carried slime, few
	particles) are Visuals.CarryTrail; this file only builds them on the HumanoidRootPart:
	  * two Attachments behind the back and a FaceCamera Trail between them, in the trail's colours;
	  * one Attachment with a ParticleEmitter (twinkles / goo blobs / hearts / stars / glints) emitting backwards.

	The engine animates both, so there is no per-frame work: `tick` (from the client's one frame loop) only looks at
	the players every CarryTrail.SWEEP_EVERY seconds, keeps the trails of the CarryTrail.MAX_DRAWN nearest carriers
	within CarryTrail.MAX_DISTANCE of the camera and removes the rest (stopped carrying, trail cleared, too far, left,
	respawned). Everything it adds is local; it never fires remotes. `stop` removes every trail.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarryTrail = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("CarryTrail"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local CarryTrailFx = {}

CarryTrailFx.TRAIL_NAME = "CarryTrail"
CarryTrailFx.PARTICLE_Z_OFFSET = -1 -- particles render a stud further from the camera: never in front of the slime

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

type Rig = { root: BasePart, trailId: string, parts: { Instance } }

local function colorSequence(keys: { CarryTrail.ColorKey }): ColorSequence
	local points = {}
	for _, k in keys do
		table.insert(points, ColorSequenceKeypoint.new(k.t, Color3.fromRGB(k.rgb[1], k.rgb[2], k.rgb[3])))
	end
	return ColorSequence.new(points)
end

local function numberSequence(keys: { CarryTrail.NumberKey }): NumberSequence
	local points = {}
	for _, k in keys do
		table.insert(points, NumberSequenceKeypoint.new(k.t, k.v))
	end
	return NumberSequence.new(points)
end

local function attachment(name: string, position: Vector3, parent: BasePart): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	a.Parent = parent
	return a
end

local function build(root: BasePart, def: CarryTrail.Def): Rig
	local look = CarryTrail.look(def)
	local t, p = look.trail, look.particles
	local name = CarryTrailFx.TRAIL_NAME

	local top = attachment(name .. "Top", Vector3.new(0, t.top, t.back), root)
	local bottom = attachment(name .. "Bottom", Vector3.new(0, t.bottom, t.back), root)
	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = colorSequence(t.colors)
	trail.Transparency = numberSequence(t.transparency)
	trail.WidthScale = numberSequence(t.width)
	trail.Lifetime = t.lifetime
	trail.LightEmission = t.lightEmission
	trail.FaceCamera = true
	trail.MinLength = 0.05
	trail.Parent = root

	local emit = attachment(name .. "Emit", Vector3.new(p.offset[1], p.offset[2], p.offset[3]), root)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name .. "Particles"
	emitter.Texture = p.texture
	emitter.Color = colorSequence(p.colors)
	emitter.Transparency = numberSequence(p.transparency)
	emitter.Size = numberSequence(p.size)
	emitter.Rate = p.rate
	emitter.Lifetime = NumberRange.new(p.lifetime[1], p.lifetime[2])
	emitter.Speed = NumberRange.new(p.speed[1], p.speed[2])
	emitter.SpreadAngle = Vector2.new(p.spread, p.spread)
	emitter.EmissionDirection = Enum.NormalId.Back -- the attachment's +Z: behind the player
	emitter.Acceleration = Vector3.new(p.accel[1], p.accel[2], p.accel[3])
	emitter.Drag = p.drag
	emitter.Rotation = NumberRange.new(p.rotation[1], p.rotation[2])
	emitter.RotSpeed = NumberRange.new(p.rotSpeed[1], p.rotSpeed[2])
	emitter.LightEmission = p.lightEmission
	emitter.LockedToPart = false
	emitter.ZOffset = CarryTrailFx.PARTICLE_Z_OFFSET
	emitter.Parent = emit

	return { root = root, trailId = def.id, parts = { trail, top, bottom, emit } }
end

local function destroy(rig: Rig)
	for _, part in rig.parts do
		part:Destroy()
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Starts drawing trails. Call `tick` once a frame from the client's frame loop.
function CarryTrailFx.start(): Controller
	local rigs: { [Player]: Rig } = {}
	local lastSweep = -math.huge

	local function remove(player: Player)
		local rig = rigs[player]
		if rig then
			destroy(rig)
			rigs[player] = nil
		end
	end

	local function sweep(camera: Camera)
		local eye = camera.CFrame.Position
		local candidates = {}
		local roots: { [Player]: BasePart } = {}
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if not root then
				continue
			end
			local distance = (root.Position - eye).Magnitude
			local trailId = player:GetAttribute(Constants.CARRY_TRAIL_ATTRIBUTE)
			local carrying = player:GetAttribute(Constants.CARRYING_ATTRIBUTE)
			if CarryTrail.shows(trailId, carrying, distance) then
				roots[player] = root
				table.insert(candidates, { key = player, distance = distance })
			end
		end
		local picked = CarryTrail.pick(candidates)
		for player, rig in rigs do
			if not picked[player] or rig.root ~= roots[player] or rig.root.Parent == nil then
				remove(player)
			end
		end
		for player in picked do
			local trailId = player:GetAttribute(Constants.CARRY_TRAIL_ATTRIBUTE)
			local rig = rigs[player]
			if rig and rig.trailId ~= trailId then
				remove(player)
				rig = nil
			end
			local def = CarryTrail.def(trailId)
			if not rig and def then
				rigs[player] = build(roots[player], def)
			end
		end
	end

	local leaving = Players.PlayerRemoving:Connect(remove)

	local function tick(camera: Camera?)
		if not camera then
			return
		end
		local now = os.clock()
		if now - lastSweep < CarryTrail.SWEEP_EVERY then
			return
		end
		lastSweep = now
		sweep(camera)
	end

	local function stop()
		leaving:Disconnect()
		for player in rigs do
			remove(player)
		end
	end

	return { tick = tick, stop = stop }
end

return CarryTrailFx
