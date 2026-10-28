--!strict
--[[
	Widgets

	Small Instance.new helpers and the UI theme. Only creates Instances when a
	function is called. At require time it waits for ReplicatedStorage.Shared
	(the theme's colours come from Shared.GooPalette).
]]

local Goo = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GooPalette"))
local Layout = require(script.Parent.Layout)

local Widgets = {}

-- The Goo palette (Shared.GooPalette): deep teal glass panels, a mint header band, ink outlines, gold money.
-- Button colours carry meaning: Gold collects a reward, Good acts (buy, merge, redeem), Info is a side action,
-- Bad loses something or closes. Only things you can press are jelly; something you can't press yet is a
-- sunken Ink well with the same outline (Widgets.status / a disabled button).
local function fromPalette(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

Widgets.Theme = table.freeze({
	Ink = fromPalette(Goo.Ink), -- every outline, dark text on bright jelly, sunken wells
	Bg = fromPalette(Goo.Bg), -- glass panel body
	Row = fromPalette(Goo.Row), -- rows and cards on the glass
	BgLight = fromPalette(Goo.BgLight), -- highlighted rows
	Band = fromPalette(Goo.Mint), -- the mint header band, its lip and drips
	Text = fromPalette(Goo.Text),
	Muted = fromPalette(Goo.Muted),
	Accent = fromPalette(Goo.Mint),
	Good = fromPalette(Goo.Mint),
	Bad = fromPalette(Goo.Bad),
	Thief = fromPalette(Goo.Thief), -- the outline on a player carrying your slime
	Info = fromPalette(Goo.Info),
	Warn = fromPalette(Goo.Warn),
	Disabled = fromPalette(Goo.Ink),
	Gold = fromPalette(Goo.Gold),
	GoldDeep = fromPalette(Goo.GoldDeep), -- the coin's edge and ring
	Silver = fromPalette(Goo.Silver), -- leaderboard second place
	Bronze = fromPalette(Goo.Bronze), -- leaderboard third place
	Glass = fromPalette(Goo.Glass), -- a glass row on a card (at Goo.GLASS_TRANSPARENCY)
	-- The carousel's accents, only on the Exclusive shop's stage behind its preview. Until GooPalette has
	-- Plum / Butter they fall back to the Info teal and the gold jelly top.
	Plum = fromPalette((Goo :: any).Plum or Goo.Info),
	Butter = fromPalette((Goo :: any).Butter or Goo.GoldHi),
	Font = Enum.Font.FredokaOne, -- titles, numbers, buttons, labels
	FontBody = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold), -- sentences (a FontFace)
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

-- How see-through the dim behind a menu or popup is: a light Ink (purple) tint, so the world stays readable.
Widgets.BACKDROP_TRANSPARENCY = 0.6

-- The full-window dim behind a menu or popup: an Ink tint, not black. A TextButton so a tap on it can close
-- the menu. The caller sizes it (Layout.backdrop) and sets ZIndex.
function Widgets.backdrop(props: { [string]: any }): TextButton
	local base: { [string]: any } = {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = Widgets.BACKDROP_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
	}
	for k, v in props do
		base[k] = v
	end
	return create("TextButton", base)
end

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

-- The label property that takes `font`: Theme.Font is an Enum.Font ("Font"), Theme.FontBody a Font ("FontFace").
function Widgets.fontKey(font: any): string
	return if typeof(font) == "Font" then "FontFace" else "Font"
end

-- Body text (Nunito) unless the caller picks a font. Setting both Font and FontFace would let table
-- order decide which wins, so the default FontFace is only added when neither is given.
function Widgets.label(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		TextColor3 = Theme.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 20),
	}
	for k, v in props do
		base[k] = v
	end
	if base.Font == nil and base.FontFace == nil then
		base.FontFace = Theme.FontBody
	end
	return create("TextLabel", base)
end

-- Roblox draws emoji above the middle of a TextLabel. How far, as a share of the text size, depends
-- on the label's font (measured in Studio); text glyphs like ★, $ and digits sit centred already.
Widgets.EMOJI_RISE = table.freeze({ Nunito = 0.1, FredokaOne = 0.035 })
local EMOJI_BMP: { [number]: boolean } = {
	[0x23F1] = true,
	[0x26A1] = true,
	[0x26F2] = true,
	[0x2705] = true,
	[0x2728] = true,
	[0x2B06] = true,
	[0x2B50] = true,
}

function Widgets.isEmoji(text: string): boolean
	for _, cp in utf8.codes(text) do
		if cp >= 0x1F000 or cp == 0xFE0F or EMOJI_BMP[cp] then
			return true
		end
	end
	return false
end

-- How far `text` rises in a label of `font` (an Enum.Font or a Font), as a share of its text size.
function Widgets.emojiRise(font: any, text: string): number
	if not Widgets.isEmoji(text) then
		return 0
	end
	local family = if typeof(font) == "Font" then font.Family else `rbxasset://fonts/families/{font.Name}.json`
	return Widgets.EMOJI_RISE[string.match(family, "([%w]+)%.json$") or ""] or 0
end

-- Moves an emoji icon label down by its rise so the emoji sits in the middle of its spot (no extra
-- instance; the label's own Y offset is kept in the EmojiBaseY attribute). `follow` keeps it centred
-- when the label's text changes later.
function Widgets.centreEmoji(label: TextLabel, follow: boolean?)
	local base = label:GetAttribute("EmojiBaseY")
	if base == nil then
		base = label.Position.Y.Offset
		label:SetAttribute("EmojiBaseY", base)
		if follow then
			label:GetPropertyChangedSignal("Text"):Connect(function()
				Widgets.centreEmoji(label)
			end)
		end
	end
	local rise = math.round(Widgets.emojiRise(label.FontFace, label.Text) * label.TextSize)
	local p = label.Position
	label.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, (base :: number) + rise)
end

export type Button = {
	instance: TextButton,
	setEnabled: (enabled: boolean) -> (),
	setText: (text: string) -> (),
	setColor: (color: Color3) -> (),
}

-- Chunky sizes shared by every panel part (design px).
Widgets.KIT = table.freeze({
	stroke = 3, -- ink outline on buttons, wells, the panel and its tiles: every slot has the same footprint
	rowStroke = 2, -- ink outline on rows and cards
	radius = 13, -- icon badges
	rowRadius = 18,
	panelRadius = 30,
	plateRadius = 18, -- the hotbar plate
	slotRadius = 16, -- hotbar slots and the Bag button
	shadeBottom = 0.78, -- a jelly's bottom brightness under its top
})

-- Buttons, wells, chips and bubbles are pills or circles: one uniform UICorner each.
function Widgets.pill(): UICorner
	return create("UICorner", { CornerRadius = UDim.new(1, 0) })
end

-- A notice's two rings: `color` (Gold = info or guidance, Bad = danger) on the card's own UIStroke and a
-- transparent wrapper `stroke` px larger carrying the Ink ring, as one UIStroke per frame allows. `radius`
-- is the card's corner radius (offset px) or nil for a pill. Returns the card's stroke and the wrapper.
function Widgets.ring(card: GuiObject, color: Color3, radius: number?): (UIStroke, Frame)
	local kit = Widgets.KIT
	local stroke = card:FindFirstChildOfClass("UIStroke") or Widgets.stroke(color, kit.stroke)
	stroke.Color = color
	stroke.Thickness = kit.stroke
	stroke.Parent = card
	local wrap = create("Frame", {
		Name = "InkRing",
		Active = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-kit.stroke, -kit.stroke),
		Size = UDim2.new(1, kit.stroke * 2, 1, kit.stroke * 2),
		ZIndex = card.ZIndex,
		Parent = card,
	}, {
		if radius then Widgets.corner(radius + kit.stroke) else Widgets.pill(),
		Widgets.stroke(Theme.Ink, kit.stroke),
	})
	return stroke, wrap
end

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

-- A jelly pill TextButton: fill, ink outline and a darker bottom. Disabled it turns into a sunken Ink well
-- with muted text (the outline stays, so its size never jumps), so it never reads as pressable. Clicks while disabled are ignored.
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
	local inst = create("TextButton", base, { Widgets.pill() }) :: TextButton
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
		inst:SetAttribute("ClickMuted", if enabled then nil else true) -- ButtonClicks stays quiet
		inst.BackgroundColor3 = if enabled then baseColor else Theme.Disabled
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
	Widgets.pill().Parent = label
	Widgets.stroke(Theme.Ink, Widgets.KIT.stroke).Parent = label
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
	(Lock, Buy pad, Sell, Rebirth, shop Buy). The server still checks.
]]
-- True while `inst` can still be pressed: every GuiObject up the chain is Visible and it reaches an enabled
-- ScreenGui. A hidden card/panel or a destroyed button (Parent nil) is not.
function Widgets.holdAlive(inst: Instance): boolean
	local node: Instance? = inst
	while node do
		if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
			return false
		elseif node:IsA("LayerCollector") then
			return (node :: LayerCollector).Enabled
		end
		node = node.Parent
	end
	return false
