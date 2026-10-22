--!strict
-- Esc / gamepad B close every menu: the nav menus, the world shop card and
-- the Guide card, through the same ContextActionService binding as the client (MenuClose), driven by a fake
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
	local prompts = MenuClose.promptMenus(Constants.GUIDE_PROMPT_NAME)
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
	it("closes every menu, nav ones, the world shop and Guide, and sinks the key", function()
		local keys = {}
		for _, entry in Nav.ENTRIES do
			table.insert(keys, entry.key)
		end
		table.insert(keys, "WorldShop")
		table.insert(keys, "Guide")
		for _, key in keys do
			local c = newClient()
			c.open = key
			expect(c.press(Enum.UserInputState.Begin)).toBe(Enum.ContextActionResult.Sink)
			expect(c.open).toBe(nil)
		end
	end)
	it("closes the Guide opened from its Talk prompt; the shop prompt opens no menu from the client", function()
		local c = newClient()
		c.trigger(Constants.SHOP_PROMPT_NAME)
		expect(c.open).toBe(nil)
		c.trigger(Constants.GUIDE_PROMPT_NAME)
		expect(c.open).toBe("Guide")
		expect(c.press(Enum.UserInputState.Begin)).toBe(Enum.ContextActionResult.Sink)
		expect(c.open).toBe(nil)
		expect(c.closes).toBe(1)
	end)
	it("passes the key on with no menu open, and ignores End / Change", function()
		local c = newClient()
		expect(c.press(Enum.UserInputState.Begin)).toBe(Enum.ContextActionResult.Pass)
		c.trigger(Constants.GUIDE_PROMPT_NAME)
		expect(c.press(Enum.UserInputState.End)).toBe(Enum.ContextActionResult.Pass)
		expect(c.open).toBe("Guide")
	end)
end)
