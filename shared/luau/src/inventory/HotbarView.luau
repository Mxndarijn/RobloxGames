--!strict
--[[
	HotbarView (client adapter): the default hotbar and inventory grid UI.

	It draws Hotbar entries and reports presses; it never changes the inventory itself. Games can use it as-is,
	restyle it, or replace parts of it:
	  theme       colours, font, corner radius, stroke merged over HotbarView.THEME
	  metrics     sizes merged over HotbarLayout.DEFAULT
	  renderIcon  (container: Frame, entry) -> ()  draws the item picture inside a slot or cell
	  renderSlot  (button: GuiButton, entry?, info) -> ()  takes over drawing a whole slot / cell (info.where is
	              "bar" or "grid"); the view still positions the button and handles presses
	  zone        (screen: Vector2, touch: boolean) -> Rect  where the bar sits (default: bottom strip)
	A game that wants a completely different look builds its own view on Hotbar + HotbarLayout instead.

	Typical use (client):
	  local view = HotbarView.new(screenGui, { onSelect = function(entry) ... send the intent ... end })
	  view.update(Hotbar.entries(snapshot, registry, extras), Hotbar.gridEntries(snapshot, registry))
	  ToolProvider.bindNumberKeys(view.pressKey)
]]

local Hotbar = if script then require(script.Parent.Hotbar) else require("./Hotbar")
local HotbarLayout = if script then require(script.Parent.HotbarLayout) else require("./HotbarLayout")

type Entry = Hotbar.Entry
type Rect = HotbarLayout.Rect

export type Theme = {
	bar: Color3,
	barTransparency: number,
	slot: Color3,
	slotEquipped: Color3,
	stroke: Color3,
	strokeEquipped: Color3,
	text: Color3,
	textMuted: Color3,
	cooldown: Color3,
	panel: Color3,
	font: Enum.Font,
	corner: number,
	strokeThickness: number,
	zIndex: number,
}

export type SlotInfo = { where: "bar" | "grid", index: number, theme: Theme }

export type Options = {
	onSelect: (entry: Entry) -> (),
	theme: { [string]: any }?,
	metrics: { [string]: any }?,
	renderIcon: ((container: Frame, entry: Entry) -> ())?,
	renderSlot: ((button: GuiButton, entry: Entry?, info: SlotInfo) -> ())?,
	zone: ((screen: Vector2, touch: boolean) -> Rect)?,
	showKeys: boolean?,
	title: string?,
	now: (() -> number)?,
}

export type View = {
	update: (bar: { Entry }, grid: { Entry }?) -> (),
	layout: (screen: Vector2, touch: boolean) -> (),
	tick: () -> (),
	pressKey: (n: number) -> (),
	setVisible: (visible: boolean) -> (),
	openGrid: () -> (),
	closeGrid: () -> (),
	isGridOpen: () -> boolean,
	destroy: () -> (),
}

local HotbarView = {}

HotbarView.THEME = table.freeze({
	bar = Color3.fromRGB(20, 22, 30),
	barTransparency = 0.25,
	slot = Color3.fromRGB(46, 50, 66),
	slotEquipped = Color3.fromRGB(88, 120, 220),
	stroke = Color3.fromRGB(10, 10, 16),
	strokeEquipped = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(255, 255, 255),
	textMuted = Color3.fromRGB(190, 195, 210),
	cooldown = Color3.fromRGB(0, 0, 0),
	panel = Color3.fromRGB(28, 30, 40),
	font = Enum.Font.GothamBold,
	corner = 8,
	strokeThickness = 2,
	zIndex = 10,
} :: Theme)

local function merge(base: { [string]: any }, over: { [string]: any }?): any
	local out = table.clone(base)
	if over then
		for k, v in over do
			out[k] = v
		end
	end
	return table.freeze(out)
end

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function rgb(c: { number }?): Color3?
	return if c then Color3.fromRGB(c[1] or 0, c[2] or 0, c[3] or 0) else nil
end

-- Default picture: the item's image, else its initial on a tile in the item's colour.
function HotbarView.defaultIcon(container: Frame, entry: Entry, theme: Theme)
	container:ClearAllChildren()
	if entry.icon then
		make("ImageLabel", {
			Parent = container,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = entry.icon,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = container.ZIndex,
		})
		return
	end
	make("TextLabel", {
		Parent = container,
		BackgroundColor3 = rgb(entry.color) or theme.slot,
		BackgroundTransparency = if entry.color then 0 else 1,
		Size = UDim2.fromScale(1, 1),
		Font = theme.font,
		Text = string.upper(string.sub(entry.name, 1, 1)),
		TextColor3 = theme.text,
		TextScaled = true,
		ZIndex = container.ZIndex,
	}, { make("UICorner", { CornerRadius = UDim.new(0, theme.corner) }) })
end

