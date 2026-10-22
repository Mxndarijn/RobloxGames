--!strict
--[[
	TouchControls

	Whether Roblox's touch jump button is on screen right now. Layout.screen steps the bottom-right status icons
	left of it only while it is there (ScreenOptions.touch).

	It reads the button itself (PlayerGui.TouchGui.TouchControlFrame.JumpButton, made by the PlayerModule) instead
	of guessing from the device: UserInputService.TouchEnabled is also true on touch laptops that never show the
	button, and the last input type flips on every key press or tap. The PlayerModule only builds TouchGui once
	touch input is in use, turns it off when touch controls are disabled and hides the button when the player
	switches to keyboard or gamepad, so the button's own visibility follows every one of those cases.

	`watch(ctx)` keeps the answer for the client: `shown()` is the value from the last poll, `poll()` (from the
	client frame loop) reads it again and returns true when it changed, so the caller re-runs the layout.
]]

local TouchControls = {}

export type Context = {
	playerGui: any, -- the local player's PlayerGui (tests: any table with FindFirstChild)
}

export type Watcher = {
	shown: () -> boolean,
	poll: () -> boolean,
}

local function visible(instance: any, property: string): boolean
	return instance ~= nil and instance[property] == true
end

-- True when the jump button is on screen: TouchGui on, its control frame and the button visible.
function TouchControls.jumpShown(playerGui: any): boolean
	local touchGui = playerGui:FindFirstChild("TouchGui")
	if not visible(touchGui, "Enabled") then
		return false
	end
	local frame = touchGui:FindFirstChild("TouchControlFrame")
	if not visible(frame, "Visible") then
		return false
	end
	return visible(frame:FindFirstChild("JumpButton"), "Visible")
end

function TouchControls.watch(ctx: Context): Watcher
	local current = TouchControls.jumpShown(ctx.playerGui)
	return {
		shown = function(): boolean
			return current
		end,
		poll = function(): boolean
			local now = TouchControls.jumpShown(ctx.playerGui)
			local changed = now ~= current
			current = now
			return changed
		end,
	}
end

return TouchControls
