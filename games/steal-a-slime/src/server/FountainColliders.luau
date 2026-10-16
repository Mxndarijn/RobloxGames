--!strict
--[[
	FountainColliders (Roblox adapter, owner: Phoenix)

	FountainColliders.place(): Folder?

	Adds the fountain slide's collision (the whole path with FEATURES.SlideCollision, else only the low stretch) (Shared.SlideColliders) under
	workspace.Map.Volcano.SlideColliders: invisible, anchored, CanCollide
	Parts, no touch or query. Unlike the silo's Basin / Trim / Silo colliders
	(MeshCollider, switched by MeshSwap) they stay on in every state: the
	fountain mesh's slide and the Chute stand-in follow the same
	WorldLayout.SLIDE_PATH, so the trough is in the same place either way.
	Wild slimes ride it anchored with CanCollide off (FountainRide), so the
	colliders never stop them. Idempotent (an existing folder is kept).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local SlideColliders = require(ReplicatedStorage.Shared.SlideColliders)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)

local FountainColliders = {}

FountainColliders.ATTRIBUTE = "FountainCollider" -- = the spec kind (Floor / Wall / Skirt)

function FountainColliders.place(): Folder?
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local volcano = map and map:FindFirstChild("Volcano")
	if not volcano then
		return nil
	end
	local existing = volcano:FindFirstChild(SlideColliders.FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = SlideColliders.FOLDER
	for _, spec in SlideColliders.build(WorldLayout.SLIDE_PATH, Config.FEATURES.SlideCollision) do
		local c, f, s = spec.centre, spec.forward, spec.size
		local centre = Vector3.new(c[1], c[2], c[3])
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Size = Vector3.new(s[1], s[2], s[3])
		part.CFrame = CFrame.lookAt(centre, centre + Vector3.new(f[1], f[2], f[3]))
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part:SetAttribute(FountainColliders.ATTRIBUTE, spec.kind)
		part.Parent = folder
	end
	folder.Parent = volcano
	return folder
end

return FountainColliders
