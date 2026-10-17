--!strict
--[[
	PvpBlaster (FEATURES.PvP, CONTRACT.md §26 "Goo Blaster line")

	The `Blaster` line handler for PvpService.registerLine (GooBlaster1-3). PvpService has already checked the
	flag, ownership, equipped item, cooldown and that the attacker is outside the safe zones. Here: the hitscan
	(Shared.PvpBlasterRules), PvpRules.canTarget on whoever the shot reaches (players that may not be targeted
	are shot through), the slow, and the PvpEvent "Effect". The server creates NOTHING in Workspace: the beam and
	the goo splat are client FX from the event.

	The slow is a walk-speed factor kept here per session (weak, never saved). `walkFactor` is multiplied into
	Carry.targetWalkSpeed, which WorldView.updatePlayer already enforces every tick, so it is restored by itself
	when the slow ends. A miss still spends the cooldown (the shot was fired); a refused use does not.
	No Humanoid health is ever changed and nothing stuns.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local PvpBlasterRules = if Shared then require(Shared.PvpBlasterRules) else require("../shared/PvpBlasterRules")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local World = if script then require(script.Parent.World) else require("./World")

type Session = World.Session
type Vec = PvpRules.Vec

export type Env = {
	positionOf: (userId: number) -> any?,
	onOwnPlot: (session: Session, userId: number) -> boolean,
	toVector3: ((position: Vec) -> any)?, -- Roblox: Vector3.new; Lune tests keep plain tables
}

local PvpBlaster = {}

local env: Env? = nil
local slows: { [Session]: { factor: number, untilTime: number } } = setmetatable({}, { __mode = "k" }) :: any

-- init.server wires the Roblox positions; nil = every use is refused (no cooldown).
function PvpBlaster.setEnv(newEnv: Env?)
	env = newEnv
end

-- Walk speed multiplier from a Goo Blaster slow (1 = none). Carry.targetWalkSpeed multiplies it in.
function PvpBlaster.walkFactor(session: Session, now: number): number
	local slow = slows[session]
	if not slow then
		return 1
	end
	if now >= slow.untilTime then
		slows[session] = nil
		return 1
	end
	return PvpBlasterRules.factorAt(slow.factor, slow.untilTime, now)
end

local function out(position: Vec): any
	local convert = env and env.toVector3
	return if convert then convert(position) else position
end

local function handler(call: PvpService.UseCall): (boolean, string?)
	local e = env
	if not e then
		return false, "can't fire right now"
	end
	local origin = call.position
	local aim: any = call.aim or call.targetPosition
	if aim == nil then
		return false, "no aim"
	end
	local dir = PvpBlasterRules.direction(origin, aim)
	if not dir then
		return false, "bad aim"
	end
	local range = PvpBlasterRules.range(call.tool)
	local attacker: PvpRules.Fighter = {
		position = origin,
		state = PvpService.state(call.session),
		rebirths = call.session.data.rebirths,
		carrying = call.session.carry ~= nil and call.session.carry.kind == "stolen",
	}
	local candidates: { PvpBlasterRules.Candidate } = {}
	for userId, other in call.world.sessions do
		local position = if other ~= call.session then e.positionOf(userId) else nil
		if position then
			local fighter: PvpRules.Fighter = {
				position = position,
				state = PvpService.state(other),
				rebirths = other.data.rebirths,
				carrying = other.carry ~= nil and other.carry.kind == "stolen",
			}
			local ok = PvpRules.canTarget(attacker, fighter, {
				now = call.now,
				toolId = call.tool.id,
				onAttackerPlot = e.onOwnPlot(call.session, userId),
				enabled = true, -- PvpService.use only calls a handler with the flag on
				data = call.session.data,
			})
			if ok then
				table.insert(candidates, { id = userId, position = position })
			end
		end
	end
	local hit = PvpBlasterRules.firstHit(origin, dir, range, candidates)
	local target = if hit then call.world.sessions[hit.id] else nil
	local state = if target then PvpService.state(target) else nil
	local applied = 0
	if target and state and hit then
		applied = PvpRules.applySlow(state, call.tool.slowSeconds or 0, call.now)
		if applied > 0 then
			slows[target] = {
				factor = PvpBlasterRules.slowFactor(call.tool),
				untilTime = call.now + applied,
			}
		end
	end
	local landed = target ~= nil and applied > 0
	PvpService.fireEffect({
		attacker = call.session.userId,
		target = if landed then (target :: Session).userId else nil,
		itemId = call.tool.id,
		effect = "Slow",
		position = out(if landed and hit then hit.position else PvpBlasterRules.endPoint(origin, dir, range)),
		duration = if landed then applied else PvpBlasterRules.MISS_FX_SECONDS,
	}, call.now, true)
	return true, nil -- a miss still spends the cooldown
end

-- Registers the Blaster line. Harmless with the flag off (PvpService.use refuses first).
function PvpBlaster.register()
	PvpService.registerLine("Blaster", handler)
end

return PvpBlaster
