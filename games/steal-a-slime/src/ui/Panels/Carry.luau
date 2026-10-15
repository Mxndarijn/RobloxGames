--!strict
--[[
	Carry overlay (bottom centre) while state.carrying is set: slime, kind,
	escape countdown for stolen slimes, Drop -> Request("Drop").

	Also a Slap button when another player who is carrying (Player attribute
	`Carrying`, CONTRACT §5.2) is within SLAP_REACH of our character. The
	server re-checks reach and decides the outcome.
]]

local Players = game:GetService("Players")

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Layout = require(UI.Layout)
local Selection = require(UI.Selection)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Carry = {}

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function Carry.new(parent: Instance, ctx: any)
	local border = Widgets.stroke(Theme.Warn, 2)
	local frame = create("Frame", {
		Name = "CarryOverlay",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(420, 96),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		ZIndex = Layout.ZINDEX.Carry, -- above the tutorial card: Drop stays clickable
		Parent = parent,
	}, { Widgets.corner(12), border })

	local swatch = create("Frame", {
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.fromOffset(12, 12),
		Parent = frame,
	}, { Widgets.corner(24) })
	local name = Widgets.label({
		Font = Theme.Font,
		TextSize = 18,
		Size = UDim2.new(1, -Layout.CARRY_TEXT_RESERVE, 0, 22),
		Position = UDim2.fromOffset(70, 10),
		Parent = frame,
	})
	local sub = Widgets.label({
		TextSize = 14,
		TextColor3 = Theme.Muted,
		TextWrapped = true, -- two lines on a phone-width card
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -Layout.CARRY_TEXT_RESERVE, 0, 36),
		Position = UDim2.fromOffset(70, 34),
		Parent = frame,
	})
	local _, setBar = Widgets.bar(frame, Theme.Bad, UDim2.new(1, -24, 0, 10), UDim2.new(0, 12, 1, -22))

	local drop = Widgets.button(
		{
			Name = "Drop",
			Text = "Drop",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(100, Layout.BUTTON),
		},
		Theme.Bad,
		function()
			ctx.send("Drop")
		end
	)
	drop.instance.Parent = frame

	local slapTarget: number? = nil
	local slap = Widgets.button(
		{
			Name = "Slap",
			Text = "SLAP!",
			Visible = false,
			TextScaled = true, -- long display names shrink instead of overflowing
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -130),
			Size = UDim2.fromOffset(Layout.SLAP.w, Layout.SLAP.h),
			ZIndex = Layout.ZINDEX.Carry,
		},
		Theme.Warn,
		function()
			if slapTarget then
				ctx.send("Slap", slapTarget)
			end
		end
	)
	slap.instance.TextColor3 = Color3.fromRGB(40, 25, 5)
	create("UITextSizeConstraint", { MaxTextSize = 22, Parent = slap.instance })
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = slap.instance,
	})
	slap.instance.Parent = parent

	local carrying: any = nil
	local myStolen: { [number]: boolean } = {}

	local self = {}

	-- Bottom card + Slap boxes from Layout.screen (above phone touch controls).
	function self.layout(screen: Layout.Screen)
		frame.AnchorPoint = Vector2.zero
		frame.Position = UDim2.fromOffset(screen.carry.x, screen.carry.y)
		frame.Size = UDim2.fromOffset(screen.carry.w, screen.carry.h)
		slap.instance.AnchorPoint = Vector2.zero
		slap.instance.Position = UDim2.fromOffset(screen.slap.x, screen.slap.y)
		slap.instance.Size = UDim2.fromOffset(screen.slap.w, screen.slap.h)
	end

	function self.update(state: any)
		carrying = state.carrying
		table.clear(myStolen)
		for _, view in state.slimes do
			if view.stolenBy ~= nil then
				myStolen[view.stolenBy] = true
			end
		end
		frame.Visible = carrying ~= nil
		if carrying then
			local slime = carrying.slime
			swatch.BackgroundColor3 = Widgets.color3(slime.color)
			name.Text = ctx.Genome.displayName(slime)
			border.Color = if carrying.kind == "stolen" then Theme.Bad else Theme.Warn
		end
		self.tick(ctx.serverNow())
	end

	local function updateSlap()
		local me = Players.LocalPlayer
		local myPos = rootPosition(me)
		local candidates = {}
		if myPos and carrying == nil then
			for _, other in Players:GetPlayers() do
				if other ~= me and other:GetAttribute("Carrying") ~= nil then
					local pos = rootPosition(other)
					if pos then
						table.insert(candidates, { userId = other.UserId, distance = (pos - myPos).Magnitude })
					end
				end
			end
		end
		slapTarget = Selection.pickSlapTarget(candidates, ctx.Config.SLAP_REACH, me.UserId)
		slap.instance.Visible = slapTarget ~= nil
		if slapTarget then
			slap.setText(
				if myStolen[slapTarget]
					then `SLAP {ctx.playerName(slapTarget)}!\nSave your slime`
					else `SLAP {ctx.playerName(slapTarget)}!`
			)
		end
	end

	function self.tick(now: number)
		updateSlap()
		if carrying == nil then
			return
		end
		if carrying.kind == "stolen" and carrying.escapeAt then
			local left = Format.remainingSeconds(carrying.escapeAt, now)
			sub.Text = `STOLEN - escapes in {Format.formatDuration(left)}! Run home!`
			sub.TextColor3 = if left < 5 then Theme.Bad else Theme.Warn
			setBar(1 - Format.progress(carrying.startedAt, carrying.escapeAt, now))
		else
			sub.Text = "Wild slime - bring it to your plot"
			sub.TextColor3 = Theme.Muted
			setBar(1)
		end
	end

	return self
end

return Carry
