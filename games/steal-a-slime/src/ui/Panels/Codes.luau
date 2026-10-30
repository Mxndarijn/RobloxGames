--!strict
--[[
	Codes panel: a small card to redeem a code. An ink-dark text box, one Redeem button (Enter
	works too), a chip for the active income boost (State.codes) and a line on what codes give.
	The server decides (Codes.redeem): a good code shows in the boost chip and the box clears once
	State.codes.redeemed grows; a refused one keeps the text, turns the box's outline pink and shows
	the server's reason in a pink line under it until the box is edited again. The line pushes the rows
	under the box down and the card grows to fit (ctx.relayout), so nothing scrolls or gets cut off.
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

-- Body rows top to bottom (design px; the body is Layout.panelBody of the Codes card).
Codes.ROWS = table.freeze({
	input = { y = 0, h = 56, size = 22, pad = 14 },
	error = { y = 62, h = 18, size = Layout.MIN_TEXT }, -- under the box, only after a refused code
	button = { y = 68, h = Layout.BUTTON, size = 22 },
	boost = { y = 136, h = 28, size = 14 },
	note = { y = 172, h = 18, size = Layout.MIN_TEXT },
})
Codes.CONTENT_H = 190 -- note.y + note.h
Codes.BOOST_ICON = 22 -- potion icon at the left end of the boost chip
Codes.CHIP_PAD = 10 -- Widgets.chip's side padding
Codes.NO_BOOST = "No boost active"
Codes.NOTE = "Each code works once and gives cash or a boost."
Codes.ERROR_SHIFT = 26 -- how far the rows under the box move down while the error line shows

-- The pink line under the box for a refused code: the server's reason as a sentence.
function Codes.errorText(result: any): string
	local message = if type(result) == "table" and type(result.message) == "string" then result.message else ""
	if message == "" then
		return "That code doesn't work."
	end
	return if string.match(message, "[%.!?]$") then message else message .. "."
end

function Codes.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "CodesPanel", "Codes", "🎁")
	local rows = Codes.ROWS
	-- Scrolls only when the card is shorter than the content (landscape
	-- phones); a fixed canvas, nothing in it moves.
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		CanvasSize = UDim2.fromOffset(0, Codes.CONTENT_H),
		Parent = panel.body,
	})

	local box = create("TextBox", {
		Name = "CodeBox",
		Text = "",
		PlaceholderText = "Type a code",
		PlaceholderColor3 = Theme.Muted,
		ClearTextOnFocus = false,
		Font = Theme.Font,
		TextSize = rows.input.size,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Theme.Ink,
		Position = UDim2.fromOffset(0, rows.input.y),
		Size = UDim2.new(1, 0, 0, rows.input.h),
		Parent = content,
	}, {
		Widgets.corner(Widgets.KIT.radius),
		Widgets.stroke(Theme.Ink, Widgets.KIT.stroke),
		Widgets.padding(rows.input.pad),
	}) :: TextBox

	local boxStroke = box:FindFirstChildOfClass("UIStroke") :: UIStroke
	-- The error line, made the first time a code is refused; the rows under the box move down while it shows.
	local errorLine: TextLabel? = nil
	local moved: { GuiObject } = {}
	local function showError(text: string?)
		local shown = text ~= nil
		if shown and errorLine == nil then
			errorLine = Widgets.label({
				Name = "Error",
				TextSize = rows.error.size,
				TextColor3 = Theme.Bad,
				Position = UDim2.fromOffset(rows.input.pad, rows.error.y), -- in line with the code box's text
				Size = UDim2.new(1, -rows.input.pad * 2, 0, rows.error.h),
				Parent = content,
			})
		end
		local line = errorLine
		if line == nil or (line.Visible == shown and line.Text == (text or "")) then
			return
		end
		line.Visible = shown
		line.Text = text or ""
		boxStroke.Color = if shown then Theme.Bad else Theme.Ink
		local shift = if shown then Codes.ERROR_SHIFT else 0
		for _, item in moved do
			item.Position = UDim2.new(item.Position.X, UDim.new(0, (item:GetAttribute("RowY") :: number) + shift))
		end
		content.CanvasSize = UDim2.fromOffset(0, Codes.CONTENT_H + shift)
		-- The card is sized to the content: measure it again now, not at the next State push.
		if ctx.relayout then
			ctx.relayout()
		end
	end
	-- Clicking back into the box to fix the code, or the box clearing after a good one, drops the error.
	box.Focused:Connect(function()
		showError(nil)
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		showError(nil)
	end)

	local function submit()
		local text = string.gsub(box.Text, "^%s+", "")
		text = string.gsub(text, "%s+$", "")
		if #text == 0 then
			return
		end
		if ctx.ask then
			ctx.ask("Redeem", function(result: any)
				if type(result) == "table" and result.ok == false then
					showError(Codes.errorText(result))
				else
					showError(nil)
				end
			end, text)
		else
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
		Text = "Redeem",
		TextSize = rows.button.size,
		Position = UDim2.fromOffset(0, rows.button.y),
		Size = UDim2.new(1, 0, 0, rows.button.h),
	}, Theme.Good, submit)
	redeem.instance.Parent = content

	local boost = Widgets.chip({
		Name = "Boost",
		Text = Codes.NO_BOOST,
		TextSize = rows.boost.size,
		TextColor3 = Theme.Muted,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, rows.boost.y),
		Size = UDim2.fromOffset(0, rows.boost.h),
		Parent = content,
	})
	local boostPad = boost:FindFirstChildOfClass("UIPadding") :: UIPadding
	-- The active boost shows its potion icon at the left end of the chip, in the chip's left padding.
	local boostIcon = ItemIconView.new({
		Name = "BoostIcon",
		Id = "Boost_Code",
		Size = Codes.BOOST_ICON,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -(Codes.BOOST_ICON + Codes.CHIP_PAD / 2), 0.5, 0),
		Parent = boost,
	}, ItemIcons.of(ctx))
	boostIcon.instance.Visible = false

	local note = Widgets.label({
		Name = "Note",
		Text = Codes.NOTE,
		TextSize = rows.note.size,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, rows.note.y),
		Size = UDim2.new(1, 0, 0, rows.note.h),
		Parent = content,
	})

	for _, item in { redeem.instance, boost, note } :: { GuiObject } do
		item:SetAttribute("RowY", item.Position.Y.Offset)
		table.insert(moved, item)
	end

	local self = { frame = panel.frame, close = panel.close }
	local last: any = nil
	local redeemedCount: number? = nil

	local function renderBoost(now: number)
		local info = if last then last.codes else nil
		local left = if info and info.boostMult > 1 then Format.remainingSeconds(info.boostEndsAt, now) else 0
		local active = left > 0
		if active then
			boost.Text = `{Format.formatMultiplier(info.boostMult)} income · {Format.formatDuration(left)} left`
		else
			boost.Text = Codes.NO_BOOST
		end
		boost.TextColor3 = if active then Theme.Gold else Theme.Muted
		boostIcon.instance.Visible = active
		boostPad.PaddingLeft =
			UDim.new(0, if active then Codes.CHIP_PAD + Codes.BOOST_ICON + Codes.CHIP_PAD / 2 else Codes.CHIP_PAD)
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
