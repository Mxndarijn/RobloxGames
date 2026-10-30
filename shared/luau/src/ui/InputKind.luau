--!strict
--[[
	InputKind (pure): which device the player is using right now, from UserInputService:GetLastInputType()
	(touch, a gamepad, else keyboard / mouse), and where a pointerless gamepad aims. Reads only the service it is
	handed, so specs pass a fake.
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

-- The true screen centre in the screen space Camera:ScreenPointToRay and input positions use: the viewport's centre
-- moved up / left by the top-bar inset (GuiService:GetGuiInset()'s top-left), so a gamepad aims where the
-- crosshair would be.
function InputKind.screenCentre(viewport: Vector2, inset: Vector2): Vector2
	return viewport / 2 - inset
end

return table.freeze(InputKind)
