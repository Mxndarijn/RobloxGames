--!strict
--[[
	ObbyCourseView (VisualsClient module, contract/obby.md §5)

	The obby course is client-only, like its backdrop: the server publishes the slot standing now (Constants.OBBY_SLOT
	on workspace.Obby, server/ObbyView) and this builds that course (ObbyCourse.build, then visuals/shared/ObbyParts)
	as workspace.Obby.Course on this client, replacing the old one when the slot changes. The local character
	collides with it on this client; ObbyFx plays its moving parts and ObbyFall reads its Slot. The Goo Ring home's
	MeshAsset slots get their kit meshes here (AssetService:CreateMeshPartAsync, one template per mesh kept between
	rebuilds; fitted like server/MeshSwap does); a mesh that fails to load leaves its slot empty. Never fires remotes.
	Call `tick` once a frame, before ObbyFx.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Constants = require(Shared:WaitForChild("Constants"))
local MeshAssets = require(Shared:WaitForChild("MeshAssets"))
local ObbyCourse = require(Shared:WaitForChild("ObbyCourse"))
local ObbyParts = require(Visuals:WaitForChild("ObbyParts"))
local WorldLayout = require(Visuals:WaitForChild("WorldLayout"))

local ObbyCourseView = {}

export type Controller = { tick: () -> (), stop: () -> () }

local templates: { [string]: MeshPart | false } = {} -- mesh name -> template (false = failed), kept between rebuilds
local loading: { [string]: { thread } } = {}

-- The template for kit mesh `name`, loading it on first ask (yields); false if it can't load.
local function template(name: string): MeshPart | false
	local have = templates[name]
	if have ~= nil then
		return have
	end
	local queue = loading[name]
	if queue then
		table.insert(queue, coroutine.running())
		return coroutine.yield()
	end
	queue = {}
	loading[name] = queue
	local meshId = MeshAssets.meshId(name)
	local ok, part = false, nil
	if meshId then
		ok, part = pcall(function()
			return AssetService:CreateMeshPartAsync(meshId, {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end)
	end
	local result: MeshPart | false = if ok and part then part else false
	templates[name] = result
	loading[name] = nil
	for _, co in queue do
		task.spawn(co, result)
	end
	return result
end

-- Fills `slot` (an invisible box with a MeshAsset attribute) with its kit mesh, standing on the box's bottom at one
-- uniform scale and turned MeshAssets.IMPORT_YAW, like server/MeshSwap. Yields.
local function fill(slot: BasePart, name: string)
	local base = template(name)
	if not base or slot.Parent == nil or slot:FindFirstChild("Mesh") then
		return
	end
	local box = slot.Size
	local size, _, drop = MeshAssets.fit(name, { box.X, box.Y, box.Z })
	local mesh = base:Clone()
	mesh.Name = "Mesh"
	mesh.Size = Vector3.new(size[1], size[2], size[3])
	mesh.CFrame = slot.CFrame * CFrame.new(0, -drop, 0) * CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CastShadow = true
	mesh.Parent = slot
end

function ObbyCourseView.start(): Controller
	local origin, yaw = WorldLayout.obbyFrame()
	local frame: ObbyCourse.Frame = { origin = origin, yaw = yaw }
	local model: Model? = nil
	local builtSlot: number? = nil

	local function clear()
		if model then
			model:Destroy()
			model = nil
		end
		builtSlot = nil
	end

	local function tick()
		local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
		local slot = folder and folder:GetAttribute(Constants.OBBY_SLOT)
		if type(slot) ~= "number" then
			return
		end
		if slot == builtSlot and model and model.Parent == folder then
			return
		end
		clear()
		local built = ObbyParts.build(ObbyCourse.build(slot), frame)
		built.Parent = folder
		for _, d in built:GetDescendants() do
			local name = d:GetAttribute("MeshAsset")
			if d:IsA("BasePart") and typeof(name) == "string" then
				task.spawn(fill, d, name)
			end
		end
		model = built
		builtSlot = slot
	end

	return { tick = tick, stop = clear }
end

return ObbyCourseView
