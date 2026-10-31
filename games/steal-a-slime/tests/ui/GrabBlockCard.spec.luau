--!strict
-- GrabBlockCard (src/ui/GrabBlockCard.luau): a blocked GrabPrompt switches style and shows its reason.
local Constants = require("../../src/shared/Constants")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local GrabBlockCard = UiHarness.ui("GrabBlockCard")

local STYLES = { blocked = "Custom", normal = "Default" }

local function prompt(attrs: { [string]: any }): any
	local model = {
		GetAttribute = function(_, name: string)
			return attrs[name]
		end,
	}
	local body = { Parent = model }
	local toggles = {}
	local p = { Style = "Default", toggles = toggles, Parent = body }
	local enabled = true
	return setmetatable(p, {
		__index = function(_, k)
			if k == "Enabled" then
				return enabled
			end
			return nil
		end,
		__newindex = function(t, k, v)
			if k == "Enabled" then
				enabled = v
				table.insert(toggles, v)
			else
				rawset(t, k, v)
			end
		end,
	})
end

local ME = { carrying = false, freePad = true, cash = 50 }

describe("GrabBlockCard", function()
	it("reads the slime from its model's attributes", function()
		local t = GrabBlockCard.target(prompt({ State = "Wild", Price = 30, [Constants.BOSS_ATTRIBUTE] = true }))
		expect(t.state).toBe("Wild")
		expect(t.price).toBe(30)
		expect(t.boss).toBe(true)
	end)
	it("gives the reason text, or nil before the first State", function()
		local p = prompt({ State = "Wild", Price = 80 })
		expect(GrabBlockCard.reasonText(p, ME)).toBe("Need $30 more")
		expect(GrabBlockCard.reasonText(p, nil)).toBeNil()
		expect(GrabBlockCard.reasonText(prompt({ State = "Wild", Price = 10 }), ME)).toBeNil()
	end)
	it("just after a drop every prompt counts down, steals too, then goes back to normal", function()
		local waiting = { carrying = false, freePad = true, cash = 50, pickupBlockedUntil = 101.5, now = 100.2 }
		expect(GrabBlockCard.waitText(waiting)).toBe("Grab in 1.3s")
		expect(GrabBlockCard.reasonText(prompt({ State = "Wild", Price = 10 }), waiting)).toBe("Grab in 1.3s")
		expect(GrabBlockCard.reasonText(prompt({ State = "Pad" }), waiting)).toBe("Grab in 1.3s")
		local over = { carrying = false, freePad = true, cash = 50, pickupBlockedUntil = 101.5, now = 101.5 }
		expect(GrabBlockCard.waitText(over)).toBeNil()
		expect(GrabBlockCard.reasonText(prompt({ State = "Wild", Price = 10 }), over)).toBeNil()
		expect(GrabBlockCard.waitText(nil)).toBeNil()
	end)
	it("switches style and re-shows an enabled prompt only on a change", function()
		local p = prompt({ State = "Wild", Price = 80 })
		GrabBlockCard.setStyle(p, true, STYLES)
		expect(p.Style).toBe("Custom")
		expect(#p.toggles).toBe(2)
		GrabBlockCard.setStyle(p, true, STYLES)
		expect(#p.toggles).toBe(2)
		GrabBlockCard.setStyle(p, false, STYLES)
		expect(p.Style).toBe("Default")
		expect(p.Enabled).toBe(true)
	end)
	it("hangs the card under the Body, clear of the name tag above it", function()
		local bodyHeight = 3
		local top = GrabBlockCard.offsetY(bodyHeight)
		expect(top < -bodyHeight / 2).toBe(true)
	end)
	it("leaves a disabled prompt disabled", function()
		local p = prompt({})
		p.Enabled = false
		table.clear(p.toggles)
		GrabBlockCard.setStyle(p, true, STYLES)
		expect(p.Style).toBe("Custom")
		expect(#p.toggles).toBe(0)
		expect(p.Enabled).toBe(false)
	end)
end)
