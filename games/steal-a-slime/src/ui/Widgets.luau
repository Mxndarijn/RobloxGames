--!strict
--[[
	Widgets

	Small Instance.new helpers and the UI theme. Only creates Instances when a
	function is called (nothing at require time).
]]

local Layout = require(script.Parent.Layout)

local Widgets = {}

-- The HUD's palette (Hud money block) for every panel: ink outlines, deep purple plates, gold money.
-- Button colours carry meaning: Gold collects a reward, Good spends cash, Info is a side action, Bad sells
-- or closes. Something you can't press yet is a sunken Ink well (Widgets.status / a disabled button).
Widgets.Theme = table.freeze({
	Ink = Color3.fromRGB(30, 18, 51), -- every outline, dark text on bright buttons, sunken wells
	Bg = Color3.fromRGB(43, 27, 77), -- panel body
	Row = Color3.fromRGB(59, 36, 102), -- rows and cards
	BgLight = Color3.fromRGB(76, 48, 130), -- highlighted rows, the header band's bottom
	Band = Color3.fromRGB(98, 68, 174), -- the header band's top, the corner icon tile
	Text = Color3.fromRGB(246, 241, 255),
	Muted = Color3.fromRGB(184, 166, 227),
	Accent = Color3.fromRGB(126, 217, 87),
	Good = Color3.fromRGB(126, 217, 87),
	Bad = Color3.fromRGB(238, 79, 99),
	Info = Color3.fromRGB(169, 139, 240),
	Warn = Color3.fromRGB(255, 190, 60),
	Disabled = Color3.fromRGB(30, 18, 51),
	Gold = Color3.fromRGB(255, 217, 59),
	Font = Enum.Font.FredokaOne,
	FontBody = Enum.Font.GothamMedium,
})

local Theme = Widgets.Theme

function Widgets.create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local create = Widgets.create

