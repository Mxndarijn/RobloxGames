--!strict
--[[
	Settings panel: the menu card opened from the gear in the top-right slot (no nav tile). Tabs Sound, Game,
	Visuals and Me (PlayerSettings.TABS); it opens on Sound. Each row is one setting: an On / Off switch, a
	choice switch (Low / Full) or, for Music and Effects volume, a slider (5 % steps, mouse or touch drag).
	Every control reads and writes through the SettingsController (`ctx.settings`), which mirrors the values onto
	player attributes and sends them to the server; this card never calls a remote for a setting.

	Extra rows: Game has "Replay tutorial" (Request ReplayTutorial, off while the tutorial runs) and Me has the
	game version with the player's id, for support, and "Reset settings" (hold to confirm).
]]

local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent
local AudioLogic = require(UI.AudioLogic)
local Icons = require(UI.Icons)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Settings = {}

Settings.STYLE = table.freeze({
	tabH = 40,
	tabGap = 6,
	tabSize = 18,
	listY = 50,
	listGap = 6,
	rowH = 62,
	sliderH = 70,
	rowPad = 12,
	icon = 30,
	iconSize = 24,
	nameSize = 18,
	nameY = 9,
	nameH = 22,
	hintSize = Layout.MIN_TEXT,
	hintY = 32,
	hintH = 18,
	toggleW = 84,
	choiceW = 76,
	btnH = 40,
	btnSize = 17,
	btnGap = 6,
	trackY = 38,
	trackH = 26,
	bar = 12,
	percentW = 64,
	actionW = 120,
	holdW = 150,
	scrollBar = 10,
})

Settings.COPY = table.freeze({
	on = "On",
	off = "Off",
	replay = "Replay tutorial",
	replayHint = "Walk through the first steps again",
	replayButton = "Replay",
	replayRunning = "Running",
	version = "Game version",
	reset = "Reset settings",
	resetHint = "Your slimes and cash stay",
	resetButton = "Hold to reset",
})

