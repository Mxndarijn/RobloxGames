--!strict
--[[
	Sound panel (FEATURES.Audio): a small menu card opened from the speaker
	icon in the top-right slot (Icons.SOUND_ON / SOUND_OFF; init.client). A big mute toggle and a Music and an
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

type Screen = Layout.Screen

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
-- Compact card (phone landscape, where the full card would sit on the bottom
-- cards): Mute | Music | SFX side by side in one row.
Sound.COMPACT_H = 60
Sound.COMPACT_MIN_W = 480
Sound.COMPACT_GAP = 12
Sound.TITLE = "Sound"
Sound.SLIDERS = table.freeze({
	table.freeze({ kind = "music", text = "🎵 Music", row = "music" }),
	table.freeze({ kind = "sfx", text = "🔔 SFX", row = "sfx" }),
})

type Rect = Layout.Rect

-- The card is compact when it was squeezed below its full height and is wide
-- enough for three columns.
function Sound.isCompact(card: Rect): boolean
	return card.w >= Sound.COMPACT_MIN_W and card.h < Layout.cardHeight(Sound.CONTENT_H)
end

-- Mute / Music / SFX boxes in body coordinates for a body `bodyW` wide.
function Sound.rowRects(bodyW: number, compact: boolean): { mute: Rect, music: Rect, sfx: Rect }
	if not compact then
		local rows = Sound.ROWS
		return {
			mute = Layout.rect(0, rows.mute.y, bodyW, rows.mute.h),
			music = Layout.rect(0, rows.music.y, bodyW, rows.music.h),
			sfx = Layout.rect(0, rows.sfx.y, bodyW, rows.sfx.h),
		}
	end
	local gap = Sound.COMPACT_GAP
	local w = (bodyW - gap * 2) / 3
	local h = Sound.COMPACT_H
	return {
		mute = Layout.rect(0, 0, w, h),
		music = Layout.rect(w + gap, 0, w, h),
		sfx = Layout.rect((w + gap) * 2, 0, w, h),
	}
end

-- Card height around the one-row body (no CARD_MIN floor: the row is the content).
function Sound.compactCardH(): number
	local c = Layout.PANEL_CHROME
	return c.header + Sound.COMPACT_H + c.pad
end

-- The Sound card on `screen`: the usual centred menu card, unless that sits on
-- the carry card (phone landscape). Then it moves to the top of the backdrop
-- and ends above it (ceiling = its top - GAP); wide cards use the one-row
-- layout (compact), never shorter than compactCardH.
function Sound.place(screen: Screen): (Rect, boolean)
	local r = Layout.panelFor(screen, "Sound", Sound.CONTENT_H)
	local ceiling = math.huge
	for _, other in { screen.carry } do
		if Layout.overlaps(r, other) then
			ceiling = math.min(ceiling, other.y - Layout.GAP)
		end
	end
	if ceiling < math.huge then
		local top = screen.panel.y
		local h = math.min(r.h, ceiling - top)
		if r.w >= Sound.COMPACT_MIN_W then
			h = Sound.compactCardH()
		end
		r = Layout.rect(r.x, top, r.w, math.max(h, 0))
	end
	return r, Sound.isCompact(r)
end

function Sound.muteText(muted: boolean): string
	return if muted then `{Icons.SOUND_OFF} Muted` else `{Icons.SOUND_ON} Sound on`
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function Sound.new(parent: Instance, controller: any)
	local panel = Widgets.panel(parent, "SoundPanel", "Sound", Icons.SOUND_ON)
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
		end
	)
	mute.instance.Parent = content

	local rowFrames: { [string]: Frame } = {}
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
		rowFrames[def.row] = row
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

	-- Called by init.client with the card rect (Sound.place): full rows, or the compact one-row layout.
	function self.layout(r: Rect)
		local compact = Sound.isCompact(r)
		local rects = Sound.rowRects(Layout.panelBody(r).w, compact)
		content.CanvasSize = UDim2.fromOffset(0, if compact then Sound.COMPACT_H else Sound.CONTENT_H)
		local function put(inst: GuiObject, b: Rect)
			inst.Position = UDim2.fromOffset(b.x, b.y)
			inst.Size = UDim2.fromOffset(b.w, b.h)
		end
		put(mute.instance, rects.mute)
		put(rowFrames.music, rects.music)
		put(rowFrames.sfx, rects.sfx)
	end
	self.refresh()
	return self
end

return Sound