function Widgets.corner(radius: number?): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function Widgets.padding(px: number): UIPadding
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function Widgets.stroke(color: Color3?, thickness: number?): UIStroke
	return create("UIStroke", {
		Color = color or Theme.Ink,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Widgets.list(direction: Enum.FillDirection?, spacing: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
end

function Widgets.label(props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = Theme.Text,
		Font = Theme.FontBody,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 20),
	}
	for k, v in props do
		base[k] = v
	end
	return create("TextLabel", base)
end

export type Button = {
	instance: TextButton,
	setEnabled: (enabled: boolean) -> (),
	setText: (text: string) -> (),
	setColor: (color: Color3) -> (),
}

-- Chunky sizes shared by every panel part (design px).
Widgets.KIT = table.freeze({
	stroke = 3, -- ink outline on buttons, the panel and its tiles
	rowStroke = 2, -- ink outline on rows and cards
	radius = 13, -- buttons, wells, icon tiles
	rowRadius = 15,
	shadeBottom = 0.8, -- a button's bottom brightness under its top (the HUD chips' lip)
})

-- A top-light to bottom-dark UIGradient (the HUD chips' depth). A UIGradient multiplies the frame's own
-- colour, so the stops are grey brightness factors.
function Widgets.shade(parent: Instance, bottom: number?)
	local b = bottom or Widgets.KIT.shadeBottom
	create("UIGradient", {
		Name = "Shade",
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(b, b, b)),
		Parent = parent,
	})
end

-- True for fills bright enough to carry Ink text (gold, green, lilac); dark or saturated fills (red) get
-- white text with an ink stroke.
function Widgets.isBright(color: Color3): boolean
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B > 0.55
end

-- Text colours for a label on `fill`.
function Widgets.inkOn(label: TextLabel | TextButton, fill: Color3)
	if Widgets.isBright(fill) then
		label.TextColor3 = Theme.Ink
		label.TextStrokeTransparency = 1
	else
		label.TextColor3 = Theme.Text
		label.TextStrokeColor3 = Theme.Ink
		label.TextStrokeTransparency = 0
	end
end

-- A chunky TextButton: fill, ink outline, a darker bottom. Disabled it turns into a sunken Ink well with
-- muted text and no outline, so it never reads as pressable. Clicks while disabled are ignored.
function Widgets.button(props: { [string]: any }, color: Color3?, onClick: () -> ()): Button
	local kit = Widgets.KIT
	local baseColor = color or Theme.Info
	local enabled = true
	local base = {
		BackgroundColor3 = baseColor,
		Font = Theme.Font,
		TextSize = 17,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(90, 30),
	}
	for k, v in props do
		base[k] = v
	end
	local inst = create("TextButton", base, { Widgets.corner(kit.radius) }) :: TextButton
	local stroke = Widgets.stroke(Theme.Ink, kit.stroke)
	stroke.Parent = inst
	Widgets.shade(inst)
	Widgets.inkOn(inst, baseColor)
	inst.Activated:Connect(function()
		if enabled then
			onClick()
		end
	end)
	local self = {} :: Button
	self.instance = inst
	local function paint()
		inst.AutoButtonColor = enabled
		inst.BackgroundColor3 = if enabled then baseColor else Theme.Disabled
		stroke.Transparency = if enabled then 0 else 1
		if enabled then
			Widgets.inkOn(inst, baseColor)
		else
			inst.TextColor3 = Theme.Muted
			inst.TextStrokeTransparency = 1
		end
	end
	function self.setEnabled(value: boolean)
		enabled = value
		paint()
	end
	function self.setText(text: string)
		inst.Text = text
	end
	function self.setColor(c: Color3)
		baseColor = c
		paint()
	end
	return self
end

-- A sunken Ink well holding a state, not an action ("✓ Owned", "🔒 Rebirth 12", "Max"). Never pressable.
function Widgets.status(props: { [string]: any }): TextLabel
	local base = {
		Name = "Status",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Ink,
		Font = Theme.Font,
		TextSize = 15,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		TextWrapped = true,
	}
	for k, v in props do
		base[k] = v
	end
	local label = Widgets.label(base)
	Widgets.corner(Widgets.KIT.radius).Parent = label
	return label
end

-- A small Ink pill for a fact in a panel's top line ("3/8 pads", "$4.66B", "Resets in 3:05").
function Widgets.chip(props: { [string]: any }, color: Color3?): TextLabel
	local base = {
		Name = "Chip",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Ink,
		Font = Theme.Font,
		TextSize = 15,
		TextColor3 = color or Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
	}
	for k, v in props do
		base[k] = v
	end
	local label = Widgets.label(base)
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = label })
	create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = label })
	return label
end

-- A list row or card: Row fill, rounded, thin ink outline.
function Widgets.rowFrame(props: { [string]: any }): Frame
	local base = { BackgroundColor3 = Theme.Row, BorderSizePixel = 0 }
	for k, v in props do
		base[k] = v
	end
	return create("Frame", base, {
		Widgets.corner(Widgets.KIT.rowRadius),
		Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke),
	}) :: Frame
end

-- Hold progress 0..1 (pure; HoldButton drives it from os.clock).
function Widgets.holdProgress(startedAt: number, now: number, duration: number): number
	if duration <= 0 then
		return 1
	end
	return math.clamp((now - startedAt) / duration, 0, 1)
end

-- Studio hook (PcwHold): the fill shown for real progress `p` when a test asked to pause at `pauseAt`
-- (nil = no pause) and whether the hold is paused there (pure).
function Widgets.holdPause(p: number, pauseAt: number?): (number, boolean)
	if pauseAt and pauseAt < 1 and p >= pauseAt then
		return math.max(pauseAt, 0), true
	end
	return p, false
end

local HOLD_INPUTS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

