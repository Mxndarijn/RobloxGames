--!strict
-- Which device the player is using (src/ui/InputKind.luau).
local InputKind = require("../../src/ui/InputKind")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function uis(last: string, gamepad: boolean?, touch: boolean?): any
	return {
		GetLastInputType = function()
			return { Name = last }
		end,
		GamepadEnabled = gamepad == true,
		TouchEnabled = touch == true,
	}
end

describe("InputKind", function()
	it("reads touch, gamepads and everything else as keyboard", function()
		expect(InputKind.kind(uis("Touch"))).toBe("touch")
		expect(InputKind.kind(uis("Gamepad1"))).toBe("gamepad")
		expect(InputKind.kind(uis("Gamepad8"))).toBe("gamepad")
		expect(InputKind.kind(uis("Keyboard"))).toBe("keyboard")
		expect(InputKind.kind(uis("MouseMovement"))).toBe("keyboard")
	end)
	it("a gamepad is active after gamepad input, or when attached with no touch screen and no input yet", function()
		expect(InputKind.gamepadActive(uis("Gamepad2"))).toBe(true)
		expect(InputKind.gamepadActive(uis("Keyboard", true, false))).toBe(false)
		expect(InputKind.gamepadActive(uis("None", true, false))).toBe(true)
		expect(InputKind.gamepadActive(uis("None", true, true))).toBe(false)
		expect(InputKind.gamepadActive(uis("Touch", true, false))).toBe(false)
	end)
end)
