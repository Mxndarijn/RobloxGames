--!strict
-- S3 inventory UI (src/ui/Inventory) under the Lune UI harness: hotbar slots / icons / selection, number keys and
-- the actions they send, the bag panel and hide rules.

local Config = require("../../src/shared/Config")
local InventoryLayout = require("../../src/ui/InventoryLayout")
local ItemIcons = require("../../src/ui/ItemIcons")
local Layout = require("../../src/ui/Layout")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local Inventory = UiHarness.ui("Inventory")

local function fakeTools(initial: { { name: string, equipped: boolean } })
	local tools = { items = initial, calls = {} :: { string }, listeners = {} :: { () -> () } }
	function tools.list()
		return tools.items
	end
	function tools.setEquipped(name: string, on: boolean)
		table.insert(tools.calls, `{if on then "equip" else "unequip"}:{name}`)
	end
	function tools.unequipAll()
		table.insert(tools.calls, "unequipAll")
	end
	function tools.onChanged(cb: () -> ())
		table.insert(tools.listeners, cb)
	end
	return tools
end

local PVP = Config.PVP_TOOLS[1]

-- GetLastInputType for an injected UserInputService stand-in: the mouse.
local function mouseLast(): any
	return { Name = "MouseMovement" }
end

local function mount(state: any, items: { { name: string, equipped: boolean } }?, extra: { [string]: any }?)
	local gui = UiHarness.root()
	local tools = fakeTools(items or { { name = "Bat", equipped = false } })
	local sent: { { any } } = {}
	local inv = Inventory.new(gui, {
		Config = Config,
		itemIcons = ItemIcons.build(Config),
		send = function(action: string, ...: any)
			table.insert(sent, { action, ... })
		end,
		tools = tools,
		serverNow = function()
			return 100
		end,
		keyboard = true,
		input = extra and extra.input,
		gui = extra and extra.gui,
	})
	inv.layout(Layout.screen(1920, 1080))
	if state then
		inv.update(state)
	end
	return inv, tools, sent, gui
end

local function pvpState(equipped: string?): any
	return { pvp = { owned = { [PVP.id] = true }, equipped = equipped, cooldowns = {} } }
end

local function visibleSlots(inv: any): { any }
	local out = {}
	for _, child in inv.root:GetChildren() do
		if string.match(child.Name, "^Slot%d$") and child.Visible then
			table.insert(out, child)
		end
	end
	return out
end