-- The version row's text: the place version and the player's id, so a bug report says which build it was.
function Settings.versionText(placeVersion: number?, userId: number?): (string, string)
	local version = if type(placeVersion) == "number" and placeVersion > 0 then `v{placeVersion}` else "Studio"
	return version, `Player ID {userId or 0}`
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function Settings.new(parent: Instance, ctx: any)
	local S = Settings.STYLE
	local PlayerSettings = ctx.PlayerSettings
	local controller = ctx.settings
	local panel = Widgets.panel(parent, "SettingsPanel", "Settings", Icons.SETTINGS)
	local c = Layout.PANEL_CHROME
	local fullH = Layout.menuHeight("Settings") - c.header - c.pad
	-- As tall as a full menu body, so init.client (Widgets.contentHeight) sizes this list menu to fill the window.
	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Layout.MENU_WIDTH, fullH),
		Parent = panel.body,
	})

	local self: any = { frame = panel.frame, close = panel.close }
	local tab = PlayerSettings.TABS[1].key
	local tabButtons: { [string]: any } = {}
	local lists: { [string]: ScrollingFrame } = {}
	local refreshers: { () -> () } = {}
	local tutorialRunning = false
	local replayButton: any = nil

	local function rowFrame(list: Instance, name: string, order: number, h: number): Frame
		return Widgets.rowFrame({
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, -S.scrollBar, 0, h),
			Parent = list,
		})
	end

	-- Icon, name and the hint line; `right` is the width kept free for the controls.
	local function texts(frame: Frame, icon: string, name: string, hint: string?, right: number)
		local iconLabel = Widgets.label({
			Name = "Icon",
			Text = icon,
			TextSize = S.iconSize,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(S.rowPad, 0),
			Size = UDim2.fromOffset(S.icon, S.rowH),
			Parent = frame,
		})
		Widgets.centreEmoji(iconLabel)
		local x = S.rowPad + S.icon + 8
		Widgets.label({
			Name = "Name",
			Text = name,
			Font = Theme.Font,
			TextSize = S.nameSize,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(x, if hint then S.nameY else (S.rowH - S.nameH) // 2),
			Size = UDim2.new(1, -(x + right), 0, S.nameH),
			Parent = frame,
		})
		if hint then
			Widgets.label({
				Name = "Hint",
				Text = hint,
				TextSize = S.hintSize,
				TextColor3 = Theme.Muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(x, S.hintY),
				Size = UDim2.new(1, -(x + right), 0, S.hintH),
				Parent = frame,
			})
		end
	end

	local function control(props: { [string]: any }, color: Color3, onClick: () -> ()): any
		local base = {
			TextSize = S.btnSize,
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(S.toggleW, S.btnH),
		}
		for k, v in props do
			base[k] = v
		end
		return Widgets.button(base, color, onClick)
	end

	local function toggleRow(list: Instance, entry: any, order: number)
		local frame = rowFrame(list, entry.id, order, S.rowH)
		texts(frame, entry.icon, entry.name, entry.hint, S.rowPad + S.toggleW + S.btnGap)
		local button = control({ Name = "Toggle", Position = UDim2.new(1, -S.rowPad, 0.5, 0) }, Theme.Row, function()
			controller.set(entry.id, not controller.get(entry.id))
		end)
		button.instance.Parent = frame
		table.insert(refreshers, function()
			local on = controller.get(entry.id) == true
			button.setText(if on then Settings.COPY.on else Settings.COPY.off)
			button.setColor(if on then Theme.Accent else Theme.Row)
		end)
	end

	local function choiceRow(list: Instance, entry: any, order: number)
		local def = PlayerSettings.schema.byId[entry.id]
		local choices: { string } = def.choices
		local labels: { string } = entry.labels or choices
		local width = #choices * S.choiceW + (#choices - 1) * S.btnGap
		local frame = rowFrame(list, entry.id, order, S.rowH)
		texts(frame, entry.icon, entry.name, entry.hint, S.rowPad + width + S.btnGap)
		local buttons: { any } = {}
		for i, choice in choices do
			local right = S.rowPad + (#choices - i) * (S.choiceW + S.btnGap)
			local button = control(
				{
					Name = `Choice_{choice}`,
					Text = labels[i] or choice,
					Position = UDim2.new(1, -right, 0.5, 0),
					Size = UDim2.fromOffset(S.choiceW, S.btnH),
				},
				Theme.Row,
				function()
					controller.set(entry.id, choice)
				end
			)
			button.instance.Parent = frame
			buttons[i] = button
		end
		table.insert(refreshers, function()
			local value = controller.get(entry.id)
			for i, choice in choices do
				buttons[i].setColor(if value == choice then Theme.Accent else Theme.Row)
			end
		end)
	end

	local function sliderRow(list: Instance, entry: any, order: number)
		local frame = rowFrame(list, entry.id, order, S.sliderH)
		texts(frame, entry.icon, entry.name, nil, S.rowPad + S.percentW)
		-- The name sits on the top line of a slider row, the track under it.
		local name = frame:FindFirstChild("Name") :: TextLabel
		name.Position = UDim2.fromOffset(name.Position.X.Offset, S.nameY)
		local iconLabel = frame:FindFirstChild("Icon") :: TextLabel
		iconLabel.Size = UDim2.fromOffset(S.icon, S.nameH + S.nameY * 2)
		local pct = Widgets.label({
			Name = "Percent",
			Font = Theme.Font,
			TextSize = S.nameSize,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S.rowPad, 0, S.nameY),
			Size = UDim2.fromOffset(S.percentW, S.nameH),
			Parent = frame,
		})
		local x = S.rowPad + S.icon + 8
		local track = create("TextButton", {
			Name = "Track",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(x, S.trackY),
			Size = UDim2.new(1, -(x + S.rowPad), 0, S.trackH),
			Parent = frame,
		}) :: TextButton
		local bar, setFill =
			Widgets.bar(track, Theme.Accent, UDim2.new(1, 0, 0, S.bar), UDim2.new(0, 0, 0.5, -S.bar / 2))
		bar.BackgroundColor3 = Theme.Bg
		table.insert(refreshers, function()
			local v = controller.get(entry.id)
			setFill(AudioLogic.volumeToAlpha(v))
			pct.Text = AudioLogic.percentText(v)
		end)
		local dragging = false
		local function setFromX(px: number)
			local v = AudioLogic.volumeFromPixel(px, track.AbsolutePosition.X, track.AbsoluteSize.X)
			if v ~= controller.get(entry.id) then
				controller.set(entry.id, v)
			end
		end
		track.InputBegan:Connect(function(input: InputObject)
			if isPress(input) then
				dragging = true
				setFromX(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if
				dragging
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				setFromX(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if isPress(input) then
				dragging = false
			end
		end)
	end

	local function actionRow(
		list: Instance,
		name: string,
		order: number,
		icon: string,
		title: string,
		hint: string?,
		width: number
	): Frame
		local frame = rowFrame(list, name, order, S.rowH)
		texts(frame, icon, title, hint, S.rowPad + width + S.btnGap)
		return frame
	end

	local function extraRows(key: string, list: Instance, order: number)
		if key == "game" then
			local frame = actionRow(
				list,
				"replayTutorial",
				order,
				"🎓",
				Settings.COPY.replay,
				Settings.COPY.replayHint,
				S.actionW
			)
			replayButton = control(
				{
					Name = "Replay",
					Text = Settings.COPY.replayButton,
					Position = UDim2.new(1, -S.rowPad, 0.5, 0),
					Size = UDim2.fromOffset(S.actionW, S.btnH),
				},
				Theme.Info,
				function()
					if ctx.request then
						ctx.request("ReplayTutorial", function() end)
					end
				end
			)
			replayButton.instance.Parent = frame
		elseif key == "me" then
			local version, id = Settings.versionText(ctx.placeVersion, ctx.userId)
			local frame = actionRow(list, "version", order, "📦", Settings.COPY.version, id, S.actionW)
			Widgets.status({
				Name = "Version",
				Text = version,
				TextSize = S.btnSize,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -S.rowPad, 0.5, 0),
				Size = UDim2.fromOffset(S.actionW, S.btnH),
				Parent = frame,
			})
			local resetFrame =
				actionRow(list, "reset", order + 1, "🔄", Settings.COPY.reset, Settings.COPY.resetHint, S.holdW)
			local reset = Widgets.holdButton(
				{
					Name = "Reset",
					Text = Settings.COPY.resetButton,
					TextSize = S.btnSize,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -S.rowPad, 0.5, 0),
					Size = UDim2.fromOffset(S.holdW, S.btnH),
				},
				Theme.Bad,
				function()
					controller.reset()
				end,
				ctx.Config.HOLD_CONFIRM_SECONDS
			)
			reset.instance.Parent = resetFrame
		end
	end

	for _, def in PlayerSettings.TABS do
		local list = Widgets.scrollList({
			Name = `List_{def.key}`,
			Position = UDim2.fromOffset(0, S.listY),
			Size = UDim2.new(1, 0, 0, fullH - S.listY),
			Visible = def.key == tab,
			Parent = content,
		}, S.listGap)
		lists[def.key] = list
		for i, entry in def.entries do
			local kind = PlayerSettings.schema.byId[entry.id].kind
			if kind == "slider" then
				sliderRow(list, entry, i)
			elseif kind == "choice" then
				choiceRow(list, entry, i)
			else
				toggleRow(list, entry, i)
			end
		end
		extraRows(def.key, list, #def.entries + 1)
		Widgets.restack(list)
	end

	local function selectTab(key: string)
		if not lists[key] then
			return
		end
		tab = key
		for k, list in lists do
			list.Visible = k == key
			if k == key then
				list.CanvasPosition = Vector2.zero
			end
		end
		for k, b in tabButtons do
			b.setColor(if k == key then Theme.Accent else Theme.Row)
		end
	end

	local tabX = 0
	for _, def in PlayerSettings.TABS do
		local w =
			math.floor((Layout.MENU_WIDTH - c.pad * 2 - S.tabGap * (#PlayerSettings.TABS - 1)) / #PlayerSettings.TABS)
		local btn = Widgets.button(
			{
				Name = `Tab_{def.key}`,
				Text = `{def.icon} {def.label}`,
				TextSize = S.tabSize,
				Position = UDim2.fromOffset(tabX, 0),
				Size = UDim2.fromOffset(w, S.tabH),
			},
			Theme.Row,
			function()
				selectTab(def.key)
			end
		)
		btn.instance.Parent = content
		tabButtons[def.key] = btn
		tabX += w + S.tabGap
	end
	selectTab(tab)

	-- Called by init.client when any setting changed (and once at build).
	function self.refresh()
		for _, fn in refreshers do
			fn()
		end
		panel.icon.Text = Icons.SETTINGS
	end

	function self.update(state: any)
		tutorialRunning = type(state) == "table" and type(state.tutorialStepId) == "string"
		if replayButton then
			replayButton.setEnabled(not tutorialRunning)
			replayButton.setText(if tutorialRunning then Settings.COPY.replayRunning else Settings.COPY.replayButton)
		end
	end

	function self.layout(r: Layout.Rect)
		local body = Layout.panelBody(r)
		local w, h = math.floor(body.w), math.floor(body.h)
		content.Size = UDim2.fromOffset(w, fullH)
		local tabW = math.floor((w - S.tabGap * (#PlayerSettings.TABS - 1)) / #PlayerSettings.TABS)
		for i, def in PlayerSettings.TABS do
			local b = tabButtons[def.key].instance
			b.Position = UDim2.fromOffset((i - 1) * (tabW + S.tabGap), 0)
			b.Size = UDim2.fromOffset(tabW, S.tabH)
		end
		for _, list in lists do
			list.Size = UDim2.fromOffset(w, math.max(S.rowH, h - S.listY))
		end
	end

	-- The open tab (tests), and switching to one.
	function self.tab(): string
		return tab
	end
	function self.showTab(key: string)
		selectTab(key)
	end

	self.refresh()
	return self
end

return Settings
