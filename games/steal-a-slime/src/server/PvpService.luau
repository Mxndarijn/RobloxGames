--!strict
--[[
	PvpService (pure, FEATURES.PvP, CONTRACT.md §26)

	Server side of the PvP fairness core. With the flag OFF nothing here does anything: `buy` refuses, no
	runtime state is created, no attribute is published. With it ON:
	  * `buy` is the `BuyPvpItem` action (Shared.PvpRules.buy + a toast)
	  * one PvpRules.State per session (shield, control immunity, cooldowns), kept in a weak table keyed by the
	    session and never saved; later PRs (knockback, traps, blaster, fun items) read it through `state`
	  * the new-player shield: from join until Config.PVP.NEW_PLAYER_SHIELD_SECONDS of play time (counted across
	    sessions in data.pvp.played) or the first rebirth, whichever first; stealing ends it for good. The join
	    lock (JOIN_LOCK_SECONDS) is separate and stays: a shielded player is protected at least as long as it.
	No code here ever lowers Humanoid health.

	PvpEvents go into world.outbox (World.Event type "PvpEvent"); init.server fires the remote when it drains it.
	Engine access (positions, plot checks, launches) comes in a `Context` per call, never from module state.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local World = if script then require(script.Parent.World) else require("./World")

type Session = World.Session

--[[
	What a line handler (PvpService.registerLine) receives. It validates its own geometry (reach, aim) and
	applies the effect; PvpService has already checked the flag, ownership, equipped item, cooldown, safe
	zones, shield and the own-plot / thief rule. Return (true) to spend the cooldown, (false, reason) to refuse
	without starting one.
]]
export type UseCall = {
	world: World.World,
	ctx: Context,
	session: Session,
	tool: Config.PvpTool,
	target: Session?, -- the targeted player's session
	aim: any?, -- Vector3 world point
	now: number,
	position: PvpRules.Vec, -- attacker position
	targetPosition: PvpRules.Vec?,
}
export type LineHandler = (call: UseCall) -> (boolean, string?)
-- What PvP needs from the engine. Actions.Context carries these fields (init.server builds one ctx for both);
-- tests pass fakes. A missing function means "can't": nobody is found, moved or on a plot.
export type Context = {
	-- a character's root position; nil = no character
	positionOf: ((userId: number) -> any?)?,
	-- the player `userId` stands on `session`'s plot (its HomeZone)
	onOwnPlot: ((session: Session, userId: number) -> boolean)?,
	-- the world point lies on `session`'s plot (its HomeZone)
	pointOnOwnPlot: ((session: Session, point: PvpRules.Vec) -> boolean)?,
	-- launches a character by `push` (Y = arc); false = not moved
	launch: ((userId: number, push: PvpRules.Vec, landing: PvpRules.Vec?) -> boolean)?,
	-- Roblox friends (cached by the adapter)
	areFriends: ((a: number, b: number, now: number) -> boolean)?,
	-- root position and horizontal look vector (the Bat picks its target from them)
	pose: ((userId: number) -> (PvpRules.Vec?, PvpRules.Vec?))?,
	-- Roblox: Vector3.new for event positions; nil keeps plain tables (Lune)
	toVector3: ((position: PvpRules.Vec) -> any)?,
	-- a slime model's Body position (the Bat's reach to the boss); nil = no model
	slimePosition: ((slimeId: string) -> PvpRules.Vec?)?,
}

local PvpService = {}

local states: { [Session]: PvpRules.State } = setmetatable({}, { __mode = "k" }) :: any
-- Per-session bookkeeping that is not part of PvpRules.State (also never saved).
type Extra = { equipped: string?, shieldSent: number | boolean, zone: string? }
local extras: { [Session]: Extra } = setmetatable({}, { __mode = "k" }) :: any
local handlers: { [string]: LineHandler? } = {}
-- Everything PvP puts in Workspace is tracked here and destroyed by `cleanup` (CONTRACT.md §26.1, zero net parts).
local spawned: { [Session]: { any } } = setmetatable({}, { __mode = "k" }) :: any

-- Server-side zones (Goo Traps) own no Instance, so they hook the same cleanup (leave, flag off).
local cleanupHooks: { (world: World.World, session: Session) -> () } = {}

function PvpService.onCleanup(hook: (world: World.World, session: Session) -> ())
	table.insert(cleanupHooks, hook)
end

local function capitalize(id: string): string
	return string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2)
end

-- Queues a PvpEvent for `target` (nil = every client). The adapter stamps serverTime when `now` is nil.
local function send(world: World.World, target: number?, payload: { [string]: any }, now: number?)
	payload.serverTime = payload.serverTime or now
	World.emit(world, { type = "PvpEvent", userId = target, payload = payload })
end

-- Later PRs fill the lines (Knockback, Trap, Blaster, Fun). One handler per line; nil unregisters.
function PvpService.registerLine(line: string, handler: LineHandler?)
	handlers[line] = handler
end

-- Track an Instance PvP created in Workspace so `cleanup` can destroy it.
function PvpService.track(session: Session, instance: any)
	local list = spawned[session]
	if not list then
		list = {}
		spawned[session] = list
	end
	table.insert(list :: { any }, instance)
