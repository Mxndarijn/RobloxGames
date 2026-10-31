--!strict
--[[
	MemberTags (client, contract/exclusive-shop.md §13)

	The VIP and Slime Club tags: a small chip over each member's head and a tag in front of their chat name, from the
	Player attribute `Member` (Constants.MEMBER_ATTRIBUTE: "vip" / "club", set by the server). Cosmetic only.

	Pure helpers (`look`, `chatPrefix`) are tested under Lune (tests/ui/MemberTags.spec.luau). `start` builds the
	chips (in PlayerGui, Adornee = the head, so nothing in the shared world changes) and sets
	TextChatService.OnIncomingMessage; it returns a stop function.

	The chip is a pixel tag (guides/roblox-world-labels.md), marked with LabelFit so it shrinks on a phone. Its Ink
	outline is on the pill's edge, not round the Ink letters, which would run them together.
]]

local LabelFit =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Lib"):WaitForChild("ui"):WaitForChild("LabelFit"))
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local MemberTags = {}

MemberTags.FOLDER = "MemberTags"
MemberTags.SIZE = table.freeze({ w = 100, h = 38, textSize = 30, stroke = 2.5, lift = 3.1, maxDistance = 80 })

export type Look = { text: string, color: Color3, hex: string }

local function hexOf(c: Color3): string
	local function byte(v: number): number
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("%02X%02X%02X", byte(c.R), byte(c.G), byte(c.B))
end

local LOOKS: { [string]: Look } = {
	vip = { text = "VIP", color = Theme.Gold, hex = hexOf(Theme.Gold) },
	club = { text = "CLUB", color = Theme.Plum, hex = hexOf(Theme.Plum) },
}

-- The tag of a `Member` attribute value, or nil (not a member, junk).
function MemberTags.look(member: any): Look?
	return if type(member) == "string" then LOOKS[member] else nil
end

-- The chat name prefix for a `Member` value: "<font color=...>[VIP]</font> ", or "" for none.
function MemberTags.chatPrefix(member: any): string
	local look = MemberTags.look(member)
	if not look then
		return ""
	end
	return `<font color="#{look.hex}">[{look.text}]</font> `
end

-- opts: Players, TextChatService (nil = no chat tags), attribute (Constants.MEMBER_ATTRIBUTE), playerGui.
function MemberTags.start(opts: { [string]: any }): () -> ()
	local Players = opts.Players
	local attribute: string = opts.attribute
	local folder = create("Folder", { Name = MemberTags.FOLDER, Parent = opts.playerGui })
	local conns: { RBXScriptConnection } = {}
	local chips: { [Player]: BillboardGui } = {}

	local function refresh(player: Player)
		local look = MemberTags.look(player:GetAttribute(attribute))
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local chip = chips[player]
		if not look or not head then
			if chip then
				chip:Destroy()
				chips[player] = nil
			end
			return
		end
		if not chip then
			local size = MemberTags.SIZE
			chip = create("BillboardGui", {
				Name = `Member_{player.UserId}`,
				Size = UDim2.fromOffset(size.w, size.h),
				StudsOffset = Vector3.new(0, size.lift, 0),
				MaxDistance = size.maxDistance,
				AlwaysOnTop = false,
				ResetOnSpawn = false,
				Parent = folder,
			}) :: BillboardGui
			local label = create("TextLabel", {
				Name = "Tag",
				Size = UDim2.fromScale(1, 1),
				Font = Theme.Font,
				TextSize = size.textSize,
				TextColor3 = Theme.Ink,
				Parent = chip,
			})
			Widgets.corner(size.h // 2).Parent = label
			create("UIStroke", {
				Color = Theme.Ink,
				Thickness = size.stroke,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Parent = label,
			})
			LabelFit.mark(chip :: BillboardGui) -- smaller pixels on a phone (Lib.ui.LabelFitView)
			chips[player] = chip
		end
		local label = (chip :: BillboardGui):FindFirstChild("Tag") :: TextLabel
		label.Text = look.text
		label.BackgroundColor3 = look.color;
		(chip :: BillboardGui).Adornee = head :: BasePart
	end

	local function watch(player: Player)
		table.insert(
			conns,
			player:GetAttributeChangedSignal(attribute):Connect(function()
				refresh(player)
			end)
		)
		table.insert(
			conns,
			player.CharacterAdded:Connect(function(character: Model)
				character:WaitForChild("Head", 10)
				refresh(player)
			end)
		)
		refresh(player)
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(conns, Players.PlayerAdded:Connect(watch))
	table.insert(
		conns,
		Players.PlayerRemoving:Connect(function(player: Player)
			local chip = chips[player]
			if chip then
				chip:Destroy()
				chips[player] = nil
			end
		end)
	)

	local chat = opts.TextChatService
	if chat then
		chat.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
			local source = message.TextSource
			local player = source and Players:GetPlayerByUserId(source.UserId)
			local prefix = if player then MemberTags.chatPrefix(player:GetAttribute(attribute)) else ""
			if prefix == "" then
				return nil
			end
			local props = Instance.new("TextChatMessageProperties")
			props.PrefixText = prefix .. message.PrefixText
			return props
		end
	end

	return function()
		for _, c in conns do
			c:Disconnect()
		end
		if chat then
			chat.OnIncomingMessage = nil :: any
		end
		folder:Destroy()
	end
end

return table.freeze(MemberTags)
