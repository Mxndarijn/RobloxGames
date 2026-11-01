--!strict
--[[
	ObbyWorld (VisualsClient module, contract/obby.md §5)

	Swaps the look while the local player is in the obby world: each frame (`tick`) it checks the local root against
	WorldLayout.inObbyWorld. On the frame that changes, the look swaps at once (ObbyLook's mix jumps to 1 inside, 0
	outside): NightSky re-blends Lighting and the Atmosphere from the map's own day / night and weather look, so the
	way back restores the map exactly, whatever changed meanwhile. The camera is set behind the player at the zoom and
	pitch it had, facing the way they face, in that same frame: one clean cut, with no veil, fade or tween (a grey veil
	here read as a flash). `tick` runs in RenderStepped, which fires after the camera module's BindToRenderStep step and
	before the frame is drawn, so the look and the camera land together on the first frame that shows the new place.
	While inside this module also tints its own ColorCorrection
	("ObbyWorldTint"), turns the place's Bloom and SunRays down and the Atmosphere Offset up (ObbyLook.BLOOM /
	SUN_RAYS / ATMOSPHERE; the place values come back exactly on the way out) and builds the world's backdrop
	(ObbyBackdrop), removing it on the way out. It also keeps ObbyLook's "inside" flag current, which the plot
	marker, the weather, the tutorial guide and the boss card read. `start()` returns { tick, stop }.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local ObbyBackdrop = require(script.Parent:WaitForChild("ObbyBackdrop"))
local ObbyLook = require(Visuals:WaitForChild("ObbyLook"))
local WorldLayout = require(Visuals:WaitForChild("WorldLayout"))

local ObbyWorld = {}

ObbyWorld.TINT_NAME = "ObbyWorldTint"
ObbyWorld.BASE_PREFIX = "ObbyWorldBase_"

-- Sets properties of one of the place's own Lighting children (Bloom, SunRays, Atmosphere) to the obby `target`
-- (inside) or back to the place value (outside). The place value is kept in an attribute while inside and put back
-- exactly on the way out.
local function swapEffect(className: string, target: { [string]: number }, inside: boolean)
	local effect: any = Lighting:FindFirstChildOfClass(className)
	if not effect then
		return
	end
	for key, value in target do
		local attribute = ObbyWorld.BASE_PREFIX .. key
		local base = effect:GetAttribute(attribute)
		if inside then
			if base == nil then
				effect:SetAttribute(attribute, effect[key])
			end
			effect[key] = value
		elseif base ~= nil then
			effect[key] = base
			effect:SetAttribute(attribute, nil)
		end
	end
end

-- Puts the camera behind the root at the distance and pitch it had, so a teleport doesn't swing or pop it. Also when
-- an obby move holds it Scriptable (ObbyMoves' cannon): ObbyMoves hands it back to Custom later in this same frame,
-- and the camera module then carries on from here instead of drawing one frame of the obby from the old spot.
local function steadyCamera(root: BasePart)
	local camera = workspace.CurrentCamera
	if
		not camera
		or (camera.CameraType ~= Enum.CameraType.Custom and camera.CameraType ~= Enum.CameraType.Scriptable)
	then
		return
	end
	local distance = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	local player = Players.LocalPlayer
	if player then -- a Scriptable camera's Focus can be stale: keep the distance within the player's zoom range
		distance = math.clamp(distance, player.CameraMinZoomDistance, player.CameraMaxZoomDistance)
	end
	local pitch = math.asin(math.clamp(camera.CFrame.LookVector.Y, -0.99, 0.99))
	local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if flat.Magnitude < 1e-3 then
		return
	end
	flat = flat.Unit
	local look = flat * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
	-- The camera module already moved its Focus to the new place this frame (it runs before RenderStepped), at the
	-- height it uses for this avatar; a stale one (a Scriptable hold) falls back to the default lift.
	local focus = camera.Focus.Position
	if (focus - root.Position).Magnitude > ObbyLook.CAMERA.focusNear then
		focus = root.Position + ObbyLook.CAMERA.focusLift
	end
	camera.CFrame = CFrame.lookAt(focus - look * distance, focus)
end

export type Controller = { tick: (dt: number) -> (), stop: () -> () }

local function localRoot(): BasePart?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function ObbyWorld.start(): Controller
	local tint: ColorCorrectionEffect? = nil
	local backdrop: Folder? = nil
	local wasInside = false

	local function paint(inside: boolean)
		swapEffect("BloomEffect", ObbyLook.BLOOM, inside)
		swapEffect("SunRaysEffect", ObbyLook.SUN_RAYS, inside)
		swapEffect("Atmosphere", ObbyLook.ATMOSPHERE, inside)
		if not inside then
			if tint then
				tint:Destroy()
				tint = nil
			end
			return
		end
		local cc = tint or Instance.new("ColorCorrectionEffect")
		cc.Name = ObbyWorld.TINT_NAME
		local t = ObbyLook.TINT
		cc.TintColor = t.TintColor
		cc.Saturation = t.Saturation
		cc.Brightness = t.Brightness
		cc.Contrast = t.Contrast
		cc.Parent = Lighting
		tint = cc
	end

	local function tick(_dt: number)
		local root = localRoot()
		local inside = false
		if root then
			local p = root.Position
			inside = WorldLayout.inObbyWorld({ p.X, p.Y, p.Z })
		end
		if inside == wasInside then
			return
		end
		wasInside = inside
		if inside and not backdrop then
			backdrop = ObbyBackdrop.build(workspace)
		elseif not inside and backdrop then
			backdrop:Destroy()
			backdrop = nil
		end
		paint(inside)
		ObbyLook.set(if inside then 1 else 0)
		ObbyLook.setInside(inside)
		if root then
			steadyCamera(root)
		end
	end

	local function stop()
		wasInside = false
		ObbyLook.setInside(false)
		ObbyLook.set(0)
		paint(false)
		if backdrop then
			backdrop:Destroy()
			backdrop = nil
		end
	end

	return { tick = tick, stop = stop }
end

return ObbyWorld
