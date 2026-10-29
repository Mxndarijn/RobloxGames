--!strict
--[[
	MemberChatTags (Roblox adapter, contract/exclusive-shop.md §13)

	The [VIP] / [CLUB] tag in front of a member's name in the legacy chat (TextChatService.ChatVersion =
	LegacyChatService): the Lua Chat System's speaker extra data "Tags", from the Player attribute `Member`
	(Constants.MEMBER_ATTRIBUTE). With the new TextChatService the client's ui/MemberTags adds the prefix instead,
	and this does nothing. Holds no rules.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MemberChatTags = {}

-- Tag look per Member value (the client chip's colours: Widgets.Theme Gold / Plum).
MemberChatTags.TAGS = table.freeze({
	vip = { TagText = "VIP", TagColor = Color3.fromRGB(255, 204, 60) },
	club = { TagText = "CLUB", TagColor = Color3.fromRGB(196, 140, 220) },
})

-- Starts tagging (yields until the legacy chat's ChatService exists; returns at once without it).
function MemberChatTags.start()
	local runner = ServerScriptService:WaitForChild("ChatServiceRunner", 30)
	local module = runner and runner:WaitForChild("ChatService", 30)
	if not (module and module:IsA("ModuleScript")) then
		return
	end
	local ChatService = require(module) :: any

	local function apply(player: Player)
		local speaker = ChatService:GetSpeaker(player.Name)
		if not speaker then
			return
		end
		local tag = (MemberChatTags.TAGS :: any)[player:GetAttribute(Constants.MEMBER_ATTRIBUTE)]
		speaker:SetExtraData("Tags", if tag then { tag } else {})
	end

	local function watch(player: Player)
		player:GetAttributeChangedSignal(Constants.MEMBER_ATTRIBUTE):Connect(function()
			apply(player)
		end)
		apply(player)
	end

	ChatService.SpeakerAdded:Connect(function(name: string)
		local player = Players:FindFirstChild(name)
		if player and player:IsA("Player") then
			apply(player)
		end
	end)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return MemberChatTags
