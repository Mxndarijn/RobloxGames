--!strict
--[[
	PvpKnockback (FEATURES.PvP, CONTRACT.md §26.4)

	The `Knockback` line handler for PvpService.registerLine (KnockGlove1-5). PvpService has already checked the
	flag, ownership, equipped item and cooldown. Here: reach, knocking a carried slime loose
	(PvpService.hitCarrier, every tier, also when the push is refused), the push (control immunity respected), the
	power punch (`call.charged`: push x CHARGE_PUSH, cooldown x CHARGE_COOLDOWN), the glove's special and the
	PvpEvent "Effect"s. The server creates NOTHING in Workspace (the look is client FX from the events).

	Specials (`tool.special`): bonk (a clean punch, clients pop "BONK!"), bounce (the victim's client pogo-bounces
	`tool.pogo`), boom (everyone else within `blastRadius` of the target is pushed `blastPush` away from it), thunder
	(up to `chain` other players within `chainRange` of the target take `push x chainFactor`), royal (a long push in a
	high `arc`). A blast / chain victim drops any slime they carry and skips immune players.

	The push goes through `ctx.launch` (init.server passes the Roblox one; Lune tests pass a recorder). No Humanoid
	health is ever changed; Roblox has no fall damage and Rescue puts anyone who still reaches the void back.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpKnockbackRules = if Shared then require(Shared.PvpKnockbackRules) else require("../shared/PvpKnockbackRules")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local World = if script then require(script.Parent.World) else require("./World")

type Vec = PvpRules.Vec
type Session = World.Session

local PvpKnockback = {}

local PVP = Config.PVP

local function out(ctx: PvpService.Context, position: Vec): any
	local convert = ctx.toVector3
	return if convert then convert(position) else position
end

-- Pushes `victim` (at `position`) along `push` / `landing` and starts the knockback control. False = not moved.
local function launch(call: PvpService.UseCall, victim: Session, push: Vec, landing: Vec): boolean
	local state = PvpService.state(victim)
	local move = call.ctx.launch
	if not state or not move or not PvpRules.canControl(state, call.now) then
		return false
	end
	if not move(victim.userId, push, landing) then
		return false
	end
	PvpRules.applyControl(state, PVP.KNOCKBACK_CONTROL_SECONDS, call.now)
	return true
end

-- Other players (not the attacker, not `around`'s owner) within `radius` of `center`, nearest first.
local function nearby(
	call: PvpService.UseCall,
	center: Vec,
	radius: number,
	skip: Session
): { { session: Session, position: Vec, d: number } }
	local found = {}
	local positionOf = call.ctx.positionOf
	if not positionOf then
		return found
	end
	for userId, other in call.world.sessions do
		if other ~= call.session and other ~= skip then
			local position = positionOf(userId)
			if position then
				local d = PvpKnockbackRules.distance(center, position)
				if d == d and d <= radius then
					table.insert(found, { session = other, position = position, d = d })
				end
			end
		end
	end
	table.sort(found, function(a, b)
		return a.d < b.d
	end)
	return found
end

-- A blast / chain victim: drops any carried slime, pushed when it may be controlled; fires its own Knockback effect.
local function splash(call: PvpService.UseCall, victim: Session, position: Vec, from: Vec, push: number)
	local caught = PvpService.hitCarrier(call.world, victim, call.session, call.now, call.ctx) ~= nil
	local landing, applied = PvpKnockbackRules.away(from, position, push, PVP.KNOCKBACK_DEFAULT_ARC)
	local pushed = launch(call, victim, applied, landing)
	if not caught and not pushed then
		return
	end
	PvpService.fireEffect(call.world, {
		attacker = call.session.userId,
		target = victim.userId,
		itemId = call.tool.id,
		effect = "Knockback",
		special = call.tool.special,
		chained = true,
		from = out(call.ctx, from),
		position = out(call.ctx, position),
		push = if pushed then PvpKnockbackRules.horizontal(applied) else 0,
		velocity = if pushed then PvpKnockbackRules.velocity(applied) else nil,
		duration = PVP.FX_SECONDS,
	}, call.now, true)
end

local function handler(call: PvpService.UseCall): (boolean, string?, number?)
	local tool = call.tool
	local target, targetPosition = call.target, call.targetPosition
	if not target or not targetPosition then
		return false, "no target"
	end
	if not PvpKnockbackRules.inReach(tool, call.position, targetPosition) then
		return false, "too far away"
	end
	local scale = if call.charged then PVP.CHARGE_PUSH else 1
	local landing, push = PvpKnockbackRules.plan(tool, call.position, targetPosition, nil, scale)
	if tool.pogo and tool.pogo[1] then
		push = { X = push.X, Y = math.min(tool.pogo[1], PVP.KNOCKBACK_ARC_HEIGHT), Z = push.Z }
	end
	local caught = PvpService.hitCarrier(call.world, target, call.session, call.now, call.ctx) ~= nil
	local pushed = launch(call, target, push, landing)
	if not caught and not pushed then
		local state = PvpService.state(target)
		return false,
			if state and not PvpRules.canControl(state, call.now) then "target is immune" else "can't push right now"
	end
	PvpService.fireEffect(call.world, {
		attacker = call.session.userId,
		target = target.userId,
		itemId = tool.id,
		effect = "Knockback",
		special = tool.special,
		charged = call.charged,
		position = out(call.ctx, targetPosition),
		push = if pushed then PvpKnockbackRules.horizontal(push) else 0,
		velocity = if pushed then PvpKnockbackRules.velocity(push) else nil, -- the victim's client applies it to its own root
		pogo = if pushed then tool.pogo else nil,
		duration = PVP.FX_SECONDS,
	}, call.now, true) -- PvpService.use only calls a handler with the flag on
	if tool.special == "boom" and tool.blastRadius then
		for _, hit in nearby(call, targetPosition, tool.blastRadius, target) do
			splash(call, hit.session, hit.position, targetPosition, tool.blastPush or 0)
		end
	elseif tool.special == "thunder" and tool.chain and tool.chainRange then
		local jumps = 0
		for _, hit in nearby(call, targetPosition, tool.chainRange, target) do
			if jumps >= tool.chain then
				break
			end
			jumps += 1
			splash(
				call,
				hit.session,
				hit.position,
				targetPosition,
				(tool.push or 0) * scale * (tool.chainFactor or 0.5)
			)
		end
	end
	return true, nil, if call.charged then tool.cooldown * PVP.CHARGE_COOLDOWN else nil
end

-- Registers the Knockback line. Harmless with the flag off (PvpService.use refuses first).
function PvpKnockback.register()
	PvpService.registerLine("Knockback", handler)
end

return PvpKnockback
