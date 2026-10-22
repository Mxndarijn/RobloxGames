--!strict
-- Runner for PromptHide (CONTRACT §5.2, §8.4): hides GrabPrompts whose
-- HideFromUserId is this player, so owners never see "Steal" on their own
-- slimes, owner-only plot prompts whose ShowOnlyToUserId is someone else, and a
-- locked base's Steal prompts for everyone its GuestsOnly list leaves out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local PromptHide = require(script.Parent:WaitForChild("PromptHide"))

PromptHide.start({
	root = workspace,
	localUserId = Players.LocalPlayer.UserId,
	attribute = Constants.PROMPT_HIDE_ATTRIBUTE,
	ownerAttribute = Constants.PROMPT_OWNER_ATTRIBUTE,
	guestsAttribute = Constants.PROMPT_GUESTS_ATTRIBUTE,
})
