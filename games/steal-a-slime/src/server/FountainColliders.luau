--!strict
--[[
	FountainColliders (Roblox adapter, owner: Phoenix)

	FountainColliders.place(): Folder?

	Adds the fountain slide's collision (the whole path with FEATURES.SlideCollision, else only the low stretch) (Shared.SlideColliders) under
	workspace.Map.Volcano.SlideColliders: a floor slab per segment, its top on the ride line, so players walk the slide as one smooth
	ramp from the mouth to the head, and a low rail on each side so they stay on it. Invisible, anchored, CanCollide Parts, no touch or query. Unlike the silo's Basin / Trim / Silo
	colliders (MeshCollider, switched by MeshSwap) they stay on in every state: the fountain mesh's slide and the Chute stand-in follow
	the same WorldLayout.SLIDE_PATH, so the trough is in the same place either way. The kit's ground posts and staves brackets get a
	box each (SlideColliders.supports). Wild slimes ride it anchored with CanCollide off (FountainRide), so the colliders never stop
	them. Idempotent (an existing folder is kept).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local SlideColliders = require(ReplicatedStorage.Shared.SlideColliders)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)

local FountainColliders = {}

FountainColliders.ATTRIBUTE = "FountainCollider" -- = the spec kind (Floor / Rail / Skirt / Joint / Post / Brace)

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

-- FEATURES.SlidePCD: MeshSwap placed the slide as a PCD collision mesh, so the boxes it replaces (SlideColliders.PCD_RETIRED:
-- Post / Brace) are destroyed. Returns how many. Called only once the mesh exists; a failed mesh keeps every box.
function FountainColliders.retirePcd(): number
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local volcano = map and map:FindFirstChild("Volcano")
	local folder = volcano and volcano:FindFirstChild(SlideColliders.FOLDER)
	local n = 0
	for _, part in if folder then folder:GetChildren() else {} do
		if SlideColliders.PCD_RETIRED[part:GetAttribute(FountainColliders.ATTRIBUTE)] then
			part:Destroy()
			n += 1
		end
	end
	return n
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
	for _, spec in
		SlideColliders.all(
			WorldLayout.SLIDE_PATH,
			WorldLayout.slidePath(WorldLayout.KIT_SLIDE_SAMPLES),
			Config.FEATURES.SlideCollision
		)
	do
		local c, f, s = spec.centre, spec.forward, spec.size
		local centre = Vector3.new(c[1], c[2], c[3])
		local frame = CFrame.lookAt(centre, centre + Vector3.new(f[1], f[2], f[3]))
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
