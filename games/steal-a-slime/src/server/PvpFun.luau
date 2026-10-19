--!strict
--[[
	PvpFun (FEATURES.PvP, CONTRACT.md §26 "Fun items")

	The `Fun` line handler for PvpService.registerLine (FunConfetti .. FunFireworks). PvpService has already
	checked the flag, ownership, equipped item, cooldown and the new-player shield. Here: each item's own targeting rule, then the PvpEvent "Effect".
	The server creates NOTHING in Workspace: the look is client FX from the event. The Bounce Pad is a data record
	(position + expiry, max `maxPlaced` per owner) announced with PvpEvent "TrapPlaced" / "TrapCleared" (itemId
	FunBouncePad) so the client draws it; the server only watches steps in the per-player WorldView tick (PvpFun.tick).
	Movement goes through `ctx.launch` (init.server passes an AssemblyLinearVelocity launch; Lune tests record). No Humanoid health is ever changed.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpKnockbackRules = if Shared then require(Shared.PvpKnockbackRules) else require("../shared/PvpKnockbackRules")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local World = if script then require(script.Parent.World) else require("./World")

type Vec = PvpRules.Vec
type Session = World.Session

type Pad = { id: string, owner: Session, position: Vec, expiresAt: number }

local PvpFun = {}

local pads: { [Session]: Pad } = setmetatable({}, { __mode = "k" }) :: any
local lastBounce: { [number]: number } = {}
local padCounter = 0

local function isThief(session: Session): boolean
	return session.carry ~= nil and session.carry.kind == "stolen"
end

local function effect(call: PvpService.UseCall, effectName: string, extra: { [string]: any }?)
	local payload: { [string]: any } = {
		attacker = call.session.userId,
		itemId = call.tool.id,
		effect = effectName,
		position = call.position,
		duration = Config.PVP.FX_SECONDS,
	}
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	PvpService.fireEffect(call.world, payload, call.now, true) -- PvpService.use only calls a handler with the flag on
end

local function distance(a: Vec, b: Vec): number
	return PvpKnockbackRules.distance(a, b)
end

-- Items that take no player target (the aim / self items).
local function noTarget(call: PvpService.UseCall): (boolean, string?)
	if call.target then
		return false, "no target needed"
	end
	return true, nil
end

local function confetti(call: PvpService.UseCall): (boolean, string?)
	local ok, why = noTarget(call)
	if not ok then
		return false, why
	end
	effect(call, "Cosmetic")
	return true, nil
end

-- An aim point within FUN_AIM_RANGE of the attacker.
local function aimPoint(call: PvpService.UseCall): (Vec?, string?)
	local aim: any = call.aim
	-- a Roblox Vector3 is a native vector (type "vector"); Lune tests also pass plain tables
	if type(aim) ~= "vector" and type(aim) ~= "table" and typeof(aim) ~= "Vector3" then
		return nil, "no aim"
	end
	local point: Vec = { X = aim.X, Y = aim.Y, Z = aim.Z }
	if point.X ~= point.X or point.Y ~= point.Y or point.Z ~= point.Z then
		return nil, "no aim"
	end
	if distance(call.position, point) > Config.PVP.FUN_AIM_RANGE then
		return nil, "too far away"
	end
	return aim :: any, nil -- the Vector3 itself: clients only draw effects at a Vector3 position
end

local function balloon(call: PvpService.UseCall): (boolean, string?)
	local ok, why = noTarget(call)
	if not ok then
		return false, why
	end
	local point, reason = aimPoint(call)
	if not point then
		return false, reason
	end
	effect(call, "Cosmetic", {
		position = point,
		duration = call.tool.fadeSeconds,
		count = call.tool.maxDecals,
	})
	return true, nil
end

local function onOwnPlot(call: PvpService.UseCall, position: Vec): boolean
	local check = call.ctx.pointOnOwnPlot
	return check ~= nil and check(call.session, position)
end

local function fireworks(call: PvpService.UseCall): (boolean, string?)
	local ok, why = noTarget(call)
	if not ok then
		return false, why
	end
	if not onOwnPlot(call, call.position) then
		return false, "only on your plot"
	end
	local point = call.position
	if call.aim ~= nil then
		local aimed, reason = aimPoint(call)
		if not aimed then
			return false, reason
		end
		if not onOwnPlot(call, aimed) then
			return false, "only on your plot"
		end
		point = aimed
	end
	effect(call, "Cosmetic", { position = point, duration = Config.PVP.FIREWORKS_SECONDS })
	return true, nil
end

-- Self (no target) or a Roblox friend in reach.
local function hatLauncher(call: PvpService.UseCall): (boolean, string?)
	local seconds = call.tool.hatSeconds
	local target = call.target
	if not target then
		effect(call, "Cosmetic", { target = call.session.userId, duration = seconds })
		return true, nil
	end
	local friends = call.ctx.areFriends -- nil = nobody is a friend
	if not friends or not friends(call.session.userId, target.userId, call.now) then
		return false, "friends only"
	end
	if not call.targetPosition or not PvpKnockbackRules.inReach(call.tool, call.position, call.targetPosition) then
		return false, "too far away"
	end
	effect(call, "Cosmetic", { target = target.userId, position = call.targetPosition, duration = seconds })
	return true, nil
end

-- Squeak, plus a tiny nudge on a thief carrying a slime. Shares the slap cooldown (Session.lastSlapAt).
local function squeaky(call: PvpService.UseCall): (boolean, string?)
	local session = call.session
	if call.now - session.lastSlapAt < Config.SLAP_COOLDOWN then
		return false, "slap on cooldown"
	end
	local target, targetPosition = call.target, call.targetPosition
	local nudged = 0
	local nudgeVelocity: PvpKnockbackRules.Vec? = nil
	if target and targetPosition then
		if not PvpKnockbackRules.inReach(call.tool, call.position, targetPosition) then
			return false, "too far away"
		end
		local state = PvpService.state(target)
		local launch = call.ctx.launch
		if isThief(target) and state and PvpRules.canControl(state, call.now) and launch then
			local _, push = PvpKnockbackRules.plan({ push = call.tool.nudge } :: any, call.position, targetPosition)
			if launch(target.userId, push) then
				nudgeVelocity = PvpKnockbackRules.velocity(push)
				PvpRules.applyControl(state, Config.PVP.FUN_NUDGE_CONTROL_SECONDS, call.now)
				nudged = PvpKnockbackRules.horizontal(push)
			end
		end
	end
	session.lastSlapAt = call.now
	effect(call, "Cosmetic", {
		target = if target then target.userId else nil,
		position = targetPosition or call.position,
		push = if nudged > 0 then nudged else nil,
		velocity = nudgeVelocity,
	})
	return true, nil
end

-- Own plot, thieves only: a short dance (control, then immunity).
local function danceBomb(call: PvpService.UseCall): (boolean, string?)
	local target, targetPosition = call.target, call.targetPosition
	if not target or not targetPosition then
		return false, "no target"
	end
	if not isThief(target) then
		return false, "only thieves"
	end
	if not onOwnPlot(call, targetPosition) then
		return false, "only on your plot"
	end
	if not PvpKnockbackRules.inReach(call.tool, call.position, targetPosition) then
		return false, "too far away"
	end
	local state = PvpService.state(target)
	if not state or not PvpRules.canControl(state, call.now) then
		return false, "target is immune"
	end
	local applied = PvpRules.applyControl(state, call.tool.control or 0, call.now)
	if applied <= 0 then
		return false, "target is immune"
	end
	effect(call, "Dance", { target = target.userId, position = targetPosition, duration = applied })
	return true, nil
end

local function clearPad(world: World.World, pad: Pad, now: number?)
	pads[pad.owner] = nil
	PvpService.fireTrap(world, "TrapCleared", {
		owner = pad.owner.userId,
		trapId = pad.id,
		itemId = "FunBouncePad",
		position = pad.position,
	}, now, true)
end

-- Drops pads that expired or whose owner left / lost PvP state.
local function prune(world: World.World, now: number)
	for owner, pad in pads do
		if now >= pad.expiresAt or not PvpService.state(owner) then
			clearPad(world, pad, now)
		end
	end
end

-- Own plot only, max `maxPlaced` at once; the pad is a record plus PvpEvent "TrapPlaced" (no server part).
local function bouncePad(call: PvpService.UseCall): (boolean, string?)
	local ok, why = noTarget(call)
	if not ok then
		return false, why
	end
	prune(call.world, call.now)
	if pads[call.session] then
		return false, "already placed"
	end
	local point = call.position
	if call.aim ~= nil then
		local aimed, reason = aimPoint(call)
		if not aimed then
			return false, reason
		end
		point = aimed
	end
	if not onOwnPlot(call, point) or not onOwnPlot(call, call.position) then
		return false, "only on your plot"
	end
	padCounter += 1
	local pad: Pad = {
		id = `pad{call.session.userId}_{padCounter}`,
		owner = call.session,
		position = point,
		expiresAt = call.now + Config.PVP.BOUNCE_PAD_SECONDS,
	}
	pads[call.session] = pad
	PvpService.fireTrap(call.world, "TrapPlaced", {
		owner = call.session.userId,
		trapId = pad.id,
		itemId = call.tool.id,
		position = point,
	}, call.now, true)
	return true, nil
end

local HANDLERS: { [string]: PvpService.LineHandler } = {
	FunConfetti = confetti,
	FunBalloon = balloon,
	FunBubbles = confetti,
	FunBouncePad = bouncePad,
	FunSqueaky = squeaky,
	FunHatLauncher = hatLauncher,
	FunDanceBomb = danceBomb,
	FunFireworks = fireworks,
}

local function handler(call: PvpService.UseCall): (boolean, string?)
	local run = HANDLERS[call.tool.id]
	if not run then
		return false, "Coming soon"
	end
	return run(call)
end

-- The placed pad of a session, or nil.
function PvpFun.padOf(session: Session): { position: Vec, expiresAt: number }?
	return pads[session]
end

--[[
	Step detection (WorldView.updatePlayer, flag on only). Standing on a pad launches straight up `height`
	studs: the owner always; anyone else only while carrying a stolen slime, who also gets `control` seconds of
	control (and its immunity). Visitors without a slime are ignored (no consent).
]]
function PvpFun.tick(world: World.World, session: Session, position: any, now: number, ctx: PvpService.Context)
	if next(pads) == nil or not position then
		return
	end
	prune(world, now)
	local tool = PvpRules.tool("FunBouncePad")
	local launch = ctx.launch
	if not tool or not launch then
		return
	end
	local radius, userId = Config.PVP.BOUNCE_PAD_RADIUS, session.userId
	for owner, pad in pads do
		local dx, dz, dy = position.X - pad.position.X, position.Z - pad.position.Z, position.Y - pad.position.Y
		if dx * dx + dz * dz <= radius * radius and dy >= -3 and dy <= 6 then
			local state = PvpService.state(session)
			if owner == session then
				if now - (lastBounce[userId] or -math.huge) >= Config.PVP.BOUNCE_RETRIGGER_SECONDS then
					lastBounce[userId] = now
					local lift = { X = 0, Y = tool.height or 0, Z = 0 }
					if launch(userId, lift) then
						PvpService.fireEffect(world, {
							attacker = userId,
							target = userId,
							itemId = tool.id,
							effect = "Bounce",
							position = position,
							duration = Config.PVP.FX_SECONDS,
							velocity = PvpKnockbackRules.velocity(lift),
						}, now, true)
					end
				end
			elseif
				state
				and isThief(session)
				and not PvpService.isShielded(session, now)
				and PvpRules.canControl(state, now)
			then
				local applied = PvpRules.applyControl(state, tool.control or 0, now)
				local lift = { X = 0, Y = tool.height or 0, Z = 0 }
				if applied > 0 and launch(userId, lift) then
					PvpService.fireEffect(world, {
						attacker = owner.userId,
						target = userId,
						itemId = tool.id,
						effect = "Bounce",
						position = position,
						duration = applied,
						velocity = PvpKnockbackRules.velocity(lift),
					}, now, true)
				end
			end
			return
		end
	end
end

-- Removes the session's pad (leave, flag off) and tells the clients.
function PvpFun.clear(world: World.World, session: Session)
	local pad = pads[session]
	if pad then
		clearPad(world, pad, nil)
	end
	lastBounce[session.userId] = nil
end

-- Forgets every pad (tests).
function PvpFun.reset()
	for owner in pads do
		pads[owner] = nil
	end
	table.clear(lastBounce)
end

-- Registers the Fun line and the pad cleanup (leave, flag off). Harmless with the flag off (PvpService.use refuses first).
function PvpFun.register()
	PvpService.registerLine("Fun", handler)
	PvpService.onCleanup(PvpFun.clear)
end

return PvpFun
