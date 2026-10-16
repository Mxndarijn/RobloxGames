--!strict
--[[
	ParadeView (Roblox adapter, owner: Phoenix, FEATURES.Parade)

	ParadeView.place(): Folder?
	  Lays the goo lane (Shared.ParadeLane.WAYPOINTS) on the plaza under
	  workspace.Map.Plaza.ParadeLane: one flat goo strip Part per waypoint
	  pair, HALF_WIDTH * 2 wide, top at LANE_Y. Visual only: anchored, no
	  collision, query or touch, so players walk over it and ground
	  raycasts (drops, landings) pass through. Neighbours overlap at the
	  joints; every other strip stands 0.03 taller so overlaps never share a
	  top face (z-fighting, like the ring path). Idempotent.

	ParadeView.splash(effects): Instance?
	  The goo splash at the drain when a lane slime leaves (World event
	  "Drained"): Visuals.Effects' "Eruption" goo puffs on a short burst,
	  cleaned up with Debris. nil without Effects.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local DespawnTelegraph = require(ReplicatedStorage.Shared.DespawnTelegraph)
local ParadeLane = require(ReplicatedStorage.Shared.ParadeLane)

local ParadeView = {}

ParadeView.FOLDER = "ParadeLane"
ParadeView.SPLASH_EMITTER = "Eruption" -- Visuals.Effects preset: goo splash puffs
ParadeView.SPLASH_COUNT = 24
ParadeView.SPLASH_SECONDS = 0.2 -- burst length (server emitters run on Rate; Emit doesn't replicate)

local GOO = DespawnTelegraph.FX.color

function ParadeView.place(): Folder?
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local plaza = map and map:FindFirstChild("Plaza")
	if not plaza then
		return nil
	end
	local existing = plaza:FindFirstChild(ParadeView.FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = ParadeView.FOLDER
	local points = ParadeLane.WAYPOINTS
	local width = ParadeLane.HALF_WIDTH * 2
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local length = math.sqrt(dx * dx + dz * dz)
		if length < 1e-3 then
			continue
		end
		local thick = ParadeLane.STRIP_THICKNESS + (if i % 2 == 0 then 0.03 else 0)
		local mid =
			Vector3.new((a[1] + b[1]) / 2, ParadeLane.LANE_Y - ParadeLane.STRIP_THICKNESS / 2, (a[2] + b[2]) / 2)
		local part = Instance.new("Part")
		part.Name = `Lane{i}`
		-- Overlap by half a width so the turns stay closed.
		part.Size = Vector3.new(width, thick, length + width / 2)
		part.CFrame = CFrame.lookAt(mid, mid + Vector3.new(dx, 0, dz))
			+ Vector3.new(0, (thick - ParadeLane.STRIP_THICKNESS) / 2, 0)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Glass
		part.Color = Color3.fromRGB(GOO[1], GOO[2], GOO[3])
		part.Transparency = 0.15
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = folder
	end
	folder.Parent = plaza
	return folder
end

function ParadeView.splash(effects: any): Instance?
	if not effects or type(effects.emitter) ~= "function" then
		return nil
	end
	local d = ParadeLane.DRAIN
	local holder = Instance.new("Part")
	holder.Name = "DrainSplash"
	holder.Size = Vector3.new(1, 1, 1)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	-- The preset blows along local +X (the Crater cylinder's up): turn +X to world up.
	holder.CFrame = CFrame.new(d.x, d.lipY, d.z) * CFrame.Angles(0, 0, math.pi / 2)
	local emitter = effects.emitter(ParadeView.SPLASH_EMITTER) :: ParticleEmitter
	emitter.Rate = ParadeView.SPLASH_COUNT / ParadeView.SPLASH_SECONDS
	emitter.Parent = holder
	holder.Parent = workspace
	task.delay(ParadeView.SPLASH_SECONDS, function()
		emitter.Enabled = false
	end)
	Debris:AddItem(holder, ParadeView.SPLASH_SECONDS + emitter.Lifetime.Max + 0.5)
	return holder
end

return ParadeView