end

function PvpService.spawnedCount(session: Session?): number
	local n = 0
	for owner, list in spawned do
		if session == nil or owner == session then
			n += #list
		end
	end
	return n
end

-- Destroys everything PvP spawned for the session (leave, flag off).
function PvpService.cleanup(world: World.World, session: Session)
	for _, hook in cleanupHooks do
		hook(world, session)
	end
	local list = spawned[session]
	spawned[session] = nil
	for _, instance: any in (list or {}) :: { any } do
		pcall(function()
			instance:Destroy()
		end)
	end
end

-- Effect for every client (FX only). No-op with the flag off.
function PvpService.fireEffect(world: World.World, payload: { [string]: any }, now: number?, flag: boolean?)
	if not PvpRules.enabled(flag) then
		return
	end
	local event = table.clone(payload)
	event.kind = "Effect"
	send(world, nil, event, now)
end

-- kind = "TrapPlaced" | "TrapCleared"; payload { owner, trapId, itemId, position }. No-op with the flag off.
function PvpService.fireTrap(world: World.World, kind: string, payload: { [string]: any }, now: number?, flag: boolean?)
	if not PvpRules.enabled(flag) then
		return
	end
	local event = table.clone(payload)
	event.kind = kind
	send(world, nil, event, now)
end

function PvpService.enabled(override: boolean?): boolean
	return PvpRules.enabled(override)
end

-- The session's runtime state, or nil while the flag is off / before join.
function PvpService.state(session: Session): PvpRules.State?
	return states[session]
end

local function start(session: Session, now: number)
	local state = PvpRules.newState()
	state.joinedAt = now
	extras[session] = { equipped = nil, shieldSent = false, zone = nil }
	local ends = PvpRules.shieldEnd(session.data.pvp.played, session.data.rebirths, now)
	if ends > 0 then
		state.shieldUntil = math.max(ends, session.lockUntil) -- covers the join lock
	end
	states[session] = state
end

-- Called by Sessions.join. `flag` overrides FEATURES.PvP (tests).
function PvpService.join(world: World.World, session: Session, now: number, flag: boolean?)
	if not PvpService.enabled(flag) then
		states[session] = nil
		extras[session] = nil
		PvpService.cleanup(world, session)
		return
	end
	start(session, now)
end

-- Whether the session's player is under the new-player shield now.
function PvpService.isShielded(session: Session, now: number): boolean
	return PvpRules.isShielded(states[session], now, session.data.rebirths)
end

-- Shield end for the player attribute (Constants.PVP_SHIELD_ATTRIBUTE): nil when not shielded or the flag is off.
function PvpService.shieldUntil(session: Session, now: number): number?
	local state = states[session]
	if state and PvpRules.isShielded(state, now, session.data.rebirths) then
		return state.shieldUntil
	end
	return nil
end

-- Stealing a slime ends the shield for good.
function PvpService.onSteal(session: Session, now: number)
	local state = states[session]
	if not state or not PvpRules.isShielded(state, now, session.data.rebirths) then
		return
	end
	state.shieldUntil = 0
	session.data.pvp.played = Config.PVP.NEW_PLAYER_SHIELD_SECONDS
	World.markDirty(session)
end

-- Called by Sessions.leave before the save: play time counts towards the shield.
function PvpService.leave(world: World.World, session: Session, now: number)
	local state = states[session]
	if not state then
		PvpService.cleanup(world, session)
		return
	end
	local pvp = session.data.pvp
	pvp.played = math.clamp(pvp.played + math.max(0, now - state.joinedAt), 0, Config.PVP.NEW_PLAYER_SHIELD_SECONDS)
	states[session] = nil
	extras[session] = nil
	PvpService.cleanup(world, session)
end

-- The equipped item id (Player attribute PvpEquipped), nil when none or the flag is off.
function PvpService.equipped(session: Session): string?
	local extra = extras[session]
	return extra and extra.equipped
end

local function runtime(session: Session, flag: boolean?): (PvpRules.State?, Extra?)
	if not PvpService.enabled(flag) then
		return nil, nil
	end
	if not states[session] then -- flag forced on by a test after join
		start(session, 0)
	end
	return states[session], extras[session]
end

-- EquipPvpItem: an owned item into the hand slot; nil unequips. Spawns nothing.
function PvpService.equip(session: Session, id: string?, flag: boolean?): (boolean, string?)
	local state, extra = runtime(session, flag)
	if not state or not extra then
		return false, "PvP is not open yet"
	end
	if id ~= nil then
		if not PvpRules.tool(id) then
			return false, "unknown item"
		end
		if not PvpRules.owns(session.data, id) then
			return false, "not owned"
		end
	end
	extra.equipped = id
	World.markDirty(session)
	return true, nil
end

local function fighterAt(position: any, session: Session?): PvpRules.Fighter
	return {
		position = position,
		state = if session then states[session] else nil,
		rebirths = if session then session.data.rebirths else nil,
		carrying = session ~= nil and session.carry ~= nil and session.carry.kind == "stolen",
	}
end

