--!strict
--[[
	ObbyCourseView (VisualsClient module, contract/obby.md §5)

	The obby course is client-only, like its backdrop: the server publishes the slot standing now (Constants.OBBY_SLOT
	on workspace.Obby, server/ObbyView) and this builds that course (ObbyCourse.build, then visuals/shared/ObbyParts)
	as workspace.Obby.Course on this client, replacing the old one when the slot changes. The local character
	collides with it on this client; ObbyFx plays its moving parts and ObbyFall reads its Slot. Never fires remotes.
	Call `tick` once a frame, before ObbyFx.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Constants = require(Shared:WaitForChild("Constants"))
local ObbyCourse = require(Shared:WaitForChild("ObbyCourse"))
local ObbyParts = require(Visuals:WaitForChild("ObbyParts"))
local WorldLayout = require(Visuals:WaitForChild("WorldLayout"))

local ObbyCourseView = {}

export type Controller = { tick: () -> (), stop: () -> () }

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
		model = built
		builtSlot = slot
	end

	return { tick = tick, stop = clear }
end

return ObbyCourseView
