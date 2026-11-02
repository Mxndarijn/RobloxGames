--!strict
--[[
	ObbyAvatarView (Roblox adapter, contract/obby.md §3)

	Reads every player's R15 body scale NumberValues (BodyHeightScale and the rest, under the Humanoid) and writes what
	ObbyAvatar.decide returns. ServerLoop calls `sync` each obby tick between ObbyService.step and ObbyView.apply, so a
	runner is resized before the lift onto the start pad and gets their own size back before the move to the portal.

	It writes the NumberValues, not Humanoid:ApplyDescription: the Humanoid rescales the moment a value changes, so it
	never yields the server loop, loads nothing and can't fail on the web, and the character is already at its run
	size when it is pivoted onto the start pad (RESPAWN_LIFT, inside the MOVE_GRACE / server-move window). Holds no
	rules.
]]

local Players = game:GetService("Players")

local ObbyAvatar = require(script.Parent.ObbyAvatar)
local World = require(script.Parent.World)

local ObbyAvatarView = {}

-- The scalable Humanoid of `character` and its scale values, or nil (R6, no Humanoid, automatic scaling off).
local function read(character: Model?): (Humanoid?, ObbyAvatar.Scales?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 or not humanoid.AutomaticScalingEnabled then
		return nil, nil
	end
	local current: ObbyAvatar.Scales = {}
	for name in ObbyAvatar.STANDARD do
		local value = humanoid:FindFirstChild(name)
		if value and value:IsA("NumberValue") then
			current[name] = value.Value
		end
	end
	return humanoid, current
end

-- Normalises runners and restores players whose run ended.
function ObbyAvatarView.sync(state: ObbyAvatar.State, world: World.World)
	for _, player in Players:GetPlayers() do
		local session = world.sessions[player.UserId]
		local running = session ~= nil and session.obbyRun ~= nil
		if not running and state[player.UserId] == nil then
			continue -- not on a run and nothing to put back
		end
		local character = player.Character
		local humanoid, current = read(character)
		local writes = ObbyAvatar.decide(state, player.UserId, running, character, current)
		if writes and humanoid then
			for name, value in writes do
				local holder = humanoid:FindFirstChild(name)
				if holder and holder:IsA("NumberValue") then
					holder.Value = value
				end
			end
		end
	end
end

return ObbyAvatarView
