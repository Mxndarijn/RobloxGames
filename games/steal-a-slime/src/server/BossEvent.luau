--!strict
--[[
	BossEvent (pure, contract/boss-event.md)

	The boss event over World: the schedule (world.nextBossAt, skipped around Slime Rain), the rotation
	(world.bossIndex), the running event (world.boss = Shared.BossFight state + the wild boss slime), Bat hits on the
	boss, its sheds (Spawner.spawnBonus), the slap that drops the
	hauled boss on the spot, and State.boss. Grabbing and bringing the boss home go through Carry (grabWild /
	depositBoss). Every change marks every session dirty, so State.boss is pushed to everyone.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local BossChoreo = if Shared then require(Shared.BossChoreo) else require("../shared/BossChoreo")
local BossFight = if Shared then require(Shared.BossFight) else require("../shared/BossFight")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Rng = if Shared then require(Shared.Rng) else require("../shared/Rng")
local SlimeRoster = if Shared then require(Shared.SlimeRoster) else require("../shared/SlimeRoster")
local Trophies = if Shared then require(Shared.Trophies) else require("../shared/Trophies")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
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
	world.boss =
		{ fight = fight, slimeId = nil, lastStepAt = now, rng = Rng.new(world.bossIndex * 7919 + math.floor(now)) }
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
	local slime = Trophies.bossSlime(world.rng, id, event.fight.species)
	if not slime then
		return
	end
	local ox, oz = origin(ctx)
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

-- Plaza spots of the players within ENGAGE_RADIUS of (x, z), and the top hitter's spot if they are one of them.
local function fighters(
	world: World,
	event: World.BossEvent,
	ctx: Context?,
	x: number,
	z: number
): ({ { number } }, { number }?)
	local players: { { number } } = {}
	local pose = ctx and ctx.pose
	if not pose then
		return players, nil
	end
	local ox, oz = origin(ctx)
	local top = BossFight.top(event.fight)
	local target: { number }? = nil
	for userId in world.sessions do
		local p = pose(userId)
		if p then
			local spot = { p.X - ox, p.Z - oz }
			if (spot[1] - x) ^ 2 + (spot[2] - z) ^ 2 <= BossEvent.ENGAGE_RADIUS ^ 2 then
				table.insert(players, spot)
				if userId == top then
					target = spot
				end
			end
		end
	end
	return players, target
end

local function noAttack(_slot: string): BossChoreo.Attack?
	return nil
end

-- The fighting boss's next move once its current one has ended. A move starts where the last one ended in time
-- (no gap for clients to fill), unless the server fell behind.
local function advance(world: World, event: World.BossEvent, now: number, ctx: Context?)
	local id = event.slimeId
	local wild = if id then world.wild[id] else nil
	local move = wild and wild.move
	if not wild or not move or event.fight.phase ~= "fight" then
		return
	end
	for _ = 1, 4 do
		if not BossChoreo.ended(move, now) then
			break
		end
		local endAt = move.at + move.seconds
		local players, target = fighters(world, event, ctx, move.tx, move.tz)
		move = BossChoreo.after(move, {
			now = if now - endAt < 0.5 then endAt else now,
			rng = event.rng,
			players = players,
			target = target,
			speed = 1,
			attack = nil,
			resolve = noAttack,
		})
	end
	wild.move = move
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
	local dt = math.max(0, now - event.lastStepAt)
	event.lastStepAt = now
	local before = BossFight.meter(fight, playerCount(world))
	for _, e in BossFight.step(fight, now, dt, playerCount(world)) do
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
	advance(world, event, now, ctx)
	-- The drain moves the meter without an action: push when it shows a new percent.
	if math.floor(BossFight.meter(fight, playerCount(world)) * 100) ~= math.floor(before * 100) then
		World.markAllDirty(world)
	end
end

--[[
	A Bat hit by `session` on the fighting boss (BatTool.swing checks reach and facing). Returns (counted, reason).
	The meter and sheds settle on this same call, so a full meter starts the haul at once.
]]
function BossEvent.hit(world: World, session: Session, now: number): (boolean, string?)
	local event = world.boss
	if not event or not BossEvent.bossId(world) then
		return false, "no boss"
	end
	local ok, reason = BossFight.hit(event.fight, session.userId, now)
	if not ok then
		return false, reason
	end
	World.markAllDirty(world)
	BossEvent.step(world, now)
	return true, nil
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
	local trophies = #session.data.trophies
	local event = world.boss
	if not event then
		return {
			active = false,
			meter = 0,
			nextAt = world.nextBossAt,
			yourPoints = 0,
			yourShare = 0,
			trophies = trophies,
		}
	end
	local fight = event.fight
	local entry = SlimeRoster.get(fight.species)
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
		trophies = trophies,
	}
end

return BossEvent