--[[
	B1: a button that confirms only after being held `duration`
	(`duration`, ctx.Config.HOLD_CONFIRM_SECONDS). A white fill sweeps left to right under the text while the
	press is down; releasing or leaving the button early cancels. A plain tap
	does nothing. Used for every UI action that spends cash or changes ownership
	(Lock / Extend, Buy pad, Sell, Rebirth, shop Buy). The server still checks.
]]
function Widgets.holdButton(props: { [string]: any }, color: Color3?, onConfirm: () -> (), duration: number): Button
	local btn = Widgets.button(props, color, function() end)
	local inst = btn.instance
	inst:SetAttribute("HoldConfirm", duration)
	local fill = create("Frame", {
		Name = "HoldFill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Visible = false,
		ZIndex = inst.ZIndex + 1,
		Active = false,
		Parent = inst,
	}, { Widgets.corner(Widgets.KIT.radius) })
	local enabled = true
	local startedAt: number? = nil
	local conn: RBXScriptConnection? = nil
	local pauseAt: number? = nil -- Studio PcwHold hook only
	local function stop()
		startedAt = nil
		if conn then
			conn:Disconnect()
			conn = nil
		end
		fill.Visible = false
		fill.Size = UDim2.fromScale(0, 1)
	end
	local function start(display: boolean?)
		if (not enabled and not display) or startedAt then
			return
		end
		local began = os.clock()
		startedAt = began
		fill.Visible = true
		conn = game:GetService("RunService").RenderStepped:Connect(function()
			local p, paused = Widgets.holdPause(Widgets.holdProgress(began, os.clock(), duration), pauseAt)
			fill.Size = UDim2.fromScale(p, 1)
			if paused then
				-- held mid-way: stays pressed (startedAt set) with the fill frozen, never confirms
				if conn then
					conn:Disconnect()
					conn = nil
				end
			elseif p >= 1 then
				stop()
				onConfirm()
			end
		end)
	end
	inst.InputBegan:Connect(function(input: InputObject)
		if HOLD_INPUTS[input.UserInputType] or input.KeyCode == Enum.KeyCode.ButtonA then
			start()
		end
	end)
	inst.InputEnded:Connect(stop)
	inst.MouseLeave:Connect(stop)
	-- Studio-only test hook for the PC watcher: attribute "PcwHold" = fraction (0..1) starts the same hold
	-- routine a real press starts and pauses at that fill without confirming; nil/false releases it (stop).
	if game:GetService("RunService"):IsStudio() then
		inst:GetAttributeChangedSignal("PcwHold"):Connect(function()
			local v = inst:GetAttribute("PcwHold")
			stop()
			if type(v) == "number" then
				pauseAt = v
				start(true) -- display only: also on a disabled (unaffordable) button, which never confirms
			else
				pauseAt = nil
			end
		end)
	end
	local setEnabled = btn.setEnabled
	function btn.setEnabled(value: boolean)
		enabled = value
		if not value and not pauseAt then -- a PcwHold display hold survives the panel's state refresh
			stop()
		end
		setEnabled(value)
	end
	return btn
end

export type Panel = { frame: Frame, body: Frame, title: TextLabel, close: TextButton, icon: TextLabel }

