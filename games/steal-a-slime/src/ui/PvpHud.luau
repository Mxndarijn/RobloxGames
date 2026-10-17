--!strict
--[[
	PvpHud (FEATURES.PvP, docs/PVP-CLIENT.md)

	The PvP HUD views over a PvpClient: the hotbar strip (one slot per PvpClient.hotbarSlots(): item icon, keybind,
	equipped rim, cooldown ring + seconds), the new-player shield chip (icon + m:ss) and the safe-zone chip. Only
	GUI objects under `parent` (a ScreenGui) and the Banners stack; nothing in Workspace. Built by PvpMount, only
	with the flag on. The client never decides: a tap calls client.activate(id) (equip, or use when already
	equipped), a number key calls client.pressKey(n); the server answers with State.pvp / PvpEvent.

	  PvpHud.new(parent, itemIcons, client, { banners = Frame?, input = UserInputService-like? })
	    .layout(screen)   hotbar boxes from PvpHudLogic.hotbar (Layout.screen design px)
	    .update()         re-read the client (slots, equipped rim); runs on client.onChanged
	    .tick()           cooldown rings, seconds, chips (cheap; ~10 Hz from init)
	    .destroy()
	The chips live in the Banners stack (LayoutOrder 11 / 12), so they take part in the banner height and hide
	with it. No `banners` = no chips. `input` (InputBegan, GetFocusedTextBox) enables the number keys.
]]

local ItemIconView = require(script.Parent.ItemIconView)
local Layout = require(script.Parent.Layout)
local PvpHudLogic = require(script.Parent.PvpHudLogic)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local PvpHud = {}

local RIM = 6 -- design px of the slot's coloured rim around its icon
local CORNER = 8

type SlotView = {
	id: string,
	button: TextButton,
	icon: any,
	key: TextLabel,
	seconds: TextLabel,
	rightHalf: Frame,
	leftHalf: Frame,
	rightGradient: UIGradient,
	leftGradient: UIGradient,
}

local function stepSequence(): NumberSequence
	local keys = {}
	for _, k in PvpHudLogic.RING_STEP do
		table.insert(keys, NumberSequenceKeypoint.new(k[1], k[2]))
	end
	return NumberSequence.new(keys)
end

-- One cooldown half: a clipped half-slot holding a slot-sized dark frame whose gradient step is rotated.
local function half(parent: Instance, name: string, right: boolean, z: number): (Frame, UIGradient)
	local clip = create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromScale(if right then 0.5 else 0, 0),
		Size = UDim2.fromScale(0.5, 1),
		Visible = false,
		ZIndex = z,
		Parent = parent,
	})
	local fill = create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.fromRGB(8, 10, 20),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(if right then -1 else 0, 0),
		Size = UDim2.fromScale(2, 1),
		ZIndex = z,
		Parent = clip,
	}, { Widgets.corner(CORNER) })
	local gradient = create("UIGradient", { Transparency = stepSequence(), Parent = fill }) :: UIGradient
	return clip, gradient
end

local function chip(parent: Instance, name: string, order: number, color: Color3): TextLabel
	local label = Widgets.label({
		Name = name,
		Visible = false,
		LayoutOrder = order,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = color,
		Font = Theme.Font,
		TextSize = 15,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, PvpHudLogic.CHIP_HEIGHT),
		ZIndex = Layout.ZINDEX.Banners,
		Parent = parent,
	})
	Widgets.corner(8).Parent = label
	return label
end