end

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
	}, { Widgets.pill() })
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
			if not Widgets.holdAlive(inst) then
				stop() -- hidden or destroyed mid-hold: never confirms
				return
			end
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
				if Widgets.holdAlive(inst) then
					onConfirm()
				end
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

-- Goo edge under a band of colour `color` whose bottom is at `y` (design px), across `parent`'s full width:
-- drips at the fractions in Layout.GOO_EDGE.drips, each one finger of goo with a round end. Everything is sized by scale or a few px, so it fits any panel width; drips stay
-- shorter than PANEL_CHROME.bodyGap so they only fall into the empty gap above the body.
function Widgets.gooEdge(parent: GuiObject, y: number, color: Color3)
	local g = Layout.GOO_EDGE
	local edge = create("Frame", {
		Name = "GooEdge",
		BackgroundTransparency = 1,
		Active = false,
		Size = UDim2.new(1, -g.inset * 2, 0, 0),
		Position = UDim2.fromOffset(g.inset, y),
		ZIndex = parent.ZIndex,
		Parent = parent,
	})
	for i, d in g.drips do
		local x, w, hang = d[1], d[2], d[3]
		-- Its round top hides in the band (same colour), so only the hanging part and its round end show.
		create("Frame", {
			Name = "Drip" .. i,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.new(x, 0, 0, -w),
			Size = UDim2.fromOffset(w, hang + w),
			ZIndex = parent.ZIndex,
			Parent = edge,
		}, { Widgets.pill() })
	end
	return edge
