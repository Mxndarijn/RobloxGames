--!strict
--[[
	ObbyWorld (VisualsClient module, contract/obby.md §5)

	Swaps the look while the local player is in the obby world: each frame (`tick`) it checks the local root against
	WorldLayout.inObbyWorld and moves ObbyLook's mix towards 1 inside, 0 outside (ObbyLook.FADE seconds for the full
	swap). NightSky re-blends Lighting and the Atmosphere on every mix change; this module tints its own
	ColorCorrection ("ObbyWorldTint", only while the mix is above 0). `start()` returns { tick, stop }.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local ObbyLook = require(Visuals:WaitForChild("ObbyLook"))
local WorldLayout = require(Visuals:WaitForChild("WorldLayout"))

local ObbyWorld = {}

ObbyWorld.TINT_NAME = "ObbyWorldTint"

export type Controller = { tick: (dt: number) -> (), stop: () -> () }

local function localRoot(): BasePart?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function ObbyWorld.start(): Controller
	local tint: ColorCorrectionEffect? = nil
	local white = Color3.new(1, 1, 1)

	local function paint(mix: number)
		if mix <= 0 then
			if tint then
				tint:Destroy()
				tint = nil
			end
			return
		end
		local cc: ColorCorrectionEffect
		if tint then
			cc = tint
		else
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = ObbyWorld.TINT_NAME
			cc.Parent = Lighting
			tint = cc
		end
		local t = ObbyLook.TINT
		cc.TintColor = white:Lerp(t.TintColor, mix)
		cc.Saturation = t.Saturation * mix
		cc.Brightness = t.Brightness * mix
	end

	local function tick(dt: number)
		local root = localRoot()
		local inside = false
		if root then
			local p = root.Position
			inside = WorldLayout.inObbyWorld({ p.X, p.Y, p.Z })
		end
		local mix = ObbyLook.get()
		local nextMix = ObbyLook.toward(mix, inside, dt)
		if nextMix ~= mix then
			ObbyLook.set(nextMix)
			paint(nextMix)
		end
	end

	local function stop()
		ObbyLook.set(0)
		paint(0)
	end

	return { tick = tick, stop = stop }
end

return ObbyWorld
