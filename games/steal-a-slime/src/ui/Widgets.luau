--!strict
--[[
	Widgets

	Small Instance.new helpers and the UI theme. Only creates Instances when a
	function is called (nothing at require time).
]]

local Layout = require(script.Parent.Layout)

local Widgets = {}

Widgets.Theme = table.freeze({
	Bg = Color3.fromRGB(28, 30, 44),
	BgLight = Color3.fromRGB(44, 47, 66),
	Row = Color3.fromRGB(52, 56, 78),
	Text = Color3.fromRGB(240, 242, 255),
	Muted = Color3.fromRGB(165, 170, 200),
	Accent = Color3.fromRGB(110, 230, 140),
	Good = Color3.fromRGB(80, 200, 120),
	Bad = Color3.fromRGB(230, 70, 90),
	Info = Color3.fromRGB(80, 150, 240),
	Warn = Color3.fromRGB(255, 190, 60),
	Disabled = Color3.fromRGB(80, 82, 100),
	Gold = Color3.fromRGB(255, 205, 70),
	Font = Enum.Font.GothamBold,
	FontBody = Enum.Font.Gotham,
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
		Color = color or Color3.new(0, 0, 0),
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

-- A rounded TextButton. Clicks while disabled are ignored.
function Widgets.button(props: { [string]: any }, color: Color3?, onClick: () -> ()): Button
	local baseColor = color or Theme.Info
	local enabled = true
	local base = {
		BackgroundColor3 = baseColor,
		TextColor3 = Theme.Text,
		Font = Theme.Font,
		TextSize = 15,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(90, 30),
	}
	for k, v in props do
		base[k] = v
	end
	local inst = create("TextButton", base, { Widgets.corner(6) }) :: TextButton
	inst.Activated:Connect(function()
		if enabled then
			onClick()
		end
	end)
	local self = {} :: Button
	self.instance = inst
	function self.setEnabled(value: boolean)
		enabled = value
		inst.AutoButtonColor = value
		inst.BackgroundColor3 = if value then baseColor else Theme.Disabled
		inst.TextTransparency = if value then 0 else 0.35
	end
	function self.setText(text: string)
		inst.Text = text
	end
	function self.setColor(c: Color3)
		baseColor = c
		if enabled then
			inst.BackgroundColor3 = c
		end
	end
	return self
end

-- A button that needs two clicks within `window` seconds (e.g. Sell, Rebirth).
function Widgets.confirmButton(
	props: { [string]: any },
	color: Color3?,
	confirmText: string,
	onConfirm: () -> ()
): Button
	local armedAt: number? = nil
	local idleText = props.Text or ""
	local btn: Button
	btn = Widgets.button(props, color, function()
		local now = os.clock()
		if armedAt and now - armedAt <= 2.5 then
			armedAt = nil
			btn.instance.Text = idleText
			onConfirm()
		else
			armedAt = now
			btn.instance.Text = confirmText
			task.delay(2.5, function()
				if armedAt and os.clock() - armedAt >= 2.4 then
					armedAt = nil
					btn.instance.Text = idleText
				end
			end)
		end
	end)
	local setText = btn.setText
	function btn.setText(text: string)
		idleText = text
		if armedAt == nil then
			setText(text)
		end
	end
	return btn
end

export type Panel = { frame: Frame, body: Frame, title: TextLabel, close: TextButton }

-- A titled, rounded menu panel (Layout.PANEL_CHROME): title top-left, a
-- close "X" top-right, `body` fills the area under them. init.client sizes
-- the frame (Layout.panelFor) and wires `close` to setOpen(nil).
function Widgets.panel(parent: Instance, name: string, titleText: string): Panel
	local c = Layout.PANEL_CHROME
	local frame = create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.04,
		Parent = parent,
	}, { Widgets.corner(12), Widgets.stroke(Color3.fromRGB(10, 10, 20), 2) })
	local title = Widgets.label({
		Name = "Title",
		Text = titleText,
		Font = Theme.Font,
		TextSize = c.titleSize,
		Size = UDim2.new(1, -(c.pad + c.close + c.closeInset * 2), 0, c.close),
		Position = UDim2.fromOffset(c.pad, c.closeInset),
		Parent = frame,
	})
	local close = create("TextButton", {
		Name = "Close",
		Text = "X",
		Font = Theme.Font,
		TextSize = 24,
		TextColor3 = Theme.Text,
		BackgroundColor3 = Theme.Bad,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -c.closeInset, 0, c.closeInset),
		Size = UDim2.fromOffset(c.close, c.close),
		ZIndex = 2,
		Parent = frame,
	}, { Widgets.corner(10) }) :: TextButton
	local body = create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -c.pad * 2, 1, -(c.header + c.pad)),
		Position = UDim2.fromOffset(c.pad, c.header),
		Parent = frame,
	})
	return { frame = frame, body = body, title = title, close = close }
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

-- A horizontal progress bar; returns the frame and a setter (0..1).
function Widgets.bar(parent: Instance, color: Color3, size: UDim2, position: UDim2?): (Frame, (number) -> ())
	local back = create("Frame", {
		Size = size,
		Position = position or UDim2.new(),
		BackgroundColor3 = Theme.BgLight,
		Parent = parent,
	}, { Widgets.corner(4) })
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color,
		Parent = back,
	}, { Widgets.corner(4) })
	return back, function(alpha: number)
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
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
