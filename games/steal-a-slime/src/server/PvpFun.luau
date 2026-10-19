--!strict
--[[
	PvpFun (FEATURES.PvP, CONTRACT.md §26.8)

	The `Fun` line handler for PvpService.registerLine (FunConfetti .. FunFireworks). PvpService has already checked
	the flag, ownership, the equipped item, the cooldown and the user's new-player shield. Every item is aimed (`aim`,
	plus `charged` for the Confetti Popper's mega pop and the Goo Fireworks volley); none takes a target player, so the
	handler picks who is hit.

	What the server keeps, all runtime-only and capped: thrown balloons / dance bombs until they land (`landings`),
	Bubble Wand streams (`streams`), Bounce Pads (`pads`, at most `maxPlaced` per owner), control holds (bubble lift,
	pancake, dance: walk speed 0 through `frozen`), the Balloon slow (`walkFactor`), hat stacks and hammer combos. It
	is stepped in the per-player WorldView.updatePlayer tick (`tick`, no loop of its own) and dropped on leave / flag
	off (PvpService.onCleanup). The look is client FX (ui/PvpFunFx) from PvpEvent "Effect"; the one server-made part
	is the bubble around a lifted player (`ctx.funBubble`, server/PvpFunView).

	Shielded players only get the cosmetic part (confetti, paint, hats); control goes through PvpRules.applyControl
	(cap, then immunity). A thief carrying a stolen slime who is lifted, bounced, bonked or made to dance loses it:
	PvpService.catchThief bounces the slime back to its owner. No Humanoid health is ever changed.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpFunRules = if Shared then require(Shared.PvpFunRules) else require("../shared/PvpFunRules")
local PvpKnockbackRules = if Shared then require(Shared.PvpKnockbackRules) else require("../shared/PvpKnockbackRules")
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local World = if script then require(script.Parent.World) else require("./World")

type Vec = PvpRules.Vec
type Session = World.Session

type Hold = { kind: string, untilTime: number, push: Vec?, attacker: number, sprung: boolean? }
type Landing = {
	kind: string, -- "balloon" | "disco"
	owner: Session,
	position: Vec,
	landAt: number,
	endsAt: number,
	hit: { [Session]: boolean },
}
type Stream = PvpFunRules.Stream & { id: string, owner: Session, popped: { [number]: boolean } }
type Pad = { id: string, owner: Session, position: Vec, expiresAt: number }

local FUN = Config.PVP_FUN
local LANDINGS_MAX = 16
local AREA_HEIGHT = 8 -- studs above / below a landing that still count as inside it
local PAD_LOW, PAD_HIGH = -3, 6 -- a root this far below / above a pad stands on it
local CONFETTI_ABOVE = 6 -- the rain reaches players up to this far above the burst
local SPRING_SLACK = 2 -- studs of reach slack for a player's root vs the hammer's reach

local PvpFun = {}

local holds: { [Session]: Hold } = setmetatable({}, { __mode = "k" }) :: any
local slows: { [Session]: { factor: number, untilTime: number } } = setmetatable({}, { __mode = "k" }) :: any
local combos: { [Session]: PvpFunRules.Combo } = setmetatable({}, { __mode = "k" }) :: any
local hats: { [Session]: { count: number, untilTime: number } } = setmetatable({}, { __mode = "k" }) :: any
local lastBounce: { [Session]: number } = setmetatable({}, { __mode = "k" }) :: any
local pads: { [Session]: { Pad } } = setmetatable({}, { __mode = "k" }) :: any
local landings: { Landing } = {}
local streams: { Stream } = {}
local counter = 0

local function nextId(prefix: string, session: Session): string
	counter += 1
	return `{prefix}{session.userId}_{counter}`
end

local function isThief(session: Session): boolean
	return session.carry ~= nil and session.carry.kind == "stolen"
end

-- A position for an event: a Vector3 in Roblox (ctx.toVector3), the plain table in Lune.
local function out(ctx: PvpService.Context, position: Vec): any
	local convert = ctx.toVector3
	return if convert then convert(position) else position
end

local function fire(world: World.World, now: number, payload: { [string]: any })
	PvpService.fireEffect(world, payload, now, true) -- PvpService.use only calls a handler with the flag on
end

-- Not shielded, has PvP state and is free of control and immunity.
local function controllable(session: Session, now: number): (boolean, PvpRules.State?)
	local state = PvpService.state(session)
	if not state or PvpService.isShielded(session, now) then
		return false, state
	end
	return PvpRules.canControl(state, now), state
end

-- The aim point: the sent `aim` when usable, else `ahead` studs in front of the user (ctx.pose), else the user's spot.
local function aimOf(call: PvpService.UseCall, ahead: number): Vec
	local aim = PvpFunRules.vec(call.aim)
	if aim then
		return aim
	end
	local pose = call.ctx.pose
	local look: Vec? = nil
	if pose then
		local _, facing = pose(call.session.userId)
		look = facing
	end
	local p = call.position
	if look then
		return { X = p.X + look.X * ahead, Y = p.Y, Z = p.Z + look.Z * ahead }
	end
	return { X = p.X, Y = p.Y, Z = p.Z }
end

-- Every other player with a character: session and root position.
local function others(call: PvpService.UseCall): { { session: Session, position: Vec } }
	local list = {}
	local positionOf = call.ctx.positionOf
	if not positionOf then
		return list
	end
	for userId, other in call.world.sessions do
		if other ~= call.session then
			local position = PvpFunRules.vec(positionOf(userId))
			if position then
				table.insert(list, { session = other, position = position })
			end
		end
	end
	return list
end

local function noTarget(call: PvpService.UseCall): (boolean, string?)
	if call.target then
		return false, "no target needed"
	end
	return true, nil
end

-- Confetti Popper: a burst along the aim (also straight up) that rains on everyone under it. Cosmetic only.
local function confetti(call: PvpService.UseCall): (boolean, string?)
	local cfg = FUN.CONFETTI
	local center = PvpFunRules.within(call.position, aimOf(call, cfg.RANGE), cfg.RANGE)
	local mega = call.charged
	local radius = if mega then cfg.MEGA_RADIUS else cfg.RADIUS
	local targets: { number } = {}
	local everyone = others(call)
	table.insert(everyone, { session = call.session, position = call.position })
	for _, other in everyone do
		local p = other.position
		if PvpFunRules.flatDistance(center, p) <= radius and p.Y <= center.Y + CONFETTI_ABOVE then
			table.insert(targets, other.session.userId)
		end
	end
	fire(call.world, call.now, {
		attacker = call.session.userId,
		itemId = call.tool.id,
		effect = "Confetti",
		position = out(call.ctx, center),
		radius = radius,
		targets = targets,
		mega = mega,
		duration = cfg.STICK_SECONDS,
	})
	return true, nil
end

local function addLanding(landing: Landing)
	table.insert(landings, landing)
	while #landings > LANDINGS_MAX do
		table.remove(landings, 1)
	end
end

-- Goo Balloon / Dance Bomb: lobbed to the aim (pulled in to AIM_RANGE); it lands after PvpFunRules.flightTime.
local function lob(call: PvpService.UseCall, kind: string, effectName: string, seconds: number?): (boolean, string?)
	local landing = PvpFunRules.landing(call.position, aimOf(call, FUN.AIM_RANGE), FUN.AIM_RANGE)
	local landAt = call.now + PvpFunRules.flightTime(call.position, landing)
	addLanding({
		kind = kind,
		owner = call.session,
		position = landing,
		landAt = landAt,
		endsAt = landAt + (seconds or FUN.LANDING_WINDOW),
		hit = {},
	})
	fire(call.world, call.now, {
		attacker = call.session.userId,
		itemId = call.tool.id,
		effect = effectName,
		origin = out(call.ctx, call.position),
		position = out(call.ctx, landing),
		landAt = landAt,
		duration = seconds,
	})
	return true, nil
end

local function balloon(call: PvpService.UseCall): (boolean, string?)
	return lob(call, "balloon", "Balloon", nil)
end

local function danceBomb(call: PvpService.UseCall): (boolean, string?)
	return lob(call, "disco", "Disco", FUN.DANCE.SECONDS)
end

-- Bubble Wand: a stream of rising bubbles toward the aim (PvpFunRules.bubbleAt); `tick` checks who touches one.
local function bubbles(call: PvpService.UseCall): (boolean, string?)
	local cfg = FUN.BUBBLES
	local p = call.position
	local direction = PvpFunRules.direction(p, aimOf(call, cfg.SPEED), true) or { X = 0, Y = 0, Z = 1 }
	local origin = { X = p.X + direction.X * 2, Y = p.Y + 1.5, Z = p.Z + direction.Z * 2 }
	local stream: Stream = {
		id = nextId("bubbles", call.session),
		owner = call.session,
		origin = origin,
		direction = direction,
		startedAt = call.now,
		popped = {},
	}
	table.insert(streams, stream)
	while #streams > cfg.STREAMS_MAX do
		table.remove(streams, 1)
	end
	fire(call.world, call.now, {
		attacker = call.session.userId,
		itemId = call.tool.id,
		effect = "Bubbles",
		streamId = stream.id,
		origin = out(call.ctx, origin),
		direction = out(call.ctx, direction),
		startedAt = call.now,
	})
	return true, nil
end

local function clearPad(world: World.World, pad: Pad, now: number?)
	local list = pads[pad.owner]
	if list then
		local i = table.find(list, pad)
		if i then
			table.remove(list, i)
		end
		if #list == 0 then
			pads[pad.owner] = nil
		end
	end
	PvpService.fireTrap(world, "TrapCleared", {
		owner = pad.owner.userId,
		trapId = pad.id,
		itemId = "FunBouncePad",
		position = pad.position,
	}, now, true)
end

-- Bounce Pad: placed at the aim; a new one past `maxPlaced` replaces the owner's oldest.
local function bouncePad(call: PvpService.UseCall): (boolean, string?)
	local point = PvpFunRules.landing(call.position, aimOf(call, 4), FUN.AIM_RANGE)
	local list = pads[call.session] or {}
	pads[call.session] = list
	while #list >= math.max(1, call.tool.maxPlaced or 1) do
		clearPad(call.world, list[1], call.now)
		pads[call.session] = list
	end
	local pad: Pad = {
		id = nextId("pad", call.session),
		owner = call.session,
		position = point,
		expiresAt = call.now + FUN.BOUNCE_PAD.SECONDS,
	}
	table.insert(list, pad)
	PvpService.fireTrap(call.world, "TrapPlaced", {
		owner = call.session.userId,
		trapId = pad.id,
		itemId = call.tool.id,
		position = out(call.ctx, point),
	}, call.now, true)
	return true, nil
end

-- Every slime the hammer could bonk: wild ones and the ones sitting on any plot's pads, with their model position.
local function slimesNear(call: PvpService.UseCall): { { id: string, position: Vec } }
	local list = {}
	local slimePosition = call.ctx.slimePosition
	if not slimePosition then
		return list
	end
	local function add(id: string)
		local position = PvpFunRules.vec(slimePosition(id))
		if position then
			table.insert(list, { id = id, position = position })
		end
	end
	for id in call.world.wild do
		add(id)
	end
	for _, owner in call.world.sessions do
		for _, slime in owner.data.slimes do
			if slime.pad ~= nil and not call.world.carriedBy[slime.id] then
				add(slime.id)
			end
		end
	end
	return list
end

--[[
	Squeaky Hammer: bonks the player or slime nearest the aim (within AIM_RADIUS of it and the tool's reach of the
	user). A player squashes flat for `control` seconds, then springs back with a push (`tick`); a shielded or immune
	player only gets the bonk. A slime squashes and springs back: cosmetic only. A whiff still squeaks.
]]
local function squeaky(call: PvpService.UseCall): (boolean, string?)
	local cfg = FUN.HAMMER
	local reach = call.tool.reach or Config.SLAP_REACH
	local aim = PvpFunRules.within(call.position, aimOf(call, 3), reach)
	local best: { session: Session?, slimeId: string?, position: Vec }? = nil
	local bestD = cfg.AIM_RADIUS
	for _, other in others(call) do
		local d = PvpFunRules.distance(aim, other.position)
		if d <= bestD and PvpFunRules.distance(call.position, other.position) <= reach + SPRING_SLACK then
			best, bestD = { session = other.session, position = other.position }, d
		end
	end
	for _, slime in slimesNear(call) do
		local d = PvpFunRules.distance(aim, slime.position)
		if d < bestD and PvpFunRules.distance(call.position, slime.position) <= reach + SPRING_SLACK then
			best, bestD = { slimeId = slime.id, position = slime.position }, d
		end
	end
	local payload: { [string]: any } = {
		attacker = call.session.userId,
		itemId = call.tool.id,
		effect = "Squash",
		position = out(call.ctx, if best then best.position else aim),
		duration = 0,
	}
	if not best then
		fire(call.world, call.now, payload)
		return true, nil
	end
	local target = best.session
	local key = if target then `p{target.userId}` else `s{best.slimeId}`
	local combo, isCombo = PvpFunRules.combo(combos[call.session], key, call.now)
	combos[call.session] = combo
	payload.combo = isCombo
	if not target then
		payload.slimeId = best.slimeId
		payload.duration = cfg.SLIME_SQUASH_SECONDS
		fire(call.world, call.now, payload)
		return true, nil
	end
	payload.target = target.userId
	PvpService.catchThief(call.world, target, call.session, call.now)
	local free, state = controllable(target, call.now)
	if free and state then
		local applied = PvpRules.applyControl(state, call.tool.control or 0, call.now)
		if applied > 0 then
			local scale = if isCombo then cfg.COMBO_PUSH_SCALE else 1
			local _, push =
				PvpKnockbackRules.plan({ push = (call.tool.nudge or 0) * scale } :: any, call.position, best.position)
			holds[target] = {
				kind = "pancake",
				untilTime = call.now + applied,
				push = push,
				attacker = call.session.userId,
			}
			payload.duration = applied
		end
	end
	fire(call.world, call.now, payload)
	return true, nil
end

-- Slime Hat Launcher: a hat shot toward the aim; the first other player in its path wears it (stacking).
local function hatLauncher(call: PvpService.UseCall): (boolean, string?)
	local cfg = FUN.HATS
	local p = call.position
	local origin = { X = p.X, Y = p.Y + 1.5, Z = p.Z }
	local direction = PvpFunRules.direction(origin, aimOf(call, cfg.RANGE)) or { X = 0, Y = 0, Z = 1 }
	local candidates: { PvpFunRules.Candidate } = {}
	for _, other in others(call) do
		table.insert(candidates, { id = other.session.userId, position = other.position })
	end
	local hit, finish = PvpFunRules.firstHit(origin, direction, cfg.RANGE, cfg.HIT_RADIUS, candidates)
	local target = if hit then call.world.sessions[hit.id] else nil
	local stack = 0
	local seconds = call.tool.hatSeconds or 0
	if target then
		local worn = hats[target]
		stack = PvpFunRules.hatStack(if worn then worn.count else 0, worn ~= nil and call.now < worn.untilTime)
		hats[target] = { count = stack, untilTime = call.now + seconds }
	end
	counter += 1
	fire(call.world, call.now, {
		attacker = call.session.userId,
		itemId = call.tool.id,
		effect = "Hat",
		target = if target then target.userId else nil,
		origin = out(call.ctx, origin),
		position = out(call.ctx, finish),
		stack = stack,
		duration = seconds,
		seed = counter,
	})
	return true, nil
end

-- Goo Fireworks: cosmetic rockets at the aim (or the user's spot), in the colour of the user's favourite slime.
local function fireworks(call: PvpService.UseCall): (boolean, string?)
	local cfg = FUN.FIREWORKS
	local point = PvpFunRules.landing(call.position, aimOf(call, 0), FUN.AIM_RANGE)
	fire(call.world, call.now, {
		attacker = call.session.userId,
		itemId = call.tool.id,
		effect = "Firework",
		position = out(call.ctx, point),
		color = PvpFunRules.fireworkColor(call.session.data),
		count = if call.charged then cfg.VOLLEY else 1,
		height = cfg.HEIGHT,
		duration = cfg.SECONDS,
	})
	return true, nil
end

local HANDLERS: { [string]: PvpService.LineHandler } = {
	FunConfetti = confetti,
	FunBalloon = balloon,
	FunBubbles = bubbles,
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
	local ok, why = noTarget(call)
	if not ok then
		return false, why
	end
	return run(call)
end

-- Walk speed 0 while lifted in a bubble, squashed flat or dancing.
function PvpFun.frozen(session: Session, now: number): boolean
	local hold = holds[session]
	return hold ~= nil and now < hold.untilTime
end

-- Walk speed multiplier from a Goo Balloon slow (1 = none). Carry.targetWalkSpeed multiplies it in.
function PvpFun.walkFactor(session: Session, now: number): number
	local slow = slows[session]
	if not slow then
		return 1
	end
	if now >= slow.untilTime then
		slows[session] = nil
		return 1
	end
	return slow.factor
end

-- Hats `session` wears now (0 = none).
function PvpFun.hatCount(session: Session, now: number): number
	local worn = hats[session]
	return if worn and now < worn.untilTime then worn.count else 0
end

-- The live Bounce Pads of an owner (oldest first).
function PvpFun.padsOf(session: Session): { { position: Vec, expiresAt: number } }
	return (pads[session] or {}) :: any
end

-- Another player popped `target`'s bubble early (its ClickDetector). True when it was still floating.
function PvpFun.pop(world: World.World, target: Session, byUserId: number, now: number): boolean
	local hold = holds[target]
	if not hold or hold.kind ~= "bubble" or now >= hold.untilTime or byUserId == target.userId then
		return false
	end
	holds[target] = nil
	fire(world, now, {
		attacker = byUserId,
		target = target.userId,
		itemId = "FunBubbles",
		effect = "Pop",
		duration = 0,
	})
	return true
end

-- A squashed player springs back with a push once the pancake is over.
local function stepHold(world: World.World, session: Session, position: Vec, now: number, ctx: PvpService.Context)
	local hold = holds[session]
	if not hold or now < hold.untilTime then
		return
	end
	holds[session] = nil
	if hold.kind ~= "pancake" or not hold.push then
		return
	end
	local launch = ctx.launch
	local push = hold.push :: Vec
	if launch then
		launch(session.userId, push)
	end
	fire(world, now, {
		attacker = hold.attacker,
		target = session.userId,
		itemId = "FunSqueaky",
		effect = "Boing",
		position = out(ctx, position),
		velocity = PvpKnockbackRules.velocity(push),
		duration = 0,
	})
end

-- Balloon splashes and disco bubbles reaching `session` while they are live.
local function stepLandings(world: World.World, session: Session, position: Vec, now: number, ctx: PvpService.Context)
	for i = #landings, 1, -1 do
		local landing = landings[i]
		if now > landing.endsAt then
			table.remove(landings, i)
		elseif now >= landing.landAt and not landing.hit[session] then
			if landing.kind == "balloon" then
				local radius = FUN.BALLOON.SPLASH_RADIUS
				if PvpFunRules.inArea(landing.position, radius, AREA_HEIGHT, position) then
					landing.hit[session] = true
					local tool = PvpRules.tool("FunBalloon") :: Config.PvpTool
					local applied = 0
					local free, state = controllable(session, now)
					if isThief(session) and session ~= landing.owner and free and state then
						applied = PvpRules.applySlow(state, tool.slowSeconds or 0, now)
						if applied > 0 then
							slows[session] = { factor = 1 - (tool.slow or 0), untilTime = now + applied }
						end
					end
					fire(world, now, {
						attacker = landing.owner.userId,
						target = session.userId,
						itemId = "FunBalloon",
						effect = "Paint",
						position = out(ctx, landing.position),
						duration = FUN.BALLOON.PAINT_SECONDS,
						slowed = applied > 0,
					})
				end
			elseif landing.kind == "disco" and session ~= landing.owner then
				if PvpFunRules.inArea(landing.position, FUN.DANCE.RADIUS, AREA_HEIGHT, position) then
					landing.hit[session] = true
					local tool = PvpRules.tool("FunDanceBomb") :: Config.PvpTool
					if not PvpService.isShielded(session, now) then
						PvpService.catchThief(world, session, landing.owner, now)
					end
					local free, state = controllable(session, now)
					local applied = if free and state then PvpRules.applyControl(state, tool.control or 0, now) else 0
					if applied > 0 then
						holds[session] = { kind = "dance", untilTime = now + applied, attacker = landing.owner.userId }
						fire(world, now, {
							attacker = landing.owner.userId,
							target = session.userId,
							itemId = "FunDanceBomb",
							effect = "Dance",
							position = out(ctx, position),
							duration = applied,
						})
					end
				end
			end
		end
	end
end

-- A bubble of someone else's stream touching `session` pops on them and lifts them (when it may).
local function stepStreams(world: World.World, session: Session, position: Vec, now: number, ctx: PvpService.Context)
	local cfg = FUN.BUBBLES
	for i = #streams, 1, -1 do
		local stream = streams[i]
		if now > PvpFunRules.streamEnds(stream) then
			table.remove(streams, i)
		elseif stream.owner ~= session then
			for index = 1, cfg.COUNT do
				local at = if stream.popped[index] then nil else PvpFunRules.bubbleAt(stream, index, now)
				if at and PvpFunRules.distance(at, position) <= cfg.RADIUS then
					stream.popped[index] = true
					local tool = PvpRules.tool("FunBubbles") :: Config.PvpTool
					local free, state = controllable(session, now)
					local applied = 0
					if not PvpService.isShielded(session, now) then
						PvpService.catchThief(world, session, stream.owner, now)
					end
					local bubble = ctx.funBubble
					if free and state and bubble then
						applied = PvpRules.applyControl(state, tool.control or 0, now)
						if applied > 0 then
							holds[session] =
								{ kind = "bubble", untilTime = now + applied, attacker = stream.owner.userId }
							bubble(session.userId, applied, cfg.LIFT, function(byUserId: number, when: number): boolean
								return PvpFun.pop(world, session, byUserId, when)
							end)
						end
					end
					fire(world, now, {
						attacker = stream.owner.userId,
						target = session.userId,
						itemId = "FunBubbles",
						effect = "Bubble",
						streamId = stream.id,
						index = index,
						position = out(ctx, position),
						duration = applied,
					})
					return
				end
			end
		end
	end
end

-- Bounce Pads under `session`: launches them (the owner higher, with a flip). Shielded players are not bounced.
local function stepPads(world: World.World, session: Session, position: Vec, now: number, ctx: PvpService.Context)
	local cfg = FUN.BOUNCE_PAD
	local launch = ctx.launch
	local tool = PvpRules.tool("FunBouncePad") :: Config.PvpTool
	for owner, list in pads do
		for i = #list, 1, -1 do
			local pad = list[i]
			if now >= pad.expiresAt or not PvpService.state(owner) then
				clearPad(world, pad, now)
			elseif
				launch
				and PvpFunRules.flatDistance(pad.position, position) <= cfg.RADIUS
				and position.Y - pad.position.Y >= PAD_LOW
				and position.Y - pad.position.Y <= PAD_HIGH
				and now - (lastBounce[session] or -math.huge) >= cfg.RETRIGGER
			then
				local isOwner = owner == session
				if isOwner or not PvpService.isShielded(session, now) then
					lastBounce[session] = now
					if not isOwner then
						PvpService.catchThief(world, session, owner, now)
					end
					local lift = { X = 0, Y = if isOwner then tool.height or cfg.HEIGHT else cfg.HEIGHT, Z = 0 }
					if launch(session.userId, lift) then
						fire(world, now, {
							attacker = owner.userId,
							target = session.userId,
							itemId = tool.id,
							effect = "Bounce",
							trapId = pad.id,
							position = out(ctx, pad.position),
							velocity = PvpKnockbackRules.velocity(lift),
							flip = isOwner,
							duration = 0,
						})
					end
					return
				end
			end
		end
	end
end

--[[
	The per-player step (WorldView.updatePlayer, flag on only): a pancake springs back, landings and bubbles reach
	the player, pads bounce them. `position` = the character's root position, nil without a character.
]]
function PvpFun.tick(world: World.World, session: Session, position: any, now: number, ctx: PvpService.Context)
	local p = PvpFunRules.vec(position)
	if not p then
		return
	end
	if holds[session] then
		stepHold(world, session, p, now, ctx)
	end
	if #landings > 0 then
		stepLandings(world, session, p, now, ctx)
	end
	if #streams > 0 then
		stepStreams(world, session, p, now, ctx)
	end
	if next(pads) ~= nil then
		stepPads(world, session, p, now, ctx)
	end
end

-- Drops everything of `session` (leave, flag off): its pads (TrapCleared), streams, landings, holds, slows, hats.
function PvpFun.clear(world: World.World, session: Session)
	for _, pad in table.clone(pads[session] or {}) do
		clearPad(world, pad, nil)
	end
	pads[session] = nil
	for i = #streams, 1, -1 do
		if streams[i].owner == session then
			table.remove(streams, i)
		end
	end
	for i = #landings, 1, -1 do
		if landings[i].owner == session then
			table.remove(landings, i)
		end
	end
	holds[session], slows[session], hats[session], combos[session], lastBounce[session] = nil, nil, nil, nil, nil
end

-- Live server-side fun records (tests: 0 once everything ended and was stepped).
function PvpFun.liveCount(): number
	local n = #landings + #streams
	for _, list in pads do
		n += #list
	end
	return n
end

-- Forgets everything (tests).
function PvpFun.reset()
	table.clear(landings)
	table.clear(streams)
	for _, map in { holds, slows, combos, hats, lastBounce, pads } :: { any } do
		for key in map do
			map[key] = nil
		end
	end
end

-- Registers the Fun line and its cleanup (leave, flag off). Harmless with the flag off (PvpService.use refuses first).
function PvpFun.register()
	PvpService.registerLine("Fun", handler)
	PvpService.onCleanup(PvpFun.clear)
end

return PvpFun
