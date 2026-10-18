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
	it("the only server names it touches are existing: EquipPvpItem", function()
		local core = fs.readFile("src/ui/InventoryCore.luau")
		expect(string.find(core, 'PVP_ACTION = "EquipPvpItem"', 1, true) ~= nil).toBe(true)
		local code = GlyphCheck.stripComments(core)
		for _, other in { "UsePvpItem", "BuyConsumable", "RemoteEvent", "InvokeServer" } do
			expect(string.find(code, other, 1, true)).toBe(nil)
		end
	end)
end)