describe("Inventory hotbar", function()
	it("a bag with only the starting Bat says it is empty and where items come from, instead of the grid", function()
		local inv = mount(nil)
		inv.setPanelOpen(true)
		local empty = UiHarness.find(inv.panel.frame, "EmptyBag")
		expect(empty ~= nil and empty.Visible).toBe(true)
		expect(UiHarness.find(empty, "Title").Text).toBe("Your bag is empty")
		expect(UiHarness.find(empty, "Body").Text).toBe(Inventory.EMPTY.body)
		expect(UiHarness.find(inv.panel.frame, "Grid").Visible).toBe(false)
		expect(UiHarness.find(inv.panel.frame, "HotbarPlate").Visible).toBe(true) -- the Bat stays on the plate
		expect(UiHarness.find(inv.panel.frame, "Count").Visible).toBe(false)
		inv.setPanelOpen(false)
		local full = mount(nil, { { name = "Bat", equipped = false }, { name = "SpeedCoil", equipped = false } })
		full.setPanelOpen(true)
		expect(UiHarness.find(full.panel.frame, "EmptyBag")).toBeNil()
		expect(UiHarness.find(full.panel.frame, "Grid").Visible).toBe(true)
	end)
	it("shows the Bat slot, a bag cell, and a picture for each", function()
		local inv = mount(nil)
		local slots = visibleSlots(inv)
		expect(#slots).toBe(1)
		expect(UiHarness.find(slots[1], "Icon") ~= nil).toBe(true)
		expect(UiHarness.find(slots[1], "Number").Text).toBe("1")
		expect(inv.root.Visible).toBe(true)
		expect(inv.bag.Visible).toBe(true)
	end)

	it("adds owned PvP items and other Tools, with their pictures", function()
		local inv =
			mount(pvpState(nil), { { name = "Bat", equipped = false }, { name = "SpeedCoil", equipped = false } })
		local slots = visibleSlots(inv)
		expect(#slots).toBe(3) -- Bat, Speed Coil, the PvP item
	end)

	it("highlights the selected slot (held Tool or equipped PvP item)", function()
		local inv = mount(nil, { { name = "Bat", equipped = true } })
		local slot = visibleSlots(inv)[1]
		expect(slot.BackgroundColor3).toBe(Inventory.COLORS.selected)
		local plain = visibleSlots(mount(nil))[1]
		expect(plain.BackgroundColor3).toBe(Inventory.COLORS.slot)
		local pvp = visibleSlots(mount(pvpState(PVP.id)))[2]
		expect(pvp.BackgroundColor3).toBe(Inventory.COLORS.selected)
	end)

	it("number keys equip through the existing paths and send nothing new", function()
		local inv, tools, sent = mount(pvpState(nil))
		expect(inv.pressKey(1)).toBe(true)
		expect(tools.calls[1]).toBe("equip:Bat")
		expect(#sent).toBe(0)
		expect(inv.pressKey(2)).toBe(true)
		expect(tools.calls[2]).toBe("unequipAll")
		expect(sent[1][1]).toBe("EquipPvpItem")
		expect(sent[1][2]).toBe(PVP.id)
		expect(inv.pressKey(3)).toBe(false) -- nothing on slot 3
		expect(inv.pressKey(9)).toBe(false)
	end)

	it("selecting the held Tool puts it away; selecting a Tool puts an equipped PvP item away first", function()
		local inv, tools = mount(nil, { { name = "Bat", equipped = true } })
		inv.pressKey(1)
		expect(tools.calls[1]).toBe("unequip:Bat")
		local inv2, tools2, sent2 = mount(pvpState(PVP.id))
		inv2.pressKey(1)
		expect(sent2[1][1]).toBe("EquipPvpItem")
		expect(sent2[1][2]).toBe(nil)
		expect(tools2.calls[1]).toBe("equip:Bat")
		inv2.pressKey(2)
		expect(sent2[2][1]).toBe("EquipPvpItem") -- toggles the item off
		expect(sent2[2][2]).toBe(nil)
	end)

	it("hides while carrying (the server unequips tools) and while a menu is open", function()
		local inv = mount(nil)
		inv.update({ carrying = { slimeId = "x" } })
		expect(inv.root.Visible).toBe(false)
		expect(inv.pressKey(1)).toBe(false)
		inv.update({})
		expect(inv.root.Visible).toBe(true)
		inv.setMenuOpen(true)
		expect(inv.root.Visible).toBe(false)
		expect(inv.pressKey(1)).toBe(false)
		inv.setMenuOpen(false)
		expect(inv.root.Visible).toBe(true)
	end)

	it("follows the Tools the server gives (a Speed Coil arriving adds a slot)", function()
		local inv, tools = mount(nil)
		expect(#visibleSlots(inv)).toBe(1)
		table.insert(tools.items, { name = "SpeedCoil", equipped = false })
		for _, cb in tools.listeners do
			cb()
		end
		expect(#visibleSlots(inv)).toBe(2)
	end)

	it("the bar stays inside its layout zone at the gate sizes", function()
		for _, size in { { 390, 844 }, { 844, 332 }, { 1920, 1080 } } do
			local inv = mount(nil)
			local s = Layout.screen(size[1], size[2])
			inv.layout(s)
			local p, z = inv.root.Position, s.hotbar
			expect(p.X.Offset >= z.x).toBe(true)
			expect(p.Y.Offset >= z.y).toBe(true)
			expect(p.X.Offset + inv.root.Size.X.Offset <= z.x + z.w).toBe(true)
			expect(p.Y.Offset + inv.root.Size.Y.Offset <= z.y + z.h).toBe(true)
		end
	end)
end)

describe("Inventory panel", function()
	it("opens a grid of everything held, each with a picture, and closes", function()
		local inv =
			mount(pvpState(nil), { { name = "Bat", equipped = false }, { name = "SpeedCoil", equipped = false } })
		expect(inv.panel.frame.Visible).toBe(false)
		inv.setPanelOpen(true)
		expect(inv.panel.frame.Visible).toBe(true)
		expect(inv.backdrop.Visible).toBe(true)
		local grid = UiHarness.find(inv.panel.frame, "Grid")
		local shown = 0
		for _, cell in grid:GetChildren() do
			if cell.Visible and cell.Name == "Item" then
				shown += 1
				expect(UiHarness.find(cell, "Icon") ~= nil).toBe(true)
			end
		end
		expect(shown).toBe(3)
		expect(UiHarness.find(inv.panel.frame, "Count").Text).toBe("3 items")
		inv.setPanelOpen(false)
		expect(inv.panel.frame.Visible).toBe(false)
	end)

	it("fills whole rows with empty slots: 4 columns on a wide screen, 3 on a portrait phone", function()
		for _, case in { { 1920, 1080, 4 }, { 390, 844, 3 } } do
			local inv = mount(nil, { { name = "Bat", equipped = false }, { name = "SpeedCoil", equipped = false } })
			inv.layout(Layout.screen(case[1], case[2]))
			inv.setPanelOpen(true)
			local items, empties, rows = 0, 0, {}
			for _, cell in UiHarness.find(inv.panel.frame, "Grid"):GetChildren() do
				if cell.Visible and (cell.Name == "Item" or cell.Name == "Empty") then
					if cell.Name == "Item" then
						items += 1
					else
						empties += 1
					end
					local y = cell.Position.Y.Offset
					rows[y] = (rows[y] or 0) + 1
				end
			end
			expect(items).toBe(2)
			expect(items + empties).toBe(InventoryLayout.CELL.minRows * case[3])
			for _, n in rows do
				expect(n).toBe(case[3])
			end
			expect(UiHarness.find(inv.panel.frame, "Count").Text).toBe("2 items")
		end
	end)

	it("cells copy the hotbar: no key tag, the selection ring on the equipped one", function()
		local inv = mount(nil, { { name = "Bat", equipped = true }, { name = "SpeedCoil", equipped = false } })
		inv.setPanelOpen(true)
		local cells = {}
		for _, cell in UiHarness.find(inv.panel.frame, "Grid"):GetChildren() do
			if cell.Visible and cell.Name == "Item" then
				cells[UiHarness.find(cell, "Name").Text] = cell
			end
		end
		local bat, coil = cells.Bat, cells["Speed Coil"]
		expect(bat ~= nil and coil ~= nil).toBe(true)
		expect(UiHarness.find(bat, "Number").Visible).toBe(false)
		expect(UiHarness.find(bat, "Amount").Visible).toBe(false) -- on the bar, but a Tool has no stack
		expect(UiHarness.find(coil, "Amount").Visible).toBe(false)
		expect(bat.BackgroundColor3).toBe(Inventory.COLORS.selected)
		expect(bat:FindFirstChildOfClass("UIStroke").Color).toBe(Inventory.COLORS.ring)
		expect(coil.BackgroundColor3).toBe(Inventory.COLORS.slot)
		expect(coil:FindFirstChildOfClass("UIStroke").Color).toBe(Inventory.COLORS.stroke)
	end)

	it("a click on a cell equips through the hotbar's path and closes the panel", function()
		local inv, tools = mount(nil)
		inv.setPanelOpen(true)
		local bat = UiHarness.find(inv.panel.frame, "Item")
		UiHarness.fire(bat, "Activated")
		expect(tools.calls[1]).toBe("equip:Bat")
		expect(inv.panelOpen()).toBe(false)
	end)

	it("sits in the Inventory menu card sized to its content and steps aside for another menu / carrying", function()
		local inv = mount(nil)
		local s = Layout.screen(1920, 1080)
		inv.layout(s)
		local body = Layout.panelBody(Layout.panelFor(s, "Inventory"))
		local footer = Layout.wrappedHeight(Inventory.footerText(true), Inventory.PANEL.hintSize, body.w)
		local r = Layout.panelFor(s, "Inventory", InventoryLayout.contentHeight(1, body.w, footer))
		expect(inv.panel.frame.Position.X.Offset).toBe(r.x)
		expect(inv.panel.frame.Size.Y.Offset).toBe(r.h)
		inv.setPanelOpen(true)
		inv.setMenuOpen(true)
		expect(inv.panel.frame.Visible).toBe(false)
		inv.setMenuOpen(false)
		inv.setPanelOpen(true)
		inv.update({ carrying = { slimeId = "x" } })
		expect(inv.panel.frame.Visible).toBe(false)
	end)
end)

describe("Inventory panel on a short landscape phone", function()
	for _, vp in { { 844, 332 }, { 640, 360 }, { 844, 390 } } do
		it(`{vp[1]}x{vp[2]}: the bag items are reachable cells of at least 44 screen px`, function()
			local inv = mount(nil, { { name = "Bat", equipped = false }, { name = "SpeedCoil", equipped = false } })
			local s = Layout.screen(vp[1], vp[2])
			inv.layout(s)
			inv.setPanelOpen(true)
			local grid = UiHarness.find(inv.panel.frame, "Grid")
			local plate = UiHarness.find(inv.panel.frame, "HotbarPlate")
			local frame = inv.panel.frame
			local body = Layout.panelBody(
				Layout.rect(frame.Position.X.Offset, frame.Position.Y.Offset, frame.Size.X.Offset, frame.Size.Y.Offset)
			)
			local gridH = body.h - grid.Position.Y.Offset
			local items = {}
			for _, cell in grid:GetChildren() do
				if cell.Name == "Item" and cell.Visible then
					table.insert(items, cell)
				end
			end
			expect(#items).toBe(2)
			for _, cell in items do
				expect(cell.Size.X.Offset * s.scale >= Layout.MIN_TOUCH).toBe(true)
				expect(cell.Size.Y.Offset * s.scale >= Layout.MIN_TOUCH).toBe(true)
				expect(cell.Position.Y.Offset + cell.Size.Y.Offset <= gridH).toBe(true) -- the first row shows whole
			end
			expect(grid.Position.X.Offset >= plate.Position.X.Offset + plate.Size.X.Offset).toBe(true)
		end)
		it(`{vp[1]}x{vp[2]}: an empty bag's message sits in the grid column, clear of the hotbar plate`, function()
			local inv = mount(nil)
			local s = Layout.screen(vp[1], vp[2])
			inv.layout(s)
			inv.setPanelOpen(true)
			local frame = inv.panel.frame
			local plate = UiHarness.find(frame, "HotbarPlate")
			local empty = UiHarness.find(frame, "EmptyBag")
			expect(empty ~= nil and empty.Visible).toBe(true)
			local body = Layout.panelBody(
				Layout.rect(frame.Position.X.Offset, frame.Position.Y.Offset, frame.Size.X.Offset, frame.Size.Y.Offset)
			)
			local x, w = empty.Position.X.Offset, empty.Size.X.Offset
			expect(empty.Size.X.Scale).toBe(0)
			expect(x >= plate.Position.X.Offset + plate.Size.X.Offset).toBe(true)
			expect(w > 0 and x + w <= body.w).toBe(true)
			expect(x).toBe(UiHarness.find(frame, "Grid").Position.X.Offset)
		end)
	end
end)

describe("Inventory bag key", function()
	local Enum = require("@lune/roblox").Enum

	it("` and B on a keyboard and Y on a gamepad are bag keys; the number keys and E are not", function()
		local inv = mount(nil)
		expect(inv.isBagKey(Enum.KeyCode.Backquote)).toBe(true)
		expect(inv.isBagKey(Enum.KeyCode.B)).toBe(true)
		expect(inv.isBagKey(Enum.KeyCode.ButtonY)).toBe(true)
		for _, key in { Enum.KeyCode.One, Enum.KeyCode.E, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB } do
			expect(inv.isBagKey(key)).toBe(false)
		end
		expect(inv.keyCodeToSlot(Enum.KeyCode.B)).toBe(nil)
	end)

	it("toggles the panel open and closed", function()
		local inv = mount(nil)
		expect(inv.toggleBag()).toBe(true)
		expect(inv.panelOpen()).toBe(true)
		expect(inv.panel.frame.Visible).toBe(true)
		expect(inv.toggleBag()).toBe(true)
		expect(inv.panelOpen()).toBe(false)
		expect(inv.panel.frame.Visible).toBe(false)
	end)

	it("does not open while a menu is open or while carrying", function()
		local inv = mount(nil)
		inv.setMenuOpen(true)
		expect(inv.toggleBag()).toBe(false)
		expect(inv.panelOpen()).toBe(false)
		inv.setMenuOpen(false)
		inv.update({ carrying = { slimeId = "x" } })
		expect(inv.toggleBag()).toBe(false)
		expect(inv.panelOpen()).toBe(false)
		inv.update({})
		expect(inv.toggleBag()).toBe(true)
	end)

	it("shows the key on the bag cell on keyboards only", function()
		local inv = mount(nil)
		local label = UiHarness.find(inv.bag, "Number")
		expect(label.Text).toBe(Inventory.BAG_KEYS.label)
		expect(label.Visible).toBe(true)
		local touch = Inventory.new(UiHarness.root(), {
			Config = Config,
			itemIcons = ItemIcons.build(Config),
			send = function() end,
			tools = fakeTools({}),
			serverNow = function()
				return 100
			end,
			keyboard = false,
		})
		expect(UiHarness.find(touch.bag, "Number").Visible).toBe(false)
	end)
end)

describe("Inventory consumable stacks (S3)", function()
	local function stackState(extra: any?): any
		local state: any = {
			consumables = { held = { LuckPotion = 1, WeatherTotem = 3 } },
			pvp = { owned = {}, cooldowns = {} },
		}
		for k, v in extra or {} do
			state[k] = v
		end
		return state
	end
	local COIL = { { name = "Bat", equipped = false }, { name = "SpeedCoil", equipped = false } }

	it("shows the Speed Coil and each consumable with its stack count on the hotbar", function()
		local inv = mount(stackState(), COIL)
		local slots = visibleSlots(inv)
		expect(#slots).toBe(4) -- Bat, Speed Coil, Luck Potion, Weather Totem
		expect(UiHarness.find(slots[3], "Count").Text).toBe("1")
		expect(UiHarness.find(slots[3], "Count").Visible).toBe(true)
		expect(UiHarness.find(slots[4], "Count").Text).toBe("3")
		expect(UiHarness.find(slots[2], "Count").Visible).toBe(false) -- a Tool has no stack
	end)

	it("bag cells show the stack amount on the gold tag and no second count", function()
		local inv = mount(stackState({ consumables = { held = { LuckPotion = 1, WeatherTotem = 120 } } }), COIL)
		inv.setPanelOpen(true)
		local cells = {}
		for _, cell in UiHarness.find(inv.panel.frame, "Grid"):GetChildren() do
			if cell.Visible and cell.Name == "Item" then
				cells[UiHarness.find(cell, "Name").Text] = cell
			end
		end
		local potion, totem = cells["Luck Potion"], cells["Weather Totem"]
		expect(potion ~= nil and totem ~= nil).toBe(true)
		expect(UiHarness.find(potion, "Amount").Visible).toBe(true)
		expect(UiHarness.find(potion, "Amount").Text).toBe("1")
		expect(UiHarness.find(potion, "Count").Visible).toBe(false)
		expect(UiHarness.find(totem, "Amount").Text).toBe("99+")
		expect(UiHarness.find(totem, "Amount").Size.X.Offset).toBe(Inventory.PANEL.tagWide)
		expect(UiHarness.find(cells["Speed Coil"], "Amount").Visible).toBe(false)
		local tagged = 0
		for _, cell in cells do
			if UiHarness.find(cell, "Amount").Visible then
				tagged += 1
			end
		end
		expect(tagged).toBe(2)
	end)

	it("a number key puts the consumable in hand, the same number again puts it away; nothing is sent", function()
		local inv, tools, sent = mount(stackState(), COIL)
		expect(inv.pressKey(4)).toBe(true)
		expect(inv.heldConsumable()).toBe("WeatherTotem")
		expect(tools.calls[1]).toBe("unequipAll") -- one hand
		expect(visibleSlots(inv)[4].BackgroundColor3).toBe(Inventory.COLORS.selected)
		expect(#sent).toBe(0)
		expect(inv.pressKey(4)).toBe(true)
		expect(inv.heldConsumable()).toBeNil()
		expect(visibleSlots(inv)[4].BackgroundColor3).toBe(Inventory.COLORS.slot)
		expect(#sent).toBe(0)
	end)

	it("a click with it in hand sends UseConsumable once per gap; nothing in hand sends nothing", function()
		local inv, _, sent = mount(stackState(), COIL)
		expect(inv.useHeld()).toBe(false)
		inv.pressKey(4)
		expect(inv.useHeld()).toBe(true)
		expect(sent[1][1]).toBe("UseConsumable")
		expect(sent[1][2]).toBe("WeatherTotem")
		expect(sent[1][3]).toBeNil()
		expect(inv.useHeld()).toBe(false) -- inside the gap: the server's rate limit is never hit by a double click
		expect(#sent).toBe(1)
	end)

	it("the hand empties when the last one is used, a Tool or PvP item is picked, or the player carries", function()
		local inv = mount(stackState(), COIL)
		inv.pressKey(3)
		expect(inv.heldConsumable()).toBe("LuckPotion")
		inv.update(stackState({ consumables = { held = { WeatherTotem = 3 } } })) -- the potion was used up
		expect(inv.heldConsumable()).toBeNil()
		inv.pressKey(3)
		expect(inv.heldConsumable()).toBe("WeatherTotem")
		inv.pressKey(1) -- the Bat
		expect(inv.heldConsumable()).toBeNil()
		inv.pressKey(3)
		inv.update(stackState({ carrying = { slimeId = "x" } }))
		expect(inv.heldConsumable()).toBeNil()
		expect(inv.useHeld()).toBe(false)
	end)
end)

describe("Inventory PvP item use", function()
	local GLOVE = "KnockGlove1"
	local animated: { string } = {}
	local alone = false -- nobody else in the world
	local function mountPvp(equipped: string?, reply: any?, cooldowns: any?)
		local gui = UiHarness.root()
		local sent: { { any } } = {}
		local aims = 0
		animated = {}
		local inv = Inventory.new(gui, {
			Config = Config,
			itemIcons = ItemIcons.build(Config),
			send = function(action: string, ...: any)
				table.insert(sent, { action, ... })
			end,
			request = function(action: string, done: (any) -> (), ...: any)
				table.insert(sent, { action, ... })
				done(reply or { ok = true })
			end,
			aim = function(_screen: any): any
				aims += 1
				return {
					self = { X = 0, Y = 3, Z = 0 },
					point = { X = 6, Y = 3, Z = 0 },
					players = if alone
						then {}
						else { { userId = 7, position = { X = 4, Y = 3, Z = 0 }, carrying = true } },
				}
			end,
			animate = function(itemId: string)
				table.insert(animated, itemId)
			end,
			tools = fakeTools({ { name = "Bat", equipped = false } }),
			serverNow = function()
				return 100
			end,
			keyboard = true,
		})
		inv.layout(Layout.screen(1920, 1080))
		inv.update({ pvp = { owned = { [GLOVE] = true }, equipped = equipped, cooldowns = cooldowns or {} } })
		return inv, sent, gui, function()
			return aims
		end
	end
	local SCREEN = { X = 500, Y = 400 }

	it("a click with a glove equipped sends UsePvpItem at the player in reach", function()
		local inv, sent = mountPvp(GLOVE)
		expect(inv.useHeld(SCREEN)).toBe(true)
		expect(sent[1][1]).toBe("UsePvpItem")
		expect(sent[1][2]).toBe(GLOVE)
		expect(sent[1][3]).toBe(7)
		expect(inv.useHeld(SCREEN)).toBe(false) -- inside the gap
		expect(#sent).toBe(1)
	end)

	it("a click plays the item's use animation at once, also a whiff with nobody in reach", function()
		local inv, sent = mountPvp(GLOVE)
		inv.useHeld(SCREEN)
		expect(animated).toEqual({ GLOVE })
		alone = true
		inv, sent = mountPvp(GLOVE)
		expect(inv.useHeld(SCREEN)).toBe(false)
		alone = false
		expect(#sent).toBe(0)
		expect(animated).toEqual({ GLOVE })
		expect(inv.useHeld(SCREEN)).toBe(false) -- the whiff starts the gap too
		expect(animated).toEqual({ GLOVE })
	end)

	it("a charging Fun item waits for the release; a long hold sends charged, a tap does not", function()
		local inv, sent = mountPvp(GLOVE)
		inv.update({ pvp = { owned = { FunConfetti = true }, equipped = "FunConfetti", cooldowns = {} } })
		expect(inv.pressHeld(SCREEN)).toBe(true)
		expect(#sent).toBe(0) -- waits for the release
		expect(inv.releaseHeld(SCREEN)).toBe(true)
		expect(sent[1][1]).toBe("UsePvpItem")
		expect(sent[1][2]).toBe("FunConfetti")
		expect(sent[1][3]).toBe(nil)
		expect(sent[1][4].X).toBe(6)
		expect(sent[1][5]).toBe(nil) -- a tap
		expect(inv.releaseHeld(SCREEN)).toBe(false) -- one release per press
		local hold, holdSent = mountPvp(GLOVE)
		hold.update({ pvp = { owned = { FunFireworks = true }, equipped = "FunFireworks", cooldowns = {} } })
		hold.pressHeld(SCREEN, Config.PVP.CHARGE_SECONDS) -- a touch long press is already held this long
		expect(hold.releaseHeld(SCREEN)).toBe(true)
		expect(holdSent[1][2]).toBe("FunFireworks")
		expect(holdSent[1][5]).toBe(true)
	end)

	it("a cooling-down item plays no animation", function()
		local inv = mountPvp(GLOVE, nil, { [GLOVE] = 103 })
		inv.useHeld(SCREEN)
		expect(animated).toEqual({})
	end)

	it("nothing equipped: a click sends nothing and samples nothing", function()
		local inv, sent, _, aims = mountPvp(nil)
		expect(inv.useHeld(SCREEN)).toBe(false)
		expect(#sent).toBe(0)
		expect(aims()).toBe(0)
	end)

	it("a server refusal shows as a tip above the slot", function()
		local inv, sent, gui = mountPvp(GLOVE, { ok = false, message = "only on your plot or against a thief" })
		expect(inv.useHeld(SCREEN)).toBe(true)
		expect(#sent).toBe(1)
		local tip = UiHarness.find(gui, "Tip")
		expect(tip.Visible).toBe(true)
		expect(tip.Text).toBe("Only on your plot or against a thief")
	end)

	it("a glove fires on the release: a tap punches, a long hold is a power punch", function()
		local inv, sent = mountPvp(GLOVE)
		expect(inv.pressHeld(SCREEN)).toBe(true)
		expect(#sent).toBe(0) -- waits for the release
		expect(inv.releaseHeld(SCREEN)).toBe(true)
		expect(sent[1][1]).toBe("UsePvpItem")
		expect(sent[1][5]).toBe(nil) -- a tap
		expect(inv.releaseHeld(SCREEN)).toBe(false) -- no press pending
		inv, sent = mountPvp(GLOVE)
		inv.pressHeld(SCREEN, Config.PVP.CHARGE_SECONDS) -- a touch long press is already held this long
		expect(inv.releaseHeld(SCREEN)).toBe(true)
		expect(sent[1][5]).toBe(true)
	end)

	it("a cooling-down item says when it is ready and sends nothing", function()
		local inv, sent, gui = mountPvp(GLOVE, nil, { [GLOVE] = 103 })
		expect(inv.useHeld(SCREEN)).toBe(false)
		expect(#sent).toBe(0)
		expect(UiHarness.find(gui, "Tip").Text).toBe("Ready in 3s")
	end)
end)

describe("Inventory hotbar order and drag", function()
	local Enum = require("@lune/roblox").Enum
	local Theme = UiHarness.ui("Widgets").Theme
	local MOUSE, MOVE, TOUCH =
		Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseMovement, Enum.UserInputType.Touch
	local COIL = { { name = "Bat", equipped = false }, { name = "SpeedCoil", equipped = false } }

	-- UserInputService stand-in: InputChanged / InputEnded keep their handlers and Fire runs them; the last input
	-- is the mouse.
	local function fakeInput()
		local function event()
			local e = { handlers = {} :: { any } }
			function e.Connect(this: any, handler: any)
				table.insert(this.handlers, handler)
				return {
					Disconnect = function()
						local i = table.find(this.handlers, handler)
						if i then
							table.remove(this.handlers, i)
						end
					end,
				}
			end
			function e.Fire(this: any, ...: any)
				for _, handler in table.clone(this.handlers) do
					handler(...)
				end
			end
			return e
		end
		return { InputChanged = event(), InputEnded = event(), GetLastInputType = mouseLast }
	end

	local function mountOrder(hotbar: { string }?, items: any?)
		local gui = UiHarness.root()
		local tools = fakeTools(items or table.clone(COIL))
		local sent: { { any } } = {}
		local input = fakeInput()
		local inv = Inventory.new(gui, {
			Config = Config,
			itemIcons = ItemIcons.build(Config),
			send = function(action: string, ...: any)
				table.insert(sent, { action, ... })
			end,
			tools = tools,
			serverNow = function()
				return 100
			end,
			keyboard = true,
			input = input,
		})
		inv.layout(Layout.screen(1920, 1080)) -- scale 1: screen px = design px
		inv.update({ hotbar = hotbar, pvp = { owned = {}, cooldowns = {} } })
		return inv, tools, sent, gui, input
	end

	local function order(...: string): { string }
		local keys = table.create(9, "")
		for i, key in { ... } do
			keys[i] = key
		end
		return keys
	end

	-- The centre of `gui` in ScreenGui space (sum of the offsets up the tree).
	local function centre(gui: any): { X: number, Y: number }
		local x, y = gui.Size.X.Offset / 2, gui.Size.Y.Offset / 2
		local node = gui
		while node and node.ClassName ~= "ScreenGui" do
			x += node.Position.X.Offset
			y += node.Position.Y.Offset
			node = node.Parent
		end
		return { X = x, Y = y }
	end

	local function bagCell(inv: any, name: string): any
		for _, cell in UiHarness.find(inv.panel.frame, "Grid"):GetChildren() do
			if cell.Visible and cell.Name == "Item" and UiHarness.find(cell, "Name").Text == name then
				return cell
			end
		end
		return nil
	end

	local function plateSlot(inv: any, i: number): any
		return UiHarness.find(inv.panel.frame, `HotbarSlot{i}`)
	end

	local function hotbarSends(sent: { { any } }): { string }
		local out = {}
		for _, call in sent do
			if call[1] == "SetHotbar" then
				table.insert(out, call[2])
			end
		end
		return out
	end

	-- A mouse drag from `cell` to point `to`, with a stop on the way so the threshold is passed.
	local function mouseDrag(input: any, cell: any, to: { X: number, Y: number })
		local from = centre(cell)
		UiHarness.fire(cell, "InputBegan", { UserInputType = MOUSE, Position = from })
		input.InputChanged:Fire({ UserInputType = MOVE, Position = { X = from.X + 20, Y = from.Y } })
		input.InputChanged:Fire({ UserInputType = MOVE, Position = to })
		input.InputEnded:Fire({ UserInputType = MOUSE, Position = to })
		UiHarness.fire(cell, "Activated") -- Roblox may still fire it on release; a drag is never a tap
	end

	it("the panel shows the hotbar plate: nine slots, keys 1-9, empty ones as Ink wells", function()
		local inv = mountOrder(order("tool:Bat", "", "tool:SpeedCoil"))
		inv.setPanelOpen(true)
		expect(UiHarness.find(inv.panel.frame, "HotbarPlate") ~= nil).toBe(true)
		for i = 1, 9 do
			local slot = plateSlot(inv, i)
			expect(UiHarness.find(slot, "Number").Text).toBe(tostring(i))
			expect(UiHarness.find(slot, "Number").Visible).toBe(true)
		end
		expect(UiHarness.find(plateSlot(inv, 1), "Name").Text).toBe("Bat")
		expect(plateSlot(inv, 2).BackgroundColor3).toBe(Theme.Ink)
		expect(UiHarness.find(plateSlot(inv, 2), "Icon").Visible).toBe(false)
		expect(UiHarness.find(plateSlot(inv, 3), "Name").Text).toBe("Speed Coil")
		expect(UiHarness.find(inv.panel.frame, "Footer").Visible).toBe(true)
	end)

	it("a drag from a bag cell onto hotbar slot 4 sends SetHotbar with that order and shows it at once", function()
		local inv, tools, sent, gui, input = mountOrder(order("tool:Bat"))
		inv.setPanelOpen(true)
		local coil = bagCell(inv, "Speed Coil")
		local from, to = centre(coil), centre(plateSlot(inv, 4))
		UiHarness.fire(coil, "InputBegan", { UserInputType = MOUSE, Position = from })
		input.InputChanged:Fire({ UserInputType = MOVE, Position = { X = from.X + 3, Y = from.Y } })
		expect(UiHarness.find(gui, "DragGhost")).toBeNil() -- under the threshold: still a press
		input.InputChanged:Fire({ UserInputType = MOVE, Position = to })
		local ghost = UiHarness.find(gui, "DragGhost")
		expect(ghost.Visible).toBe(true)
		expect(ghost.Position.X.Offset).toBe(math.round(to.X))
		expect(UiHarness.find(plateSlot(inv, 4), "DropRing") ~= nil).toBe(true)
		expect(UiHarness.find(coil, "Lift") ~= nil).toBe(true)
		input.InputEnded:Fire({ UserInputType = MOUSE, Position = to })
		UiHarness.fire(coil, "Activated")
		expect(table.concat(hotbarSends(sent), "|")).toBe("tool:Bat,,,tool:SpeedCoil,,,,,")
		expect(#tools.calls).toBe(0) -- the drop is not a tap
		expect(inv.panelOpen()).toBe(true)
		expect(ghost.Visible).toBe(false)
		expect(UiHarness.find(coil, "Lift")).toBeNil()
		expect(UiHarness.find(plateSlot(inv, 4), "Name").Text).toBe("Speed Coil")
		-- a State still carrying the old order does not undo the drop; one with the new order confirms it
		inv.update({ hotbar = order("tool:Bat"), pvp = { owned = {}, cooldowns = {} } })
		expect(UiHarness.find(plateSlot(inv, 4), "Name").Text).toBe("Speed Coil")
		inv.update({ hotbar = order("tool:Bat", "", "", "tool:SpeedCoil"), pvp = { owned = {}, cooldowns = {} } })
		inv.update({ hotbar = order("tool:Bat"), pvp = { owned = {}, cooldowns = {} } })
		expect(plateSlot(inv, 4).BackgroundColor3).toBe(Theme.Ink) -- confirmed: the server's order rules again
	end)

	it("a press that does not move is a tap: it equips and closes the panel, and sends no order", function()
		local inv, tools, sent, _, input = mountOrder(order("tool:Bat"))
		inv.setPanelOpen(true)
		local coil = bagCell(inv, "Speed Coil")
		local at = centre(coil)
		UiHarness.fire(coil, "InputBegan", { UserInputType = MOUSE, Position = at })
		input.InputEnded:Fire({ UserInputType = MOUSE, Position = at })
		UiHarness.fire(coil, "Activated")
		expect(tools.calls[1]).toBe("equip:SpeedCoil")
		expect(inv.panelOpen()).toBe(false)
		expect(#hotbarSends(sent)).toBe(0)
	end)

	it("dragging between hotbar slots swaps them; dragging one off the bar clears it", function()
		local inv, _, sent, _, input = mountOrder(order("tool:Bat", "tool:SpeedCoil"))
		inv.setPanelOpen(true)
		mouseDrag(input, plateSlot(inv, 1), centre(plateSlot(inv, 2)))
		expect(hotbarSends(sent)[1]).toBe("tool:SpeedCoil,tool:Bat,,,,,,,")
		local inv2, _, sent2, _, input2 = mountOrder(order("tool:Bat", "tool:SpeedCoil"))
		inv2.setPanelOpen(true)
		mouseDrag(input2, plateSlot(inv2, 2), centre(bagCell(inv2, "Bat")))
		expect(hotbarSends(sent2)[1]).toBe("tool:Bat,,,,,,,,")
		expect(inv2.panelOpen()).toBe(true)
	end)

	it("a touch drag follows its own finger only; another finger moving does nothing", function()
		local inv, _, sent, _, input = mountOrder(order("tool:Bat"))
		inv.setPanelOpen(true)
		local coil = bagCell(inv, "Speed Coil")
		local finger = { UserInputType = TOUCH, Position = centre(coil) }
		UiHarness.fire(coil, "InputBegan", finger)
		local thumb = { UserInputType = TOUCH, Position = centre(plateSlot(inv, 2)) }
		input.InputChanged:Fire(thumb)
		input.InputEnded:Fire(thumb)
		expect(#hotbarSends(sent)).toBe(0)
		finger.Position = centre(plateSlot(inv, 2))
		input.InputChanged:Fire(finger)
		input.InputEnded:Fire(finger)
		expect(hotbarSends(sent)[1]).toBe("tool:Bat,tool:SpeedCoil,,,,,,,")
	end)

	it("the bottom bar follows the slots: empty slots in between are dim cells and their key does nothing", function()
		local inv, tools = mountOrder(order("tool:Bat", "", "", "tool:SpeedCoil"))
		local slots = visibleSlots(inv)
		expect(#slots).toBe(4)
		local second = UiHarness.find(inv.root, "Slot2")
		expect(second.BackgroundColor3).toBe(Theme.Ink)
		expect(UiHarness.find(second, "Icon").Visible).toBe(false)
		expect(inv.pressKey(2)).toBe(false)
		expect(inv.pressKey(4)).toBe(true)
		expect(tools.calls[1]).toBe("equip:SpeedCoil")
		expect(inv.pressKey(5)).toBe(false)
		expect(#tools.calls).toBe(1)
	end)

	it("no saved order: the bar is the list order and nothing is sent", function()
		local inv, _, sent = mountOrder(nil)
		expect(#visibleSlots(inv)).toBe(2)
		expect(#hotbarSends(sent)).toBe(0)
	end)

	it("an item new this session lands on the first empty slot (one SetHotbar); a respawn's Tools do not", function()
		local inv, tools, sent = mountOrder(order("tool:Bat"))
		expect(#hotbarSends(sent)).toBe(0) -- the first State is the baseline: the unassigned Speed Coil stays off
		inv.update({ hotbar = order("tool:Bat"), pvp = { owned = { [PVP.id] = true }, cooldowns = {} } })
		expect(table.concat(hotbarSends(sent), "|")).toBe(`tool:Bat,pvp:{PVP.id},,,,,,,`)
		expect(#visibleSlots(inv)).toBe(2)
		-- respawn: the Backpack empties and fills again; nothing already seen counts as new
		tools.items = {}
		for _, cb in tools.listeners do
			cb()
		end
		tools.items = table.clone(COIL)
		for _, cb in tools.listeners do
			cb()
		end
		expect(#hotbarSends(sent)).toBe(1)
	end)

	it(
		"a Tool arriving just after the first State is not new (one taken off the bar stays off); later ones land",
		function()
			UiHarness.virtualTime(true)
			local inv, tools, sent = mountOrder(order("tool:Bat"), { { name = "Bat", equipped = false } })
			-- rejoin: the Speed Coil the player took off the bar reaches the Backpack after the first State
			tools.items = table.clone(COIL)
			for _, cb in tools.listeners do
				cb()
			end
			expect(#hotbarSends(sent)).toBe(0)
			expect(#visibleSlots(inv)).toBe(1)
			UiHarness.advance(Inventory.JOIN_GRACE + 1)
			tools.items = { COIL[1], COIL[2], { name = "Grapple", equipped = false } }
			for _, cb in tools.listeners do
				cb()
			end
			expect(table.concat(hotbarSends(sent), "|")).toBe("tool:Bat,tool:Grapple,,,,,,,")
			UiHarness.virtualTime(false)
		end
	)

	it("a new item lands on a bar whose every slot is kept for items no longer held", function()
		local ghosts: { string } = {}
		for i = 2, 10 do
			table.insert(ghosts, `pvp:{Config.PVP_TOOLS[i].id}`)
		end
		local inv, _, sent = mountOrder(ghosts)
		expect(#visibleSlots(inv)).toBe(0)
		inv.update({ hotbar = ghosts, pvp = { owned = { [PVP.id] = true }, cooldowns = {} } })
		local want = table.clone(ghosts)
		want[1] = `pvp:{PVP.id}`
		expect(table.concat(hotbarSends(sent), "|")).toBe(table.concat(want, ","))
		expect(#visibleSlots(inv)).toBe(1)
	end)

	it("dropping an item the server can't take on the bar says so and sends nothing", function()
		local inv, _, sent, _, input = mountOrder(order("tool:Bat"), {
			{ name = "Bat", equipped = false },
			{ name = "Bad,Name", equipped = false },
		})
		inv.setPanelOpen(true)
		mouseDrag(input, bagCell(inv, "Bad,Name"), centre(plateSlot(inv, 3)))
		expect(#hotbarSends(sent)).toBe(0)
		expect(UiHarness.find(inv.panel.frame, "Hint").Text).toBe(Inventory.ORDER_TEXT.blanked)
		expect(plateSlot(inv, 3).BackgroundColor3).toBe(Theme.Ink)
	end)

	it("with no saved order a new item sends nothing (the default order already lists it)", function()
		local inv, _, sent = mountOrder(nil)
		inv.update({ pvp = { owned = { [PVP.id] = true }, cooldowns = {} } })
		expect(#hotbarSends(sent)).toBe(0)
		expect(#visibleSlots(inv)).toBe(3)
	end)
end)

describe("Inventory hotbar order through request", function()
	local Enum = require("@lune/roblox").Enum
	local Theme = UiHarness.ui("Widgets").Theme

	-- `hold`: replies wait in the returned `dones` list until the test answers them.
	local function mountRequest(replies: { any }, hold: boolean?)
		local gui = UiHarness.root()
		local calls: { { any } } = {}
		local dones: { (any) -> () } = {}
		local handlers: { any } = {}
		local input = {
			GetLastInputType = mouseLast,
			InputChanged = {
				Connect = function(_self: any, h: any)
					handlers.changed = h
					return { Disconnect = function() end }
				end,
			},
			InputEnded = {
				Connect = function(_self: any, h: any)
					handlers.ended = h
					return { Disconnect = function() end }
				end,
			},
		}
		local inv = Inventory.new(gui, {
			Config = Config,
			itemIcons = ItemIcons.build(Config),
			send = function() end,
			request = function(action: string, done: (any) -> (), ...: any)
				table.insert(calls, { action, ... })
				if hold then
					table.insert(dones, done)
				else
					done(replies[#calls] or { ok = true })
				end
			end,
			tools = fakeTools({ { name = "Bat", equipped = false }, { name = "SpeedCoil", equipped = false } }),
			serverNow = function()
				return 100
			end,
			keyboard = true,
			input = input,
		})
		inv.layout(Layout.screen(1920, 1080))
		local keys = table.create(9, "")
		keys[1] = "tool:Bat"
		inv.update({ hotbar = keys, pvp = { owned = {}, cooldowns = {} } })
		inv.setPanelOpen(true)
		return inv, calls, handlers, dones
	end

	local function centre(gui: any): { X: number, Y: number }
		local x, y = gui.Size.X.Offset / 2, gui.Size.Y.Offset / 2
		local node = gui
		while node and node.ClassName ~= "ScreenGui" do
			x += node.Position.X.Offset
			y += node.Position.Y.Offset
			node = node.Parent
		end
		return { X = x, Y = y }
	end

	local function dragCoilTo4(inv: any, handlers: any)
		local coil
		for _, cell in UiHarness.find(inv.panel.frame, "Grid"):GetChildren() do
			if cell.Name == "Item" and cell.Visible and UiHarness.find(cell, "Name").Text == "Speed Coil" then
				coil = cell
			end
		end
		local to = centre(UiHarness.find(inv.panel.frame, "HotbarSlot4"))
		UiHarness.fire(coil, "InputBegan", { UserInputType = Enum.UserInputType.MouseButton1, Position = centre(coil) })
		handlers.changed({ UserInputType = Enum.UserInputType.MouseMovement, Position = to })
		handlers.ended({ UserInputType = Enum.UserInputType.MouseButton1, Position = to })
	end

	it("a rate-limited SetHotbar keeps the new order and sends it again after the gap", function()
		UiHarness.virtualTime(true)
		local inv, calls, handlers = mountRequest({ { ok = false, message = "too fast" } })
		dragCoilTo4(inv, handlers)
		expect(#calls).toBe(1)
		expect(UiHarness.find(UiHarness.find(inv.panel.frame, "HotbarSlot4"), "Name").Text).toBe("Speed Coil")
		UiHarness.advance(Inventory.ORDER_GAP + 0.05)
		expect(#calls).toBe(2)
		expect(calls[2][1]).toBe("SetHotbar")
		expect(calls[2][2]).toBe(calls[1][2])
		expect(calls[2][2]).toBe("tool:Bat,,,tool:SpeedCoil,,,,,")
		UiHarness.advance(Inventory.ORDER_TIMEOUT)
		expect(#calls).toBe(2) -- accepted: nothing more to send
		UiHarness.virtualTime(false)
	end)

	it("a refusal for any other reason puts the server's order back and says the hotbar wasn't saved", function()
		local inv, calls, handlers = mountRequest({ { ok = false, message = "bad argument" } })
		dragCoilTo4(inv, handlers)
		expect(#calls).toBe(1)
		expect(UiHarness.find(inv.panel.frame, "HotbarSlot4").BackgroundColor3).toBe(Theme.Ink)
		expect(UiHarness.find(inv.panel.frame, "Hint").Text).toBe(Inventory.ORDER_TEXT.refused)
	end)

	it(
		"an order still being sent outlives ORDER_TIMEOUT: a stale State keeps it and a late refusal resends it",
		function()
			UiHarness.virtualTime(true)
			local inv, calls, handlers, dones = mountRequest({}, true)
			local function slot4(): string
				local slot = UiHarness.find(inv.panel.frame, "HotbarSlot4")
				return if slot.BackgroundColor3 == Theme.Ink then "" else UiHarness.find(slot, "Name").Text
			end
			local stale = table.create(9, "")
			stale[1] = "tool:Bat"
			dragCoilTo4(inv, handlers)
			expect(#calls).toBe(1)
			UiHarness.advance(Inventory.ORDER_TIMEOUT - 0.2)
			dones[1]({ ok = false, message = "too fast" })
			expect(#calls).toBe(2) -- the gap passed long ago: sent again at once
			UiHarness.advance(0.4) -- ORDER_TIMEOUT since the drag, with the second send still out
			inv.update({ hotbar = stale, pvp = { owned = {}, cooldowns = {} } })
			expect(slot4()).toBe("Speed Coil")
			dones[2]({ ok = false, message = "too fast" })
			UiHarness.advance(Inventory.ORDER_GAP + 0.05)
			expect(#calls).toBe(3)
			expect(calls[3][2]).toBe("tool:Bat,,,tool:SpeedCoil,,,,,")
			inv.update({ hotbar = stale, pvp = { owned = {}, cooldowns = {} } })
			expect(slot4()).toBe("Speed Coil")
			dones[3]({ ok = true })
			local saved = table.clone(stale)
			saved[4] = "tool:SpeedCoil"
			inv.update({ hotbar = saved, pvp = { owned = {}, cooldowns = {} } })
			expect(slot4()).toBe("Speed Coil")
			UiHarness.virtualTime(false)
		end
	)
end)

describe("Inventory gamepad", function()
	local Enum = require("@lune/roblox").Enum
	local ITEMS = { { name = "Bat", equipped = false }, { name = "SpeedCoil", equipped = false } }

	it("the bumpers cycle the filled slots through the number-key path, wrapping both ways", function()
		local inv, tools, sent = mount(pvpState(nil), ITEMS) -- slots: Bat, Speed Coil, the PvP item
		expect(inv.cycleSlot(1)).toBe(true) -- nothing in hand: the first
		expect(tools.calls[#tools.calls]).toBe("equip:Bat")
		tools.items[1].equipped = true
		inv.update(pvpState(nil))
		expect(inv.cycleSlot(1)).toBe(true)
		expect(tools.calls[#tools.calls]).toBe("equip:SpeedCoil")
		tools.items[1].equipped, tools.items[2].equipped = false, true
		inv.update(pvpState(nil))
		inv.cycleSlot(1)
		expect(sent[#sent][1]).toBe("EquipPvpItem")
		expect(sent[#sent][2]).toBe(PVP.id)
		inv.update(pvpState(PVP.id))
		inv.cycleSlot(1) -- wraps to the Bat
		expect(tools.calls[#tools.calls]).toBe("equip:Bat")
		tools.items[1].equipped, tools.items[2].equipped = true, false
		inv.update(pvpState(nil))
		inv.cycleSlot(-1) -- wraps back to the last
		expect(sent[#sent][2]).toBe(PVP.id)
	end)

	it("with nothing in hand the previous bumper picks the last slot", function()
		local inv, _, sent = mount(pvpState(nil), ITEMS)
		expect(inv.cycleSlot(-1)).toBe(true)
		expect(sent[1][2]).toBe(PVP.id)
	end)

	it("skips an empty slot and does nothing with a single filled slot already in hand", function()
		local inv, tools = mount(nil, { { name = "Bat", equipped = true } })
		expect(inv.cycleSlot(1)).toBe(false)
		expect(#tools.calls).toBe(0)
	end)

	it("follows the keyboard guards: carrying, a menu and the open bag", function()
		local inv = mount(nil, ITEMS)
		inv.update({ carrying = { slimeId = "x" } })
		expect(inv.cycleSlot(1)).toBe(false)
		inv.update({})
		inv.setMenuOpen(true)
		expect(inv.cycleSlot(1)).toBe(false)
		inv.setMenuOpen(false)
		inv.setPanelOpen(true)
		expect(inv.cycleSlot(1)).toBe(false)
	end)

	it("opening the bag on a gamepad focuses the first hotbar plate slot, closing clears it", function()
		local gui = UiHarness.guiService
		UiHarness.lastInputType = Enum.UserInputType.Gamepad1
		local inv = mount(nil)
		inv.setPanelOpen(true)
		expect(gui.SelectedObject ~= nil).toBe(true)
		expect(gui.SelectedObject.Name).toBe("HotbarSlot1")
		inv.setPanelOpen(false)
		expect(gui.SelectedObject).toBeNil()
		UiHarness.lastInputType = Enum.UserInputType.MouseMovement
	end)

	it("leaves the focus alone with a mouse or touch, and a focus outside the panel on close", function()
		local gui = UiHarness.guiService
		UiHarness.lastInputType = Enum.UserInputType.Touch
		local inv = mount(nil)
		inv.setPanelOpen(true)
		expect(gui.SelectedObject).toBeNil()
		local other = UiHarness.root()
		gui.SelectedObject = other
		inv.setPanelOpen(false)
		expect(gui.SelectedObject).toBe(other)
		gui.SelectedObject = nil
		UiHarness.lastInputType = Enum.UserInputType.MouseMovement
	end)

	it("reads the device from the injected input service and focuses through the injected gui service", function()
		local fakeInput = table.clone(UiHarness.userInput)
		fakeInput.GetLastInputType = function()
			return Enum.UserInputType.Gamepad1
		end
		local fakeGui: any = { SelectedObject = nil }
		UiHarness.lastInputType = Enum.UserInputType.MouseMovement -- the real service says mouse
		local inv = mount(nil, nil, { input = fakeInput, gui = fakeGui })
		inv.setPanelOpen(true)
		expect(fakeGui.SelectedObject ~= nil).toBe(true)
		expect(fakeGui.SelectedObject.Name).toBe("HotbarSlot1")
		expect(UiHarness.guiService.SelectedObject).toBeNil()
		inv.setPanelOpen(false)
		expect(fakeGui.SelectedObject).toBeNil()
	end)
end)
