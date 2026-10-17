--!strict
--[[
	Sound panel (FEATURES.Audio): a small menu card opened from the last nav
	button (Icons.SOUND_ON / SOUND_OFF). A big mute toggle and a Music and an
	SFX slider (5% steps, mouse or touch drag). The values live in the
	SoundController (player attributes); this card only reads and sets them.
]]

local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent
local AudioLogic = require(UI.AudioLogic)
local Icons = require(UI.Icons)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Sound = {}

-- Body rows top to bottom (design px; the body is Layout.panelBody of the
-- Sound card, MENU_HEIGHTS.Sound tall). Slider row = name line + touch track.
Sound.ROWS = table.freeze({
	mute = { y = 0, h = Layout.BUTTON },
	music = { y = 68, h = 60 },
	sfx = { y = 136, h = 60 },
})
Sound.NAME_H = 24
Sound.TRACK_Y = 28
Sound.TRACK_H = 32
Sound.CONTENT_H = 196 -- sfx.y + sfx.h
Sound.TITLE = "Sound"
Sound.SLIDERS = table.freeze({
	table.freeze({ kind = "music", text = "🎵 Music", row = "music" }),
	table.freeze({ kind = "sfx", text = "🔔 SFX", row = "sfx" }),
})

function Sound.muteText(muted: boolean): string
	return if muted then `{Icons.SOUND_OFF} Muted` else `{Icons.SOUND_ON} Sound on`
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function Sound.new(parent: Instance, controller: any)
	local panel = Widgets.panel(parent, "SoundPanel", Sound.TITLE, Icons.SOUND_ON, Color3.fromRGB(80, 170, 230))
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		CanvasSize = UDim2.fromOffset(0, Sound.CONTENT_H),
		Parent = panel.body,
	})

	local mute = Widgets.button(
		{
			Name = "Mute",
			TextSize = 22,
			Position = UDim2.fromOffset(0, Sound.ROWS.mute.y),
			Size = UDim2.new(1, 0, 0, Sound.ROWS.mute.h),
		},
		Theme.Good,
		function()
			controller.setMuted(not controller.settings().muted)
			controller.play("click")
		end
	)
	mute.instance.Parent = content

	local refreshers: { () -> () } = {}
	local dragging: { [string]: boolean } = {}
	for _, def in Sound.SLIDERS do
		local kind = def.kind :: "music" | "sfx"
		local rowDef = (Sound.ROWS :: any)[def.row]
		local row = create("Frame", {
			Name = def.row,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, rowDef.y),
			Size = UDim2.new(1, 0, 0, rowDef.h),
			Parent = content,
		})
		Widgets.label({
			Name = "Name",
			Text = def.text,
			Font = Theme.Font,
			TextSize = 18,
			Size = UDim2.new(0.7, 0, 0, Sound.NAME_H),
			Parent = row,
		})
		local pct = Widgets.label({
			Name = "Percent",
			Font = Theme.Font,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.7, 0),
			Size = UDim2.new(0.3, 0, 0, Sound.NAME_H),
			Parent = row,
		})
		local track = create("TextButton", {
			Name = "Track",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, Sound.TRACK_Y),
			Size = UDim2.new(1, 0, 0, Sound.TRACK_H),
			Parent = row,
		}) :: TextButton
		local bar, setFill = Widgets.bar(track, Theme.Accent, UDim2.new(1, 0, 0, 12), UDim2.new(0, 0, 0.5, -6))
		bar.BackgroundColor3 = Theme.Row
		local function refresh()
			local v = controller.settings()[kind]
			setFill(AudioLogic.volumeToAlpha(v))
			pct.Text = AudioLogic.percentText(v)
		end
		table.insert(refreshers, refresh)
		local function setFromX(x: number)
			local v = AudioLogic.volumeFromPixel(x, track.AbsolutePosition.X, track.AbsoluteSize.X)
			if v ~= controller.settings()[kind] then
				controller.setVolume(kind, v)
			end
		end
		track.InputBegan:Connect(function(input: InputObject)
			if isPress(input) then
				dragging[kind] = true
				setFromX(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if
				dragging[kind]
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				setFromX(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if isPress(input) and dragging[kind] then
				dragging[kind] = false
				controller.play("click")
			end
		end)
	end

	local self = { frame = panel.frame, close = panel.close }

	-- Called by init.client on every settings change (and once at build).
	function self.refresh()
		local muted = controller.settings().muted
		mute.setText(Sound.muteText(muted))
		mute.setColor(if muted then Theme.Bad else Theme.Good)
		panel.icon.Text = if muted then Icons.SOUND_OFF else Icons.SOUND_ON
		for _, r in refreshers do
			r()
		end
	end
	self.refresh()
	return self
end

return Sound
