--!strict
--[[
	Inventory (S3): the hotbar and the inventory panel that replace Roblox's default backpack bar.

	Bottom-centre hotbar (Layout.screen's `hotbar` zone, InventoryLayout): the player's hotbar slots 1-9
	(InventoryCore.hotbarSlots: the saved State.hotbar order, or by default the Bat, every other held Tool, every
	owned PvP item and consumable in InventoryCore.entries order), up to the last filled slot, each a rounded
	purple slot with its ItemIcons picture, a selected highlight, the stack count when there is one and the
	number key (1-9) on keyboards; an empty slot before the last filled one is a dim Ink cell and its key does
	nothing.
	The name shows on hover (mouse) or on a long press (touch). A tap / click / number key equips (or puts
	away) the item through the EXISTING actions only: a Tool through the Humanoid, a PvP item through
	Request("EquipPvpItem"), a consumable (the stack count on its slot) goes into the hand client-side and is
	used by clicking / tapping the world while held: Request("UseConsumable") (the server checks ownership and
	stock and takes one off the stack). An equipped PvP item is used the same way: the click becomes
	Request("UsePvpItem", id, targetUserId?, aim?, charged?) (InventoryCore.pvpUseRequest from deps.aim's sample);
	a glove, the Goo Cannon, the Confetti Popper and Goo Fireworks fire on the release (pressHeld / releaseHeld), so a
	hold is a power punch / an aimed lob / a mega pop / a volley. A refusal (cooldown, out of reach) shows as a short tip above the slot. The last cell is the bag: it opens the inventory panel, a grid of everything
	held (also the items that did not fit the bar on a narrow phone). Hidden while carrying (the server
	unequips tools then) and while a menu is open. Client-only: the stack counts come from State.consumables.

	The bag panel (built on first open) shows the hotbar on a plate (the 9 slots on two rows, empty ones as Ink
	wells with their key) over the bag: every owned item as a hotbar-style cell with the name under the picture
	and, when it is a stack, a gold tag with how many are held; empty Ink slots fill the grid to whole rows
	(InventoryLayout.CELL) and the card is sized to its content. A tap / click on a cell or plate slot equips like
	the hotbar and closes the panel. Pressing one and moving past DRAG.threshold drags it instead: a ghost follows
	the pointer, the plate slot under it gets a gold ring, and the drop rearranges the hotbar
	(InventoryCore.applyDrop). The new order shows at once and goes to the server as Request("SetHotbar", order);
	it wins over State.hotbar until a State carries it (or the server refuses it, which shows a short tip). An
	item first seen this session while an order is saved goes on the first empty slot, else on a slot kept for an
	item the player no longer holds (InventoryCore.placeNew), so a new purchase still lands on the bar.
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

-- The hotbar in the Goo kit: a glass plate, glass-row slots, the equipped slot lighter with the Gold ring.
Inventory.COLORS = table.freeze({
	plate = Theme.Bg,
	slot = Theme.Row,
	selected = Theme.BgLight,
	stroke = Theme.Ink,
	ring = Theme.Gold,
})

-- Bag panel text sizes and the empty slot's see-through Ink.
Inventory.PANEL = table.freeze({
	hintSize = 14,
	chipSize = Layout.MIN_TEXT,
	nameSize = 14,
	headingSize = 18,
	emptyTransparency = 0.45,
	headingRoom = 120, -- width a heading keeps left of its hint / count chip
	plateRadius = 18,
	plateStroke = 3,
	tagSize = Layout.MIN_TEXT, -- the gold amount tag on a bag cell that holds a stack
	tagW = 22,
	tagWide = 30, -- for "99+"
	tagH = 18,
	tagInset = 5,
})

-- Dragging a cell onto the hotbar plate.
Inventory.DRAG = table.freeze({
	threshold = 8, -- design px a press moves before it is a drag instead of a tap
	rotation = -6, -- the ghost's tilt
	ring = 3, -- the ghost's white ring and the target's gold ring
	ringOut = 8, -- how far the target ring sits outside the slot (both sides together)
	liftTransparency = 0.35, -- the Ink veil over the dragged item's own cell
})

Inventory.ORDER_GAP = 0.35 -- seconds between two SetHotbar sends (the server allows one per 0.3 s)
Inventory.ORDER_TIMEOUT = 5 -- seconds an unconfirmed order (or an unanswered send) is trusted after its last send
-- Server refusals that pass on their own (Actions: rate limit, session not loaded yet): the order is sent again,
-- up to ORDER_RETRIES times.
Inventory.ORDER_RETRY = table.freeze({ ["too fast"] = true, ["still loading"] = true })
Inventory.ORDER_RETRIES = 10
Inventory.JOIN_GRACE = 10 -- seconds after the first State in which an arriving Tool is not new (placeNewItems)
Inventory.HINT = "Drag items here" -- the plate heading's hint
-- The bag panel holding nothing but the starting Bat (already on the hotbar): this message instead of the grid.
Inventory.EMPTY = table.freeze({
	title = "Your bag is empty",
	body = "Items you buy at the Item shop and rewards from goals show up here.",
	titleSize = 24,
	titleH = 30,
	bodySize = 16,
	bodyH = 44,
	gap = 8,
})
Inventory.ORDER_TEXT = table.freeze({
	refused = "Couldn't save your hotbar",
	blanked = "That item can't go on the hotbar",
})

-- True when the bag holds nothing but the Bat every player starts with.
function Inventory.bagEmpty(entries: { InventoryCore.Entry }): boolean
	for _, e in entries do
		if not (e.kind == "tool" and e.itemId == InventoryCore.BAT) then
			return false
		end
	end
	return true
end

function Inventory.footerText(keyboard: boolean): string
	return "Drag an item onto a hotbar slot to put it there. Drag it off the bar to take it off. "
		.. `{if keyboard then "Click" else "Tap"} an item to equip it.`
end

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
	-- Plays the equipped item's use animation on the local character (ui/PvpAnim); nil = none.
	animate: ((itemId: string) -> ())?,
	tools: any, -- InventoryTools.Provider
	serverNow: () -> number,
	keyboard: boolean?, -- show number keys (default true)
	-- UserInputService (InputChanged / InputEnded follow a drag); default the real service.
	input: any?,
}

type Slot = {
	button: TextButton,
	icon: any,
	number: TextLabel,
	count: TextLabel,
	cooldown: TextLabel,
	entry: Entry?,
	name: TextLabel?, -- panel cells: the name under the picture
	tag: TextLabel?, -- bag cells: the gold amount tag
	from: InventoryCore.DragFrom?, -- panel cells: what a drag from here moves
}
type Entry = InventoryCore.Entry
type Rect = InventoryLayout.Rect
type Press = {
	slot: Slot,
	from: InventoryCore.DragFrom,
	input: InputObject,
	x: number,
	y: number,
	dragging: boolean,
	conns: { RBXScriptConnection },
}

function Inventory.new(parent: Instance, deps: Deps)
	local registry = InventoryCore.withTools(deps.itemIcons)
	local C = Inventory.COLORS
	local P = Inventory.PANEL
	local DRAG = Inventory.DRAG
	local CELL = InventoryLayout.CELL
	local MAX = InventoryLayout.MAX_SLOTS
	local keyboard = deps.keyboard ~= false
	local userInput: any = deps.input or game:GetService("UserInputService")
	local footerText = Inventory.footerText(keyboard)

	local state: any = nil -- latest State
	local entries: { Entry } = {}
	local slots: { Entry? } = {} -- the hotbar slots 1..MAX (holes = empty)
	local keys: { string } = table.create(MAX, "") -- their keys, "" = empty
	local signature = ""
	local menuOpen = false
	local carrying = false
	local screen: Layout.Screen? = nil
	local panelOpen = false
	local heldConsumable: string? = nil -- the consumable in hand (client-side; the server only validates the use)
	local lastUse = -math.huge
	local lastPvpEquipped: string? = nil
	local holdStartedAt: number? = nil -- os.clock() a press on a hold item (InventoryCore.pvpHolds) went down, until released
	local pendingOrder: { string }? = nil -- the order the player just made, until a State confirms it
	local seen: { [string]: boolean }? = nil -- every entry key seen this session (nil until the first State)
	local joinedAt = -math.huge -- os.clock() of the first State
	local retries = 0 -- passing refusals of the pending order sent again so far
	local setPanelOpen: (open: boolean) -> ()
	local orderTip: (text: string) -> ()

	-- Hotbar ------------------------------------------------------------------------------------------
	local root = create("Frame", {
		Name = "Hotbar",
		BackgroundColor3 = C.plate,
		BackgroundTransparency = 0.05,
		ZIndex = Layout.ZINDEX.Base,
		Parent = parent,
	}, { Widgets.corner(Widgets.KIT.plateRadius), Widgets.stroke(C.stroke, Widgets.KIT.stroke) })

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
		}, { Widgets.corner(Widgets.KIT.slotRadius), Widgets.stroke(C.stroke, Widgets.KIT.stroke) }) :: TextButton
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
			BackgroundColor3 = Theme.Ink,
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
		slot.icon.instance.Visible = true
		slot.button.BackgroundColor3 = if entry.equipped then C.selected else C.slot
		slot.button.BackgroundTransparency = 0
		local stroke = slot.button:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = if entry.equipped then C.ring else C.stroke
		stroke.Thickness = if entry.equipped then 3 else 2
		local text = InventoryCore.countText(entry.count)
		slot.count.Visible = text ~= nil
		slot.count.Text = text or ""
		local left = InventoryCore.cooldownText(entry, now)
		slot.cooldown.Visible = left ~= nil
		slot.cooldown.Text = left or ""
		slot.number.TextColor3 = Theme.Text
		if slot.name then
			slot.name.Text = entry.name
			slot.name.Visible = true
		end
	end

	-- An empty hotbar slot: an Ink well (see-through by `transparency`) with only its key number.
	local function styleEmpty(slot: Slot, transparency: number)
		slot.entry = nil
		slot.icon.instance.Visible = false
		slot.button.BackgroundColor3 = Theme.Ink
		slot.button.BackgroundTransparency = transparency
		local stroke = slot.button:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = C.stroke
		stroke.Thickness = 2
		slot.count.Visible = false
		slot.cooldown.Visible = false
		slot.number.TextColor3 = Theme.Muted
		if slot.name then
			slot.name.Visible = false
		end
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

	-- The tap that ends a drag is not a tap: the cell the drag started from ignores its next Activated.
	local suppressTap: GuiObject? = nil

	local function bindSlot(
		slot: Slot,
		onActivate: (Entry) -> (),
		withTip: boolean,
		onPress: ((Slot, InputObject) -> ())?
	)
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
			if onPress then
				onPress(slot, input)
			end
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
			if suppressTap == slot.button then
				suppressTap = nil
				return
			end
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
	for i = 1, MAX do
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
	}, { Widgets.corner(Widgets.KIT.slotRadius), Widgets.stroke(C.stroke, Widgets.KIT.stroke) }) :: TextButton
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

	-- The bar for the current slots and screen (geometry only): slots 1..last filled, clamped to what fits.
	local function barGeometry(): InventoryLayout.Bar
		local zone = if screen then screen.hotbar else Layout.rect(0, 0, 600, 67)
		local compact = if screen then screen.compact else false
		local tight = if screen then screen.tight else false
		return InventoryLayout.bar(zone, InventoryCore.lastFilled(slots, MAX), compact, Layout.MIN_TOUCH_DESIGN, tight)
	end

	-- Hotbar order ------------------------------------------------------------------------------------
	local function savedOrder(): { string }?
		return pendingOrder or InventoryCore.savedKeys(if state then state.hotbar else nil, MAX)
	end

	-- One SetHotbar in flight at a time, ORDER_GAP apart; a newer order made meanwhile goes after it.
	local flight = { busy = false, at = -math.huge, queued = false, delayed = false }
	local function sendOrder()
		local order = pendingOrder
		if order == nil then
			return
		end
		local now = os.clock()
		if flight.busy and now - flight.at < Inventory.ORDER_TIMEOUT then
			flight.queued = true
			return
		end
		local wait = flight.at + Inventory.ORDER_GAP - now
		if wait > 0 then
			if not flight.delayed then
				flight.delayed = true
				task.delay(wait, function()
					flight.delayed = false
					sendOrder()
				end)
			end
			return
		end
		flight.at = now
		flight.queued = false
		local text = InventoryCore.orderString(order)
		local call = deps.request
		if call then
			flight.busy = true
			local sentAt = now
			call(InventoryCore.HOTBAR_ACTION, function(result: any)
				flight.busy = false
				local refused = type(result) == "table" and result.ok == false
				if refused and pendingOrder == order then
					local passing = Inventory.ORDER_RETRY[result.message] == true
					if passing and retries < Inventory.ORDER_RETRIES then
						retries += 1
						flight.queued = true -- the same order again, ORDER_GAP after this one
					else
						pendingOrder = nil -- refused: the server's order stands
						sync(true)
						orderTip(Inventory.ORDER_TEXT.refused)
					end
				end
				if flight.queued then
					sendOrder()
				end
			end, text)
			-- a call that never answers (the remote failed) frees the line after ORDER_TIMEOUT
			task.delay(Inventory.ORDER_TIMEOUT, function()
				if flight.busy and flight.at == sentAt then
					flight.busy = false
					if flight.queued then
						sendOrder()
					end
				end
			end)
		else
			deps.send(InventoryCore.HOTBAR_ACTION, text)
		end
	end

	-- Makes `order` the hotbar now and sends it; false when it is the order already shown.
	local function setOrder(wanted: { string }): boolean
		local order = InventoryCore.cleanOrder(wanted)
		if InventoryCore.orderString(order) == InventoryCore.orderString(keys) then
			return false
		end
		pendingOrder = order
		retries = 0
		keys = order
		sendOrder()
		return true
	end

	--[[
		Items first seen this session go on the first empty slot of a saved order, else on a slot kept for an item
		the player no longer holds. PvP items and consumables come in State, so the first State lists all the
		player already had. Tools reach the Backpack on their own schedule, often after that first State: for
		JOIN_GRACE seconds after it an arriving Tool counts as already had, so a Tool the player took off the bar
		stays off on rejoin, and no saved Tool slot is handed to another item while the Tools are still arriving.
		After that a Tool seen this session keeps its slot while a respawn refills the Backpack.
	]]
	local function placeNewItems()
		local known = seen
		if known == nil then
			return
		end
		local joining = os.clock() - joinedAt < Inventory.JOIN_GRACE
		local fresh: { string } = {}
		local owned: { [string]: boolean } = {}
		for _, entry in entries do
			owned[entry.key] = true
			if not known[entry.key] then
				known[entry.key] = true
				if not (joining and entry.kind == "tool") then
					table.insert(fresh, entry.key)
				end
			end
		end
		local saved = savedOrder()
		if #fresh > 0 and saved then
			for _, key in saved do
				if string.sub(key, 1, 5) == "tool:" and (joining or known[key]) then
					owned[key] = true
				end
			end
			local placed, changed = InventoryCore.placeNew(saved, fresh, owned)
			if changed then
				setOrder(placed)
			end
		end
	end

	-- Inventory panel -------------------------------------------------------------------------------
	local backdrop = Widgets.backdrop({
		Name = "InventoryBackdrop",
		ZIndex = Layout.ZINDEX.Menu,
		Parent = parent,
	})
	local panel = Widgets.panel(parent, "InventoryPanel", "Inventory", "🎒")

	local function bodyWidth(): number
		return if screen then Layout.panelBody(Layout.panelFor(screen, "Inventory")).w else Layout.MENU_WIDTH
	end

	-- The card sized to its content (Layout.panelFor clamps it to the backdrop; the bag grid scrolls past that).
	-- Returns the body height, nil before the first layout.
	local function placePanel(): number?
		if not screen then
			return nil
		end
		local bodyW = bodyWidth()
		local footerH = Layout.wrappedHeight(footerText, P.hintSize, bodyW)
		local r = Layout.panelFor(screen, "Inventory", InventoryLayout.contentHeight(#entries, bodyW, footerH))
		panel.frame.Position = fromOffset(r.x, r.y)
		panel.frame.Size = fromOffset(r.w, r.h)
		return Layout.panelBody(r).h
	end

	-- A heading line: the title left, `detail` (a label or chip) right.
	local function heading(name: string, text: string): Frame
		local row = create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, CELL.top),
			Parent = panel.body,
		})
		Widgets.label({
			Name = "Title",
			Text = text,
			Font = Theme.Font,
			TextSize = P.headingSize,
			TextColor3 = Theme.Text,
			TextStrokeColor3 = Theme.Ink,
			TextStrokeTransparency = 0,
			Size = UDim2.new(1, -P.headingRoom, 1, 0),
			Parent = row,
		})
		return row
	end

	local panelOnDrag: (Slot, InputObject) -> ()

	-- A panel cell: a hotbar slot with the name under the picture.
	local function makeCell(host: Instance, size: number, withNumber: boolean): Slot
		local slot = makeSlot(host, size, withNumber)
		Widgets.shade(slot.button)
		slot.icon.instance.AnchorPoint = Vector2.new(0.5, 0)
		slot.count.AnchorPoint = Vector2.new(1, 0)
		slot.count.Position = UDim2.new(1, -6, 0, 4)
		bindSlot(slot, function(e: Entry)
			perform(e)
			setPanelOpen(false)
		end, false, panelOnDrag)
		slot.name = Widgets.label({
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
		return slot
	end

	-- Sizes a panel cell: `size` square, the picture above the name.
	local function sizeCell(slot: Slot, size: number)
		local iconSize = math.max(1, size - CELL.inset * 2 - CELL.name)
		slot.button.Size = fromOffset(size, size)
		slot.icon.instance.Size = fromOffset(iconSize, iconSize)
		slot.icon.instance.Position = UDim2.new(0.5, 0, 0, CELL.inset)
	end

	type Parts = {
		bagHeading: Frame,
		countChip: TextLabel,
		barHeading: Frame,
		hint: TextLabel,
		plate: Frame,
		plateSlots: { Slot },
		list: ScrollingFrame,
		footer: TextLabel,
	}
	local parts: Parts? = nil
	local gridCells: { Slot } = {}
	local emptyCells: { Frame } = {}
	local plateHits: { Rect } = {} -- the plate slots in design px (ScreenGui space), for the drop

	-- The panel's content, built on first open.
	local function ensureParts(): Parts
		if parts then
			return parts
		end
		-- the bag heading first: its count chip is the panel's first "Count"
		local bagHeading = heading("BagHeading", "Bag")
		local countChip = Widgets.chip({
			Name = "Count",
			FontFace = Theme.FontBody,
			TextSize = P.chipSize,
			TextColor3 = Theme.Muted,
			BackgroundColor3 = Theme.Row,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 1),
			Size = fromOffset(0, CELL.top - 2),
			Parent = bagHeading,
		})
		local barHeading = heading("HotbarHeading", "Hotbar")
		local hint = Widgets.label({
			Name = "Hint",
			Text = Inventory.HINT,
			TextSize = P.hintSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, P.headingRoom * 2, 1, 0),
			Parent = barHeading,
		})
		local plate = create("Frame", {
			Name = "HotbarPlate",
			BackgroundColor3 = C.plate,
			Parent = panel.body,
		}, { Widgets.corner(P.plateRadius), Widgets.stroke(Theme.Ink, P.plateStroke) })
		local plateSlots: { Slot } = {}
		for i = 1, MAX do
			local slot = makeCell(plate, InventoryLayout.PLATE.max, true)
			slot.button.Name = `HotbarSlot{i}`
			slot.number.Text = tostring(i)
			slot.from = { kind = "bar", index = i }
			plateSlots[i] = slot
		end
		local list = Widgets.scroll({
			Name = "Grid",
			AutomaticCanvasSize = Enum.AutomaticSize.None,
			Parent = panel.body,
		})
		local footer = Widgets.label({
			Name = "Footer",
			Text = footerText,
			TextSize = P.hintSize,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = list,
		})
		local made: Parts = {
			bagHeading = bagHeading,
			countChip = countChip,
			barHeading = barHeading,
			hint = hint,
			plate = plate,
			plateSlots = plateSlots,
			list = list,
			footer = footer,
		}
		parts = made
		return made
	end

	-- A short note about the hotbar order: in the plate heading's hint while the panel is open, else above the bag.
	local hintToken = 0
	function orderTip(text: string)
		local p = parts
		if not (panelOpen and p) then
			showTip(bag, text, Inventory.TIP_SECONDS)
			return
		end
		hintToken += 1
		local token = hintToken
		p.hint.Text = text
		p.hint.TextColor3 = Theme.Warn
		task.delay(Inventory.TIP_SECONDS, function()
			if hintToken == token then
				p.hint.Text = Inventory.HINT
				p.hint.TextColor3 = Theme.Muted
			end
		end)
	end

	local function makeTag(slot: Slot): TextLabel
		local tag = Widgets.label({
			Name = "Amount",
			Visible = false,
			Font = Theme.Font,
			TextSize = P.tagSize,
			TextColor3 = Theme.Ink,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -P.tagInset, 0, P.tagInset),
			Size = fromOffset(P.tagW, P.tagH),
			ZIndex = 6,
			Parent = slot.button,
		})
		Widgets.corner(6).Parent = tag
		Widgets.stroke(Theme.Ink, 2).Parent = tag
		return tag
	end

	local function makeEmpty(host: Instance): Frame
		return create("Frame", {
			Name = "Empty",
			BackgroundColor3 = Theme.Ink,
			BackgroundTransparency = P.emptyTransparency,
			BorderSizePixel = 0,
			Parent = host,
		}, { Widgets.corner(10) })
	end

	-- Design-px offset of `gui` from the ScreenGui (every frame on the way is top-left anchored).
	local function offsetOf(gui: GuiObject): (number, number)
		local x, y = 0, 0
		local node: Instance? = gui
		while node and node ~= parent and node:IsA("GuiObject") do
			local pos = (node :: GuiObject).Position
			x += pos.X.Offset
			y += pos.Y.Offset
			node = node.Parent
		end
		return x, y
	end

	-- The empty state in place of the bag grid: a title and one line on where items come from. Built on first use.
	local emptyState: Frame? = nil
	local function showEmpty(empty: boolean, y: number)
		if empty and emptyState == nil then
			local e = Inventory.EMPTY
			local frame = create("Frame", {
				Name = "EmptyBag",
				BackgroundTransparency = 1,
				Parent = panel.body,
			})
			Widgets.label({
				Name = "Title",
				Text = e.title,
				Font = Theme.Font,
				TextSize = e.titleSize,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, e.titleH),
				Parent = frame,
			})
			Widgets.label({
				Name = "Body",
				Text = e.body,
				TextSize = e.bodySize,
				TextColor3 = Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				Position = UDim2.fromOffset(0, e.titleH + e.gap),
				Size = UDim2.new(1, 0, 0, e.bodyH),
				Parent = frame,
			})
			emptyState = frame
		end
		local frame = emptyState
		if frame then
			frame.Visible = empty
			frame.Position = UDim2.fromOffset(0, y + Inventory.EMPTY.gap)
			frame.Size = UDim2.new(1, 0, 0, Inventory.EMPTY.titleH + Inventory.EMPTY.gap + Inventory.EMPTY.bodyH)
		end
	end

	local function refreshPanel(now: number)
		local p = ensureParts()
		local bodyW = bodyWidth()
		local bodyH = placePanel()
		local empty = Inventory.bagEmpty(entries)
		-- Hotbar plate.
		local slotSize = InventoryLayout.plateSlot(bodyW, bodyH)
		local plateRect, plateRects = InventoryLayout.plate(bodyW, slotSize)
		p.barHeading.Position = fromOffset(0, 0)
		p.plate.Position = fromOffset(plateRect.x, plateRect.y)
		p.plate.Size = fromOffset(plateRect.w, plateRect.h)
		local plateX, plateY = offsetOf(p.plate)
		for i, slot in p.plateSlots do
			local r = plateRects[i]
			sizeCell(slot, r.w)
			slot.button.Position = fromOffset(r.x, r.y)
			local entry = slots[i]
			if entry then
				styleSlot(slot, entry, now)
			else
				styleEmpty(slot, 0)
			end
			plateHits[i] = { x = plateX + r.x, y = plateY + r.y, w = r.w, h = r.h }
		end
		-- Bag.
		local headingY, gridY = InventoryLayout.bagTop(slotSize)
		p.bagHeading.Position = fromOffset(0, headingY)
		p.list.Visible = not empty
		p.countChip.Visible = not empty
		showEmpty(empty, gridY)
		p.list.Position = fromOffset(0, gridY)
		p.list.Size = UDim2.new(1, 0, 1, -gridY)
		local cols = InventoryLayout.columns(bodyW)
		local size = InventoryLayout.cellSize(bodyW)
		local total = InventoryLayout.slotCount(#entries, bodyW)
		local gridW = cols * size + (cols - 1) * CELL.gap
		local x0 = math.floor((bodyW - gridW) / 2)
		local function at(i: number): UDim2
			local col, row = (i - 1) % cols, (i - 1) // cols
			return fromOffset(x0 + col * (size + CELL.gap), CELL.gridPad + row * (size + CELL.gap))
		end
		for i, entry in entries do
			local slot = gridCells[i]
			if slot == nil then
				slot = makeCell(p.list, size, false)
				slot.button.Name = "Item"
				slot.tag = makeTag(slot)
				gridCells[i] = slot
			end
			styleSlot(slot, entry, now)
			slot.from = { kind = "bag", key = entry.key }
			-- the amount shows on the gold tag, not as the slot's own count
			local amount = InventoryCore.countText(entry.count)
			local tag = slot.tag :: TextLabel
			tag.Visible = amount ~= nil
			tag.Text = amount or ""
			tag.Size = fromOffset(if amount and #amount > 2 then P.tagWide else P.tagW, P.tagH)
			slot.count.Visible = false
			slot.button.Visible = true
			slot.button.Position = at(i)
			sizeCell(slot, size)
		end
		for i = #entries + 1, #gridCells do
			gridCells[i].button.Visible = false
			gridCells[i].entry = nil
		end
		local empties = total - #entries
		for k = 1, math.max(empties, #emptyCells) do
			local cell = emptyCells[k]
			if k <= empties then
				if cell == nil then
					cell = makeEmpty(p.list)
					emptyCells[k] = cell
				end
				cell.Visible = true
				cell.Size = fromOffset(size, size)
				cell.Position = at(#entries + k)
			elseif cell then
				cell.Visible = false
			end
		end
		p.countChip.Text = if #entries == 1 then "1 item" else `{#entries} items`
		local gridH = InventoryLayout.gridHeight(total, bodyW)
		local footerH = Layout.wrappedHeight(footerText, P.hintSize, bodyW)
		local footerY = CELL.gridPad + gridH + InventoryLayout.PLATE.footerGap
		p.footer.Position = fromOffset(0, footerY)
		p.footer.Size = fromOffset(bodyW, footerH)
		p.list.CanvasSize = fromOffset(0, footerY + footerH)
	end

	-- Drag ---------------------------------------------------------------------------------------------
	type DragParts = { ghost: Frame, icon: any, name: TextLabel, lift: Frame, ring: Frame }
	local dragParts: DragParts? = nil
	local press: Press? = nil

	local function ensureDragParts(): DragParts
		if dragParts then
			return dragParts
		end
		local ghost = create("Frame", {
			Name = "DragGhost",
			Visible = false,
			BackgroundColor3 = C.slot,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = DRAG.rotation,
			ZIndex = Layout.ZINDEX.Banners,
			Parent = parent,
		}, { Widgets.corner(10), Widgets.stroke(C.ring, DRAG.ring) })
		Widgets.shade(ghost)
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = "Unknown",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, CELL.inset),
			ZIndex = 2,
			Parent = ghost,
		}, registry)
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
			Parent = ghost,
		})
		local lift = create("Frame", {
			Name = "Lift",
			BackgroundColor3 = Theme.Ink,
			BackgroundTransparency = DRAG.liftTransparency,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
		}, { Widgets.corner(10) })
		local ring = create("Frame", {
			Name = "DropRing",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, DRAG.ringOut, 1, DRAG.ringOut),
			ZIndex = 9,
		}, { Widgets.corner(14), Widgets.stroke(Theme.Gold, DRAG.ring) })
		local made: DragParts = { ghost = ghost, icon = icon, name = name, lift = lift, ring = ring }
		dragParts = made
		return made
	end

	local function toDesign(position: any): (number, number)
		local scale = if screen then screen.scale else 1
		return position.X / scale, position.Y / scale
	end

	local function endPress()
		local p = press
		if p == nil then
			return
		end
		press = nil
		for _, conn in p.conns do
			conn:Disconnect()
		end
		if dragParts then
			dragParts.ghost.Visible = false
			dragParts.lift.Parent = nil
			dragParts.ring.Parent = nil
		end
		if parts then
			parts.list.ScrollingEnabled = true
		end
	end

	local function beginDrag(p: Press)
		local entry = p.slot.entry
		if entry == nil then
			return
		end
		p.dragging = true
		suppressTap = p.slot.button
		hideTip()
		local d = ensureDragParts()
		local size = p.slot.button.Size.X.Offset
		d.ghost.Size = fromOffset(size, size)
		local iconSize = math.max(1, size - CELL.inset * 2 - CELL.name)
		d.icon.instance.Size = fromOffset(iconSize, iconSize)
		d.icon.set(entry.iconId)
		d.name.Text = entry.name
		d.ghost.Visible = true
		d.lift.Parent = p.slot.button
		if parts then
			parts.list.ScrollingEnabled = false -- a touch drag moves the item, not the bag
		end
	end

	local function moveDrag(x: number, y: number)
		local d = ensureDragParts()
		d.ghost.Position = fromOffset(x, y)
		local target = InventoryLayout.hit(plateHits, x, y)
		local p = parts
		d.ring.Parent = if target and p then p.plateSlots[target].button else nil
	end

	local function drop(from: InventoryCore.DragFrom, x: number, y: number)
		local target = InventoryLayout.hit(plateHits, x, y)
		local to: InventoryCore.DragTo = if target then { kind = "bar", index = target } else { kind = "bag" }
		local wanted = InventoryCore.applyDrop(keys, from, to)
		local _, blanked = InventoryCore.cleanOrder(wanted)
		if blanked then
			orderTip(Inventory.ORDER_TEXT.blanked)
		end
		if setOrder(wanted) then
			sync(true)
		end
	end

	-- A press on a panel cell: it becomes a drag once it moves DRAG.threshold, else the button's Activated taps.
	-- Moves and the release come from UserInputService (they leave the cell); a touch follows its own finger only.
	function panelOnDrag(slot: Slot, io: InputObject)
		local kind = io.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		suppressTap = nil
		endPress()
		local from = slot.from
		if not panelOpen or slot.entry == nil or from == nil then
			return
		end
		local x, y = toDesign(io.Position)
		local touch = kind == Enum.UserInputType.Touch
		local p: Press = { slot = slot, from = from, input = io, x = x, y = y, dragging = false, conns = {} }
		press = p
		local function ours(other: InputObject, mouseKind: Enum.UserInputType): boolean
			return if touch then other == io else other.UserInputType == mouseKind
		end
		table.insert(
			p.conns,
			userInput.InputChanged:Connect(function(changed: InputObject)
				if press ~= p or not ours(changed, Enum.UserInputType.MouseMovement) then
					return
				end
				local cx, cy = toDesign(changed.Position)
				if not p.dragging then
					local dx, dy = cx - p.x, cy - p.y
					if dx * dx + dy * dy < DRAG.threshold * DRAG.threshold then
						return
					end
					beginDrag(p)
				end
				moveDrag(cx, cy)
			end)
		)
		table.insert(
			p.conns,
			userInput.InputEnded:Connect(function(ended: InputObject)
				if press ~= p or not ours(ended, Enum.UserInputType.MouseButton1) then
					return
				end
				local dragging = p.dragging
				local ex, ey = toDesign(ended.Position)
				endPress()
				if dragging then
					drop(p.from, ex, ey)
				end
			end)
		)
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
				local entry = slots[i]
				if entry then
					styleSlot(slot, entry, now)
				else
					styleEmpty(slot, P.emptyTransparency)
				end
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
		placeNewItems()
		local saved = savedOrder()
		keys = InventoryCore.slotKeys(entries, saved, MAX)
		slots = InventoryCore.hotbarSlots(entries, saved, MAX)
		local sig = `{InventoryCore.signature(entries)}#{InventoryCore.orderString(keys)}`
		if sig ~= signature or force then
			signature = sig
			applyBar()
			if panelOpen and press == nil then
				refreshPanel(deps.serverNow())
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
			sync(true)
			refreshPanel(deps.serverNow())
		else
			endPress()
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

	-- `guiInset` (GuiService:GetGuiInset) lets the dim reach under the Roblox top bar.
	function self.layout(s: Layout.Screen, guiInset: Vector2?)
		screen = s
		local back = Layout.backdrop(s, if guiInset then guiInset.X else 0, if guiInset then guiInset.Y else 0)
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
		local pending = pendingOrder
		if pending then
			local server = InventoryCore.savedKeys(if newState then newState.hotbar else nil, MAX)
			local confirmed = server ~= nil and InventoryCore.orderString(server) == InventoryCore.orderString(pending)
			-- unconfirmed: kept while a send is out, queued or waiting its gap, and ORDER_TIMEOUT after the last one
			local idle = not (flight.busy or flight.queued or flight.delayed)
			if confirmed or (idle and os.clock() - flight.at > Inventory.ORDER_TIMEOUT) then
				pendingOrder = nil
			end
		end
		if carrying and panelOpen then
			setPanelOpen(false)
		end
		sync()
		if seen == nil then
			-- the first State: what the player has now is not new
			local known: { [string]: boolean } = {}
			for _, entry in entries do
				known[entry.key] = true
			end
			seen = known
			joinedAt = os.clock()
		end
	end

	-- A Menu card is open: the hotbar and the panel step aside.
	function self.setMenuOpen(open: boolean)
		menuOpen = open
		if open and panelOpen then
			setPanelOpen(false)
		end
		sync()
	end

	-- Number key n (1-9) selects hotbar slot n when the bar shows it; false when it is empty / the bar is hidden.
	function self.pressKey(n: number): boolean
		if menuOpen or carrying or panelOpen then
			return false
		end
		local bar = applyBar()
		local entry = InventoryCore.byKey(slots, bar.shown, n)
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
	function self.useHeld(at: (Vector2 | Vector3)?, held: number?): boolean
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
			local serverNow = deps.serverNow()
			local use, reason = InventoryCore.pvpUseRequest(
				pvpEntry,
				toolDef(pvpEntry.itemId),
				deps.aim(at),
				deps.Config,
				serverNow,
				held
			)
			if deps.animate and InventoryCore.pvpReady(pvpEntry, serverNow) then
				-- the swing / punch / throw shows at once, also for a whiff the server never hears about
				lastUse = now
				deps.animate(pvpEntry.itemId)
			end
			if not use then
				if reason then
					feedback(pvpEntry, reason)
				end
				return false
			end
			lastUse = now
			sendUse(pvpEntry, { use.action, use.itemId, use.target, use.aim, use.charged }, 5)
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

	-- A press on the world (`alreadyHeld` = seconds a touch long press was held before it fired). A hold item
	-- (InventoryCore.pvpHolds) waits for the release; everything else is used at once (useHeld).
	function self.pressHeld(at: Vector2 | Vector3, alreadyHeld: number?): boolean
		local entry = if heldConsumable == nil then equippedPvp() else nil
		if entry and not (menuOpen or carrying or panelOpen) and InventoryCore.pvpHolds(toolDef(entry.itemId)) then
			holdStartedAt = os.clock() - (alreadyHeld or 0)
			return true
		end
		holdStartedAt = nil
		return self.useHeld(at)
	end

	-- The release of a held press: sends the use with the seconds held (InventoryCore.pvpCharged: a power punch, a mega
	-- pop, a volley), the Cannon lobs at `at`.
	function self.releaseHeld(at: Vector2 | Vector3): boolean
		local started = holdStartedAt
		holdStartedAt = nil
		if started == nil then
			return false
		end
		return self.useHeld(at, os.clock() - started)
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