function HotbarView.new(parent: Instance, options: Options): View
	assert(type(options) == "table" and type(options.onSelect) == "function", "HotbarView.new: onSelect is required")
	local theme: Theme = merge(HotbarView.THEME :: any, options.theme)
	local metrics = HotbarLayout.metrics(options.metrics)
	local showKeys = options.showKeys ~= false
	local now = options.now or os.clock
	local z = theme.zIndex

	local barEntries: { Entry } = {}
	local gridEntries: { Entry } = {}
	local barSignature, gridSignature = "", ""
	local shown = 0
	local visible = true
	local gridOpen = false
	local screen, touch = Vector2.new(1280, 720), false

	local root = make("Frame", {
		Name = "Hotbar",
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	local bar = make("Frame", {
		Name = "Bar",
		Parent = root,
		BackgroundColor3 = theme.bar,
		BackgroundTransparency = theme.barTransparency,
		ZIndex = z,
	}, { make("UICorner", { CornerRadius = UDim.new(0, theme.corner + 4) }) })

	type Slot = {
		button: TextButton,
		icon: Frame,
		count: TextLabel,
		key: TextLabel,
		cooldown: TextLabel,
		stroke: UIStroke,
	}

	local function newSlot(container: Instance, name: string): Slot
		local stroke = make("UIStroke", { Color = theme.stroke, Thickness = theme.strokeThickness })
		local button = make("TextButton", {
			Name = name,
			Parent = container,
			AutoButtonColor = false,
			BackgroundColor3 = theme.slot,
			Text = "",
			ZIndex = z + 1,
		}, { make("UICorner", { CornerRadius = UDim.new(0, theme.corner) }), stroke })
		local icon = make("Frame", {
			Name = "Icon",
			Parent = button,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.72, 0.72),
			BackgroundTransparency = 1,
			ZIndex = z + 2,
		})
		local function label(labelName: string, props: { [string]: any }): TextLabel
			local base = {
				Name = labelName,
				Parent = button,
				BackgroundTransparency = 1,
				Font = theme.font,
				TextColor3 = theme.text,
				TextStrokeTransparency = 0.4,
				ZIndex = z + 3,
				Text = "",
			}
			for k, v in props do
				base[k] = v
			end
			return make("TextLabel", base)
		end
		return {
			button = button,
			icon = icon,
			stroke = stroke,
			count = label("Count", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -3, 1, -1),
				Size = UDim2.fromScale(0.6, 0.32),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
			key = label("Key", {
				Position = UDim2.fromOffset(4, 2),
				Size = UDim2.fromScale(0.3, 0.28),
				TextScaled = true,
				TextColor3 = theme.textMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			cooldown = label("Cooldown", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = theme.cooldown,
				BackgroundTransparency = 1,
				TextScaled = true,
				Visible = false,
				ZIndex = z + 4,
			}),
		}
	end

	local function paint(slot: Slot, entry: Entry?, info: SlotInfo)
		if options.renderSlot then
			options.renderSlot(slot.button, entry, info)
			return
		end
		local equipped = entry ~= nil and entry.equipped
		slot.button.BackgroundColor3 = if equipped then theme.slotEquipped else theme.slot
		slot.stroke.Color = if equipped then theme.strokeEquipped else theme.stroke
		slot.count.Text = if entry then Hotbar.countText(entry.count) or "" else ""
		slot.key.Text = if showKeys
				and info.where == "bar"
				and info.index <= Hotbar.MAX_KEYS
			then tostring(info.index)
			else ""
		if entry then
			if options.renderIcon then
				options.renderIcon(slot.icon, entry)
			else
				HotbarView.defaultIcon(slot.icon, entry, theme)
			end
		else
			slot.icon:ClearAllChildren()
		end
	end

	local barSlots: { Slot } = {}
	local connections: { RBXScriptConnection } = {}

	local function slotAt(index: number): Slot
		local slot = barSlots[index]
		if slot == nil then
			slot = newSlot(bar, `Slot{index}`)
			barSlots[index] = slot
			table.insert(
				connections,
				slot.button.Activated:Connect(function()
					local entry = barEntries[index]
					if entry and index <= shown then
						options.onSelect(entry)
					end
				end)
			)
		end
		return slot
	end

	-- Bag button and grid panel.
	local bag = newSlot(bar, "Bag")
	bag.key.Text = ""
	make("TextLabel", {
		Parent = bag.icon,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = theme.font,
		Text = "≡",
		TextColor3 = theme.text,
		TextScaled = true,
		ZIndex = z + 2,
	})

	local panel = make("Frame", {
		Name = "Grid",
		Parent = root,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = theme.panel,
		Visible = false,
		ZIndex = z + 5,
	}, { make("UICorner", { CornerRadius = UDim.new(0, theme.corner + 4) }) })
	make("TextLabel", {
		Name = "Title",
		Parent = panel,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -72, 0, 36),
		Font = theme.font,
		Text = options.title or "Inventory",
		TextColor3 = theme.text,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = z + 6,
	})
	local close = make("TextButton", {
		Name = "Close",
		Parent = panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = theme.slot,
		Font = theme.font,
		Text = "X",
		TextColor3 = theme.text,
		TextSize = 22,
		ZIndex = z + 6,
	}, { make("UICorner", { CornerRadius = UDim.new(0, theme.corner) }) })
	local scroll = make("ScrollingFrame", {
		Name = "Cells",
		Parent = panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 56),
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		ZIndex = z + 6,
	})
	local cells: { Slot } = {}

	local function cellAt(index: number): Slot
		local cell = cells[index]
		if cell == nil then
			cell = newSlot(scroll, `Cell{index}`)
			cell.button.ZIndex = z + 7
			cell.icon.ZIndex = z + 8
			cells[index] = cell
			table.insert(
				connections,
				cell.button.Activated:Connect(function()
					local entry = gridEntries[index]
					if entry then
						options.onSelect(entry)
					end
				end)
			)
		end
		return cell
	end

	local view = {} :: View

	local function place(inst: GuiObject, r: Rect, origin: Rect?)
		local ox, oy = if origin then origin.x else 0, if origin then origin.y else 0
		inst.Position = UDim2.fromOffset(math.round(r.x - ox), math.round(r.y - oy))
		inst.Size = UDim2.fromOffset(math.round(r.w), math.round(r.h))
	end

	local function relayoutBar()
		local zone = if options.zone
			then options.zone(screen, touch)
			else HotbarLayout.defaultZone(metrics, screen.X, screen.Y, touch)
		local geometry = HotbarLayout.bar(metrics, zone, #barEntries, touch)
		shown = geometry.shown
		place(bar, geometry.rect)
		for i = 1, math.max(#barSlots, shown) do
			local slot = slotAt(i)
			slot.button.Visible = i <= shown
			if i <= shown then
				place(slot.button, geometry.slots[i], geometry.rect)
				paint(slot, barEntries[i], { where = "bar", index = i, theme = theme })
			end
		end
		bag.button.Visible = geometry.bag ~= nil
		if geometry.bag then
			place(bag.button, geometry.bag, geometry.rect)
		end
		bar.Visible = visible and (shown > 0 or geometry.bag ~= nil)
	end

	local function relayoutGrid()
		local w = math.min(screen.X - 32, 560)
		local h = math.min(screen.Y - 32, 460)
		panel.Size = UDim2.fromOffset(w, h)
		local bodyW = w - 32
		scroll.Size = UDim2.fromOffset(bodyW, h - 72)
		scroll.CanvasSize = UDim2.fromOffset(0, HotbarLayout.gridHeight(metrics, #gridEntries, bodyW))
		for i = 1, math.max(#cells, #gridEntries) do
			local cell = cellAt(i)
			local entry = gridEntries[i]
			cell.button.Visible = entry ~= nil
			if entry then
				place(cell.button, HotbarLayout.cell(metrics, i, bodyW))
				paint(cell, entry, { where = "grid", index = i, theme = theme })
			end
		end
	end

	function view.update(newBar: { Entry }, newGrid: { Entry }?)
		local sig = Hotbar.signature(newBar)
		barEntries = newBar
		if sig ~= barSignature then
			barSignature = sig
			relayoutBar()
		end
		if newGrid then
			local gsig = Hotbar.signature(newGrid)
			gridEntries = newGrid
			if gsig ~= gridSignature then
				gridSignature = gsig
				if gridOpen then
					relayoutGrid()
				end
			end
		end
	end

	function view.layout(newScreen: Vector2, isTouch: boolean)
		screen, touch = newScreen, isTouch
		relayoutBar()
		if gridOpen then
			relayoutGrid()
		end
	end

	-- Cooldown overlays; call from the game's existing client loop (a few times a second is enough).
	function view.tick()
		local t = now()
		for i = 1, shown do
			local entry, slot = barEntries[i], barSlots[i]
			if entry and slot and not options.renderSlot then
				local text = Hotbar.cooldownText(entry, t)
				slot.cooldown.Visible = text ~= nil
				slot.cooldown.Text = text or ""
				slot.cooldown.BackgroundTransparency = if text then 0.45 else 1
			end
		end
	end

	function view.pressKey(n: number)
		local entry = Hotbar.byKey(barEntries, shown, n)
		if entry and visible then
			options.onSelect(entry)
		end
	end

	function view.setVisible(on: boolean)
		visible = on
		bar.Visible = on and (shown > 0 or metrics.bag)
		if not on then
			view.closeGrid()
		end
	end

	function view.openGrid()
		gridOpen = true
		panel.Visible = true
		relayoutGrid()
	end

	function view.closeGrid()
		gridOpen = false
		panel.Visible = false
	end

	function view.isGridOpen(): boolean
		return gridOpen
	end

	function view.destroy()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		root:Destroy()
	end

	table.insert(
		connections,
		bag.button.Activated:Connect(function()
			if gridOpen then
				view.closeGrid()
			else
				view.openGrid()
			end
		end)
	)
	table.insert(connections, close.Activated:Connect(view.closeGrid))

	relayoutBar()
	return view
end

return table.freeze(HotbarView)
