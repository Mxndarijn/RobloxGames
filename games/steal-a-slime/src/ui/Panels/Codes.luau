--!strict
--[[
	Codes panel (v29): a small card to redeem a code. A gift badge and a text
	box, one Redeem button (Enter works too), a line for the active income
	boost (State.codes) and a hint of what codes give. The server decides
	(Codes.redeem); its result comes back as a toast. The typed text stays
	after a failed try (typo?) and clears once State.codes.redeemed grows.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Codes = {}

-- Body rows top to bottom (design px; the body is Layout.panelBody of the
-- Codes card, MENU_HEIGHTS.Codes tall).
Codes.ROWS = table.freeze({
	input = { y = 0, h = 64 }, -- gift badge + text box
	button = { y = 76, h = Layout.BUTTON },
	boost = { y = 144, h = 40 },
	note = { y = 192, h = 18 },
})
Codes.BADGE = 64
Codes.CONTENT_H = 210 -- note.y + note.h
Codes.NO_BOOST = "No boost active"

function Codes.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "CodesPanel", "Codes", "🎁", Color3.fromRGB(190, 90, 200))
	local rows = Codes.ROWS
	-- Scrolls only when the card is shorter than the content (landscape
	-- phones); a fixed canvas, nothing in it moves.
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		CanvasSize = UDim2.fromOffset(0, Codes.CONTENT_H),
		Parent = panel.body,
	})

	ItemIconView.new({
		Name = "Gift",
		Id = "Gift",
		Size = Codes.BADGE,
		Position = UDim2.fromOffset(0, rows.input.y),
		Parent = content,
	}, ItemIcons.of(ctx)).setActive(true)

	local box = create("TextBox", {
		Name = "CodeBox",
		Text = "",
		PlaceholderText = "Type a code",
		PlaceholderColor3 = Theme.Muted,
		ClearTextOnFocus = false,
		Font = Theme.Font,
		TextSize = 22,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Theme.Row,
		Position = UDim2.fromOffset(Codes.BADGE + 12, rows.input.y),
		Size = UDim2.new(1, -(Codes.BADGE + 12), 0, rows.input.h),
		Parent = content,
	}, { Widgets.corner(12), Widgets.stroke(Color3.fromRGB(70, 75, 100), 2), Widgets.padding(12) }) :: TextBox

	local function submit()
		local text = string.gsub(box.Text, "^%s+", "")
		text = string.gsub(text, "%s+$", "")
		if #text > 0 then
			ctx.send("Redeem", text)
		end
	end
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submit()
		end
	end)

	local redeem = Widgets.button({
		Name = "RedeemButton",
		Text = "🎁 Redeem",
		TextSize = 20,
		Position = UDim2.fromOffset(0, rows.button.y),
		Size = UDim2.new(1, 0, 0, rows.button.h),
	}, Theme.Good, submit)
	redeem.instance.Parent = content

	local boost = Widgets.label({
		Name = "Boost",
		Font = Theme.Font,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.BgLight,
		Text = Codes.NO_BOOST,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(0, rows.boost.y),
		Size = UDim2.new(1, 0, 0, rows.boost.h),
		Parent = content,
	})
	Widgets.corner(10).Parent = boost
	-- The active boost shows its potion icon at the left end of the chip.
	local boostIcon = ItemIconView.new({
		Name = "BoostIcon",
		Id = "Boost_Code",
		Size = rows.boost.h - 8,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		ZIndex = 2,
		Parent = boost,
	}, ItemIcons.of(ctx))
	boostIcon.instance.Visible = false

	Widgets.label({
		Name = "Note",
		Text = "Codes give 💰 cash or ⚡ boosts. One use each.",
		TextSize = 13,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, rows.note.y),
		Size = UDim2.new(1, 0, 0, rows.note.h),
		Parent = content,
	})

	local self = { frame = panel.frame, close = panel.close }
	local last: any = nil
	local redeemedCount: number? = nil

	local function renderBoost(now: number)
		local info = if last then last.codes else nil
		local left = if info and info.boostMult > 1 then Format.remainingSeconds(info.boostEndsAt, now) else 0
		if left > 0 then
			boost.Text = `⚡ {Format.formatMultiplier(info.boostMult)} income · {Format.formatDuration(left)} left`
			boost.TextColor3 = Theme.Gold
			boostIcon.instance.Visible = true
		else
			boostIcon.instance.Visible = false
			boost.Text = Codes.NO_BOOST
			boost.TextColor3 = Theme.Muted
		end
	end

	function self.update(state: any)
		last = state
		local info = state.codes
		if type(info) == "table" and type(info.redeemed) == "number" then
			if redeemedCount ~= nil and info.redeemed > redeemedCount then
				box.Text = ""
			end
			redeemedCount = info.redeemed
		end
		renderBoost(ctx.serverNow())
	end

	-- Local countdown between State pushes.
	function self.tick(now: number)
		if panel.frame.Visible then
			renderBoost(now)
		end
	end

	return self
end

return Codes
