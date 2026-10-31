--!strict
--[[
	ObbyFall (VisualsClient module, contract/obby.md §3)

	No checkpoints: a fall goes straight back to the start pad. The local player owns their character's physics, so
	this puts them back the frame their root drops Config.OBBY.FALL_DEPTH under the lowest platform they could still
	land on (ObbyCourse.fallHeight, from the course rebuilt here from workspace.Obby.Course's Slot attribute), with a
	short white flash so it reads. Only while ObbyLook.isInside. The server sees the jump back (ObbyService `resets`:
	it counts the fall and opens the anti-cheat's server-move window) and moves the runner itself past a deeper
	backup depth. Never fires remotes. Call `tick` once a frame.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Constants = require(Shared:WaitForChild("Constants"))
local ObbyCourse = require(Shared:WaitForChild("ObbyCourse"))
local ObbyLook = require(Visuals:WaitForChild("ObbyLook"))
local WorldLayout = require(Visuals:WaitForChild("WorldLayout"))

local ObbyFall = {}

ObbyFall.COOLDOWN = 0.5 -- seconds before another reset (the new position must reach the server first)
ObbyFall.FLASH_BRIGHTNESS = 0.45 -- ColorCorrection brightness at the start of the flash
ObbyFall.FLASH_SECONDS = 0.35
ObbyFall.FLASH_NAME = "ObbyFallFlash"

export type Controller = { tick: () -> (), stop: () -> () }

function ObbyFall.start(): Controller
	local origin, yaw = WorldLayout.obbyFrame()
	local frame: ObbyCourse.Frame = { origin = origin, yaw = yaw }
	local course: ObbyCourse.Course? = nil
	local readyAt = 0
	local flash: ColorCorrectionEffect? = nil
	local tween: Tween? = nil

	local function currentCourse(): ObbyCourse.Course?
		local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
		local model = folder and folder:FindFirstChild(Constants.OBBY_COURSE)
		local slot = model and model:GetAttribute("Slot")
		if type(slot) ~= "number" then
			return nil
		end
		if not course or course.slot ~= slot then
			course = ObbyCourse.build(slot)
		end
		return course
	end

	local function playFlash()
		if not flash or flash.Parent ~= Lighting then
			local effect = Instance.new("ColorCorrectionEffect")
			effect.Name = ObbyFall.FLASH_NAME
			effect.Brightness = 0
			effect.Parent = Lighting
			flash = effect
		end
		local effect = flash :: ColorCorrectionEffect
		if tween then
			tween:Cancel()
		end
		effect.Brightness = ObbyFall.FLASH_BRIGHTNESS
		local t = TweenService:Create(
			effect,
			TweenInfo.new(ObbyFall.FLASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }
		)
		t:Play()
		tween = t
	end

	local function tick()
		if not ObbyLook.isInside() then
			return
		end
		local now = os.clock()
		if now < readyAt then
			return
		end
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid or humanoid.Health <= 0 then
			return
		end
		local c = currentCourse()
		if not c then
			return
		end
		local pos = root.Position
		local p = ObbyCourse.toLocal(frame, { pos.X, pos.Y, pos.Z })
		if p[2] >= ObbyCourse.fallHeight(c, p) then
			return
		end
		readyAt = now + ObbyFall.COOLDOWN
		local at = ObbyCourse.toWorld(frame, c.start)
		local a = math.rad(frame.yaw)
		local start = Vector3.new(at[1], at[2], at[3])
		character:PivotTo(CFrame.lookAt(start, start + Vector3.new(math.sin(a), 0, math.cos(a))))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid:ChangeState(Enum.HumanoidStateType.Landed)
		playFlash()
	end

	return {
		tick = tick,
		stop = function()
			if tween then
				tween:Cancel()
			end
			if flash then
				flash:Destroy()
				flash = nil
			end
			course = nil
		end,
	}
end

return ObbyFall
