--!strict
-- Esc / gamepad B close every menu (v28 Esc audit): the nav menus, the Shop
-- opened by the ShopStand prompt and the Guide card, through the same
-- ContextActionService binding as the client (MenuClose), driven by a fake
-- service. Esc must also work when Roblox already processed the key.
local roblox = require("@lune/roblox") :: any

local Constants = require("../../src/shared/Constants")
local Layout = require("../../src/ui/Layout")
local Nav = require("../../src/ui/Nav")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Enum = roblox.Enum
local MenuClose = UiHarness.ui("MenuClose") -- loaded with the Roblox globals (Enum)

-- Mirrors init.client: setOpen(key) / setOpen(nil), prompt path included.
local function newClient()
	local c: any = { open = nil :: string?, bound = nil, keys = nil, closes = 0 }
	local fake = {
		BindAction = function(_: any, name: string, handler: any, touch: boolean, ...: any)
			c.bound = { name = name, handler = handler, touch = touch }
			c.keys = { ... }
		end,
	}
	MenuClose.bind(fake, Layout.CLOSE_WITH_ESCAPE, function()
		return c.open
	end, function()
		c.closes += 1
		c.open = nil
	end)
	local prompts = MenuClose.promptMenus(Constants.SHOP_PROMPT_NAME, Constants.GUIDE_PROMPT_NAME)
	function c.trigger(promptName: string)
		local key = prompts[promptName]
		if key then
			c.open = key
		end
	end
	function c.press(inputState: any)
		return c.bound.handler("CloseMenu", inputState, nil)
	end
	return c
end

describe("MenuClose (Esc / gamepad B)", function()
	it("binds CloseMenu to ButtonB and Escape, no touch button", function()
		local c = newClient()
		expect(c.bound.name).toBe("CloseMenu")
		expect(c.bound.touch).toBe(false)
		expect(table.find(c.keys, Enum.KeyCode.ButtonB) ~= nil).toBe(true)
		expect(table.find(c.keys, Enum.KeyCode.Escape) ~= nil).toBe(true)
	end)
	it("closes every menu, nav ones and Guide, and sinks the key", function()
		local keys = {}
		for _, entry in Nav.ENTRIES do
			table.insert(keys, entry.key)
		end
		table.insert(keys, "Guide")
		for _, key in keys do
			local c = newClient()
			c.open = key
			expect(c.press(Enum.UserInputState.Begin)).toBe(Enum.ContextActionResult.Sink)
			expect(c.open).toBe(nil)
		end
	end)
	it("closes the Shop opened from the ShopStand prompt, the Guide from its Talk prompt", function()
		local c = newClient()
		c.trigger(Constants.SHOP_PROMPT_NAME)
		expect(c.open).toBe("Shop")
		expect(c.press(Enum.UserInputState.Begin)).toBe(Enum.ContextActionResult.Sink)
		expect(c.open).toBe(nil)
		c.trigger(Constants.GUIDE_PROMPT_NAME)
		expect(c.open).toBe("Guide")
		c.press(Enum.UserInputState.Begin)
		expect(c.open).toBe(nil)
		expect(c.closes).toBe(2)
	end)
	it("passes the key on with no menu open, and ignores End / Change", function()
		local c = newClient()
		expect(c.press(Enum.UserInputState.Begin)).toBe(Enum.ContextActionResult.Pass)
		c.trigger(Constants.SHOP_PROMPT_NAME)
		expect(c.press(Enum.UserInputState.End)).toBe(Enum.ContextActionResult.Pass)
		expect(c.open).toBe("Shop")
	end)
	it("is not gated on gameProcessedEvent: the client uses ContextActionService only", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/ui/init.client.luau")
		expect(string.find(src, "InputBegan", 1, true)).toBe(nil)
		expect(string.find(src, "MenuClose.bind(ContextActionService", 1, true) ~= nil).toBe(true)
	end)
end)