function PvpHud.new(parent: Instance, itemIcons: any, client: any, opts: { banners: Instance?, input: any? }?)
	local o: { banners: Instance?, input: any? } = opts or {}
	local z = Layout.ZINDEX.Base

	local frame = create("Frame", {
		Name = "PvpHotbar",
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = z,
		Parent = parent,
	})
	local strip = create("ScrollingFrame", {
		Name = "Strip",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.new(),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = frame,
	}) :: ScrollingFrame

	local shieldChip: TextLabel? = nil
	local shieldIcon: any = nil
	local zoneChip: TextLabel? = nil
	if o.banners then
		local shield = chip(o.banners, "PvpShield", PvpHudLogic.CHIP_ORDER_SHIELD, Color3.fromRGB(40, 100, 190))
		shield.TextXAlignment = Enum.TextXAlignment.Left
		Widgets.create("UIPadding", { PaddingLeft = UDim.new(0, PvpHudLogic.CHIP_HEIGHT + 6), Parent = shield })
		shieldIcon = ItemIconView.new({
			Name = "ShieldIcon",
			Id = "Lock",
			Size = PvpHudLogic.CHIP_HEIGHT - 6,
			Position = UDim2.fromOffset(-(PvpHudLogic.CHIP_HEIGHT + 2), 3),
			ZIndex = Layout.ZINDEX.Banners + 1,
			Parent = shield,
		}, itemIcons)
		shieldIcon.setActive(true)
		shieldChip = shield
		zoneChip = chip(o.banners, "PvpSafeZone", PvpHudLogic.CHIP_ORDER_ZONE, Color3.fromRGB(40, 130, 80))
	end

	local views: { [string]: SlotView } = {}
	local order: { string } = {}
	local screen: Layout.Screen? = nil
	local placedCount = -1
	local self: any = { frame = frame, strip = strip, views = views }

	local function buildSlot(slot: any, index: number): SlotView
		local size = PvpHudLogic.SLOT
		local button = create("TextButton", {
			Name = `Slot_{slot.id}`,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.BgLight,
			Position = UDim2.fromOffset((index - 1) * (size + PvpHudLogic.SLOT_GAP), 0),
			Size = UDim2.fromOffset(size, size),
			ZIndex = z + 1,
			Parent = strip,
		}, { Widgets.corner(CORNER) }) :: TextButton
		button:SetAttribute("ItemId", slot.id)
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = slot.id,
			Size = size - RIM * 2,
			Position = UDim2.fromOffset(RIM, RIM),
			ZIndex = z + 2,
			Parent = button,
		}, itemIcons)
		icon.setActive(true)
		local rightHalf, rightGradient = half(button, "RightHalf", true, z + 4)
		local leftHalf, leftGradient = half(button, "LeftHalf", false, z + 4)
		local key = Widgets.label({
			Name = "Keybind",
			Font = Theme.Font,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextStrokeTransparency = 0.4,
			Position = UDim2.fromOffset(5, 2),
			Size = UDim2.fromOffset(18, 14),
			ZIndex = z + 6,
			Parent = button,
		})
		local seconds = Widgets.label({
			Name = "Seconds",
			Font = Theme.Font,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			TextStrokeTransparency = 0.3,
			Visible = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z + 6,
			Parent = button,
		})
		button.Activated:Connect(function()
			client.activate(slot.id)
		end)
		return {
			id = slot.id,
			button = button,
			icon = icon,
			key = key,
			seconds = seconds,
			rightHalf = rightHalf,
			leftHalf = leftHalf,
			rightGradient = rightGradient,
			leftGradient = leftGradient,
		}
	end

	local function place()
		local s = screen
		if s == nil then
			return
		end
		local p = PvpHudLogic.hotbar(s, #order)
		placedCount = #order
		frame.Visible = p.visible > 0
		frame.Position = UDim2.fromOffset(math.round(p.box.x), math.round(p.box.y))
		frame.Size = UDim2.fromOffset(math.round(p.box.w), math.round(p.box.h))
		strip.CanvasSize = UDim2.fromOffset(math.round(p.canvasW), 0)
		strip.ScrollingEnabled = p.scrolls
	end

	function self.tick()
		for _, id in order do
			local view = views[id]
			local fraction, left = client.cooldown(id)
			local ring = PvpHudLogic.ring(fraction)
			view.rightGradient.Rotation = ring.rightRotation
			view.leftGradient.Rotation = ring.leftRotation
			view.rightHalf.Visible = ring.showRight
			view.leftHalf.Visible = ring.showLeft
			local text = PvpHudLogic.cooldownText(left)
			view.seconds.Text = text
			view.seconds.Visible = text ~= ""
		end
		if shieldChip then
			local active, secondsLeft = client.shield()
			local text = PvpHudLogic.shieldText(active, secondsLeft)
			shieldChip.Text = text or ""
			shieldChip.Visible = text ~= nil
		end
		if zoneChip then
			local text = PvpHudLogic.zoneText(client.safeZone())
			zoneChip.Text = text or ""
			zoneChip.Visible = text ~= nil
		end
	end

	function self.update()
		local slots = client.hotbarSlots()
		local wanted: { [string]: boolean } = {}
		for _, slot in slots do
			wanted[slot.id] = true
		end
		for id, view in views do
			if not wanted[id] then
				view.icon.destroy()
				view.button:Destroy()
				views[id] = nil
			end
		end
		table.clear(order)
		local equipped = client.equipped()
		for i, slot in slots do
			local view = views[slot.id]
			if view == nil then
				view = buildSlot(slot, i)
				views[slot.id] = view
			end
			view.button.Position = UDim2.fromOffset((i - 1) * (PvpHudLogic.SLOT + PvpHudLogic.SLOT_GAP), 0)
			view.button.LayoutOrder = i
			view.button.BackgroundColor3 = if slot.id == equipped then Theme.Accent else Theme.BgLight
			view.button:SetAttribute("Equipped", slot.id == equipped)
			view.key.Text = slot.keybind or ""
			view.key.TextColor3 = if slot.id == equipped then Color3.fromRGB(16, 40, 24) else Theme.Muted
			table.insert(order, slot.id)
		end
		if #order ~= placedCount then
			place()
		end
		self.tick()
	end

	function self.layout(s: Layout.Screen)
		screen = s
		place()
	end

	local disconnects: { () -> () } = {}
	table.insert(disconnects, client.onChanged(self.update))

	-- Number keys 1..9 (not while typing: gameProcessed / a focused TextBox).
	if o.input then
		local input = o.input
		local connection = input.InputBegan:Connect(function(event: any, processed: boolean)
			if processed or event.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if input.GetFocusedTextBox and input:GetFocusedTextBox() ~= nil then
				return
			end
			local n = PvpHudLogic.keyNumber(event.KeyCode.Name)
			if n then
				client.pressKey(n)
			end
		end)
		table.insert(disconnects, function()
			connection:Disconnect()
		end)
	end

	function self.destroy()
		for _, disconnect in disconnects do
			disconnect()
		end
		table.clear(disconnects)
		for _, view in views do
			view.icon.destroy()
		end
		table.clear(views)
		if shieldIcon then
			shieldIcon.destroy()
		end
		frame:Destroy()
		if shieldChip then
			shieldChip:Destroy()
		end
		if zoneChip then
			zoneChip:Destroy()
		end
	end

	self.update()
	return self
end

return PvpHud
