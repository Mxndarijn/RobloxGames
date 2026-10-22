--!strict
--[[
	BossEvent (pure, contract/boss-event.md)

	The boss event over World: the schedule (world.nextBossAt, skipped around Slime Rain), the rotation
	(world.bossIndex), the running event (world.boss = Shared.BossFight state + the wild boss slime), Bat hits on the
	boss, its sheds (Spawner.spawnBonus), the slap that drops the
	hauled boss on the spot, and State.boss. Grabbing and bringing the boss home go through Carry (grabWild /
	depositBoss); hits and wins are credited through BossCredit. Every change marks every session dirty, so State.boss
	is pushed to everyone.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local BatRules = if Shared then require(Shared.BatRules) else require("../shared/BatRules")
local BossAttacks = if Shared then require(Shared.BossAttacks) else require("../shared/BossAttacks")
local BossBadges = if Shared then require(Shared.BossBadges) else require("../shared/BossBadges")
local BossChoreo = if Shared then require(Shared.BossChoreo) else require("../shared/BossChoreo")
local BossFight = if Shared then require(Shared.BossFight) else require("../shared/BossFight")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PvpKnockbackRules = if Shared then require(Shared.PvpKnockbackRules) else require("../shared/PvpKnockbackRules")
local Rng = if Shared then require(Shared.Rng) else require("../shared/Rng")
local SlimeRoster = if Shared then require(Shared.SlimeRoster) else require("../shared/SlimeRoster")
local BossSlime = if Shared then require(Shared.BossSlime) else require("../shared/BossSlime")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local BossCredit = if script then require(script.Parent.BossCredit) else require("./BossCredit")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local BOSS = Config.BOSS

type Vec = { X: number, Y: number, Z: number }

-- What the adapter tells the boss about the world (server/ServerContext; tests pass a fake or nothing).
export type Context = {
	pose: ((userId: number) -> (Vec?, Vec?))?, -- a character's root position and look
	plazaOrigin: (() -> Vec)?, -- the fountain centre in world studs (plaza coordinates are round it)
	airborne: ((userId: number) -> boolean)?, -- off the ground (jumping clears a stomp's ring)
	launch: ((userId: number, push: Vec, landing: Vec) -> boolean)?, -- an attack's knockback (PvpLaunch)
}

local BossEvent = {}

-- Studs from the boss within which a player counts as in the fight (it looks at them, strolls toward them).
BossEvent.ENGAGE_RADIUS = 70

local function origin(ctx: Context?): (number, number)
	local get = ctx and ctx.plazaOrigin
	local o = if get then get() else nil
	return if o then o.X else 0, if o then o.Z else 0
end

local function playerCount(world: World): number
	local n = 0
	for _ in world.sessions do
		n += 1
	end
	return n
end

local function nameOf(world: World, userId: number?): string?
	local session = if userId then world.sessions[userId] else nil
	return session and session.name
end

-- The boss species for rotation slot `index` on a server whose fountain is at `fountainTier`: a Secret-tier boss
-- needs BOSS.SECRET_FOUNTAIN_TIER, otherwise that slot is BOSS.SECRET_FALLBACK.
function BossEvent.speciesFor(index: number, fountainTier: number): string
	local rotation = BOSS.ROTATION
	local species = rotation[(index - 1) % #rotation + 1]
	local entry = SlimeRoster.get(species)
	if entry and entry.tier >= Config.SECRET_TIER and fountainTier < BOSS.SECRET_FOUNTAIN_TIER then
		return BOSS.SECRET_FALLBACK
	end
	return species
end

-- True when the arrival at `arriveAt` must move: Slime Rain still runs then, or starts within BOSS.RAIN_GAP after it.
function BossEvent.rainBlocks(world: World, now: number, arriveAt: number): boolean
	local raining, endsAt, nextAt = Spawner.rain(world, now)
	if raining then
		return endsAt == nil or endsAt > arriveAt
	end
	return nextAt ~= nil and nextAt - arriveAt <= BOSS.RAIN_GAP
end

-- Id of the boss slime while it is in the world (fight or haul), else nil.
function BossEvent.bossId(world: World): string?
	local event = world.boss
	return if event and event.slimeId and world.wild[event.slimeId] then event.slimeId else nil
end

-- The fight phase, or nil with no event.
function BossEvent.phase(world: World): BossFight.Phase?
	return if world.boss then world.boss.fight.phase else nil
end

-- True when `session` carries the hauled boss.
function BossEvent.isCarrier(session: Session): boolean
	return session.carry ~= nil and session.carry.boss == true
end

-- Starts the warning for the next boss (the arrival is world.nextBossAt). Returns the species.
local function begin(world: World, now: number): string
	local species = BossEvent.speciesFor(world.bossIndex, world.fountainTier)
	world.bossIndex += 1
	local fight = BossFight.new(species, now)
	fight.endsAt = world.nextBossAt
	world.boss = {
		fight = fight,
		slimeId = nil,
		lastStepAt = now,
		rng = Rng.new(world.bossIndex * 7919 + math.floor(now)),
		nextAttackAt = math.huge,
		attackIndex = 0,
		struck = {},
		struckMove = 0,
		targets = {},
		spits = {},
		puddles = {},
		guards = {},
		rewarded = false,
	}
	world.nextBossAt += BOSS.INTERVAL
	local entry = SlimeRoster.get(species)
	local name = if entry then entry.name else species
	local seconds = math.max(0, math.floor(fight.endsAt - now + 0.5))
	World.notify(world, nil, `BOSS INCOMING! {name} reaches the plaza in {seconds} s. Grab your bat!`, "good", "Rain")
	World.markAllDirty(world)
	return species
end

-- The boss slime arrives at the plaza boss spot (WorldView), outside the wild cap.
local function arrive(world: World, event: World.BossEvent, now: number, ctx: Context?)
	local id = world.newId()
	local slime = BossSlime.build(world.rng, id, event.fight.species)
	if not slime then
		return
	end
	local ox, oz = origin(ctx)
	event.nextAttackAt = now + BOSS.FIRST_ATTACK
	world.wild[id] = {
		move = BossChoreo.first(now, ox, oz),
		slime = slime,
		price = 0,
		spawnedAt = now,
		expiresAt = event.fight.endsAt,
		angle = BOSS.SPOT_ANGLE,
		radius = BOSS.SPOT_RADIUS,
		position = nil,
		boss = true,
	}
	event.slimeId = id
	World.notify(
		world,
		nil,
		`{slime.name} is in the plaza! Hit it with your bat to fill the goo meter!`,
		"good",
		"Rain"
	)
end

-- The meter is full: the boss shrinks to carry size and the top contributor's head start runs.
local function startHaul(world: World, event: World.BossEvent, now: number)
	local fight = event.fight
	local wild = event.slimeId and world.wild[event.slimeId]
	if wild then
		wild.expiresAt = fight.endsAt
		if wild.move then
			wild.move = BossChoreo.hold("down", wild.move, now, BOSS.HAUL_SECONDS)
		end
	end
	local top = nameOf(world, fight.priorityUserId)
	local name = if wild then wild.slime.name else "The boss"
	local text = if top
		then `{name} is down! {top} gets first grab, then anyone. Carry it home!`
		else `{name} is down! Grab it and carry it home!`
	World.notify(world, nil, text, "good", "Rain")
end

-- Fight or haul lost: the boss (carried or not) gets away. No slimes: the sheds were the fight's reward.
local function escape(world: World, event: World.BossEvent, now: number, reason: string)
	local id = event.slimeId
	if id then
		local carrier = world.carriedBy[id]
		if carrier then
			Carry.release(world, carrier, now, nil, "drop")
		end
		world.wild[id] = nil
		world.carriedBy[id] = nil
		event.slimeId = nil
	end
	local text = if reason == "fight"
		then "The boss got away! Fill the meter faster next time."
		else "Nobody brought the boss home! It got away."
	World.notify(world, nil, text, "info", "Rain")
end

-- A player as the boss sees them: plaza spot, root height and whether they are off the ground.
type Spot = { userId: number, x: number, y: number, z: number, airborne: boolean }

-- Every player's plaza spot (none without ctx.pose).
local function spots(world: World, ctx: Context?): { Spot }
	local out: { Spot } = {}
	local pose = ctx and ctx.pose
	if not pose then
		return out
	end
	local ox, oz = origin(ctx)
	local airborne = ctx and ctx.airborne
	for userId in world.sessions do
		local p = pose(userId)
		if p then
			table.insert(out, {
				userId = userId,
				x = p.X - ox,
				y = p.Y,
				z = p.Z - oz,
				airborne = if airborne then airborne(userId) else false,
			})
		end
	end
	return out
end

-- Plaza spots of the players within ENGAGE_RADIUS of (x, z), and the top hitter's spot if they are one of them.
local function fighters(event: World.BossEvent, all: { Spot }, x: number, z: number): ({ { number } }, { number }?)
	local players: { { number } } = {}
	local top = BossFight.top(event.fight)
	local target: { number }? = nil
	for _, s in all do
		if (s.x - x) ^ 2 + (s.z - z) ^ 2 <= BossEvent.ENGAGE_RADIUS ^ 2 then
			local spot = { s.x, s.z }
			table.insert(players, spot)
			if s.userId == top then
				target = spot
			end
		end
	end
	return players, target
end

local function bossWild(world: World, event: World.BossEvent): World.Wild?
	local id = event.slimeId
	local wild = if id then world.wild[id] else nil
	return if wild and wild.position == nil and not world.carriedBy[id :: string] then wild else nil
end

-- Move and attack pace: +STAGE_SPEEDUP for every stage of the meter reached.
local function speedOf(event: World.BossEvent): number
	return 1 + BOSS.STAGE_SPEEDUP * BossFight.stage(event.fight)
end

-- A spit's landing spots, picked at its windup: the players nearest the boss, then spots round it.
local function spitTargets(
	event: World.BossEvent,
	players: { { number } },
	x: number,
	z: number,
	count: number
): { { number } }
	local sorted = table.clone(players)
	table.sort(sorted, function(a, b)
		return (a[1] - x) ^ 2 + (a[2] - z) ^ 2 < (b[1] - x) ^ 2 + (b[2] - z) ^ 2
	end)
	local out = {}
	for i = 1, count do
		local p = sorted[i]
		if p then
			table.insert(out, { p[1], p[2] })
		else
			local a = event.rng:float() * 2 * math.pi
			table.insert(out, { x + math.cos(a) * BOSS.SPIT_SPREAD, z + math.sin(a) * BOSS.SPIT_SPREAD })
		end
	end
	return out
end

-- Things that start with a move: a windup picks spit targets, a spit attack throws them, a rise calls its guards.
local function began(event: World.BossEvent, move: BossChoreo.Move, players: { { number } })
	local species = event.fight.species
	local attack = BossAttacks.get(species, move.slot)
	if move.kind == "windup" and attack and attack.kind == "spit" then
		event.targets = spitTargets(event, players, move.tx, move.tz, attack.count or 3)
	elseif move.kind == "attack" and attack and attack.kind == "spit" then
		for _, t in event.targets do
			table.insert(event.spits, {
				x = t[1],
				z = t[2],
				landAt = move.at + BOSS.SPIT_FLIGHT,
				seconds = attack.slowSeconds or 6,
				slow = attack.slow or 0.5,
				burst = attack.burst,
			})
		end
		event.targets = {}
	elseif move.kind == "rise" and attack then
		event.guards = {}
		for _, p in BossAttacks.guardSpots(move.fx, move.fz, move.hx, move.hz, attack.count or 3) do
			table.insert(event.guards, { x = p[1], z = p[2], alive = true })
		end
	end
	if move.kind ~= "rise" then
		event.guards = {}
	end
end

-- A guard call that ran out with guards still standing: a `heal` attack (Queen Jelly) gets that share of the
-- meter back.
local function healIfGuardsHeld(world: World, event: World.BossEvent, rise: BossChoreo.Move)
	local attack = BossAttacks.get(event.fight.species, rise.slot)
	local heal = attack and attack.heal
	if not heal then
		return
	end
	for _, g in event.guards do
		if g.alive then
			local target = BossFight.target(playerCount(world))
			event.fight.points = math.max(0, event.fight.points - heal * target)
			local entry = SlimeRoster.get(event.fight.species)
			World.notify(
				world,
				nil,
				`The guards healed {if entry then entry.name else "the boss"}! Pop them faster.`,
				"bad",
				nil
			)
			World.markAllDirty(world)
			return
		end
	end
end

-- The fighting boss's next move once its current one has ended. A move starts where the last one ended in time
-- (no gap for clients to fill), unless the server fell behind. An attack winds up from a stop once it is due.
local function advance(world: World, event: World.BossEvent, now: number, all: { Spot })
	local wild = bossWild(world, event)
	local move = wild and wild.move
	if not wild or not move or event.fight.phase ~= "fight" then
		return
	end
	local species = event.fight.species
	local speed = speedOf(event)
	local function resolve(slot: string): BossChoreo.Attack?
		return BossAttacks.get(species, slot)
	end
	for _ = 1, 4 do
		if not BossChoreo.ended(move, now) then
			break
		end
		local endAt = move.at + move.seconds
		local start = if now - endAt < 0.5 then endAt else now
		local players, target = fighters(event, all, move.tx, move.tz)
		local slots = BossAttacks.available(species, BossFight.meter(event.fight, playerCount(world)))
		local due = if start >= event.nextAttackAt and #slots > 0 then slots[event.attackIndex % #slots + 1] else nil
		local prev = move
		if prev.kind == "rise" then
			healIfGuardsHeld(world, event, prev)
		end
		move = BossChoreo.after(prev, {
			now = start,
			rng = event.rng,
			players = players,
			target = target,
			speed = speed,
			attack = due,
			resolve = resolve,
		})
		if move.kind == "windup" then
			event.attackIndex += 1
			event.nextAttackAt = math.huge
		elseif prev.kind == "dazed" or prev.kind == "land" then
			local gap = BOSS.ATTACK_GAP
			event.nextAttackAt = start + (gap[1] + event.rng:float() * (gap[2] - gap[1])) / speed
		end
		began(event, move, players)
		if move.kind ~= "stroll" and move.kind ~= "look" then
			World.markAllDirty(world) -- State.boss shows the daze and the guards
		end
	end
	wild.move = move
end

-- Knocks `spot`'s player away from the boss at plaza (bx, bz) and stuns their bat (Config.BOSS.STUN_SECONDS).
local function strike(world: World, ctx: Context?, spot: Spot, bx: number, bz: number, push: number, now: number)
	local session = world.sessions[spot.userId]
	if not session then
		return
	end
	local ox, oz = origin(ctx)
	local from = { X = bx + ox, Y = spot.y, Z = bz + oz }
	local at = { X = spot.x + ox, Y = spot.y, Z = spot.z + oz }
	local landing, vector = PvpKnockbackRules.away(from, at, push, BOSS.HIT_ARC)
	local launch = ctx and ctx.launch
	if launch then
		launch(spot.userId, vector, landing)
	end
	PvpService.fireEffect(world, {
		attacker = 0,
		target = spot.userId,
		itemId = "Bat",
		effect = "Knockback",
		position = at,
		push = PvpKnockbackRules.horizontal(vector),
		velocity = PvpKnockbackRules.velocity(vector),
		duration = Config.PVP.FX_SECONDS,
	}, now, true) -- live for everyone, whatever FEATURES.PvP says
	session.bossStunUntil = now + BOSS.STUN_SECONDS
	local entry = SlimeRoster.get(world.boss and world.boss.fight.species or "")
	World.notify(world, spot.userId, `{if entry then entry.name else "The boss"} got you! Dodge the red.`, "bad", nil)
	World.markDirty(session)
end

-- The running attack between the last step and `now`: who it strikes, spits landing, puddles slowing players.
local function attacks(world: World, event: World.BossEvent, now: number, t0: number, all: { Spot }, ctx: Context?)
	local wild = bossWild(world, event)
	local move = wild and wild.move
	if move and event.fight.phase == "fight" then
		if move.n ~= event.struckMove then
			event.struckMove = move.n
			event.struck = {}
		end
		local attacking = move.kind == "attack" or move.kind == "hop"
		local attack = if attacking then BossAttacks.get(event.fight.species, move.slot) else nil
		if attack and move then
			local bx, bz = BossChoreo.pose(move, now)
			for _, s in all do
				local hit, part = BossAttacks.strikes(move, attack, t0, now, s)
				local key = `{s.userId}:{part}`
				if hit and not event.struck[key] then
					event.struck[key] = true
					strike(world, ctx, s, bx, bz, attack.push or 35, now)
				end
			end
		end
	end
	for i = #event.spits, 1, -1 do
		local spit = event.spits[i]
		if now >= spit.landAt then
			table.remove(event.spits, i)
			local burst = spit.burst
			table.insert(event.puddles, {
				x = spit.x,
				z = spit.z,
				untilAt = now + spit.seconds,
				slow = spit.slow,
				burstAt = if burst then now + (burst.delay or 1.5) else nil,
				burst = burst,
				struck = {},
			})
		end
	end
	for i = #event.puddles, 1, -1 do
		local puddle = event.puddles[i]
		-- a rune puddle (Goomancer) bursts into a ring of its own
		local burst, burstAt = puddle.burst, puddle.burstAt
		if burst and burstAt and now >= burstAt then
			for _, s in all do
				local speed, radius = burst.speed or 16, burst.radius or 10
				if
					not puddle.struck[s.userId]
					and BossAttacks.ringBand(puddle.x, puddle.z, burstAt, speed, radius, t0, now, s)
				then
					puddle.struck[s.userId] = true
					strike(world, ctx, s, puddle.x, puddle.z, burst.push or 30, now)
				end
			end
		end
		if now >= puddle.untilAt then
			table.remove(event.puddles, i)
		else
			for _, s in all do
				if (s.x - puddle.x) ^ 2 + (s.z - puddle.z) ^ 2 <= BOSS.PUDDLE_RADIUS ^ 2 then
					local session = world.sessions[s.userId]
					if session then
						session.bossSlow = { factor = puddle.slow, untilTime = now + 0.4 }
					end
				end
			end
		end
	end
end

-- The boss's world position { X, Y = 0, Z } at `now` from its move, or nil when it has none (no fight, or dropped).
function BossEvent.spot(world: World, now: number): Vec?
	local id = BossEvent.bossId(world)
	local wild = if id then world.wild[id] else nil
	local move = wild and wild.move
	if not move or (wild and wild.position ~= nil) then
		return nil
	end
	local x, z = BossChoreo.world(move, now)
	return { X = x, Y = 0, Z = z }
end

local settle: (world: World, event: World.BossEvent, now: number, ctx: Context?) -> ()

-- Call every frame: the schedule, then the running event.
function BossEvent.step(world: World, now: number, ctx: Context?)
	local event = world.boss
	if not event then
		if now >= world.nextBossAt - BOSS.WARNING_SECONDS then
			if BossEvent.rainBlocks(world, now, world.nextBossAt) then
				world.nextBossAt += BOSS.SKIP_DELAY
			else
				begin(world, now)
			end
		end
		return
	end
	local fight = event.fight
	if BossFight.over(fight, now) then
		world.boss = nil
		World.markAllDirty(world)
		return
	end
	if fight.phase == "won" and not event.rewarded then
		-- A team win: a lucky slime spills from the fountain for every player who helped.
		event.rewarded = true
		local helpers = 0
		for userId in world.sessions do
			if BossFight.share(fight, userId) >= BOSS.WIN_SHARE then
				helpers += 1
			end
		end
		if helpers > 0 then
			Spawner.spawnBonus(world, now, helpers * BOSS.WIN_SHOWER, BOSS.DROP_LUCK)
			World.notify(
				world,
				nil,
				"Victory shower! Lucky slimes spill from the fountain for the team!",
				"good",
				"Rain"
			)
		end
	end
	local t0 = event.lastStepAt
	settle(world, event, now, ctx)
	if world.boss ~= event then
		return
	end
	local all = spots(world, ctx)
	attacks(world, event, now, t0, all, ctx)
	advance(world, event, now, all)
end

-- The meter, sheds and phase changes up to `now` (also after a hit, without moving the boss).
function settle(world: World, event: World.BossEvent, now: number, ctx: Context?)
	local fight = event.fight
	local dt = math.max(0, now - event.lastStepAt)
	event.lastStepAt = now
	local before = BossFight.meter(fight, playerCount(world))
	local wild = bossWild(world, event)
	local kind = wild and wild.move and wild.move.kind
	local paused = kind == "windup" or kind == "attack" or kind == "hop" or kind == "rise" or kind == "land"
	for _, e in BossFight.step(fight, now, dt, playerCount(world), paused) do
		if e.kind == "fight" then
			arrive(world, event, now, ctx)
		elseif e.kind == "shed" then
			Spawner.spawnBonus(world, now, (e :: any).count, BOSS.DROP_LUCK)
		elseif e.kind == "haul" then
			startHaul(world, event, now)
		elseif e.kind == "fail" then
			escape(world, event, now, (e :: any).reason)
		end
		World.markAllDirty(world)
	end
	-- The drain moves the meter without an action: push when it shows a new percent.
	if math.floor(BossFight.meter(fight, playerCount(world)) * 100) ~= math.floor(before * 100) then
		World.markAllDirty(world)
	end
end

-- True while `session` is stunned by a boss attack (no bat hits, no slaps).
function BossEvent.stunned(session: Session, now: number): boolean
	return session.bossStunUntil ~= nil and now < session.bossStunUntil
end

local function plaza(position: Vec?, ctx: Context?): { number }?
	if not position then
		return nil
	end
	local ox, oz = origin(ctx)
	return { position.X - ox, position.Z - oz }
end

--[[
	A Bat hit by `session` on the fighting boss (BatTool.swing checks reach and facing), swung from world `from`.
	Returns (counted, reason). It counts BossAttacks.hitValue points: more while dazed, none while it floats out of
	reach or while the swinger is stunned. The meter and sheds settle on this same call, so a full meter starts the
	haul at once.
]]
function BossEvent.hit(world: World, session: Session, now: number, from: Vec?, ctx: Context?): (boolean, string?)
	local event = world.boss
	if not event or not BossEvent.bossId(world) then
		return false, "no boss"
	end
	if BossEvent.stunned(session, now) then
		return false, "stunned"
	end
	local wild = bossWild(world, event)
	local meter = BossFight.meter(event.fight, playerCount(world))
	local points, why = BossAttacks.hitValue(event.fight.species, meter, wild and wild.move, now, plaza(from, ctx))
	if not points then
		return false, why
	end
	local ok, reason = BossFight.hit(event.fight, session.userId, now, points)
	if not ok then
		return false, reason
	end
	event.lastHit = { userId = session.userId, points = points, at = now }
	World.markAllDirty(world)
	BossCredit.record(world, session, { kind = "hit" }, now)
	settle(world, event, now, ctx)
	return true, nil
end

-- The live guards' world spots, for the view and the Bat (index -> { X, Y = 0, Z }).
function BossEvent.guardSpots(world: World, ctx: Context?): { [number]: Vec }
	local out: { [number]: Vec } = {}
	local event = world.boss
	if not event then
		return out
	end
	local ox, oz = origin(ctx)
	for i, g in event.guards do
		if g.alive then
			out[i] = { X = g.x + ox, Y = 0, Z = g.z + oz }
		end
	end
	return out
end

--[[
	A Bat swing by `session` from `from` facing `look` at the guards (reach BOSS.GUARD_REACH, in front). Pops the
	nearest; each is BOSS.GUARD_POINTS meter points. The last one drops the boss down, dazed. Returns true on a pop.
]]
function BossEvent.hitGuard(world: World, session: Session, now: number, from: Vec, look: Vec, ctx: Context?): boolean
	local event = world.boss
	if not event or event.fight.phase ~= "fight" or #event.guards == 0 or BossEvent.stunned(session, now) then
		return false
	end
	local candidates: { BatRules.Candidate } = {}
	for i, p in BossEvent.guardSpots(world, ctx) do
		table.insert(candidates, { userId = -i, position = { X = p.X, Y = from.Y, Z = p.Z }, carrying = true })
	end
	local picked = BatRules.pickTarget(from, look, candidates, session.userId, BOSS.GUARD_REACH)
	if not picked then
		return false
	end
	event.guards[-picked].alive = false
	BossFight.add(event.fight, session.userId, BOSS.GUARD_POINTS, now)
	local left = 0
	for _, g in event.guards do
		if g.alive then
			left += 1
		end
	end
	local wild = bossWild(world, event)
	if left == 0 and wild and wild.move and wild.move.kind == "rise" then
		wild.move = BossChoreo.hold("land", wild.move, now, BOSS.LAND_SECONDS, "daze")
		event.guards = {}
		World.notify(world, nil, "Every guard is down! The boss is dazed: hit it now!", "good", nil)
	end
	World.markAllDirty(world)
	settle(world, event, now, ctx)
	return true
end

--[[
	A Bat slap on the boss carrier `target` (reach SLAP_REACH, the shared slap cooldown): the boss drops at `position`
	(the carrier's spot; adapter-defined, nil = its landing) and anyone may grab it. Returns (ok, reason).
]]
function BossEvent.slapCarrier(
	world: World,
	slapper: Session,
	target: Session,
	distance: number,
	now: number,
	position: any?
): (boolean, string?)
	if slapper.userId == target.userId then
		return false, "can't slap yourself"
	end
	if not BossEvent.isCarrier(target) then
		return false, "target isn't carrying the boss"
	end
	if now - slapper.lastSlapAt < Config.SLAP_COOLDOWN then
		return false, "slap on cooldown"
	end
	if distance ~= distance or distance > Config.SLAP_REACH then
		return false, "too far away"
	end
	slapper.lastSlapAt = now
	Carry.release(world, target.userId, now, position, "slap")
	World.notify(world, slapper.userId, `You bonked {target.name}! The boss dropped. Grab it!`, "good", "Slap", "Slap")
	World.notify(world, target.userId, `{slapper.name} bonked you! You dropped the boss.`, "bad", "Slap", "Slap")
	return true, nil
end

-- State.boss for `session` (contract/boss-event.md).
function BossEvent.view(world: World, session: Session, now: number): Types.BossView
	local badges = BossBadges.count(session.data)
	local event = world.boss
	if not event then
		return {
			active = false,
			meter = 0,
			nextAt = world.nextBossAt,
			yourPoints = 0,
			yourShare = 0,
			badges = badges,
		}
	end
	local fight = event.fight
	local entry = SlimeRoster.get(fight.species)
	local wild = if fight.phase == "fight" then bossWild(world, event) else nil
	local move = wild and wild.move
	local guardsLeft = 0
	for _, g in event.guards do
		if g.alive then
			guardsLeft += 1
		end
	end
	local haul = fight.phase == "haul"
	local priorityOn = haul and fight.priorityUntil ~= nil and now < fight.priorityUntil
	return {
		active = BossFight.active(fight),
		phase = fight.phase,
		kind = fight.species,
		name = if entry then entry.name else fight.species,
		tier = if entry then entry.tier else nil,
		meter = BossFight.meter(fight, playerCount(world)),
		endsAt = fight.endsAt,
		nextAt = world.nextBossAt,
		yourPoints = fight.contributions[session.userId] or 0,
		yourShare = BossFight.share(fight, session.userId),
		carrierName = if haul then nameOf(world, fight.carrierUserId) else nil,
		priorityName = if priorityOn then nameOf(world, fight.priorityUserId) else nil,
		priorityUntil = if priorityOn then fight.priorityUntil else nil,
		winnerName = if fight.phase == "won" then nameOf(world, fight.winnerUserId) else nil,
		badges = badges,
		move = move and move.kind,
		moveEndsAt = move and move.at + move.seconds,
		multiplier = if move and move.kind == "dazed" then BOSS.DAZED_MULTIPLIER else nil,
		guardsLeft = if move and move.kind == "rise" then guardsLeft else nil,
		guardsTotal = if move and move.kind == "rise" then #event.guards else nil,
		stunnedUntil = if BossEvent.stunned(session, now) then session.bossStunUntil else nil,
	}
end

return BossEvent
