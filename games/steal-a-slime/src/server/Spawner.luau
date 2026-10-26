--!strict
--[[
	Spawner (pure)

	The fountain: drops a wild slime every SPAWN_INTERVAL (no cap on how many
	are alive), expires unclaimed ones after their lifetime
	(Fountain.wildLifetime: WILD_LIFETIME, longer for Mythic / Secret) and
	runs the Slime Rain schedule (every RAIN_INTERVAL for RAIN_DURATION:
	RAIN_SPAWN_INTERVAL, RAIN_LUCK).

	FEATURES.Parade: a wild's spot is a pure function of time left
	(ParadeLane: ride, glide along the goo lane round the plaza, slide into
	the goo drain). A dropped slime walks back to the lane and is on it again
	when it arrives (wild.returning, contract/slime-walk.md). The world keeps its Fountain.roll angle / radius (the lateral
	offset on the lane); removal stays at expiresAt, and a slime that leaves
	from the lane emits a "Drained" event (the splash at the drain).

	FREE_DROP_CHANCE of drops are free; the rest cost Economy.wildPrice
	(WILD_PRICE_SECONDS of its rarity x base income), charged on grab
	(Carry.grab). A Mystery Egg is always free.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local DespawnTelegraph = if Shared then require(Shared.DespawnTelegraph) else require("../shared/DespawnTelegraph")
local WeeklyEvents = if Shared then require(Shared.WeeklyEvents) else require("../shared/WeeklyEvents")
local EventSecrets = if Shared then require(Shared.EventSecrets) else require("../shared/EventSecrets")
local Consumables = if Shared then require(Shared.Consumables) else require("../shared/Consumables")
local CycleModifier = if Shared then require(Shared.CycleModifier) else require("../shared/CycleModifier")
local DayNight = if Shared then require(Shared.DayNight) else require("../shared/DayNight")
local EggKind = if Shared then require(Shared.EggKind) else require("../shared/EggKind")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local MysteryEgg = if Shared then require(Shared.MysteryEgg) else require("../shared/MysteryEgg")
local ParadeChoreo = if Shared then require(Shared.ParadeChoreo) else require("../shared/ParadeChoreo")
local ParadeLane = if Shared then require(Shared.ParadeLane) else require("../shared/ParadeLane")
local Progression = if Shared then require(Shared.Progression) else require("../shared/Progression")
local Fountain = if Shared then require(Shared.Fountain) else require("../shared/Fountain")
local FountainTiers = if Shared then require(Shared.FountainTiers) else require("../shared/FountainTiers")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

local Spawner = {}

-- Unix seconds for the weekly schedule (WeeklyEvents is a function of wall-clock UTC, not server uptime);
-- tests replace it (tests/ServerFixtures pins it to nil = no weekly schedule, so seeded drops never depend on the date).
Spawner.unixTime = os.time :: () -> number?

-- Price of a wild slime: 0 when `roll` < FREE_DROP_CHANCE.
function Spawner.price(slime: Genome.Slime, roll: number): number
	if roll < Config.FREE_DROP_CHANCE then
		return 0
	end
	return Economy.wildPrice(slime)
end

-- Wild slimes on the plaza (the boss never counts).
function Spawner.wildCount(world: World): number
	local n = 0
	for _, wild in world.wild do
		if not wild.boss then
			n += 1
		end
	end
	return n
end

-- Returns (active, endsAt?, nextAt?) in server time.
function Spawner.rain(world: World, now: number): (boolean, number?, number?)
	local active, left = Progression.rainStatus(now - world.startedAt, world.rainForcedUntil)
	if active then
		return true, now + left, nil
	end
	return false, nil, now + left
end

-- Starts a Slime Rain right now (e.g. a future server-wide product).
function Spawner.forceRain(world: World, now: number)
	world.rainForcedUntil = now - world.startedAt + Config.RAIN_DURATION
end

-- Pity floor for the next drop (CONTRACT.md §8.7), or nil.
function Spawner.pityTier(pity: World.Pity): number?
	if pity.sinceLegendary + 1 >= Config.PITY_LEGENDARY then
		return 5
	elseif pity.sinceEpic + 1 >= Config.PITY_EPIC then
		return 4
	end
	return nil
end

-- "A LEGENDARY Globble spilled from the fountain!" (Mythic gets "!!").
function Spawner.rareText(slime: Genome.Slime): string
	local rarity = string.upper(Genome.rarity(slime.tier).name)
	local bang = if slime.tier >= Config.SECRET_TIER - 1 then "!!" else "!"
	return `A {rarity} {slime.name} spilled from the fountain{bang}`
end

-- FEATURES.FountainTiers: raises world.fountainTier to the best rank on the server (it never drops again while
-- the server lives, so the look doesn't flap when a high-rank player leaves) and tells everyone.
-- Returns true when the tier rose. `enabled` (tests) overrides FEATURES.FountainTiers.
function Spawner.stepFountainTier(world: World, enabled: boolean?): boolean
	if not (if enabled == nil then Config.FEATURES.FountainTiers else enabled) then
		return false
	end
	local best = 0
	for _, session in world.sessions do
		best = math.max(best, session.data.rebirths)
	end
	local tier = FountainTiers.tierFor(best)
	if tier <= world.fountainTier then
		return false
	end
	world.fountainTier = tier
	local text = FountainTiers.upgradeText(tier)
	if text then
		World.notify(world, nil, text, "good", "Rare")
	end
	World.markAllDirty(world)
	return true
end

-- Family ids whose species the fountain drops besides Classic: every family, whatever the ranks on the server
-- (nil with the feature off: Classic only).
function Spawner.familyPool(enabled: boolean?): { string }?
	if not (if enabled == nil then Config.FEATURES.FountainTiers else enabled) then
		return nil
	end
	return FountainTiers.allFamilies()
end

-- Loose Mystery Eggs (on the lane, dropped or carried).
function Spawner.wildEggCount(world: World): number
	local n = 0
	for _, wild in world.wild do
		if wild.slime.egg then
			n += 1
		end
	end
	return n
end

-- FEATURES.MysteryEggs: whether this fountain drop is an egg (rolled on world.eggRng). `enabled` (tests) overrides
-- the flag.
function Spawner.rollEgg(world: World, enabled: boolean?): boolean
	if not (if enabled == nil then Config.FEATURES.MysteryEggs else enabled) then
		return false
	end
	if Spawner.wildEggCount(world) >= MysteryEgg.wildCap(world.raining) then
		return false
	end
	return world.eggRng:float() < MysteryEgg.dropChance(world.raining)
end

-- A wild Mystery Egg on the lane (contract/mystery-egg.md): the slime inside is rolled now; no pity, no luck.
function Spawner.spawnEgg(world: World, now: number): string
	local id = world.newId()
	local rng = world.eggRng
	local slime, kind = MysteryEgg.rollWild(rng, id)
	local rare = if kind.announce then kind.tier else nil
	if rare then
		World.notify(
			world,
			nil,
			`A {string.upper(EggKind.displayName(kind))} rolled out of the fountain!`,
			"good",
			"Rare"
		)
		World.emit(world, { type = "Rare", slimeId = id, tier = kind.tier })
	end
	local at = Spawner.slot(world, now)
	world.wild[id] = {
		slime = slime,
		price = 0, -- a wild egg is always free to grab
		spawnedAt = at,
		expiresAt = at + Fountain.wildLifetime(slime),
		angle = rng:float() * math.pi * 2,
		radius = Fountain.MIN_RADIUS + rng:float() * (Fountain.MAX_RADIUS - Fountain.MIN_RADIUS),
		position = nil,
		rare = rare,
	}
	return id
end

-- FEATURES.SlimeChoreo: the lane beats of a new lane wild. A copycat (ParadeChoreo.copies, a hash of its id, no
-- world.rng roll) of the same species right behind another lane wild takes that slime's seed, so it repeats its beats
-- at the same lane spots. nil with the feature or the parade off.
function Spawner.choreoFor(
	world: World,
	id: string,
	slime: Genome.Slime,
	now: number,
	enabled: boolean?
): { seed: number }?
	if not (if enabled == nil then Config.FEATURES.SlimeChoreo else enabled) or not ParadeLane.enabled() then
		return nil
	end
	local seed = ParadeChoreo.seedFor(id)
	if slime.species and ParadeChoreo.copies(id) then
		local ahead: World.Wild? = nil
		for otherId, wild in world.wild do
			if
				otherId ~= id
				and wild.choreo ~= nil
				and not wild.boss
				and ParadeLane.onLane(wild, world.carriedBy[otherId] ~= nil)
				and now - wild.spawnedAt <= ParadeChoreo.COPY_WINDOW
				and (ahead == nil or wild.spawnedAt > ahead.spawnedAt)
			then
				ahead = wild
			end
		end
		if ahead and ahead.choreo and ahead.slime.species == slime.species then
			seed = ahead.choreo.seed
		end
	end
	return { seed = seed }
end

-- One fountain drop: now and then a Mystery Egg (Spawner.rollEgg), else a slime.
Spawner.SLIDE_GAP = 1.6 -- seconds between two drops down the fountain slide: they never ride or walk inside each other

-- The spawn time of a drop asked for at `now`: the next free slide slot (FEATURES.Parade), at least SLIDE_GAP after
-- the last one, so a burst of drops rides down one after another. A drop whose slot is still to come exists in
-- World (it counts in wildCount) but has no model yet (Scene.describe).
function Spawner.slot(world: World, now: number): number
	if not ParadeLane.enabled() then
		return now
	end
	local at = math.max(now, world.slideFreeAt or now)
	world.slideFreeAt = at + Spawner.SLIDE_GAP
	return at
end

function Spawner.spawnOne(world: World, now: number): string
	if Spawner.rollEgg(world) then
		return Spawner.spawnEgg(world, now)
	end
	return Spawner.spawnSlime(world, now)
end

-- One wild slime from the fountain: luck, pity, families, event Secrets and the Legendary+ announcement.
function Spawner.spawnSlime(world: World, now: number): string
	local id = world.newId()
	local luckMult = CycleModifier.multiplier(world.modifier)
	luckMult = Consumables.spawnLuck(luckMult, world.potionUntil > now)
	-- A live admin event replaces the weekly boost (never stacks with it): see CONTRACT.md §17.
	local unix = Spawner.unixTime()
	if world.adminEvent == nil and unix then
		luckMult *= WeeklyEvents.multiplier(unix)
	end
	local drop = Fountain.roll(
		world.rng,
		id,
		world.raining,
		Spawner.pityTier(world.pity),
		luckMult,
		Spawner.familyPool(),
		if unix then EventSecrets.extraSpecies(unix) else nil
	)
	local tier = drop.slime.tier
	local pity = world.pity
	pity.sinceEpic = if tier >= 4 then 0 else pity.sinceEpic + 1
	pity.sinceLegendary = if tier >= 5 then 0 else pity.sinceLegendary + 1
	local rare = if tier >= Config.RARE_ANNOUNCE_TIER then tier else nil
	if rare then
		-- Secrets get their own fanfare; both Notifies go to every player (userId nil).
		local sound = if tier >= Config.SECRET_TIER then "Secret" else "Rare"
		World.notify(world, nil, Spawner.rareText(drop.slime), "good", sound)
		World.emit(world, { type = "Rare", slimeId = id, tier = tier })
	end
	local at = Spawner.slot(world, now)
	world.wild[id] = {
		slime = drop.slime,
		price = Spawner.price(drop.slime, world.rng:float()),
		spawnedAt = at,
		expiresAt = at + Fountain.wildLifetime(drop.slime),
		angle = drop.angle,
		radius = drop.radius,
		position = nil,
		rare = rare,
		choreo = Spawner.choreoFor(world, id, drop.slime, at),
	}
	return id
end

-- Bonus wild slimes on top of the fountain drops (unused by the boss since it stopped shedding): `luckMult` on the
-- rarity roll, free, no pity, no rare announcement. Returns their ids.
function Spawner.spawnBonus(world: World, now: number, count: number, luckMult: number): { string }
	local ids = {}
	for _ = 1, count do
		local id = world.newId()
		local drop = Fountain.roll(world.rng, id, false, nil, luckMult)
		local at = Spawner.slot(world, now)
		world.wild[id] = {
			slime = drop.slime,
			price = 0,
			spawnedAt = at,
			expiresAt = at + Fountain.wildLifetime(drop.slime),
			angle = drop.angle,
			radius = drop.radius,
			position = nil,
			choreo = Spawner.choreoFor(world, id, drop.slime, at),
		}
		table.insert(ids, id)
	end
	return ids
end

-- FEATURES.CycleModifier: re-rolls the server modifier when the DayNight phase
-- (dawn / dusk) changes; the previous one ends right there. Pushes State to everyone.
function Spawner.stepModifier(world: World, now: number)
	local admin = world.adminEvent
	if admin then
		if now < admin.endsAt then
			if world.modifier ~= admin.modifier then
				world.modifier = admin.modifier
				World.markAllDirty(world)
			end
			world.modifierEndsAt = admin.endsAt
			return
		end
		-- Over: fall back to the dawn / dusk roll for this phase.
		world.adminEvent = nil
		world.modifier = CycleModifier.NONE
		world.modifierPhase = -1
		world.modifierEndsAt = nil
		World.markAllDirty(world)
	end
	if not Config.FEATURES.CycleModifier then
		return
	end
	local phase, left = DayNight.phase(now - world.startedAt)
	world.modifierEndsAt = now + left
	if phase == world.modifierPhase then
		return
	end
	local first = world.modifierPhase < 0
	world.modifierPhase = phase
	local modifier = CycleModifier.forPhase(world.modifierSeed, phase)
	if modifier == world.modifier and first then
		return
	end
	world.modifier = modifier
	if modifier.name ~= "None" then
		World.notify(
			world,
			nil,
			`{modifier.label}! Active until {if phase % 2 == 0 then "dusk" else "dawn"}.`,
			"good",
			nil
		)
	end
	World.markAllDirty(world)
end

-- Call every frame (or at least every few tenths of a second).
function Spawner.step(world: World, now: number)
	Spawner.stepModifier(world, now)
	Spawner.stepFountainTier(world)
	local raining = Spawner.rain(world, now)
	if raining ~= world.raining then
		world.raining = raining
		World.emit(world, { type = "Rain", active = raining })
		if raining then
			World.notify(world, nil, "SLIME RAIN! The fountain is overflowing!", "good", "Rain")
			world.nextSpawnAt = math.min(world.nextSpawnAt, now)
		else
			World.notify(world, nil, "The Slime Rain is over.", "info", nil)
		end
		World.markAllDirty(world)
	end

	-- A dropped slime that walked back to the lane is on it again (ParadeLane.returnPose ends where the lane pose
	-- at arriveAt starts, contract/slime-walk.md).
	for id, wild in world.wild do
		local plan = wild.returning
		if plan and now >= plan.arriveAt and world.carriedBy[id] == nil then
			wild.returning = nil
			wild.position = nil
		end
	end

	-- Removal stays at expiresAt; the telegraph (DespawnAt, Scene) only warns before it. The boss leaves through
	-- server/BossEvent, never here.
	for id, wild in world.wild do
		if not wild.boss and DespawnTelegraph.shouldRemove(now, wild.expiresAt) and world.carriedBy[id] == nil then
			world.wild[id] = nil
			if ParadeLane.enabled() and ParadeLane.onLane(wild, false) then
				World.emit(world, { type = "Drained", slimeId = id })
			end
		end
	end

	if now >= world.nextSpawnAt then
		world.nextSpawnAt = now + Fountain.spawnInterval(raining)
		Spawner.spawnOne(world, now)
	end
end

return Spawner
