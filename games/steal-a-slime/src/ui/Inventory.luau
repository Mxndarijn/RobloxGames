--!strict
--[[
	Inventory (S3): the hotbar and the inventory panel that replace Roblox's default backpack bar.

	Bottom-centre hotbar (Layout.screen's `hotbar` zone, InventoryLayout): the Bat first, then every other
	held Tool and every owned PvP item (InventoryCore.entries), each a rounded purple slot with its ItemIcons
	picture, a selected highlight, the stack count when there is one and the number key (1-9) on keyboards.
	The name shows on hover (mouse) or on a long press (touch). A tap / click / number key equips (or puts
	away) the item through the EXISTING actions only: a Tool through the Humanoid, a PvP item through
	Request("EquipPvpItem"). The last cell is the bag: it opens the inventory panel, a grid of everything
	held (also the items that did not fit the bar on a narrow phone). Hidden while carrying (the server
	unequips tools then) and while a menu is open. Client-only: no new server state, no new remote.
]]

local InventoryCore = require(script.Parent.InventoryCore)
local InventoryLayout = require(script.Parent.InventoryLayout)
local ItemIconView = require(script.Parent.ItemIconView)
local Layout = require(script.Parent.Layout)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

-- UDim offsets are whole pixels (int32): fractional design px (a phone's 487.5) round, as init.client's do.
local function fromOffset(x: number, y: number): UDim2
	return UDim2.fromOffset(math.round(x), math.round(y))
end

local Inventory = {}

Inventory.LONG_PRESS = 0.4 -- seconds a finger holds a slot to see its name
Inventory.TIP_SECONDS = 1.6

-- The HUD tile palette (Hud money plates): rounded purple with the dark stroke.
Inventory.COLORS = table.freeze({
	plate = Color3.fromRGB(58, 36, 110),
	slot = Color3.fromRGB(84, 58, 150),
	selected = Color3.fromRGB(128, 86, 224),
	stroke = Color3.fromRGB(10, 10, 20),
	ring = Color3.fromRGB(255, 255, 255),
})

local KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

type Deps = {
	Config: any,
	itemIcons: any, -- ItemIcons registry
	send: (action: string, ...any) -> (),
	tools: any, -- InventoryTools.Provider
	serverNow: () -> number,
	keyboard: boolean?, -- show number keys (default true)
}

type Slot = {
	button: TextButton,
	icon: any,
	number: TextLabel,
	count: TextLabel,
	cooldown: TextLabel,
	entry: Entry?,
}
type Entry = InventoryCore.Entry

function Inventory.new(parent: Instance, deps: Deps)
	local registry = InventoryCore.withTools(deps.itemIcons)
	local C = Inventory.COLORS
	local keyboard = deps.keyboard ~= false

	local state: any = nil -- latest State
	local entries: { Entry } = {}
	local signature = ""
	local menuOpen = false
	local carrying = false
	local screen: Layout.Screen? = nil
	local panelOpen = false
	local setPanelOpen: (open: boolean) -> ()

	-- Hotbar ------------------------------------------------------------------------------------------
	local root = create("Frame", {
		Name = "Hotbar",
		BackgroundColor3 = C.plate,
		BackgroundTransparency = 0.05,
		ZIndex = Layout.ZINDEX.Base,
		Parent = parent,
	}, { Widgets.corner(14), Widgets.stroke(C.stroke, 2) })

	local tip = Widgets.label({
		Name = "Tip",
		Visible = false,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Theme.Bg,
		Font = Theme.Font,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = fromOffset(0, 28),
		ZIndex = Layout.ZINDEX.Banners,
		Parent = parent,
	})
	Widgets.corner(8).Parent = tip
	create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = tip })
	local tipToken = 0

	-- Above `cell`, a cell of the bar (design px, relative to the bar).
	local function showTip(cell: GuiObject, text: string, seconds: number?)
		tipToken += 1
		local token = tipToken
		tip.Text = text
		local x = root.Position.X.Offset + cell.Position.X.Offset + cell.Size.X.Offset / 2
		tip.Position = fromOffset(x, root.Position.Y.Offset - 6)
		tip.Visible = true
		if seconds then
			task.delay(seconds, function()
				if tipToken == token then
					tip.Visible = false
				end
			end)
		end
	end
	local function hideTip()
		tipToken += 1
		tip.Visible = false
	end

	local function makeSlot(host: Instance, size: number, withNumber: boolean): Slot
		local button = create("TextButton", {
			Name = "Slot",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.slot,
			Size = fromOffset(size, size),
			Parent = host,
		}, { Widgets.corner(10), Widgets.stroke(C.stroke, 2) }) :: TextButton
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = "Unknown",
			Size = size - 14,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 2,
			Parent = button,
		}, registry)
		icon.setActive(true)
		local number = Widgets.label({
			Name = "Number",
			Text = "",
			Visible = withNumber,
			Font = Theme.Font,
			TextSize = 13,
			TextStrokeTransparency = 0.4,
			TextTruncate = Enum.TextTruncate.None,
			Size = fromOffset(18, 16),
			Position = fromOffset(4, 1),
			ZIndex = 6,
			Parent = button,
		})
		local count = Widgets.label({
			Name = "Count",
			Text = "",
			Visible = false,
			Font = Theme.Font,
			TextSize = 14,
			TextColor3 = Theme.Gold,
			TextStrokeTransparency = 0.2,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.None,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -2),
			Size = fromOffset(32, 16),
			ZIndex = 6,
			Parent = button,
		})
		local cooldown = Widgets.label({
			Name = "Cooldown",
			Text = "",
			Visible = false,
			Font = Theme.Font,
			TextSize = 18,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
			Parent = button,
		})
		Widgets.corner(10).Parent = cooldown
		return { button = button, icon = icon, number = number, count = count, cooldown = cooldown, entry = nil }
	end

	local function styleSlot(slot: Slot, entry: Entry, now: number)
		slot.entry = entry
		slot.icon.set(entry.iconId)
		slot.button.BackgroundColor3 = if entry.equipped then C.selected else C.slot
		local stroke = slot.button:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = if entry.equipped then C.ring else C.stroke
		stroke.Thickness = if entry.equipped then 3 else 2
		local text = InventoryCore.countText(entry.count)
		slot.count.Visible = text ~= nil
		slot.count.Text = text or ""
		local left = InventoryCore.cooldownText(entry, now)
		slot.cooldown.Visible = left ~= nil
		slot.cooldown.Text = left or ""
	end

	local function perform(entry: Entry)
		local action = InventoryCore.select(entry)
		if action.kind == "Tool" then
			-- one hand: put a PvP item away first, as equipping a Tool replaces it in the default backpack
			if action.equip and state and state.pvp and state.pvp.equipped then
				deps.send(InventoryCore.PVP_ACTION)
			end
			deps.tools.setEquipped(action.toolName, action.equip)
		else
			if action.arg then
				deps.tools.unequipAll()
			end
			if action.arg then
				deps.send(action.action, action.arg)
			else
				deps.send(action.action)
			end
		end
	end

	local function bindSlot(slot: Slot, onActivate: (Entry) -> (), withTip: boolean)
		local pressedAt: number? = nil
		local longPressed = false
		if withTip then
			slot.button.MouseEnter:Connect(function()
				if slot.entry then
					showTip(slot.button, slot.entry.name)
				end
			end)
			slot.button.MouseLeave:Connect(hideTip)
		end
		slot.button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			longPressed = false
			local at = os.clock()
			pressedAt = at
			task.delay(Inventory.LONG_PRESS, function()
				if pressedAt == at and slot.entry and withTip then
					longPressed = true
					showTip(slot.button, slot.entry.name, Inventory.TIP_SECONDS)
				end
			end)
		end)
		slot.button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				pressedAt = nil
			end
		end)
		slot.button.Activated:Connect(function()
			if longPressed then
				longPressed = false
				return
			end
			if slot.entry then
				hideTip()
				onActivate(slot.entry)
			end
		end)
	end

	local barSlots: { Slot } = {}
	for i = 1, InventoryLayout.MAX_SLOTS do
		local slot = makeSlot(root, InventoryLayout.SLOT, keyboard)
		slot.button.Name = `Slot{i}`
		slot.number.Text = tostring(i)
		slot.button.Visible = false
		bindSlot(slot, perform, true)
		barSlots[i] = slot
	end
	-- The bag cell.
	local bag = create("TextButton", {
		Name = "Bag",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.BgLight,
		Parent = root,
	}, { Widgets.corner(10), Widgets.stroke(C.stroke, 2) }) :: TextButton
	local bagIcon = Widgets.label({
		Name = "Glyph",
		Text = "🎒",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 0.7),
		ZIndex = 2,
		Parent = bag,
	})
	Widgets.label({
		Name = "Caption",
		Text = "Bag",
		Font = Theme.Font,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 14),
		ZIndex = 2,
		Parent = bag,
	})
	bagIcon.TextYAlignment = Enum.TextYAlignment.Center
	bag.MouseEnter:Connect(function()
		showTip(bag, "Inventory")
	end)
	bag.MouseLeave:Connect(hideTip)

	-- Inventory panel -------------------------------------------------------------------------------
	local backdrop = create("TextButton", {
		Name = "InventoryBackdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = Layout.ZINDEX.Menu,
		Parent = parent,
	}) :: TextButton
	local panel = Widgets.panel(parent, "InventoryPanel", "Inventory", "🎒", Color3.fromRGB(120, 80, 210))
	local list = Widgets.scroll({ Name = "Grid", Parent = panel.body })
	local gridCells: { Slot } = {}
	local cellNames: { TextLabel } = {}

	local function makeCell(): (Slot, TextLabel)
		local cell = InventoryLayout.CELL
		local slot = makeSlot(list, cell.icon + 14, false)
		slot.button.Size = fromOffset(cell.w, cell.h)
		slot.icon.instance.Size = fromOffset(cell.icon, cell.icon)
		slot.icon.instance.AnchorPoint = Vector2.new(0.5, 0)
		slot.icon.instance.Position = UDim2.new(0.5, 0, 0, 8)
		bindSlot(slot, function(e: Entry)
			perform(e)
			setPanelOpen(false)
		end, false)
		local name = Widgets.label({
			Name = "Name",
			Font = Theme.Font,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -8, 0, 32),
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 6,
			Parent = slot.button,
		})
		return slot, name
	end

	local function refreshGrid(now: number)
		local cell = InventoryLayout.CELL
		local bodyW = if screen then Layout.panelBody(Layout.panelFor(screen, "Inventory")).w else 520
		local cols = InventoryLayout.columns(bodyW)
		local gridW = cols * cell.w + (cols - 1) * cell.gap
		local x0 = math.floor((bodyW - gridW) / 2)
		for i, entry in entries do
			if gridCells[i] == nil then
				gridCells[i], cellNames[i] = makeCell()
			end
			local slot, name = gridCells[i], cellNames[i]
			styleSlot(slot, entry, now)
			name.Text = entry.name
			slot.button.Visible = true
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			slot.button.Position = fromOffset(x0 + col * (cell.w + cell.gap), row * (cell.h + cell.gap))
		end
		for i = #entries + 1, #gridCells do
			gridCells[i].button.Visible = false
		end
		list.CanvasSize = fromOffset(0, InventoryLayout.gridHeight(#entries, bodyW))
	end

	-- Refresh --------------------------------------------------------------------------------------
	local function currentEntries(): { Entry }
		return InventoryCore.entries({
			tools = deps.tools.list(),
			pvp = if state then state.pvp else nil,
			config = deps.Config,
			registry = registry,
			counts = nil,
			now = deps.serverNow(),
		})
	end

	local function applyBar()
		local now = deps.serverNow()
		local zone = if screen then screen.hotbar else Layout.rect(0, 0, 600, 67)
		local compact = if screen then screen.compact else false
		local tight = if screen then screen.tight else false
		local bar = InventoryLayout.bar(zone, #entries, compact, Layout.MIN_TOUCH_DESIGN, tight)
		root.Position = fromOffset(bar.rect.x, bar.rect.y)
		root.Size = fromOffset(bar.rect.w, bar.rect.h)
		local slotSize = if bar.slots[1]
			then bar.slots[1].w
			else InventoryLayout.slotSize(compact, Layout.MIN_TOUCH_DESIGN, tight)
		for i, slot in barSlots do
			local r = bar.slots[i]
			if r then
				slot.button.Visible = true
				slot.button.Position = fromOffset(r.x - bar.rect.x, r.y - bar.rect.y)
				slot.button.Size = fromOffset(r.w, r.h)
				slot.icon.instance.Size = fromOffset(r.w - 14, r.h - 14)
				styleSlot(slot, entries[i], now)
			else
				slot.button.Visible = false
				slot.entry = nil
			end
		end
		bag.Position = fromOffset(bar.bag.x - bar.rect.x, bar.bag.y - bar.rect.y)
		bag.Size = fromOffset(slotSize, slotSize)
		return bar
	end

	local self = {}
	self.root = root
	self.panel = panel
	self.backdrop = backdrop
	self.bag = bag

	local function sync(force: boolean?)
		entries = currentEntries()
		local sig = InventoryCore.signature(entries)
		if sig ~= signature or force then
			signature = sig
			applyBar()
			if panelOpen then
				refreshGrid(deps.serverNow())
			end
		end
		root.Visible = not (menuOpen or carrying)
		if not root.Visible then
			tip.Visible = false
		end
	end

	function setPanelOpen(open: boolean)
		panelOpen = open
		panel.frame.Visible = open
		backdrop.Visible = open
		if open then
			hideTip()
			entries = currentEntries()
			signature = InventoryCore.signature(entries)
			refreshGrid(deps.serverNow())
		end
	end
	self.setPanelOpen = setPanelOpen
	function self.panelOpen(): boolean
		return panelOpen
	end

	bag.Activated:Connect(function()
		setPanelOpen(not panelOpen)
	end)
	backdrop.Activated:Connect(function()
		setPanelOpen(false)
	end)
	panel.close.Activated:Connect(function()
		setPanelOpen(false)
	end)

	function self.layout(s: Layout.Screen)
		screen = s
		local back = Layout.backdrop(s, 0, 0)
		backdrop.Position = fromOffset(back.x, back.y)
		backdrop.Size = fromOffset(back.w, back.h)
		local r = Layout.panelFor(s, "Inventory")
		panel.frame.Position = fromOffset(r.x, r.y)
		panel.frame.Size = fromOffset(r.w, r.h)
		sync(true)
	end

	function self.update(newState: any)
		state = newState
		carrying = newState ~= nil and newState.carrying ~= nil
		if carrying and panelOpen then
			setPanelOpen(false)
		end
		sync()
	end

	-- A Menu card is open: the hotbar and the panel step aside.
	function self.setMenuOpen(open: boolean)
		menuOpen = open
		if open and panelOpen then
			setPanelOpen(false)
		end
		sync()
	end

	-- Number key n (1-9) selects the n-th slot shown; false when nothing was there / the bar is hidden.
	function self.pressKey(n: number): boolean
		if menuOpen or carrying or panelOpen then
			return false
		end
		local bar = applyBar()
		local entry = InventoryCore.byKey(entries, bar.shown, n)
		if entry then
			perform(entry)
			return true
		end
		return false
	end

	function self.keyCodeToSlot(key: Enum.KeyCode): number?
		return KEYS[key]
	end

	-- Cooldown numbers tick once a second between State pushes.
	function self.tick()
		local now = deps.serverNow()
		for _, slot in barSlots do
			if slot.entry and slot.entry.readyAt then
				styleSlot(slot, slot.entry, now)
			end
		end
	end

	deps.tools.onChanged(function()
		sync()
	end)
	sync(true)
	return self
end

return Inventory
