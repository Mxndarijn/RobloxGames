--!strict
--[[
	ObbyWorld (VisualsClient module, contract/obby.md §5)

	Swaps the look while the local player is in the obby world: each frame (`tick`) it checks the local root against
	WorldLayout.inObbyWorld and moves ObbyLook's mix towards 1 inside, 0 outside (ObbyLook.FADE seconds for the full
	swap). NightSky re-blends Lighting and the Atmosphere on every mix change; this module tints its own
	ColorCorrection ("ObbyWorldTint", only while the mix is above 0), turns the place's Bloom and SunRays down and the
	Atmosphere Offset up by the mix (ObbyLook.BLOOM / SUN_RAYS / ATMOSPHERE) and builds the world's backdrop
	(ObbyBackdrop) on arrival, removing it once the look has faded out again. It also keeps ObbyLook's "inside" flag
	current, which the plot marker, the weather and the tutorial guide read. `start()` returns { tick, stop }.
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

-- Blends properties of one of the place's own Lighting children (Bloom, SunRays, Atmosphere) towards `target` by
-- mix. The place value is captured once into an attribute, so a blend never mistakes a half-faded value for the base.
local function blendEffect(className: string, target: { [string]: number }, mix: number)
	local effect: any = Lighting:FindFirstChildOfClass(className)
	if not effect then
		return
	end
	for key, value in target do
		local attribute = ObbyWorld.BASE_PREFIX .. key
		local base = effect:GetAttribute(attribute)
		if base == nil then
			base = effect[key]
			effect:SetAttribute(attribute, base)
		end
		effect[key] = base + (value - base) * mix
	end
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
	local white = Color3.new(1, 1, 1)

	local function paint(mix: number)
		blendEffect("BloomEffect", ObbyLook.BLOOM, mix)
		blendEffect("SunRaysEffect", ObbyLook.SUN_RAYS, mix)
		blendEffect("Atmosphere", ObbyLook.ATMOSPHERE, mix)
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
		cc.Contrast = t.Contrast * mix
	end

	local function tick(dt: number)
		local root = localRoot()
		local inside = false
		if root then
			local p = root.Position
			inside = WorldLayout.inObbyWorld({ p.X, p.Y, p.Z })
		end
		ObbyLook.setInside(inside)
		if inside and not backdrop then
			backdrop = ObbyBackdrop.build(workspace)
		end
		local mix = ObbyLook.get()
		local nextMix = ObbyLook.toward(mix, inside, dt)
		if nextMix <= 0 and backdrop then
			backdrop:Destroy()
			backdrop = nil
		end
		if nextMix ~= mix then
			ObbyLook.set(nextMix)
			paint(nextMix)
		end
	end

	local function stop()
		ObbyLook.setInside(false)
		ObbyLook.set(0)
		paint(0)
		if backdrop then
			backdrop:Destroy()
			backdrop = nil
		end
	end

	return { tick = tick, stop = stop }
end

return ObbyWorld
