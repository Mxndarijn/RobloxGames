--!strict
--[[
	EffectsView (Roblox adapter)

	Archer's Effects module (ReplicatedStorage.Visuals.Effects, nil when Visuals is missing) and the targets its
	bursts play on: a World "Effect" event goes to the slime's Body (slimeId), the plot's MergeVat (plotIndex) or
	the player's root (userId), in that order (CONTRACT.md §5.4). The goo-drain splash (ParadeView) uses the
	same module. Bursts never block gameplay: Outbox calls these through safeCall.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParadeView = require(script.Parent.ParadeView)
local World = require(script.Parent.World)
local WorldView = require(script.Parent.WorldView)

export type EffectsView = {
	play: (event: World.Event) -> (),
	splash: () -> (),
}

local EffectsView = {}

local function loadEffects(): any
	local visuals = ReplicatedStorage:FindFirstChild("Visuals")
	local module = visuals and visuals:FindFirstChild("Effects")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		return if ok then result else nil
	end
	return nil
end

local function targetOf(event: World.Event): Instance?
	if event.slimeId then
		local body = WorldView.slimeBody(event.slimeId)
		if body then
			return body
		end
	end
	if event.plotIndex then
		local plot = WorldView.plot(event.plotIndex)
		local vat = plot and plot:FindFirstChild("MergeVat")
		if vat and vat:IsA("BasePart") then
			return vat
		end
	end
	return if event.userId then WorldView.rootPart(Players:GetPlayerByUserId(event.userId)) else nil
end

function EffectsView.new(): EffectsView
	local Effects = loadEffects()
	return {
		play = function(event: World.Event)
			if not Effects or not event.effect then
				return
			end
			local target = targetOf(event)
			if target then
				Effects.play(event.effect, target)
			end
		end,
		splash = function()
			ParadeView.splash(Effects)
		end,
	}
end

return EffectsView
