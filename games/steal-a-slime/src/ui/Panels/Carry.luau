--!strict
--[[
	Carry overlay (bottom centre) while state.carrying is set: slime, kind,
	Drop -> Request("Drop"). There is no time limit on a carry.

	Thieves are hit with the default Bat Tool (server/BatTool), not a button here.
]]

local UI = script.Parent.Parent
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Carry = {}

function Carry.new(parent: Instance, ctx: any)
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
	}, { Widgets.corner(Layout.NOTICE_RADIUS) })
	-- A notice: the Gold info ring while you carry a wild slime, the danger ring for a stolen one.
	local border = Widgets.ring(frame, Theme.Gold, Layout.NOTICE_RADIUS)

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

	local carrying: any = nil

	local self = {}

	-- Bottom card box from Layout.screen (above phone touch controls).
	function self.layout(screen: Layout.Screen)
		frame.AnchorPoint = Vector2.zero
		frame.Position = UDim2.fromOffset(screen.carry.x, screen.carry.y)
		frame.Size = UDim2.fromOffset(screen.carry.w, screen.carry.h)
	end

	function self.update(state: any)
		carrying = state.carrying
		frame.Visible = carrying ~= nil
		if carrying then
			local slime = carrying.slime
			swatch.BackgroundColor3 = Widgets.color3(slime.color)
			name.Text = ctx.Genome.displayName(slime)
			local stolen = carrying.kind == "stolen"
			border.Color = if stolen then Theme.Bad else Theme.Gold
			sub.Text = if stolen then "Bring the slime to your plot!" else "Wild slime - bring it to your plot"
			sub.TextColor3 = if stolen then Theme.Warn else Theme.Muted
		end
	end

	return self
end

return Carry
