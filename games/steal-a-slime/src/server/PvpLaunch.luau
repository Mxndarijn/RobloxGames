--!strict
--[[
	PvpLaunch (FEATURES.PvP, CONTRACT.md §26 "Knockback feel")

	Server half of a PvP launch: sets the root's AssemblyLinearVelocity (works for server-owned characters; a real
	player's character is network-owned, so the same vector also goes to the victim's client in the PvpEvent
	`velocity` field) and holds the humanoid in PlatformStand for KNOCKBACK_SECONDS so ground friction does not eat
	the push, then restores it. Remembers the launch time so the void guard (Rescue.shouldRescuePvp) is armed for
	LAUNCH_GUARD_SECONDS. Nothing here runs with the flag off (only the PvP handlers call it); no Instance is created.
]]

local Players = game:GetService("Players")

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpKnockbackRules = if Shared then require(Shared.PvpKnockbackRules) else require("../shared/PvpKnockbackRules")
local Rescue = require(script.Parent.Rescue)
local WorldView = require(script.Parent.WorldView)

local PvpLaunch = {}

local lastLaunchAt: { [number]: number } = {}

-- Launches `userId` along the displacement `push` (Y = arc / bounce height). False = no character.
function PvpLaunch.launch(userId: number, push: { X: number, Y: number, Z: number }, now: number): boolean
	local player = Players:GetPlayerByUserId(userId)
	local root = WorldView.rootPart(player)
	if not root then
		return false
	end
	local v = PvpKnockbackRules.velocity(push)
	root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z)
	local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and not humanoid.PlatformStand then
		humanoid.PlatformStand = true
		task.delay(Config.PVP.KNOCKBACK_SECONDS, function()
			if humanoid.Parent then
				humanoid.PlatformStand = false
			end
		end)
	end
	for id, at in lastLaunchAt do
		if now - at > Config.PVP.LAUNCH_GUARD_SECONDS then
			lastLaunchAt[id] = nil
		end
	end
	lastLaunchAt[userId] = now
	return true
end

-- Void guard armed? (control end time comes from the caller's PvpService state)
function PvpLaunch.guardActive(userId: number, controlUntil: number?, now: number): boolean
	return Rescue.pvpActive(now, lastLaunchAt[userId], controlUntil, Config.PVP.LAUNCH_GUARD_SECONDS)
end

return PvpLaunch
