--!strict
--[[
	PvpTrap (FEATURES.PvP, CONTRACT.md §26.5)

	The `Trap` line handler for PvpService.registerLine (GooTrap1-3). A use throws one trap charge at the clicked
	point (within Config.PVP.TRAP_PLACE_RANGE of the owner's server position, anywhere on the map). An owner has at
	most TRAP_MAX_LIVE live traps over all tiers: a new one past that removes the oldest. A trap is a server-side
	zone (Shared.PvpTrapRules data) checked in the existing per-player WorldView tick: it creates NO Instance. The
	look is client FX from PvpEvent "TrapPlaced" / "TrapCleared" / "Effect".

	Anyone but the owner springs a trap. Puddle: slowed. Sticky: held, then slowed. Mega: held,
	everyone else within `pull` is pulled in and held too, and they are spat out with a small bounce when the hold
	ends. A thief is always caught (PvpService.catchThief: the slime goes home). Holds / slows go through PvpRules
	(clamped, then immunity) and PvpSlow (the walk speed); a player who is immune and carries nothing passes and the
	trap stays. A trap that caught someone, or that is TRAP_LIFETIME_SECONDS old, is removed. No damage, ever.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpKnockbackRules = if Shared then require(Shared.PvpKnockbackRules) else require("../shared/PvpKnockbackRules")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpTrapRules = if Shared then require(Shared.PvpTrapRules) else require("../shared/PvpTrapRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local PvpSlow = if script then require(script.Parent.PvpSlow) else require("./PvpSlow")
local World = if script then require(script.Parent.World) else require("./World")

type Session = World.Session
type Vec = PvpRules.Vec

local PvpTrap = {}

local PVP = Config.PVP

-- A Mega Trap victim waiting to be spat out when its hold ends.
type Spit = { at: number, from: Vec, push: number, arc: number, itemId: string, owner: number }

local traps: { [Session]: { PvpTrapRules.Trap } } = setmetatable({}, { __mode = "k" }) :: any
local spits: { [Session]: Spit } = setmetatable({}, { __mode = "k" }) :: any
local nextId = 0

function PvpTrap.count(session: Session?): number
	local n = 0
	for owner, list in traps do
		if session == nil or owner == session then
			n += #list
		end
	end
	return n
end

function PvpTrap.list(session: Session): { PvpTrapRules.Trap }
	return traps[session] or {}
end

local function out(ctx: PvpService.Context?, position: Vec): any
	local convert = ctx and ctx.toVector3
	return if convert then convert(position) else position
end

local function cleared(world: World.World, trap: PvpTrapRules.Trap, now: number?, ctx: PvpService.Context?)
	PvpService.fireTrap(world, "TrapCleared", {
		owner = trap.owner,
		trapId = trap.id,
		itemId = trap.itemId,
		position = out(ctx, trap.position),
	}, now, true)
end

local function handler(call: PvpService.UseCall): (boolean, string?, number?)
	local session = call.session
	local data = session.data
	local ok, reason =
		PvpTrapRules.canPlace(call.tool, PvpRules.charges(data, call.tool.id), call.position, call.aim, true) -- PvpService.use only calls a handler with the flag on
	if not ok then
		return false, reason
	end
	PvpRules.useCharge(data, call.tool.id)
	local list = traps[session] or {}
	traps[session] = list
	for _ = 1, PvpTrapRules.overflow(#list) do
		cleared(call.world, table.remove(list, 1) :: PvpTrapRules.Trap, call.now, call.ctx)
	end
	nextId += 1
	local trap = PvpTrapRules.new(`trap{nextId}`, session.userId, call.tool, call.aim :: any, call.now)
	table.insert(list, trap)
	PvpService.fireTrap(call.world, "TrapPlaced", {
		owner = trap.owner,
		trapId = trap.id,
		itemId = trap.itemId,
		position = call.aim,
	}, call.now, true)
	return true, nil
end

--[[
	What the trap does to one `victim` (owner = the trap owner's session, may be nil after leave). Returns true when
	it affected them (caught, held or slowed): the trap is used up.
]]
local function spring(
	world: World.World,
	ctx: PvpService.Context?,
	trap: PvpTrapRules.Trap,
	owner: Session?,
	victim: Session,
	now: number
): boolean
	local state = PvpService.state(victim)
	local tool = PvpRules.tool(trap.itemId)
	if not state or not tool then
		return false
	end
	local caught = PvpService.catchThief(world, victim, owner, now) ~= nil
	local effect = PvpTrapRules.effect(tool)
	local held, slowed = 0, 0
	if effect.hold > 0 then
		held = PvpRules.applyControl(state, effect.hold, now)
		if held > 0 then
			local tail = math.min(effect.slowSeconds, math.max(0, PVP.SLOW_MAX_SECONDS - held))
			PvpSlow.hold(victim, now, now + held, 1 - effect.slow, now + held + tail)
			if effect.spit > 0 then
				spits[victim] = {
					at = now + held,
					from = trap.position,
					push = effect.spit,
					arc = effect.spitArc,
					itemId = trap.itemId,
					owner = trap.owner,
				}
			end
		end
	elseif effect.slowSeconds > 0 then
		slowed = PvpRules.applySlow(state, effect.slowSeconds, now)
		if slowed > 0 then
			PvpSlow.slow(victim, now, 1 - effect.slow, now + slowed)
		end
	end
	if not caught and held <= 0 and slowed <= 0 then
		return false
	end
	PvpService.fireEffect(world, {
		attacker = trap.owner,
		target = victim.userId,
		itemId = trap.itemId,
		trapId = trap.id,
		effect = "Freeze",
		position = out(ctx, trap.position),
		duration = if held > 0 then held else slowed,
		hold = held,
	}, now, true)
	return true
end

-- Mega Trap: everyone else within `pull` studs is pulled onto the trap and springs it too.
local function pullIn(
	world: World.World,
	ctx: PvpService.Context?,
	trap: PvpTrapRules.Trap,
	owner: Session?,
	first: Session,
	now: number
)
	local tool = PvpRules.tool(trap.itemId)
	local radius = if tool then tool.pull or 0 else 0
	local positionOf = ctx and ctx.positionOf
	if radius <= 0 or not positionOf then
		return
	end
	for userId, other in world.sessions do
		if other ~= first and userId ~= trap.owner then
			local position = positionOf(userId)
			if position and PvpTrapRules.within(trap.position, trap.radius + radius, position) then
				local state = PvpService.state(other)
				local move = ctx and ctx.launch
				if state and move and PvpRules.canControl(state, now) then
					local dx, dz = trap.position.X - position.X, trap.position.Z - position.Z
					local landing, push = PvpRules.clampKnockback(position, { X = dx, Y = 1, Z = dz })
					move(userId, push, landing)
				end
				spring(world, ctx, trap, owner, other, now)
			end
		end
	end
end

-- A held Mega Trap victim is spat out once its hold ends (a small bounce away from the trap).
local function spitOut(world: World.World, victim: Session, position: Vec, now: number, ctx: PvpService.Context?)
	local spit = spits[victim]
	if not spit or now < spit.at then
		return
	end
	spits[victim] = nil
	local move = ctx and ctx.launch
	if not move then
		return
	end
	local landing, push = PvpKnockbackRules.away(spit.from, position, spit.push, spit.arc)
	if move(victim.userId, push, landing) then
		PvpService.fireEffect(world, {
			attacker = spit.owner,
			target = victim.userId,
			itemId = spit.itemId,
			effect = "Knockback",
			position = out(ctx, position),
			push = PvpKnockbackRules.horizontal(push),
			velocity = PvpKnockbackRules.velocity(push),
			duration = PVP.FX_SECONDS,
		}, now, true)
	end
end

--[[
	Per-player tick (WorldView.updatePlayer, flag on only): expires old traps, spits a held Mega Trap victim out, and
	springs the first trap `victim` at `position` stands in. Returns true when a trap caught them.
]]
function PvpTrap.tick(
	world: World.World,
	victim: Session,
	position: any?,
	now: number,
	ctx: PvpService.Context?
): boolean
	if next(traps) == nil and next(spits) == nil then
		return false
	end
	for owner, list in traps do
		for i = #list, 1, -1 do
			if PvpTrapRules.expired(list[i], now) then
				cleared(world, table.remove(list, i) :: PvpTrapRules.Trap, now, ctx)
			end
		end
		if #list == 0 then
			traps[owner] = nil
		end
	end
	if not position then
		return false
	end
	spitOut(world, victim, position, now, ctx)
	if not PvpService.state(victim) then
		return false
	end
	for owner, list in traps do
		for i, trap in list do
			if PvpTrapRules.triggers(trap, victim.userId, position, now) then
				if spring(world, ctx, trap, owner, victim, now) then
					table.remove(list, i)
					cleared(world, trap, now, ctx)
					pullIn(world, ctx, trap, owner, victim, now)
					return true
				end
			end
		end
	end
	return false
end

-- Removes the owner's traps (leave, flag off) and tells the clients.
local function clear(world: World.World, session: Session)
	local list: { PvpTrapRules.Trap } = traps[session] or {}
	traps[session] = nil
	spits[session] = nil
	for _, trap in list do
		cleared(world, trap, nil, nil)
	end
end
PvpTrap.clear = clear

-- Registers the Trap line. Harmless with the flag off (PvpService.use refuses first).
function PvpTrap.register()
	PvpService.registerLine("Trap", handler)
	PvpService.onCleanup(clear)
end

return PvpTrap
