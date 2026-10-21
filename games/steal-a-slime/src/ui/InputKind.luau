--!strict
--[[
	InputKind: which device the player is using right now, from UserInputService:GetLastInputType()
	(touch, a gamepad, else keyboard / mouse). Pure apart from the service it is handed.
]]

export type Kind = "keyboard" | "touch" | "gamepad"

local InputKind = {}

-- `last` = an Enum.UserInputType (only its Name is read).
function InputKind.of(last: { Name: string }): Kind
	if last.Name == "Touch" then
		return "touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "gamepad"
	end
	return "keyboard"
end

function InputKind.kind(uis: any): Kind
	return InputKind.of(uis:GetLastInputType())
end

-- A gamepad is the active device: the last input came from one, or one is attached and there is no touch screen
-- (a console before its first input).
function InputKind.gamepadActive(uis: any): boolean
	local last = uis:GetLastInputType()
	if InputKind.of(last) == "gamepad" then
		return true
	end
	return last.Name == "None" and uis.GamepadEnabled == true and uis.TouchEnabled ~= true
end

return table.freeze(InputKind)
