--!strict
--[[
	PlazaColliders (Roblox adapter, owner: Jolt)

	PlazaColliders.place(): Folder?

	Makes the landing ring (ranch_landing_ring) and the goo drain (ranch_goo_drain) solid: invisible anchored
	CanCollide Parts under workspace.Map.Plaza.PlazaColliders, from WorldLayout.plazaColliders() (the curb stones'
	real footprint, step-over height; the ring is open at the slide mouth and lane start). Both meshes stay decor
	(MeshAssets.COLLISION has no entry for them: the slot boxes are deeper than the stones). Wild slimes never
	collide (SlimeMesh), so the lane and the slide ride are untouched. Built at runtime like FountainColliders, so the
	1400 layout parts budget is not spent. Idempotent. docs/COLLISION.md.
]]

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)
local WorldLayout = require(game:GetService("ReplicatedStorage").Visuals.WorldLayout)

local PlazaColliders = {}

PlazaColliders.FOLDER = "PlazaColliders"

function PlazaColliders.place(): Folder?
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local plaza = map and map:FindFirstChild("Plaza")
	if not plaza then
		return nil
	end
	local existing = plaza:FindFirstChild(PlazaColliders.FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = PlazaColliders.FOLDER
	for _, node in WorldLayout.plazaColliders() do
		local size, pos, rot = node.size :: { number }, node.pos :: { number }, node.rot or { 0, 0, 0 }
		local part = Instance.new("Part")
		part.Name = node.name
		part.Shape = if node.shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
		part.Size = Vector3.new(size[1], size[2], size[3])
		part.CFrame = CFrame.new(pos[1], pos[2], pos[3])
			* CFrame.Angles(0, math.rad(rot[2]), 0)
			* CFrame.Angles(0, 0, math.rad(rot[3]))
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = folder
	end
	folder.Parent = plaza
	return folder
end

return PlazaColliders
