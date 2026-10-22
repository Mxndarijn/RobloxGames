--!strict
--[[
	PvpService (pure, FEATURES.PvP, CONTRACT.md §26)

	Server side of PvP. With the flag OFF nothing here does anything: `buy` refuses, no runtime state is created,
	no attribute is published. With it ON:
	  * `buy` is the `BuyPvpItem` action (Shared.PvpRules.buy + a toast)
	  * one PvpRules.State per session (control immunity, cooldowns), kept in a weak table keyed by the
	    session and never saved; the lines (knockback, traps, blasters, fun items) read it through `state`
	  * `catchThief`: the one way a PvP item sends a stolen slime home (StealService.escape, the Bat's path)
	There are no safe zones. No code here ever lowers Humanoid health.

	PvpEvents go into world.outbox (World.Event type "PvpEvent"); init.server fires the remote when it drains it.
	Engine access (positions, plot checks, launches) comes in a `Context` per call, never from module state.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local PvpSlow = if script then require(script.Parent.PvpSlow) else require("./PvpSlow")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

type Session = World.Session

--[[
	What a line handler (PvpService.registerLine) receives. It validates its own geometry (reach, aim) and
	applies the effect; PvpService has already checked the flag, ownership, equipped item and cooldown
	(PvpRules.canTarget). Return (true) to spend the tool's cooldown,
	(true, nil, seconds) for another cooldown (0 = none: a Squirter shot inside its tank), (false, reason) to refuse
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
	charged: boolean, -- the button was held CHARGE_SECONDS (glove power punch, mega confetti pop, fireworks volley)
}
export type LineHandler = (call: UseCall) -> (boolean, string?, number?)
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
	-- the fountain centre in world studs: the boss's plaza coordinates are round it (BossEvent.Context)
	plazaOrigin: (() -> PvpRules.Vec)?,
	-- the ground point straight below `point` (a goo splat lands there); nil = keep the point
	groundBelow: ((point: PvpRules.Vec) -> PvpRules.Vec?)?,
	-- the Bubble Wand lift (server/PvpFunView): `userId` floats `lift` studs in a clickable bubble for `seconds`;
	-- `onPop(byUserId, now)` answers whether a click popped it. False = no character.
	funBubble: ((
		userId: number,
		seconds: number,
		lift: number,
		onPop: (byUserId: number, now: number) -> boolean
	) -> boolean)?,
}

local PvpService = {}

local states: { [Session]: PvpRules.State } = setmetatable({}, { __mode = "k" }) :: any
-- Per-session bookkeeping that is not part of PvpRules.State (also never saved).
type Extra = { equipped: string? }
local extras: { [Session]: Extra } = setmetatable({}, { __mode = "k" }) :: any
local handlers: { [string]: LineHandler? } = {}
-- Everything PvP puts in Workspace is tracked here and destroyed by `cleanup` (CONTRACT.md §26.1, zero net parts).
local spawned: { [Session]: { any } } = setmetatable({}, { __mode = "k" }) :: any

-- Server-side zones (Goo Traps) own no Instance, so they hook the same cleanup (leave, flag off).
local cleanupHooks: { (world: World.World, session: Session) -> () } = {}

function PvpService.onCleanup(hook: (world: World.World, session: Session) -> ())
	table.insert(cleanupHooks, hook)
end

-- Called on every join with the flag on (after the session's PvP state exists): a line catches the joiner up.
local joinHooks: { (world: World.World, session: Session, now: number) -> () } = {}

function PvpService.onJoin(hook: (world: World.World, session: Session, now: number) -> ())
	if not table.find(joinHooks, hook) then
		table.insert(joinHooks, hook)
	end
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
-- `target` = one userId (a replay to a joiner), nil = every client.
function PvpService.fireTrap(
	world: World.World,
	kind: string,
	payload: { [string]: any },
	now: number?,
	flag: boolean?,
	target: number?
)
	if not PvpRules.enabled(flag) then
		return
	end
	local event = table.clone(payload)
	event.kind = kind
	send(world, target, event, now)
end

function PvpService.enabled(override: boolean?): boolean
	return PvpRules.enabled(override)
end

-- The session's runtime state, or nil while the flag is off / before join.
function PvpService.state(session: Session): PvpRules.State?
	return states[session]
end

local function start(session: Session)
	extras[session] = { equipped = nil }
	states[session] = PvpRules.newState()
end

-- Called by Sessions.join. `flag` overrides FEATURES.PvP (tests).
function PvpService.join(world: World.World, session: Session, now: number, flag: boolean?)
	if not PvpService.enabled(flag) then
		states[session] = nil
		extras[session] = nil
		PvpService.cleanup(world, session)
		return
	end
	start(session)
	for _, hook in joinHooks do
		hook(world, session, now)
	end
end

-- Called by Sessions.leave before the save.
function PvpService.leave(world: World.World, session: Session, _now: number)
	local state = states[session]
	if not state then
		PvpService.cleanup(world, session)
		return
	end
	states[session] = nil
	extras[session] = nil
	PvpSlow.clear(session)
	PvpService.cleanup(world, session)
end

--[[
	A PvP item hit or caught `thief`. When they carry a stolen slime it bounces home exactly like a Bat hit
	(StealService.escape "slap": drop, bounce home, the carrier's and owner's toasts, the SlapHitAt StealAlerts FX)
	and `attacker` (nil for nobody to tell) gets a toast. Returns the slime id, or nil when nothing stolen was carried.
]]
function PvpService.catchThief(world: World.World, thief: Session, attacker: Session?, now: number): string?
	local carry = thief.carry
	if not carry or carry.kind ~= "stolen" then
		return nil
	end
	StealService.escape(world, thief, now, "slap")
	if attacker and attacker ~= thief then
		World.notify(world, attacker.userId, `You caught {thief.name}! The slime went home.`, "good", "Slap", "Slap")
	end
	return carry.slimeId
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
		start(session)
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

function PvpService.fighterAt(position: any, session: Session?): PvpRules.Fighter
	return {
		position = position,
		state = if session then states[session] else nil,
		rebirths = if session then session.data.rebirths else nil,
		carrying = session ~= nil and session.carry ~= nil and session.carry.kind == "stolen",
	}
end

--[[
	UsePvpItem. Order: flag, item exists, equipped, line handler present ("Coming soon" starts no cooldown),
	cooldown, PvpRules.canTarget for a targeted or cosmetic use (an aimed use leaves the rest to the handler),
	then the line handler. Only a handler success marks the
	cooldown (the handler may set its length, 0 = none) and sends the "Cooldown" PvpEvent. A use that spent the
	item's last trap charge unequips it.
]]
function PvpService.use(
	world: World.World,
	session: Session,
	id: string,
	targetUserId: number?,
	aim: any?,
	now: number,
	flag: boolean?,
	ctx: Context,
	charged: boolean?
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
	if target or tool.cosmetic then
		local ok, reason = PvpRules.canTarget(
			PvpService.fighterAt(position, session),
			if target then PvpService.fighterAt(targetPosition, target) else nil,
			{ now = now, toolId = id, enabled = true, data = session.data }
		)
		if not ok then
			return false, reason
		end
	end
	local used, why, cooldown = handler({
		world = world,
		ctx = ctx,
		session = session,
		tool = tool,
		target = target,
		aim = aim,
		now = now,
		position = position,
		targetPosition = targetPosition,
		charged = charged == true,
	})
	if not used then
		return false, why or "failed"
	end
	if not PvpRules.owns(session.data, id) then
		extra.equipped = nil -- the last trap charge is gone
	end
	World.markDirty(session)
	if cooldown == 0 then
		return true, nil
	end
	PvpRules.markUsed(state, id, now, cooldown)
	local endsAt = state.cooldowns[id]
	send(world, session.userId, {
		kind = "Cooldown",
		itemId = id,
		duration = endsAt - now,
		startedAt = now,
	}, now)
	return true, nil
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
	local charges: { [string]: number } = {}
	for _, tool in Config.PVP_TOOLS do
		local n = PvpRules.charges(data, tool.id)
		if n > 0 then
			charges[tool.id] = n
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
		charges = charges,
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
