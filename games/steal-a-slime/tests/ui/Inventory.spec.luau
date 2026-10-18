--!strict
-- S3 inventory UI (src/ui/Inventory) under the Lune UI harness: hotbar slots / icons / selection, number keys and
-- the actions they send, the bag panel, hide rules, and the init.client mount.
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local GlyphCheck = require("./GlyphCheck")
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

local function mount(state: any, items: { { name: string, equipped: boolean } }?)
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
			if cell.Visible then
				shown += 1
				expect(UiHarness.find(cell, "Icon") ~= nil).toBe(true)
			end
		end
		expect(shown).toBe(3)
		inv.setPanelOpen(false)
		expect(inv.panel.frame.Visible).toBe(false)
	end)

	it("sits in the Inventory menu card and steps aside for another menu / carrying", function()
		local inv = mount(nil)
		local s = Layout.screen(1920, 1080)
		inv.layout(s)
		local r = Layout.panelFor(s, "Inventory")
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

describe("Inventory mount", function()
	local src = fs.readFile("src/ui/init.client.luau")
	local function has(needle: string): boolean
		return string.find(src, needle, 1, true) ~= nil
	end
	it("init.client mounts it with a minimal hook: layout, state, menu and tick", function()
		expect(has("Inventory.new(gui")).toBe(true)
		expect(has("inventory.layout(s)")).toBe(true)
		expect(has("inventory.update(state)")).toBe(true)
		expect(has("inventory.setMenuOpen(")).toBe(true)
		expect(has("inventory.tick()")).toBe(true)
		expect(has("InventoryTools.hideDefaultBackpack()")).toBe(true)
	end)
	it("the default Roblox backpack is switched off through StarterGui", function()
		local tools = fs.readFile("src/ui/InventoryTools.luau")
		expect(string.find(tools, "SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)", 1, true) ~= nil).toBe(true)
	end)
	it("the only server names it touches are EquipPvpItem, UsePvpItem and UseConsumable", function()
		local core = fs.readFile("src/ui/InventoryCore.luau")
		expect(string.find(core, 'PVP_ACTION = "EquipPvpItem"', 1, true) ~= nil).toBe(true)
		expect(string.find(core, 'USE_ACTION = "UseConsumable"', 1, true) ~= nil).toBe(true)
		expect(string.find(core, 'PVP_USE_ACTION = "UsePvpItem"', 1, true) ~= nil).toBe(true)
		local code = GlyphCheck.stripComments(core)
		-- "BuyConsumable" is only the ItemIcons key of a consumable's picture, never sent
		for _, other in { "BuyUpgrade", "RemoteEvent", "InvokeServer" } do
			expect(string.find(code, other, 1, true)).toBe(nil)
		end
		expect(select(2, string.gsub(code, "BuyConsumable", ""))).toBe(1)
	end)
end)

describe("Inventory consumable stacks (S3)", function()
	local function stackState(extra: any?): any
		local state: any = {
			consumables = { held = { LuckPotion = 3, MutationSpray = 1 } },
			slimes = { { slime = { id = "s1", tier = 2 } } },
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
		expect(#slots).toBe(4) -- Bat, Speed Coil, Mutation Spray, Luck Potion
		expect(UiHarness.find(slots[3], "Count").Text).toBe("1")
		expect(UiHarness.find(slots[3], "Count").Visible).toBe(true)
		expect(UiHarness.find(slots[4], "Count").Text).toBe("3")
		expect(UiHarness.find(slots[2], "Count").Visible).toBe(false) -- a Tool has no stack
	end)

	it("a number key puts the consumable in hand, the same number again puts it away; nothing is sent", function()
		local inv, tools, sent = mount(stackState(), COIL)
		expect(inv.pressKey(4)).toBe(true)
		expect(inv.heldConsumable()).toBe("LuckPotion")
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
		expect(sent[1][2]).toBe("LuckPotion")
		expect(sent[1][3]).toBeNil()
		expect(inv.useHeld()).toBe(false) -- inside the gap: the server's rate limit is never hit by a double click
		expect(#sent).toBe(1)
	end)

	it("the spray goes on the usual target slime", function()
		local inv, _, sent = mount(stackState())
		inv.pressKey(2) -- Bat, Mutation Spray
		expect(inv.useHeld()).toBe(true)
		expect(sent[1][2]).toBe("MutationSpray")
		expect(sent[1][3]).toBe("s1")
	end)

	it("the hand empties when the last one is used, a Tool or PvP item is picked, or the player carries", function()
		local inv = mount(stackState(), COIL)
		inv.pressKey(3)
		expect(inv.heldConsumable()).toBe("MutationSpray")
		inv.update(stackState({ consumables = { held = { LuckPotion = 3 } } })) -- the spray was used up
		expect(inv.heldConsumable()).toBeNil()
		inv.pressKey(3)
		expect(inv.heldConsumable()).toBe("LuckPotion")
		inv.pressKey(1) -- the Bat
		expect(inv.heldConsumable()).toBeNil()
		inv.pressKey(3)
		inv.update(stackState({ carrying = { slimeId = "x" } }))
		expect(inv.heldConsumable()).toBeNil()
		expect(inv.useHeld()).toBe(false)
	end)

	it("the bag panel lists the stacks too", function()
		local inv = mount(stackState(), COIL)
		inv.setPanelOpen(true)
		local seen = 0
		for _, child in UiHarness.find(inv.panel.frame, "Grid"):GetChildren() do
			if child.Visible and UiHarness.find(child, "Count") and UiHarness.find(child, "Count").Visible then
				seen += 1
			end
		end
		expect(seen).toBe(2)
	end)
end)

describe("Inventory PvP item use", function()
	local GLOVE = "KnockGlove1"
	local function mountPvp(equipped: string?, reply: any?, cooldowns: any?)
		local gui = UiHarness.root()
		local sent: { { any } } = {}
		local aims = 0
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
					players = { { userId = 7, position = { X = 4, Y = 3, Z = 0 }, carrying = true } },
				}
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

	it("a cooling-down item says when it is ready and sends nothing", function()
		local inv, sent, gui = mountPvp(GLOVE, nil, { [GLOVE] = 103 })
		expect(inv.useHeld(SCREEN)).toBe(false)
		expect(#sent).toBe(0)
		expect(UiHarness.find(gui, "Tip").Text).toBe("Ready in 3s")
	end)
end)