-- A menu card (Layout.PANEL_CHROME), the same frame for every menu: a purple
-- header band with an ink rule under it, the menu's `icon` on a nav-style tile
-- poking up over the top-left corner, the title in chunky stroked type and the
-- red close "X" top-right; `body` fills the area under them. init.client sizes
-- the frame (Layout.panelFor) over the dimmed backdrop and wires `close` to
-- setOpen(nil).
function Widgets.panel(parent: Instance, name: string, titleText: string, icon: string?): Panel
	local c = Layout.PANEL_CHROME
	local kit = Widgets.KIT
	local radius = 20
	local frame = create("Frame", {
		Name = name,
		Visible = false, -- shown only by setOpen / the menu manager
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0,
		ZIndex = Layout.ZINDEX.Menu,
		Parent = parent,
	}, { Widgets.corner(radius), Widgets.stroke(Theme.Ink, kit.stroke) })
	-- The band: rounded on top, square at the bottom (a second, unrounded strip covers the lower corners).
	local bandH = c.header - c.bodyGap - kit.stroke
	local bandShade = 0.78 -- the band's bottom brightness; the square foot strip matches it
	local band = create("Frame", {
		Name = "Band",
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Band,
		Size = UDim2.new(1, 0, 0, bandH),
		Parent = frame,
	}, { Widgets.corner(radius) })
	Widgets.shade(band, bandShade)
	create("Frame", {
		Name = "BandFoot",
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Band:Lerp(Color3.new(0, 0, 0), 1 - bandShade),
		Size = UDim2.new(1, 0, 0, radius),
		Position = UDim2.fromOffset(0, bandH - radius),
		Parent = frame,
	})
	create("Frame", {
		Name = "BandRule",
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Ink,
		Size = UDim2.new(1, 0, 0, kit.stroke),
		Position = UDim2.fromOffset(0, bandH),
		Parent = frame,
	})
	local tile = create("Frame", {
		Name = "IconTile",
		BackgroundColor3 = Theme.Band,
		Size = UDim2.fromOffset(c.icon, c.icon),
		Position = UDim2.fromOffset(c.pad, -c.iconRise),
		Parent = frame,
	}, { Widgets.corner(17), Widgets.stroke(Theme.Ink, kit.stroke) })
	Widgets.shade(tile)
	local iconLabel = Widgets.label({
		Name = "Icon",
		Text = icon or "",
		TextSize = c.iconSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		Parent = tile,
	})
	local titleX = c.pad + c.icon + 10
	local title = Widgets.label({
		Name = "Title",
		Text = titleText,
		Font = Theme.Font,
		TextSize = c.titleSize,
		TextColor3 = Theme.Text,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		Size = UDim2.new(1, -(titleX + c.close + c.closeInset * 2), 0, c.close),
		Position = UDim2.fromOffset(titleX, c.closeInset),
		Parent = frame,
	})
	local close = create("TextButton", {
		Name = "Close",
		Text = "X",
		Font = Theme.Font,
		TextSize = 24,
		TextColor3 = Theme.Text,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		BackgroundColor3 = Theme.Bad,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -c.closeInset, 0, c.closeInset),
		Size = UDim2.fromOffset(c.close, c.close),
		ZIndex = 2,
		Parent = frame,
	}, { Widgets.corner(kit.radius), Widgets.stroke(Theme.Ink, kit.stroke) }) :: TextButton
	Widgets.shade(close)
	local body = create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -c.pad * 2, 1, -(c.header + c.pad)),
		Position = UDim2.fromOffset(c.pad, c.header),
		Parent = frame,
	})
	return { frame = frame, body = body, title = title, close = close, icon = iconLabel }
end

-- An emoji icon tile (shop items, rebirth rewards, goals): `size` square,
-- `color` fill, rounded with a thin ink outline.
function Widgets.iconBadge(props: { [string]: any }, icon: string, color: Color3, size: number): TextLabel
	local base = {
		Name = "Icon",
		Text = icon,
		TextSize = math.floor(size * 0.55),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(size, size),
	}
	for k, v in props do
		base[k] = v
	end
	local badge = Widgets.label(base)
	Widgets.corner(Widgets.KIT.radius).Parent = badge
	Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke).Parent = badge
	return badge
end

function Widgets.scroll(props: { [string]: any }): ScrollingFrame
	local base = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromScale(1, 1),
	}
	for k, v in props do
		base[k] = v
	end
	return create("ScrollingFrame", base)
end

-- Row gap of a scroll list (attribute on its ScrollingFrame).
local LIST_GAP = "ListGap"

-- A vertical scroll list: rows from the top (Layout.SCROLL_LIST) with edge
-- padding, so the first and last rows are never clipped. Returns the
-- ScrollingFrame; parent rows to it (fixed offset heights, no
-- AutomaticSize) and call Widgets.restack after changing them
-- (keyedList.sync does). No UIListLayout / UIPadding: see
-- Layout.SCROLL_LIST for why rows are placed explicitly.
function Widgets.scrollList(props: { [string]: any }, spacing: number?): ScrollingFrame
	local frame = Widgets.scroll(props)
	frame.AutomaticCanvasSize = Enum.AutomaticSize.None
	frame:SetAttribute(LIST_GAP, spacing or 6)
	Widgets.restack(frame)
	return frame
end

