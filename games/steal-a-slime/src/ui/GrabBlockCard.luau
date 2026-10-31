--!strict
--[[
	GrabBlockCard

	When you can't grab a slime (GrabBlock: already carrying one, plot full, not enough money), its GrabPrompt
	shows why instead of a key: this client switches that prompt to the Custom style, so Roblox draws no "E"
	bubble, and draws a small Goo glass card with the slime's name and the reason while ProximityPromptService
	shows it. Once the reason goes away the prompt gets its Default style back.

	The card hangs under the slime, its top edge just below the Body: a wild slime's name tag (SlimeInfoCard) sits
	above the Body, so the two never cover each other.

	The Style switch is local only (the server never writes Style). Holding the key on a blocked prompt still reaches
	the server, which refuses it with the same reason as a toast.

	`reasonText` and `setStyle` work on mock prompts under Lune (tests/ui/GrabBlockCard.spec.luau); `start` returns
	{ refresh, stop }: refresh after each State, stop disconnects everything and removes the card.
]]

local UI = script.Parent
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GrabBlock = require(Shared:WaitForChild("GrabBlock"))
local LabelFit =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Lib"):WaitForChild("ui"):WaitForChild("LabelFit"))
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local GrabBlockCard = {}

GrabBlockCard.PROMPT_NAME = "GrabPrompt"
GrabBlockCard.CARD = table.freeze({
	w = 250,
	pad = 10,
	titleH = 24,
	titleSize = 18,
	reasonH = 22,
	reasonSize = 16,
	radius = 18,
	stroke = 3,
	drop = 0.3, -- studs between the slime's Body bottom and the card's top edge
	maxDistance = 40,
	bgTransparency = 0.06,
})

export type Styles = { blocked: any, normal: any } -- Enum.ProximityPromptStyle Custom / Default

-- What a GrabPrompt's slime is, from its model's attributes (WorldView.place).
function GrabBlockCard.target(prompt: Instance): GrabBlock.Target
	local body = prompt.Parent
	local model = body and body.Parent
	if not model then
		return { state = nil, price = nil, boss = false }
	end
	local price = model:GetAttribute("Price")
	return {
		state = model:GetAttribute("State") :: string?,
		price = if type(price) == "number" then price else nil,
		boss = model:GetAttribute(Constants.BOSS_ATTRIBUTE) == true,
		rebirths = model:GetAttribute(Constants.GRAB_REBIRTHS_ATTRIBUTE) :: number?,
	}
end

-- The reason text a GrabPrompt shows for `me` (nil = grabbable, or no State yet).
function GrabBlockCard.reasonText(prompt: any, me: GrabBlock.Me?): string?
	local target = GrabBlockCard.target(prompt)
	local reason = if me then GrabBlock.reason(me, target) else nil
	return if reason then GrabBlock.text(reason, target, me) else nil
end

-- Gives a prompt its blocked or normal style. A switch on an enabled prompt turns it off and on again so Roblox
-- shows it again in the new style.
function GrabBlockCard.setStyle(prompt: any, blocked: boolean, styles: Styles)
	local style = if blocked then styles.blocked else styles.normal
	if prompt.Style == style then
		return
	end
	prompt.Style = style
	if prompt.Enabled then
		prompt.Enabled = false
		prompt.Enabled = true
	end
end

-- Studs from the Body's centre to the card's top edge: below the Body, clear of the name tag above it.
function GrabBlockCard.offsetY(bodyHeight: number): number
	return -(bodyHeight / 2 + GrabBlockCard.CARD.drop)
end

export type Options = {
	root: Instance, -- where the slimes live (workspace)
	prompts: ProximityPromptService,
	playerGui: Instance,
	me: () -> GrabBlock.Me?, -- from the latest State; nil before the first one
}

