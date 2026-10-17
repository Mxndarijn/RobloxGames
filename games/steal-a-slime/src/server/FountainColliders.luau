--!strict
--[[
	FountainColliders (Roblox adapter, owner: Phoenix)

	FountainColliders.place(): Folder?

	Adds the fountain slide's collision (the whole path with FEATURES.SlideCollision, else only the low stretch) (Shared.SlideColliders) under
	workspace.Map.Volcano.SlideColliders: a solid block along the slide so players can neither
	walk up it nor stand in it. Invisible, anchored, CanCollide
	Parts (a Fill is two WedgeParts forming a steep ridge roof, bug #9), no touch or query. Unlike the silo's Basin / Trim / Silo colliders
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

FountainColliders.ATTRIBUTE = "FountainCollider" -- = the spec kind (Floor / Fill / Skirt / Joint)

local function place(part: BasePart, kind: string, folder: Folder)
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part:SetAttribute(FountainColliders.ATTRIBUTE, kind)
	part.Parent = folder
end

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
		local frame = CFrame.lookAt(centre, centre + Vector3.new(f[1], f[2], f[3]))
		if spec.kind == "Fill" then
			-- Bug #9: a roof, not a flat top. Two wedges (left / right of the centreline), the tall face on the
			-- centreline, base on the ride line, faces >= RIDGE_ANGLE steep and frictionless: nobody stays on top.
			local ridge = SlideColliders.ridge(spec)
			local lift = ridge.height / 2 - SlideColliders.FILL / 2
			for _, side in { -1, 1 } do
				-- wedge Y = up, Z = toward the centreline (the tall face is at +Z), X = Y x Z along the slide
				local across = frame.RightVector * -side
				local at = frame.Position + frame.RightVector * (side * ridge.half / 2) + frame.UpVector * lift
				local part = Instance.new("WedgePart")
				part.Name = spec.name .. (if side < 0 then "L" else "R")
				part.Size = Vector3.new(s[3], ridge.height, ridge.half)
				part.CFrame = CFrame.fromMatrix(at, frame.UpVector:Cross(across), frame.UpVector, across)
				part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
				place(part, spec.kind, folder)
			end
			continue
		end
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Size = Vector3.new(s[1], s[2], s[3])
		part.CFrame = frame
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		place(part, spec.kind, folder)
	end
	folder.Parent = volcano
	return folder
end

return FountainColliders
