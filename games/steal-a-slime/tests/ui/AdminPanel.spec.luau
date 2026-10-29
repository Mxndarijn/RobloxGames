--!strict
-- The admin menu card (src/ui/Panels/Admin.luau) and its starter (src/ui/AdminMenu.luau), contract/admin-menu.md §5.
local AdminCommands = require("../../src/shared/AdminCommands")
local Config = require("../../src/shared/Config")
local SlimeRoster = require("../../src/shared/SlimeRoster")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function build(): (any, { any })
	local sent = {}
	local ctx: any = {
		Config = Config,
		AdminCommands = AdminCommands,
		SlimeRoster = SlimeRoster,
		ask = function(action: string, done: (any) -> (), ...: any)
			table.insert(sent, { action, ... })
			done({ ok = true, message = "Done here" })
		end,
	}
	return UiHarness.ui("Panels/Admin").new(UiHarness.root(), ctx), sent
end

local function button(panel: any, rowKey: string, index: number): any
	local row = UiHarness.find(panel.frame, rowKey)
	assert(row, `no row {rowKey}`)
	return UiHarness.find(row, `Button{index}`)
end

describe("Admin panel", function()
	it("opens on Me with a tab per AdminCommands tab", function()
		local panel = build()
		expect(panel.tab()).toBe("Me")
		for _, name in AdminCommands.TABS do
			expect(UiHarness.find(panel.frame, `Tab{name}`) ~= nil).toBe(true)
		end
	end)
	it("a button sends its command with its number and shows the server's line", function()
		local panel, sent = build()
		panel.update({ admin = { cheats = true }, rebirths = 2, padsUnlocked = 3 })
		UiHarness.fire(button(panel, "cashAdd", 2), "Activated")
		expect(sent[1]).toEqual({ "Admin", "cashAdd", nil, 1e6 })
		UiHarness.fire(button(panel, "setRebirths", 2), "Activated")
		expect(sent[2]).toEqual({ "Admin", "setRebirths", nil, 3 })
		expect(UiHarness.find(panel.frame, "Reply").Text).toBe("Done here")
	end)
	it("locks cheat rows with the reason on real saves, admin tools stay pressable", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build()
		panel.update({ admin = { cheats = false } })
		local cash = UiHarness.find(panel.frame, "cashAdd")
		expect(UiHarness.find(cash, "Button1")).toBe(nil)
		expect(UiHarness.find(cash, "Locked").Text).toBe("cheats only work on a test save")
		expect(UiHarness.find(UiHarness.find(panel.frame, "goHome"), "Button1") ~= nil).toBe(true)
		expect(UiHarness.find(panel.frame, "Mode").TextColor3).toBe(Theme.Warn)
		panel.update({ admin = { cheats = true } })
		expect(UiHarness.find(UiHarness.find(panel.frame, "cashAdd"), "Locked")).toBe(nil)
		expect(UiHarness.find(panel.frame, "Mode").TextColor3).toBe(Theme.Good)
	end)
	it("Items grants an Exclusive seat by its product key", function()
		local panel, sent = build()
		panel.update({ admin = { cheats = true } })
		panel.showTab("Items")
		UiHarness.fire(button(panel, "product_Seat_ufo", 1), "Activated")
		expect(sent[1]).toEqual({ "Admin", "grantProduct", "Seat_ufo", nil })
	end)
	it("Spawn has a row per rarity and per species, each sending its tier", function()
		local panel, sent = build()
		panel.update({ admin = { cheats = true } })
		panel.showTab("Spawn")
		for tier in Config.RARITIES do
			expect(UiHarness.find(panel.frame, `tier_{tier}`) ~= nil).toBe(true)
		end
		UiHarness.fire(button(panel, "species_mochi", 1), "Activated")
		expect(sent[1]).toEqual({ "Admin", "spawnSlime", "mochi", 1 })
	end)
	it("every row names a known command", function()
		local rows = UiHarness.ui("Panels/Admin").rows({ Config = Config, SlimeRoster = SlimeRoster })
		for _, tab in AdminCommands.TABS do
			for _, row in rows[tab] do
				if not row.head then
					local command = AdminCommands.get(row.command)
					expect(command ~= nil).toBe(true)
					expect((command :: any).tab).toBe(tab)
				end
			end
		end
	end)
end)

describe("AdminMenu starter", function()
	local function fakeInput()
		local handlers = {}
		return {
			handlers = handlers,
			InputBegan = {
				Connect = function(_self: any, fn: any)
					table.insert(handlers, fn)
					return { Disconnect = function() end }
				end,
			},
		}
	end

	it("builds nothing and binds no key until State names the player an admin", function()
		local AdminMenu = UiHarness.ui("AdminMenu")
		local input = fakeInput()
		local built, toggles = 0, 0
		local update = AdminMenu.start({
			gui = UiHarness.root(),
			ctx = {},
			input = input :: any,
			build = function()
				built += 1
				return { frame = UiHarness.root(), update = function() end }
			end,
			addPanel = function() end,
			toggle = function()
				toggles += 1
			end,
		})
		update({ cash = 1 })
		expect(built).toBe(0)
		expect(#input.handlers).toBe(0)
		update({ admin = { cheats = false } })
		update({ admin = { cheats = false } })
		expect(built).toBe(1)
		expect(#input.handlers).toBe(1)
		input.handlers[1]({ KeyCode = AdminMenu.KEY }, false)
		input.handlers[1]({ KeyCode = AdminMenu.KEY }, true) -- typing in a text box
		expect(toggles).toBe(1)
	end)
end)