--[[
	UsePvpItem. Order: flag, item exists, equipped, line handler present ("Coming soon" starts no cooldown),
	cooldown, safe zones / shield / own-plot rule (PvpRules.canTarget), then the line handler. Only a handler
	success marks the cooldown and sends the "Cooldown" PvpEvent.
]]
function PvpService.use(
	world: World.World,
	session: Session,
	id: string,
	targetUserId: number?,
	aim: any?,
	now: number,
	flag: boolean?,
	ctx: Context
): (boolean, string?)
	local state, extra = runtime(session, flag)
	if not state or not extra then
		return false, "PvP is not open yet"
	end
	local tool = PvpRules.tool(id)
	if not tool then
		return false, "unknown item"
	end
	if extra.equipped ~= id or not PvpRules.owns(session.data, id) then
		return false, "not equipped"
	end
	local handler = handlers[tool.line]
	if not handler then
		return false, "Coming soon"
	end
	if not PvpRules.ready(state, id, now) then
		return false, "not ready"
	end
	local positionOf = ctx.positionOf
	local position = if positionOf then positionOf(session.userId) else nil
	if not position then
		return false, "can't find you"
	end
	local target: Session? = nil
	local targetPosition: any = nil
	if targetUserId ~= nil then
		target = world.sessions[targetUserId]
		targetPosition = if target and positionOf then positionOf(targetUserId) else nil
		if not target or not targetPosition then
			return false, "no such player"
		end
		if target == session then
			return false, "can't target yourself"
		end
	end
	local onPlot = target ~= nil and ctx.onOwnPlot ~= nil and ctx.onOwnPlot(session, targetUserId :: number)
	if target or tool.cosmetic then
		local ok, reason = PvpRules.canTarget(
			fighterAt(position, session),
			if target then fighterAt(targetPosition, target) else nil,
			{ now = now, toolId = id, onAttackerPlot = onPlot, enabled = true, data = session.data }
		)
		if not ok then
			return false, reason
		end
	elseif PvpRules.inSafeZone(position) then -- aimed / placed items: the handler checks the rest
		return false, "safe zone"
	end
	local used, why = handler({
		world = world,
		ctx = ctx,
		session = session,
		tool = tool,
		target = target,
		aim = aim,
		now = now,
		position = position,
		targetPosition = targetPosition,
	})
	if not used then
		return false, why or "failed"
	end
	PvpRules.markUsed(state, id, now)
	local endsAt = state.cooldowns[id]
	send(world, session.userId, {
		kind = "Cooldown",
		itemId = id,
		duration = endsAt - now,
		startedAt = now,
	}, now)
	return true, nil
end

-- Per-player server tick (called from WorldView.updatePlayer, no loop of its own): sends Shield / SafeZone
-- changes. `position` = the character's root position, nil without a character. No-op with the flag off.
function PvpService.tick(world: World.World, session: Session, position: any, now: number)
	local extra = extras[session]
	if not extra then
		return
	end
	local shield = PvpService.shieldUntil(session, now)
	if extra.shieldSent ~= (shield or false) then
		extra.shieldSent = shield or false
		send(world, session.userId, { kind = "Shield", endsAt = shield }, now)
	end
	if position then
		local zone = PvpRules.safeZoneAt(position)
		if zone ~= extra.zone then
			local old = extra.zone
			extra.zone = zone
			if old then
				send(world, session.userId, { kind = "SafeZone", zone = capitalize(old), inside = false }, now)
			end
			if zone then
				send(world, session.userId, { kind = "SafeZone", zone = capitalize(zone), inside = true }, now)
			end
		end
	end
end

-- State.pvp (CONTRACT.md §26.1): nil with the flag off.
function PvpService.view(session: Session, now: number): Types.PvpView?
	local state, extra = states[session], extras[session]
	if not state or not extra then
		return nil
	end
	local data = session.data
	local owned: { [string]: boolean } = {}
	for _, tool in Config.PVP_TOOLS do
		if PvpRules.owns(data, tool.id) then
			owned[tool.id] = true
		end
	end
	local best: { [string]: string } = {}
	for _, line in PvpRules.LINES do
		local tool = PvpRules.bestTool(data, line)
		if tool then
			best[line] = tool.id
		end
	end
	local cooldowns: { [string]: number } = {}
	for id, endsAt in state.cooldowns do
		if endsAt > now then
			cooldowns[id] = endsAt
		end
	end
	return {
		rank = data.rebirths,
		owned = owned,
		best = best,
		equipped = extra.equipped,
		cooldowns = cooldowns,
		shieldUntil = PvpService.shieldUntil(session, now),
		safeZone = if extra.zone then capitalize(extra.zone) else nil,
	}
end

-- BuyPvpItem. `flag` overrides FEATURES.PvP (tests).
function PvpService.buy(world: World.World, session: Session, id: string, flag: boolean?): (boolean, string?)
	local ok, reason = PvpRules.buy(session.data, id, flag)
	if not ok then
		return false, reason
	end
	local tool = PvpRules.tool(id)
	World.markDirty(session)
	World.notify(world, session.userId, `{if tool then tool.name else id} bought!`, "good", "Cash", id)
	return true, nil
end

return PvpService
