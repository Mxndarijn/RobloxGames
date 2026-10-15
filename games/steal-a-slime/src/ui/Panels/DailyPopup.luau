--!strict
--[[
	Daily reward popup: a centred modal with the streak track, today's
	amount and Claim (`Request("Daily")`). Opens by itself when a claim
	becomes available and the tutorial is done (PopupQueue, init.client) and
	from the HUD Daily button. Once the
	server reports it claimed, it shows "Come back tomorrow" and closes.
]]

local UI = script.Parent.Parent
local Daily = require(UI.Daily)
local Format = require(UI.Format)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local CELL_COLORS = {
	claimed = Theme.Good,
	today = Theme.Gold,
	upcoming = Theme.BgLight,
}

local DailyPopup = {}

function DailyPopup.new(parent: Instance, ctx: any)
	local cap: number = ctx.Config.DAILY_STREAK_CAP or 7

	local backdrop = create("TextButton", {
		Name = "DailyPopup",
		Visible = false,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Layout.ZINDEX.Daily, -- under the tutorial card (v15: it covered step 1)
		Parent = parent,
	})

	local card = create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.DAILY.w, Layout.DAILY.h),
		BackgroundColor3 = Theme.Bg,
		ZIndex = 21,
		Parent = backdrop,
	}, { Widgets.corner(14), Widgets.stroke(Theme.Gold, 3) })

	local function text(props: { [string]: any }): TextLabel
		props.ZIndex = 22
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
		props.Parent = card
		return Widgets.label(props)
	end

	text({
		Name = "Title",
		Text = "Daily Reward",
		Font = Theme.Font,
		TextSize = 24,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 12),
	})
	local streakLine = text({
		Name = "Streak",
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 46),
	})

	local track = create("Frame", {
		Name = "Track",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.new(1, -32, 0, 48),
		ZIndex = 22,
		Parent = card,
	}, { Widgets.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
	local cells: { TextLabel } = {}
	for day = 1, cap do
		local cell = Widgets.label({
			Name = `Day{day}`,
			LayoutOrder = day,
			Text = `Day\n{day}`,
			Font = Theme.Font,
			TextSize = 13,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.BgLight,
			Size = UDim2.fromOffset(46, 46),
			ZIndex = 23,
			Parent = track,
		})
		Widgets.corner(8).Parent = cell
		cells[day] = cell
	end

	local amount = text({
		Name = "Amount",
		Font = Theme.Font,
		TextSize = 36,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 136),
	})
	local hint = text({
		Name = "Hint",
		TextSize = 13,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 182),
		Text = "Come back every day to grow your streak.",
	})

	local claim = Widgets.button(
		{
			Name = "Claim",
			Text = "Claim!",
			TextSize = 20,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16),
			Size = UDim2.fromOffset(200, Layout.BUTTON),
			ZIndex = 22,
		},
		Theme.Gold,
		function()
			ctx.send("Daily")
		end
	)
	claim.instance.TextColor3 = Color3.fromRGB(40, 30, 10)
	claim.instance.Parent = card

	local self = { frame = backdrop }

	local close = Widgets.button(
		{
			Name = "Close",
			Text = "X",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 10),
			Size = UDim2.fromOffset(Layout.MIN_TOUCH_DESIGN, Layout.MIN_TOUCH_DESIGN),
			ZIndex = 22,
		},
		Theme.BgLight,
		function()
			self.close()
		end
	)
	close.instance.Parent = card

	local closeToken = 0

	function self.open()
		closeToken += 1
		backdrop.Visible = true
	end

	function self.close()
		closeToken += 1
		backdrop.Visible = false
	end

	-- Card size from Layout.screen (narrower on small screens).
	function self.layout(screen: Layout.Screen)
		card.Size = UDim2.fromOffset(screen.daily.w, screen.daily.h)
	end

	function self.isOpen(): boolean
		return backdrop.Visible
	end

	local wasAvailable: boolean? = nil

	function self.update(state: any)
		local daily = state.daily
		if type(daily) ~= "table" then
			return
		end
		local available = daily.available == true
		local day = Daily.dayOf(daily, ctx.Config.DAILY_BASE or 0, state.rebirthMultiplier or 1, cap)
		for _, c in Daily.track(day, cap, available) do
			local cell = cells[c.day]
			if cell then
				cell.BackgroundColor3 = CELL_COLORS[c.state]
				cell.TextColor3 = if c.state == "upcoming" then Theme.Muted else Color3.fromRGB(30, 30, 40)
			end
		end
		streakLine.Text = if available
			then `Day {day} of your streak`
			else `Streak: {daily.streak} day{if daily.streak == 1 then "" else "s"}`
		amount.Text = if available then `+{Format.formatCash(daily.amount)}` else "Claimed!"
		hint.Text = if available
			then "Come back every day to grow your streak."
			else "Come back tomorrow for the next reward."
		claim.setEnabled(available)
		claim.setText(if available then "Claim!" else "Claimed")

		if wasAvailable == true and not available and backdrop.Visible then
			-- Just claimed: let the "Claimed!" state show, then close.
			closeToken += 1
			local token = closeToken
			task.delay(1.5, function()
				if token == closeToken then
					backdrop.Visible = false
				end
			end)
		end
		wasAvailable = available
	end

	backdrop.Activated:Connect(function()
		self.close() -- click outside the card
	end)

	return self
end

return DailyPopup
