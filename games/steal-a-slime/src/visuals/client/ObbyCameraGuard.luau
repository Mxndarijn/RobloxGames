--!strict
--[[
	ObbyCameraGuard (VisualsClient module)

	Keeps the third-person camera out of the obby's non-collide course parts. Roblox's camera only stops at parts that
	collide, so it would slide into a lava floor and, from inside it, show straight through it. Each frame, while the local
	player is in the obby world (ObbyLook.isInside) and the camera is the normal player camera, this follows the line
	from the camera's focus to the camera and, where it enters such a part, moves the camera to MARGIN in front of that
	face: the same as a wall. Which parts count and the margin are visuals/shared/ObbyCameraClip
	(Config.OBBY.CAMERA_CLIP); parts are read live each frame, so moving, fading and hidden parts are handled.

	It finds the built course (ObbyCourseView) at most every FIND_EVERY seconds and caches its plain non-collide parts
	(no MeshParts: a kit mesh's box is not its shape; no special meshes, such as the moon zone's dome). `tick()` runs in
	VisualsClient's RenderStepped, after the camera module has placed the camera and after ObbyWorld's cut; `start()`
	returns { tick, stop }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Constants = require(Shared:WaitForChild("Constants"))
local ObbyCameraClip = require(Visuals:WaitForChild("ObbyCameraClip"))
local ObbyLook = require(Visuals:WaitForChild("ObbyLook"))

local ObbyCameraGuard = {}

ObbyCameraGuard.FIND_EVERY = 0.5 -- seconds between looks for a (re)built course
ObbyCameraGuard.MIN_LENGTH = 0.5 -- studs: closer is first person, nothing to do

export type Controller = { tick: () -> (), stop: () -> () }

local function candidates(course: Instance): { BasePart }
	local out: { BasePart } = {}
	for _, d in course:GetDescendants() do
		if
			d:IsA("BasePart")
			and not d:IsA("MeshPart")
			and not d.CanCollide
			and d:FindFirstChildOfClass("SpecialMesh") == nil
		then
			table.insert(out, d)
		end
	end
	return out
end

function ObbyCameraGuard.start(): Controller
	local course: Instance? = nil
	local parts: { BasePart } = {}
	local nextFind = 0

	local function find()
		local clock = os.clock()
		if clock < nextFind then
			return
		end
		nextFind = clock + ObbyCameraGuard.FIND_EVERY
		local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
		local found = folder and folder:FindFirstChild(Constants.OBBY_COURSE)
		course = found
		parts = if found then candidates(found) else {}
	end

	local function tick()
		if not ObbyLook.isInside() then
			return
		end
		if course == nil or course.Parent == nil then
			find()
			if course == nil then
				return
			end
		end
		local camera = workspace.CurrentCamera
		if not camera or camera.CameraType ~= Enum.CameraType.Custom then
			return
		end
		local focus = camera.Focus.Position
		local eye = camera.CFrame.Position
		local ray = eye - focus
		local length = ray.Magnitude
		if length < ObbyCameraGuard.MIN_LENGTH then
			return
		end
		local best: number? = nil
		for _, part in parts do
			if part.CanCollide or part.LocalTransparencyModifier >= 1 or part.Parent == nil then
				continue
			end
			local size = part.Size
			-- cheap reject: the part's bounding sphere is further from the focus than the camera
			if (part.Position - focus).Magnitude - size.Magnitude / 2 > length then
				continue
			end
			if not ObbyCameraClip.blocks(size.X, size.Y, size.Z, part.Transparency) then
				continue
			end
			local cf = part.CFrame
			local o = cf:PointToObjectSpace(focus)
			local d = cf:VectorToObjectSpace(ray)
			local t = ObbyCameraClip.entry(o.X, o.Y, o.Z, d.X, d.Y, d.Z, size.X / 2, size.Y / 2, size.Z / 2)
			if t and (best == nil or t < best) then
				best = t
			end
		end
		if best == nil then
			return
		end
		local distance = ObbyCameraClip.distance(length, best)
		camera.CFrame = camera.CFrame + (focus + ray.Unit * distance - eye)
	end

	return {
		tick = tick,
		stop = function()
			course = nil
			parts = {}
		end,
	}
end

return ObbyCameraGuard