end

-- The goo edge each ScreenGui's menus share (weak keys: a destroyed gui frees its edge).
local sharedEdges: { [Instance]: Frame } = setmetatable({}, { __mode = "k" }) :: any

-- A menu card (Layout.PANEL_CHROME), the same frame for every menu: deep teal
-- glass with a mint header band that drips goo, the menu's `icon` on a white
-- jelly tile poking up over the top-left corner, the title in ink on the mint
-- and the round pink close "X" top-right; `body` fills the area under them.
-- init.client sizes the frame (Layout.panelFor) over the dimmed backdrop and
-- wires `close` to setOpen(nil).
function Widgets.panel(parent: Instance, name: string, titleText: string, icon: string?): Panel
	local c = Layout.PANEL_CHROME
	local kit = Widgets.KIT
	local radius = kit.panelRadius
	local frame = create("Frame", {
		Name = name,
		Visible = false, -- shown only by setOpen / the menu manager
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.04,
		ZIndex = Layout.ZINDEX.Menu,
		Active = true, -- a tap on the card is not a tap on the backdrop behind it (which closes the menu)
		Parent = parent,
	}, { Widgets.corner(radius), Widgets.stroke(Theme.Ink, kit.stroke) })
	-- The band: rounded on top, square at the bottom (a second, unrounded strip covers the lower corners).
	local bandH = c.header - c.bodyGap
	create("Frame", {
		Name = "Band",
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Band,
		Size = UDim2.new(1, 0, 0, bandH),
		Parent = frame,
	}, { Widgets.corner(radius) })
	create("Frame", {
		Name = "BandFoot",
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Band,
		Size = UDim2.new(1, 0, 0, radius),
		Position = UDim2.fromOffset(0, bandH - radius),
		Parent = frame,
	})
	-- One goo edge per ScreenGui, moved into whichever menu is shown: only one menu is open at a time, so
	-- the lip and drips cost their instances once, not once per panel (ui-perf-budget.json).
	-- A destroyed panel takes the edge with it (Parent nil); the next panel then builds a fresh one.
	local function claimEdge()
		local edge = sharedEdges[parent]
		if edge == nil or edge.Parent == nil then
			sharedEdges[parent] = Widgets.gooEdge(frame, bandH, Theme.Band)
		elseif edge.Parent ~= frame then
			edge.Parent = frame
		end
	end
	if sharedEdges[parent] == nil or (sharedEdges[parent] :: Frame).Parent == nil then
		claimEdge()
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			claimEdge()
		end
	end)
	local tile = create("Frame", {
		Name = "IconTile",
		BackgroundColor3 = Theme.Text,
		Size = UDim2.fromOffset(c.icon, c.icon),
		Position = UDim2.fromOffset(c.pad, -c.iconRise),
		Parent = frame,
	}, { Widgets.pill(), Widgets.stroke(Theme.Ink, kit.stroke) })
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
	Widgets.centreEmoji(iconLabel, true)
	local titleX = c.pad + c.icon + 10
	local title = Widgets.label({
		Name = "Title",
		Text = titleText,
		Font = Theme.Font,
		TextSize = c.titleSize,
		TextColor3 = Theme.Ink,
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
	}, { Widgets.pill(), Widgets.stroke(Theme.Ink, kit.stroke) }) :: TextButton
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
	Widgets.centreEmoji(badge, true)
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
