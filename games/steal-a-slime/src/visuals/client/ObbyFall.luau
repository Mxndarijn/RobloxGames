--!strict
--[[
	ObbyFall (VisualsClient module, contract/obby.md §3, contract/obby-sections.md §5 and §7)

	No checkpoints: a fall or a hazard goes straight back to the start pad. The local player owns their character's
	physics, so `ObbyFall.reset(reason)` puts them back on the start pad at once, with a short white flash so it
	reads. `tick` calls it with "fall" the frame their root drops Config.OBBY.FALL_DEPTH under the lowest platform they
	could still land on (ObbyCourse.fallHeight, from the course rebuilt here from workspace.Obby.Course's Slot
	attribute), only while ObbyLook.isInside. ObbyFx calls it with "hazard" when the player touches red goo.

	Before the jump back, every `onReset` listener runs (in the order they were added): ObbyMoves ends its character
	controllers there, ObbyFx clears the player's clocks, keys, melted tiles and collapsed pieces. So nothing a
	controller set (WalkSpeed, gravity, PlatformStand, camera) is still on when the player lands on the start pad.

	The server sees the jump back (ObbyService `resets`: it counts the fall and opens the anti-cheat's server-move
	window) and moves the runner itself past a deeper backup depth. Never fires remotes. Call `tick` once a frame.
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
export type Reason = string -- "fall" | "hazard" | any other caller's name

type Listener = { fn: (reason: Reason) -> () }

local listeners: { Listener } = {}
local readyAt = 0
-- The running controller's jump back to the start pad (nil until `start`, and after `stop`).
local putBack: (() -> boolean)? = nil

-- Calls `fn(reason)` on every reset, before the player is moved. Returns a function that removes it again.
function ObbyFall.onReset(fn: (reason: Reason) -> ()): () -> ()
	local entry: Listener = { fn = fn }
	table.insert(listeners, entry)
	return function()
		local i = table.find(listeners, entry)
		if i then
			table.remove(listeners, i)
		end
	end
end

-- Sends the local player back to the start pad: ends every controller and clears the per-player course state
-- (the onReset listeners) first, then moves them and flashes. False (and nothing happens) during the cooldown
-- after the last reset, or when there is no character or course to put back on.
function ObbyFall.reset(reason: Reason): boolean
	local now = os.clock()
	if now < readyAt or putBack == nil then
		return false
	end
	readyAt = now + ObbyFall.COOLDOWN
	-- A copy, so a listener that removes itself does not skip the next one.
	for _, entry in table.clone(listeners) do
		local ok, err = pcall(function()
			entry.fn(reason)
		end)
		if not ok then
			warn(`[ObbyFall] reset listener failed: {err}`)
		end
	end
	return (putBack :: () -> boolean)()
end

function ObbyFall.start(): Controller
	local origin, yaw = WorldLayout.obbyFrame()
	local frame: ObbyCourse.Frame = { origin = origin, yaw = yaw }
	local course: ObbyCourse.Course? = nil
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

	-- The local character, when it is alive.
	local function body(): (Model?, BasePart?, Humanoid?)
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid or humanoid.Health <= 0 then
			return nil, nil, nil
		end
		return character, root, humanoid
	end

	putBack = function(): boolean
		local character, root, humanoid = body()
		local c = currentCourse()
		if not character or not root or not humanoid or not c then
			return false
		end
		local at = ObbyCourse.toWorld(frame, c.start)
		local a = math.rad(frame.yaw)
		local start = Vector3.new(at[1], at[2], at[3])
		character:PivotTo(CFrame.lookAt(start, start + Vector3.new(math.sin(a), 0, math.cos(a))))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid:ChangeState(Enum.HumanoidStateType.Landed)
		playFlash()
		return true
	end

	local function tick()
		if not ObbyLook.isInside() or os.clock() < readyAt then
			return
		end
		local _, root = body()
		if not root then
			return
		end
		local c = currentCourse()
		if not c then
			return
		end
		local pos = root.Position
		local p = ObbyCourse.toLocal(frame, { pos.X, pos.Y, pos.Z })
		if p[2] < ObbyCourse.fallHeight(c, p) then
			ObbyFall.reset("fall")
		end
	end

	return {
		tick = tick,
		stop = function()
			putBack = nil
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