function GrabBlockCard.start(opts: Options): { refresh: () -> (), stop: () -> () }
	local C = GrabBlockCard.CARD
	local styles: Styles = { blocked = Enum.ProximityPromptStyle.Custom, normal = Enum.ProximityPromptStyle.Default }

	local card = create("BillboardGui", {
		Name = "GrabBlockCard",
		Enabled = false,
		AlwaysOnTop = true,
		ResetOnSpawn = false,
		LightInfluence = 0,
		MaxDistance = C.maxDistance,
		SizeOffset = Vector2.new(0, -0.5), -- top edge on the offset point: the card hangs down from it
		Size = UDim2.fromOffset(C.w, C.pad * 2 + C.titleH + C.reasonH),
		Parent = opts.playerGui,
	}) :: BillboardGui
	LabelFit.mark(card) -- smaller pixels on a phone (Lib.ui.LabelFitView)
	local frame = create("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = C.bgTransparency,
		Size = UDim2.fromScale(1, 1),
		Parent = card,
	}, { Widgets.corner(C.radius) :: Instance, Widgets.stroke(Theme.Ink, C.stroke) })
	local title = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = C.titleSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(C.pad, C.pad),
		Size = UDim2.new(1, -C.pad * 2, 0, C.titleH),
		Parent = frame,
	})
	local reasonLabel = Widgets.label({
		Name = "Reason",
		TextSize = C.reasonSize,
		TextColor3 = Theme.Bad,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(C.pad, C.pad + C.titleH),
		Size = UDim2.new(1, -C.pad * 2, 0, C.reasonH),
		Parent = frame,
	})

	local reasons: { [ProximityPrompt]: string? } = {}
	local watched: { [ProximityPrompt]: { RBXScriptConnection } } = {}
	local shown: ProximityPrompt? = nil
	local conns: { RBXScriptConnection } = {}

	local function draw()
		local prompt = shown
		local text = if prompt then reasons[prompt] else nil
		local body = if prompt then prompt.Parent else nil
		if not prompt or not text or not body or not body:IsA("BasePart") then
			card.Enabled = false
			card.Adornee = nil :: any
			return
		end
		title.Text = prompt.ObjectText
		reasonLabel.Text = text
		local anchor = body:FindFirstChild(Constants.TAG_ANCHOR)
		card.Adornee = if anchor and anchor:IsA("Attachment") then anchor else body
		card.StudsOffsetWorldSpace = Vector3.new(0, GrabBlockCard.offsetY(body.Size.Y), 0)
		card.Enabled = true
	end

	local function update(prompt: ProximityPrompt)
		local text = GrabBlockCard.reasonText(prompt, opts.me())
		reasons[prompt] = text
		GrabBlockCard.setStyle(prompt, text ~= nil, styles)
		if prompt == shown then
			draw()
		end
	end

	local function isGrabPrompt(inst: Instance): boolean
		return inst.Name == GrabBlockCard.PROMPT_NAME and inst:IsA("ProximityPrompt")
	end

	local function watch(prompt: ProximityPrompt)
		if watched[prompt] then
			return
		end
		local list: { RBXScriptConnection } = {}
		local model = prompt.Parent and prompt.Parent.Parent
		if model then
			table.insert(
				list,
				model.AttributeChanged:Connect(function(name: string)
					if name == "Price" or name == "State" or name == Constants.BOSS_ATTRIBUTE then
						update(prompt)
					end
				end)
			)
		end
		table.insert(
			list,
			prompt.AncestryChanged:Connect(function()
				if prompt:IsDescendantOf(opts.root) then
					return
				end
				local mine = watched[prompt]
				if mine then
					for _, c in mine do
						c:Disconnect()
					end
				end
				watched[prompt] = nil
				reasons[prompt] = nil
				if shown == prompt then
					shown = nil
					draw()
				end
			end)
		)
		watched[prompt] = list
		update(prompt)
	end

	for _, inst in opts.root:GetDescendants() do
		if isGrabPrompt(inst) then
			watch(inst :: ProximityPrompt)
		end
	end
	table.insert(
		conns,
		opts.root.DescendantAdded:Connect(function(inst: Instance)
			if isGrabPrompt(inst) then
				watch(inst :: ProximityPrompt)
			end
		end)
	)
	table.insert(
		conns,
		opts.prompts.PromptShown:Connect(function(prompt: ProximityPrompt)
			if isGrabPrompt(prompt) and reasons[prompt] then
				shown = prompt
				draw()
			end
		end)
	)
	table.insert(
		conns,
		opts.prompts.PromptHidden:Connect(function(prompt: ProximityPrompt)
			if prompt == shown then
				shown = nil
				draw()
			end
		end)
	)

	local function refresh()
		for prompt in watched do
			update(prompt)
		end
	end

	local function stop()
		for _, c in conns do
			c:Disconnect()
		end
		for _, list in watched do
			for _, c in list do
				c:Disconnect()
			end
		end
		table.clear(watched)
		card:Destroy()
	end

	return { refresh = refresh, stop = stop }
end

return GrabBlockCard
