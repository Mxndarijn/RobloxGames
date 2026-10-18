--!strict
--[[
	PvpTrap (FEATURES.PvP, CONTRACT.md §26 "Goo Trap line")

	The `Trap` line handler for PvpService.registerLine (GooTrap1-3). A trap is a server-side trigger zone
	(Shared.PvpTrapRules data) checked against positions in the existing per-player WorldView tick: it creates
	NO Instance (zero runtime parts, nothing to track). The look is client FX from PvpEvent "TrapPlaced" /
	"TrapCleared" / "Effect" (effect = "Freeze").

	A thief carrying the OWNER's slime who enters the radius is frozen for the tier's `control` seconds
	(PvpRules.applyControl: <= 2 s, then 3 s immunity; an immune thief passes and the trap stays armed). The
	freeze is WalkSpeed 0 through the normal TargetWalkSpeed enforcement (WorldView asks `frozen`). No damage.
	Placing beyond the tier's `traps` count is refused. Traps go on owner leave (PvpService.onCleanup).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpTrapRules = if Shared then require(Shared.PvpTrapRules) else require("../shared/PvpTrapRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local World = if script then require(script.Parent.World) else require("./World")

type Session = World.Session

local PvpTrap = {}

local traps: { [Session]: { PvpTrapRules.Trap } } = setmetatable({}, { __mode = "k" }) :: any
local frozenUntil: { [Session]: number } = setmetatable({}, { __mode = "k" }) :: any
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

-- True while a trap holds this player (WorldView sets the target WalkSpeed to 0).
function PvpTrap.frozen(session: Session, now: number): boolean
	local untilTime = frozenUntil[session]
	return untilTime ~= nil and now < untilTime
end

local function handler(call: PvpService.UseCall): (boolean, string?)
	local session = call.session
	local list = traps[session] or {}
	local check = call.ctx.pointOnOwnPlot -- nil = nothing can be placed
	local onPlot = check ~= nil and PvpTrapRules.validAim(call.aim) and check(session, call.aim)
	local ok, reason = PvpTrapRules.canPlace(call.tool, #list, call.aim, onPlot, true) -- PvpService.use only calls a handler with the flag on
	if not ok then
		return false, reason
	end
	nextId += 1
	local trap = PvpTrapRules.new(`trap{nextId}`, session.userId, call.tool, call.aim :: any, call.now)
	table.insert(list, trap)
	traps[session] = list
	PvpService.fireTrap(call.world, "TrapPlaced", {
		owner = trap.owner,
		trapId = trap.id,
		itemId = trap.itemId,
		position = call.aim,
	}, call.now, true)
	return true, nil
end

--[[
	Per-player tick (WorldView.updatePlayer, flag on only): does `victim` at `position` spring a trap?
	Returns the freeze seconds applied (0 = nothing).
]]
function PvpTrap.tick(world: World.World, victim: Session, position: any?, now: number): number
	if not position or next(traps) == nil then
		return 0
	end
	local state = PvpService.state(victim)
	if not state then
		return 0
	end
	local carry = victim.carry
	local shielded = PvpService.isShielded(victim, now)
	for owner, list in traps do
		for _, trap in list do
			local thief = carry ~= nil and carry.kind == "stolen" and carry.ownerUserId == trap.owner
			if
				PvpTrapRules.triggers(trap, victim.userId, position, thief, shielded, now)
				-- an immune thief passes through; the trap stays armed
				and PvpRules.canControl(state, now)
			then
				local applied = PvpRules.applyControl(state, trap.control, now)
				if applied > 0 then
					PvpTrapRules.spring(trap, now)
					frozenUntil[victim] = now + applied
					PvpService.fireEffect(world, {
						attacker = owner.userId,
						target = victim.userId,
						itemId = trap.itemId,
						effect = "Freeze",
						position = trap.position,
						duration = applied,
					}, now, true)
					return applied
				end
			end
		end
	end
	return 0
end

-- Removes the owner's traps (leave, flag off) and tells the clients.
local function clear(world: World.World, session: Session)
	local list: { PvpTrapRules.Trap } = traps[session] or {}
	traps[session] = nil
	frozenUntil[session] = nil
	for _, trap in list do
		PvpService.fireTrap(world, "TrapCleared", {
			owner = trap.owner,
			trapId = trap.id,
			itemId = trap.itemId,
			position = trap.position,
		}, nil, true)
	end
end
PvpTrap.clear = clear

-- Registers the Trap line. Harmless with the flag off (PvpService.use refuses first).
function PvpTrap.register()
	PvpService.registerLine("Trap", handler)
	PvpService.onCleanup(clear)
end

return PvpTrap
