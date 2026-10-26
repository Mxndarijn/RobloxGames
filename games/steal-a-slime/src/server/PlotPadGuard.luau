--!strict
--[[
	PlotPadGuard

	The pure range check behind the owner-only plot pad prompts (LockPrompt, BuyPadPrompt, MergePrompt) and the HUD Lock
	button while standing at the pad. These are measured against the plot's own prompt part, never against a world shop
	stand (the shop gate only covers the shop purchases). Holds no state and no Roblox APIs; the adapter measures
	`access` (distance from the HumanoidRootPart to the prompt's part, and whether the character is alive).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")

export type Access = { distance: number?, alive: boolean? } -- distance nil = no character / no prompt part

local PlotPadGuard = {}

-- The pad actions behind those prompts (the vat prompt only opens the owner's menu, so it runs none).
PlotPadGuard.KINDS = table.freeze({ Lock = true, BuyPad = true, ToggleFriends = true })

PlotPadGuard.MESSAGES = table.freeze({
	NoCharacter = "walk closer to your lock pad",
	Dead = "you can't do that right now",
	OutOfRange = "walk closer to your lock pad",
})

-- Studs from the prompt part within which the owner may use the pad: the prompt's own activation distance plus slack.
function PlotPadGuard.range(): number
	return Config.PLOT_PAD_PROMPT_DISTANCE + Config.PLOT_PAD_RANGE_SLACK
end

-- nil when the owner may use the pad, else the deny code (NoCharacter, Dead, OutOfRange); exactly the range counts.
function PlotPadGuard.check(access: Access?, range: number?): string?
	if not access or type(access.distance) ~= "number" or access.distance ~= access.distance then
		return "NoCharacter"
	end
	if access.alive == false then
		return "Dead"
	end
	if access.distance > (range or PlotPadGuard.range()) then
		return "OutOfRange"
	end
	return nil
end

return PlotPadGuard
