--!strict
-- TouchControls: the HUD treats the screen as touch only while Roblox's jump button is on screen, and a poll
-- reports when that changes (input switched, touch controls turned off) so the client re-runs the layout.

local TestRunner = require("../TestRunner")
local TouchControls = require("../../src/ui/TouchControls")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- A PlayerGui-like tree: name -> child, plus the properties TouchControls reads.
local function node(props: { [string]: any }, children: { [string]: any }?): any
	local n: any = table.clone(props)
	local kids = children or {}
	function n.FindFirstChild(_: any, name: string): any
		return kids[name]
	end
	n.children = kids
	return n
end

-- PlayerGui with the PlayerModule's touch controls (or none: a keyboard-only device).
local function playerGui(touch: boolean): (any, any, any, any)
	if not touch then
		return node({}), nil, nil, nil
	end
	local jump = node({ Visible = true })
	local frame = node({ Visible = true }, { JumpButton = jump })
	local touchGui = node({ Enabled = true }, { TouchControlFrame = frame })
	return node({}, { TouchGui = touchGui }), touchGui, frame, jump
end

describe("TouchControls", function()
	it("no TouchGui (keyboard, or a touch laptop never tapped): no jump button", function()
		expect(TouchControls.jumpShown(playerGui(false))).toBe(false)
	end)

	it("the PlayerModule's jump button on screen counts; hidden or disabled anywhere up the tree does not", function()
		local gui, touchGui, frame, jump = playerGui(true)
		expect(TouchControls.jumpShown(gui)).toBe(true)
		jump.Visible = false -- switched to keyboard / gamepad
		expect(TouchControls.jumpShown(gui)).toBe(false)
		jump.Visible = true
		frame.Visible = false
		expect(TouchControls.jumpShown(gui)).toBe(false)
		frame.Visible = true
		touchGui.Enabled = false -- GuiService.TouchControlsEnabled off
		expect(TouchControls.jumpShown(gui)).toBe(false)
		touchGui.Enabled = true
		frame.children.JumpButton = nil
		expect(TouchControls.jumpShown(gui)).toBe(false)
	end)

	it("watch: shown() keeps the last poll's answer and poll() is true only when it changed", function()
		local gui = node({})
		local watcher = TouchControls.watch({ playerGui = gui })
		expect(watcher.shown()).toBe(false)
		expect(watcher.poll()).toBe(false)
		local touchGui = playerGui(true).children.TouchGui
		gui.children.TouchGui = touchGui -- first tap: the PlayerModule builds the touch controls
		expect(watcher.shown()).toBe(false) -- unchanged until the next poll
		expect(watcher.poll()).toBe(true)
		expect(watcher.shown()).toBe(true)
		expect(watcher.poll()).toBe(false)
		touchGui.children.TouchControlFrame.children.JumpButton.Visible = false
		expect(watcher.poll()).toBe(true)
		expect(watcher.shown()).toBe(false)
	end)
end)
