--!strict
--[[
	Hint overlay: a pulsing gold ring round the button a tutorial step asks
	for, with a short bubble next to it (Hint.place). UI chrome only; the
	world arrow is Archer's TutorialArrow. Neither box is Active, so taps go
	through to the button underneath.
]]

local UI = script.Parent.Parent
local Hint = require(UI.Hint)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local HintOverlay = {}

function HintOverlay.new(parent: Instance)
	local ringStroke = Widgets.stroke(Theme.Gold, 3)
	local ring = create("Frame", {
		Name = "HintRing",
		Visible = false,
		Active = false,
		BackgroundTransparency = 1,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = parent,
	}, { Widgets.corner(12), ringStroke })

	local bubble = Widgets.label({
		Name = "HintBubble",
		Visible = false,
		Active = false,
		Font = Theme.Font,
		TextSize = Hint.TEXT_SIZE,
		TextColor3 = Color3.fromRGB(40, 30, 10),
		TextStrokeTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Gold,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = parent,
	})
	Widgets.corner(8).Parent = bubble
	create("UIPadding", {
		PaddingLeft = UDim.new(0, Hint.PAD_X),
		PaddingRight = UDim.new(0, Hint.PAD_X),
		Parent = bubble,
	})

	local placed = false
	local self = {}

	-- `placement` nil hides the hint.
	function self.set(placement: Hint.Placement?, text: string?)
		placed = placement ~= nil
		if placement == nil then
			ring.Visible = false
			bubble.Visible = false
			return
		end
		local r, b = placement.ring, placement.bubble
		ring.Position = UDim2.fromOffset(r.x, r.y)
		ring.Size = UDim2.fromOffset(r.w, r.h)
		bubble.Position = UDim2.fromOffset(b.x, b.y)
		bubble.Size = UDim2.fromOffset(b.w, b.h)
		bubble.Text = text or ""
	end

	-- `allowed` false (tutorial card hidden) hides it without forgetting it.
	function self.tick(now: number, allowed: boolean)
		local show = placed and allowed
		ring.Visible = show
		bubble.Visible = show
		if show then
			ringStroke.Transparency = 0.5 - 0.5 * math.cos(now * 2 * math.pi)
		end
	end

	return self
end

return HintOverlay
