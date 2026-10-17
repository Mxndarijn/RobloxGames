--!strict
--[[
	PvpKnockback (FEATURES.PvP, CONTRACT.md §26 "Knockback line")

	The `Knockback` line handler for PvpService.registerLine (KnockGlove1-5). PvpService has already checked the
	flag, ownership, equipped item, cooldown, safe zones, shield and the own-plot / thief rule. Here: reach, control
	immunity, the push, dropping a stolen slime, and the PvpEvent "Effect". The server creates NOTHING in Workspace
	(the look is client FX from the event), so there is nothing to track or clean up.

	The push goes through an injectable mover (init.server sets the Roblox one: a short AssemblyLinearVelocity launch;
	Lune tests inject a recorder). No Humanoid health is ever changed; Roblox has no fall damage and Rescue
	puts anyone who still reaches the kill plane back on their plot.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpKnockbackRules = if Shared then require(Shared.PvpKnockbackRules) else require("../shared/PvpKnockbackRules")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")

type Vec = PvpRules.Vec

-- (userId, push, landing) -> moved. `push` is the clamped displacement (Y = arc), `landing` the end point.
export type Mover = (userId: number, push: Vec, landing: Vec) -> boolean

local PvpKnockback = {}

local mover: Mover? = nil

-- nil = nobody can be moved (every use is refused, no cooldown).
function PvpKnockback.setMover(newMover: Mover?)
	mover = newMover
end

local function handler(call: PvpService.UseCall): (boolean, string?)
	local target, targetPosition = call.target, call.targetPosition
	if not target or not targetPosition then
		return false, "no target"
	end
	if not PvpKnockbackRules.inReach(call.tool, call.position, targetPosition) then
		return false, "too far away"
	end
	local state = PvpService.state(target)
	if not state or not PvpRules.canControl(state, call.now) then
		return false, "target is immune"
	end
	local move = mover
	if not move then
		return false, "can't push right now"
	end
	local landing, push = PvpKnockbackRules.plan(call.tool, call.position, targetPosition)
	if not move(target.userId, push, landing) then
		return false, "can't find them"
	end
	PvpRules.applyControl(state, Config.PVP.KNOCKBACK_CONTROL_SECONDS, call.now)
	-- A thief drops the slime exactly like the base slap does.
	StealService.escape(call.world, target, call.now, "slap")
	PvpService.fireEffect({
		attacker = call.session.userId,
		target = target.userId,
		itemId = call.tool.id,
		effect = "Knockback",
		position = targetPosition,
		push = PvpKnockbackRules.horizontal(push),
		velocity = PvpKnockbackRules.velocity(push), -- the victim's client applies it to its own root (it owns the character)
		duration = Config.PVP.FX_SECONDS,
	}, call.now, true) -- PvpService.use only calls a handler with the flag on
	return true, nil
end

-- Registers the Knockback line. Harmless with the flag off (PvpService.use refuses first).
function PvpKnockback.register()
	PvpService.registerLine("Knockback", handler)
end

return PvpKnockback
