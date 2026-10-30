--!strict
-- Every button under the root clicks, driven through minimal mock instances.
local ButtonClicks = require("../../src/ui/ButtonClicks")
local TestRunner = require("../../testing/TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return {
				Disconnect = function()
					local i = table.find(handlers, fn)
					if i then
						table.remove(handlers, i)
					end
				end,
			}
		end,
		Fire = function(_, ...)
			for _, fn in table.clone(handlers) do
				fn(...)
			end
		end,
	}
end

local function instance(isButton: boolean): any
	local self = { Activated = signal(), DescendantAdded = signal(), children = {}, attrs = {} }
	function self.GetAttribute(_, key)
		return self.attrs[key]
	end
	function self.IsA(_, cls)
		return isButton and cls == "GuiButton"
	end
	function self.GetDescendants()
		return self.children
	end
	return self
end

local function setup()
	local played = {}
	local root = instance(false)
	local stop = ButtonClicks.start(root, function(name)
		table.insert(played, name)
	end)
	return root, played, stop
end

describe("ButtonClicks", function()
	it("clicks for buttons that exist at start", function()
		local root = instance(false)
		local button = instance(true)
		table.insert(root.children, button)
		local played = {}
		ButtonClicks.start(root, function(name)
			table.insert(played, name)
		end)
		button.Activated:Fire()
		expect(#played).toBe(1)
		expect(played[1]).toBe("click")
	end)
	it("clicks for buttons added later, once each", function()
		local root, played = setup()
		local button = instance(true)
		root.DescendantAdded:Fire(button)
		root.DescendantAdded:Fire(button)
		button.Activated:Fire()
		expect(#played).toBe(1)
	end)
	it("ignores anything that is not a button", function()
		local root, played = setup()
		local frame = instance(false)
		root.DescendantAdded:Fire(frame)
		frame.Activated:Fire()
		expect(#played).toBe(0)
	end)
	it("stays quiet for hold-to-confirm and disabled buttons, checked on each press", function()
		local root, played = setup()
		local hold = instance(true)
		hold.attrs.HoldConfirm = 1
		local plain = instance(true)
		root.DescendantAdded:Fire(hold)
		root.DescendantAdded:Fire(plain)
		hold.Activated:Fire()
		plain.attrs.ClickMuted = true
		plain.Activated:Fire()
		expect(#played).toBe(0)
		plain.attrs.ClickMuted = nil
		plain.Activated:Fire()
		expect(#played).toBe(1)
	end)
	it("takes its own sound name, skip attributes and on / off switch", function()
		local root = instance(false)
		local button = instance(true)
		table.insert(root.children, button)
		local played = {}
		local on = true
		ButtonClicks.start(root, function(name)
			table.insert(played, name)
		end, function(): boolean
			return on
		end, { sound = "tap", skipAttributes = { "Silent" } })
		button.Activated:Fire()
		button.attrs.HoldConfirm = 1
		button.Activated:Fire()
		button.attrs.Silent = true
		button.Activated:Fire()
		button.attrs.Silent = nil
		on = false
		button.Activated:Fire()
		expect(played).toEqual({ "tap", "tap" })
	end)
	it("goes quiet after cleanup", function()
		local root, played, stop = setup()
		local before = instance(true)
		root.DescendantAdded:Fire(before)
		stop()
		before.Activated:Fire()
		local after = instance(true)
		root.DescendantAdded:Fire(after)
		after.Activated:Fire()
		expect(#played).toBe(0)
	end)
end)
