--!strict
--[[
	Inventory (S3): the hotbar and the inventory panel that replace Roblox's default backpack bar.

	Bottom-centre hotbar (Layout.screen's `hotbar` zone, InventoryLayout): the Bat first, then every other
	held Tool and every owned PvP item (InventoryCore.entries), each a rounded purple slot with its ItemIcons
	picture, a selected highlight, the stack count when there is one and the number key (1-9) on keyboards.
	The name shows on hover (mouse) or on a long press (touch). A tap / click / number key equips (or puts
	away) the item through the EXISTING actions only: a Tool through the Humanoid, a PvP item through
	Request("EquipPvpItem"), a consumable (the stack count on its slot) goes into the hand client-side and is
	used by clicking / tapping the world while held: Request("UseConsumable") (the server checks ownership and
	stock and takes one off the stack). An equipped PvP item is used the same way: the click becomes
	Request("UsePvpItem", id, targetUserId?, aim?) (InventoryCore.pvpUseRequest from deps.aim's sample); a refusal
	(cooldown, safe zone, out of reach) shows as a short tip above the slot. The last cell is the bag: it opens the inventory panel, a grid of everything
	held (also the items that did not fit the bar on a narrow phone). Hidden while carrying (the server
	unequips tools then) and while a menu is open. Client-only: the stack counts come from State.consumables.

	The bag panel's cells are hotbar slots (same fill, outline, selection ring and key number for the items on
	the bar) with the name under the picture; empty Ink slots fill the grid to whole rows (InventoryLayout.CELL)
	and the card is sized to that grid. A tap / click on a cell equips like the hotbar and closes the panel.
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
Inventory.USE_GAP = 0.5 -- seconds between two uses (the server's own limit for UseConsumable)

-- The HUD tile palette (Hud money plates): rounded purple with the dark stroke.
Inventory.COLORS = table.freeze({
	plate = Color3.fromRGB(58, 36, 110),
	slot = Color3.fromRGB(84, 58, 150),
	selected = Color3.fromRGB(128, 86, 224),
	stroke = Color3.fromRGB(10, 10, 20),
	ring = Color3.fromRGB(255, 255, 255),
})

-- Bag panel text sizes and the empty slot's see-through Ink.
Inventory.PANEL = table.freeze({
	hintSize = 14,
	chipSize = 13,
	nameSize = 14,
	emptyTransparency = 0.45,
	chipRoom = 96, -- width the hint leaves for the count chip
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

-- Keys that open / close the bag: ` (Roblox's own backpack key, free while the default backpack is off), B, and
-- gamepad Y. `label` is the key shown on the bag cell and in its tooltip on keyboards.
Inventory.BAG_KEYS = table.freeze({
	keys = table.freeze({
		[Enum.KeyCode.Backquote] = true,
		[Enum.KeyCode.B] = true,
		[Enum.KeyCode.ButtonY] = true,
	}),
	label = "`",
})

type Deps = {
	Config: any,
	itemIcons: any, -- ItemIcons registry
	send: (action: string, ...any) -> (),
	-- Like send, but `done` gets the RequestResult ({ ok, message? }) of a call that reached the server.
	request: ((action: string, done: (result: any) -> (), ...any) -> ())?,
	-- What a click at a screen point aims at (ui/PvpAim.sample); nil = PvP items can't be used.
	aim: ((screen: Vector2 | Vector3) -> InventoryCore.Aim)?,
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
	local heldConsumable: string? = nil -- the consumable in hand (client-side; the server only validates the use)
	local lastUse = -math.huge
	local lastPvpEquipped: string? = nil
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

	local sync: (force: boolean?) -> ()

	local function perform(entry: Entry)
		local action = InventoryCore.select(entry)
		if action.kind == "Consumable" then
			-- one hand: a Tool or a PvP item goes away first
			if action.equip then
				deps.tools.unequipAll()
				if state and state.pvp and state.pvp.equipped then
					deps.send(InventoryCore.PVP_ACTION)
				end
			end
			heldConsumable = if action.equip then action.itemId else nil
			sync(true)
			return
		end
		heldConsumable = nil
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
	Widgets.label({
		Name = "Number",
		Text = Inventory.BAG_KEYS.label,
		Visible = keyboard,
		Font = Theme.Font,
		TextSize = 13,
		TextStrokeTransparency = 0.4,
		TextTruncate = Enum.TextTruncate.None,
		Size = fromOffset(18, 16),
		Position = fromOffset(4, 1),
		ZIndex = 6,
		Parent = bag,
	})
	bagIcon.TextYAlignment = Enum.TextYAlignment.Center
	local bagTip = if keyboard then `Inventory ({Inventory.BAG_KEYS.label})` else "Inventory"
	bag.MouseEnter:Connect(function()
		showTip(bag, bagTip)
	end)
	bag.MouseLeave:Connect(hideTip)

	-- The bar for the current entries and screen (geometry only).
	local function barGeometry(): InventoryLayout.Bar
		local zone = if screen then screen.hotbar else Layout.rect(0, 0, 600, 67)
		local compact = if screen then screen.compact else false
		local tight = if screen then screen.tight else false
		return InventoryLayout.bar(zone, #entries, compact, Layout.MIN_TOUCH_DESIGN, tight)
	end

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
	local panel = Widgets.panel(parent, "InventoryPanel", "Inventory", "🎒")
	local P = Inventory.PANEL
	local CELL = InventoryLayout.CELL
	Widgets.label({
		Name = "Hint",
		Text = `{if keyboard then "Click" else "Tap"} an item to equip it.`,
		TextSize = P.hintSize,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, -P.chipRoom, 0, CELL.top),
		Parent = panel.body,
	})
	local countChip = Widgets.chip({
		Name = "Count",
		Font = Theme.FontBody,
		TextSize = P.chipSize,
		TextColor3 = Theme.Muted,
		BackgroundColor3 = Theme.Row,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 1),
		Size = fromOffset(0, CELL.top - 2),
		Parent = panel.body,
	})
	local list = Widgets.scroll({
		Name = "Grid",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		Position = fromOffset(0, CELL.top + CELL.topGap),
		Size = UDim2.new(1, 0, 1, -(CELL.top + CELL.topGap)),
		Parent = panel.body,
	})
	local gridCells: { Slot } = {}
	local cellNames: { TextLabel } = {}
	local emptyCells: { Frame } = {}

	local function makeCell(): (Slot, TextLabel)
		local slot = makeSlot(list, CELL.max, false)
		slot.button.Name = "Item"
		Widgets.shade(slot.button)
		slot.icon.instance.AnchorPoint = Vector2.new(0.5, 0)
		slot.count.AnchorPoint = Vector2.new(1, 0)
		slot.count.Position = UDim2.new(1, -6, 0, 4)
		bindSlot(slot, function(e: Entry)
			perform(e)
			setPanelOpen(false)
		end, false)
		local name = Widgets.label({
			Name = "Name",
			Font = Theme.Font,
			TextSize = P.nameSize,
			TextColor3 = Theme.Text,
			TextStrokeColor3 = Theme.Ink,
			TextStrokeTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -CELL.inset / 2),
			Size = UDim2.new(1, -CELL.inset, 0, CELL.name),
			ZIndex = 6,
			Parent = slot.button,
		})
		return slot, name
	end

	local function makeEmpty(): Frame
		return create("Frame", {
			Name = "Empty",
			BackgroundColor3 = Theme.Ink,
			BackgroundTransparency = P.emptyTransparency,
			BorderSizePixel = 0,
			Parent = list,
		}, { Widgets.corner(10) })
	end

	local function bodyWidth(): number
		return if screen then Layout.panelBody(Layout.panelFor(screen, "Inventory")).w else Layout.MENU_WIDTH
	end

	-- The card sized to its grid (Layout.panelFor clamps it to the backdrop; the grid scrolls past that).
	local function placePanel()
		if not screen then
			return
		end
		local r = Layout.panelFor(screen, "Inventory", InventoryLayout.contentHeight(#entries, bodyWidth()))
		panel.frame.Position = fromOffset(r.x, r.y)
		panel.frame.Size = fromOffset(r.w, r.h)
	end

	local function refreshGrid(now: number)
		local bodyW = bodyWidth()
		local cols = InventoryLayout.columns(bodyW)
		local size = InventoryLayout.cellSize(bodyW)
		local total = InventoryLayout.slotCount(#entries, bodyW)
		local gridW = cols * size + (cols - 1) * CELL.gap
		local x0 = math.floor((bodyW - gridW) / 2)
		local shown = if keyboard then barGeometry().shown else 0
		local iconSize = size - CELL.inset * 2 - CELL.name
		local function at(i: number): UDim2
			local col, row = (i - 1) % cols, (i - 1) // cols
			return fromOffset(x0 + col * (size + CELL.gap), row * (size + CELL.gap))
		end
		for i, entry in entries do
			if gridCells[i] == nil then
				gridCells[i], cellNames[i] = makeCell()
			end
			local slot, name = gridCells[i], cellNames[i]
			styleSlot(slot, entry, now)
			name.Text = entry.name
			slot.number.Visible = i <= shown
			slot.number.Text = tostring(i)
			slot.button.Visible = true
			slot.button.Size = fromOffset(size, size)
			slot.button.Position = at(i)
			slot.icon.instance.Size = fromOffset(iconSize, iconSize)
			slot.icon.instance.Position = UDim2.new(0.5, 0, 0, CELL.inset)
		end
		for i = #entries + 1, #gridCells do
			gridCells[i].button.Visible = false
		end
		local empties = total - #entries
		for k = 1, math.max(empties, #emptyCells) do
			local cell = emptyCells[k]
			if k <= empties then
				if cell == nil then
					cell = makeEmpty()
					emptyCells[k] = cell
				end
				cell.Visible = true
				cell.Size = fromOffset(size, size)
				cell.Position = at(#entries + k)
			elseif cell then
				cell.Visible = false
			end
		end
		countChip.Text = if #entries == 1 then "1 item" else `{#entries} items`
		list.CanvasSize = fromOffset(0, InventoryLayout.gridHeight(total, bodyW))
		placePanel()
	end

	-- Refresh --------------------------------------------------------------------------------------
	local function currentEntries(): { Entry }
		local stackList = InventoryCore.entries({
			tools = deps.tools.list(),
			pvp = if state then state.pvp else nil,
			config = deps.Config,
			registry = registry,
			counts = nil,
			held = if state and state.consumables then state.consumables.held else nil,
			heldConsumable = heldConsumable,
			now = deps.serverNow(),
		})
		if heldConsumable then
			-- the last one was used (or the stack is gone): the hand is empty again
			local still = false
			for _, entry in stackList do
				still = still or (entry.kind == "consumable" and entry.itemId == heldConsumable)
			end
			if not still then
				heldConsumable = nil
				for _, entry in stackList do
					entry.equipped = entry.equipped and entry.kind ~= "consumable"
				end
			end
		end
		return stackList
	end

	local function applyBar()
		local now = deps.serverNow()
		local compact = if screen then screen.compact else false
		local tight = if screen then screen.tight else false
		local bar = barGeometry()
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

	function sync(force: boolean?)
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
		sync(true)
		placePanel()
	end

	function self.update(newState: any)
		state = newState
		carrying = newState ~= nil and newState.carrying ~= nil
		if carrying then
			heldConsumable = nil -- the server unequips while carrying
		end
		local pvpNow = if newState and newState.pvp then newState.pvp.equipped else nil
		if pvpNow ~= nil and pvpNow ~= lastPvpEquipped then
			heldConsumable = nil -- an equipped PvP item took the hand
		end
		lastPvpEquipped = pvpNow
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

	-- A short tip above the bar slot of `entry` (the bag cell when it did not fit the bar).
	local function feedback(entry: Entry, text: string)
		for _, slot in barSlots do
			if slot.button.Visible and slot.entry and slot.entry.key == entry.key then
				showTip(slot.button, text, Inventory.TIP_SECONDS)
				return
			end
		end
		showTip(bag, text, Inventory.TIP_SECONDS)
	end

	-- Sends `request`; a refusal from the server becomes a tip on the entry's slot.
	local function sendUse(entry: Entry, request: { any }, count: number)
		local call = deps.request
		if call then
			call(request[1], function(result: any)
				if type(result) == "table" and result.ok == false then
					feedback(entry, InventoryCore.reasonText(result.message))
				end
			end, table.unpack(request, 2, count))
		else
			deps.send(table.unpack(request, 1, count))
		end
	end

	local function equippedPvp(): Entry?
		for _, entry in entries do
			if entry.kind == "pvp" and entry.equipped then
				return entry
			end
		end
		return nil
	end

	local function toolDef(id: string): any
		for _, def in deps.Config.PVP_TOOLS do
			if def.id == id then
				return def
			end
		end
		return nil
	end

	-- Click / tap in the world (`at` = its screen point) with a consumable in hand or a PvP item equipped:
	-- asks the server to use it. False when nothing is held, the bar is hidden, the use is too soon after the
	-- last, or there is nothing to send yet (then a tip says why).
	function self.useHeld(at: (Vector2 | Vector3)?): boolean
		if menuOpen or carrying or panelOpen then
			return false
		end
		local pvpEntry = if heldConsumable == nil then equippedPvp() else nil
		if heldConsumable == nil and pvpEntry == nil then
			return false
		end
		local now = os.clock()
		if now - lastUse < Inventory.USE_GAP then
			return false
		end
		if pvpEntry then
			if not deps.aim or not at then
				return false
			end
			local use, reason = InventoryCore.pvpUseRequest(
				pvpEntry,
				toolDef(pvpEntry.itemId),
				deps.aim(at),
				deps.Config,
				deps.serverNow()
			)
			if not use then
				if reason then
					feedback(pvpEntry, reason)
				end
				return false
			end
			lastUse = now
			sendUse(pvpEntry, { use.action, use.itemId, use.target, use.aim }, 4)
			return true
		end
		for _, entry in entries do
			if entry.kind == "consumable" and entry.itemId == heldConsumable then
				local request = InventoryCore.useRequest(entry)
				if not request then
					feedback(entry, "Not in hand")
					return false
				end
				lastUse = now
				sendUse(entry, request, #request)
				return true
			end
		end
		return false
	end

	function self.heldConsumable(): string?
		return heldConsumable
	end

	function self.keyCodeToSlot(key: Enum.KeyCode): number?
		return KEYS[key]
	end

	function self.isBagKey(key: Enum.KeyCode): boolean
		return Inventory.BAG_KEYS.keys[key] == true
	end

	-- The bag key: closes an open bag, opens it unless the bar is hidden (a menu is open or carrying).
	-- True when the panel changed.
	function self.toggleBag(): boolean
		if panelOpen then
			setPanelOpen(false)
			return true
		end
		if menuOpen or carrying then
			return false
		end
		setPanelOpen(true)
		return true
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
		for _, tool in deps.tools.list() do
			if tool.equipped then
				heldConsumable = nil -- a Tool took the hand
			end
		end
		sync()
	end)
	sync(true)
	return self
end

return Inventory