-- Places a scroll list's visible rows top to bottom by LayoutOrder (then
-- Name) at Layout.stackRows offsets and sets the canvas to fit them.
-- Neither depends on the list's AbsoluteSize, so a hidden list is laid out
-- the same as a shown one. No-op for anything but a Widgets.scrollList.
function Widgets.restack(frame: Instance)
	local gap = frame:GetAttribute(LIST_GAP)
	if type(gap) ~= "number" then
		return
	end
	local rows: { GuiObject } = {}
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") and (child :: GuiObject).Visible then
			table.insert(rows, child :: GuiObject)
		end
	end
	table.sort(rows, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)
	local heights = {}
	for i, row in rows do
		heights[i] = row.Size.Y.Offset
	end
	local ys, canvas = Layout.stackRows(heights, gap)
	for i, row in rows do
		row.AnchorPoint = Vector2.zero
		row.Position = UDim2.fromOffset(0, ys[i])
	end
	(frame :: ScrollingFrame).CanvasSize = UDim2.fromOffset(0, canvas)
end

-- Design-px height of a panel body's content: the lowest top-anchored child
-- (a scroll frame counts as its position plus canvas), plus whatever sits
-- pinned to the bottom edge (Position.Y.Scale 1, negative offset). Children
-- sized by scale are ignored. Drives Layout.panelFor's content-sized cards.
function Widgets.contentHeight(body: Instance): number
	local top, bottomReserve = 0, 0
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") and (child :: GuiObject).Visible then
			local g = child :: GuiObject
			local pos, size = g.Position.Y, g.Size.Y
			if g:IsA("ScrollingFrame") then
				top = math.max(top, pos.Offset + (g :: ScrollingFrame).CanvasSize.Y.Offset)
			elseif pos.Scale == 0 and size.Scale == 0 then
				top = math.max(top, pos.Offset + size.Offset)
			elseif pos.Scale == 1 and size.Scale == 0 then
				bottomReserve = math.max(bottomReserve, -pos.Offset)
			end
		end
	end
	return top + bottomReserve
end

-- A horizontal progress bar: a rounded Ink track with the shaded fill inset 2 px. Returns the track and a
-- setter (0..1); an empty bar hides its fill so no sliver of colour shows.
function Widgets.bar(parent: Instance, color: Color3, size: UDim2, position: UDim2?): (Frame, (number) -> ())
	local back = create("Frame", {
		Size = size,
		Position = position or UDim2.new(),
		BackgroundColor3 = Theme.Ink,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 2),
			PaddingLeft = UDim.new(0, 2),
			PaddingRight = UDim.new(0, 2),
		}),
	})
	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Visible = false,
		Parent = back,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	Widgets.shade(fill, 0.78)
	return back,
		function(alpha: number)
			local a = math.clamp(alpha, 0, 1)
			fill.Size = UDim2.fromScale(a, 1)
			fill.Visible = a > 0
		end
end

function Widgets.color3(rgb: { number }?): Color3
	if type(rgb) ~= "table" then
		return Color3.new(1, 1, 1)
	end
	return Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

-- Keyed row reuse so buttons survive frequent State pushes.
export type KeyedList<T> = { sync: (items: { T }) -> (), rows: { [string]: any } }

function Widgets.keyedList<T>(
	container: Instance,
	key: (T) -> string,
	makeRow: (T) -> any, -- returns a row table with field `instance: GuiObject`
	updateRow: (any, T, number) -> ()
): KeyedList<T>
	local rows: { [string]: any } = {}
	local function sync(items: { T })
		local seen = {}
		for index, item in items do
			local k = key(item)
			seen[k] = true
			local row = rows[k]
			if row == nil then
				row = makeRow(item)
				rows[k] = row
				row.instance.Parent = container
			end
			row.instance.LayoutOrder = index
			updateRow(row, item, index)
		end
		for k, row in rows do
			if not seen[k] then
				row.instance:Destroy()
				rows[k] = nil
			end
		end
		Widgets.restack(container)
	end
	return { sync = sync, rows = rows }
end

return Widgets
