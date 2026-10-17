--!strict
--[[
	Spawner (pure)

	The fountain: drops a wild slime every SPAWN_INTERVAL while fewer than
	MAX_WILD_SLIMES are alive, expires unclaimed ones after WILD_LIFETIME and
	runs the Slime Rain schedule (every RAIN_INTERVAL for RAIN_DURATION:
	faster spawns, RAIN_LUCK, more mutations, double cap), with a heads-up
	toast RAIN_WARNING_SECONDS before each rain.

	FEATURES.Parade: a wild's spot is a pure function of time left
	(ParadeLane: ride, hop along the goo lane round the plaza, slide into the
	goo drain). The world keeps its Fountain.roll angle / radius (the lateral
	offset on the lane); removal stays at expiresAt, and a slime that leaves
	from the lane emits a "Drained" event (the splash at the drain).

	FREE_DROP_CHANCE of drops are free; the rest cost WILD_PRICE_SECONDS of
	the slime's base income, charged on grab (Carry.grab).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local DespawnTelegraph = if Shared then require(Shared.DespawnTelegraph) else require("../shared/DespawnTelegraph")
local WeeklyEvents = if Shared then require(Shared.WeeklyEvents) else require("../shared/WeeklyEvents")
local Consumables = if Shared then require(Shared.Consumables) else require("../shared/Consumables")
local CycleModifier = if Shared then require(Shared.CycleModifier) else require("../shared/CycleModifier")
local DayNight = if Shared then require(Shared.DayNight) else require("../shared/DayNight")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
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
	return math.max(1, math.floor(Genome.baseIncome(slime) * Config.WILD_PRICE_SECONDS))
end

function Spawner.wildCount(world: World): number
	local n = 0
	for _ in world.wild do
		n += 1
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

-- "A LEGENDARY Glow Globble spilled from the fountain!" (Mythic gets "!!").
function Spawner.rareText(slime: Genome.Slime): string
	local rarity = string.upper(Genome.rarity(slime.tier).name)
	local shown = Genome.mutationsDisplay(Genome.mutationList(slime))
	local mutation = if shown ~= "" then `{shown} ` else ""
	local bang = if slime.tier >= Config.SECRET_TIER - 1 then "!!" else "!"
	return `A {rarity} {mutation}{slime.name} spilled from the fountain{bang}`
end

-- FEATURES.FountainTiers: raises world.fountainTier to the best rank on the server (it never drops again while
-- the server lives, so the look and the pool don't flap when a high-rank player leaves) and tells everyone.
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

-- Family ids the fountain can drop (nil with the feature off: Classic only, no extra rng draws).
function Spawner.familyPool(world: World, enabled: boolean?): { string }?
	if not (if enabled == nil then Config.FEATURES.FountainTiers else enabled) then
		return nil
	end
	return FountainTiers.pool(world.fountainTier)
end

function Spawner.spawnOne(world: World, now: number): string
	local id = world.newId()
	local luckMult, mutationMult = CycleModifier.multipliers(world.modifier)
	luckMult = Consumables.spawnLuck(luckMult, world.potionUntil > now)
	local weeklyMutation, weeklyBonus = nil, 0
	-- A live admin event replaces the weekly boosts (never stacks with them): see CONTRACT.md §17.
	local unix = Spawner.unixTime()
	if world.adminEvent == nil and unix then
		local weeklyLuck, weeklyMutationMult = WeeklyEvents.multipliers(unix)
		luckMult *= weeklyLuck
		mutationMult *= weeklyMutationMult
		weeklyMutation, weeklyBonus = WeeklyEvents.mutationBoost(unix)
	end
	local drop = Fountain.roll(
		world.rng,
		id,
		world.raining,
		Spawner.pityTier(world.pity),
		luckMult,
		mutationMult,
		weeklyMutation,
		weeklyBonus,
		Spawner.familyPool(world)
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
	world.wild[id] = {
		slime = drop.slime,
		price = Spawner.price(drop.slime, world.rng:float()),
		spawnedAt = now,
		expiresAt = now + Config.WILD_LIFETIME,
		angle = drop.angle,
		radius = drop.radius,
		position = nil,
		rare = rare,
	}
	return id
end

-- The Boss Slime: a free, max-size Epic (or better) with at least Glow, alive
-- BOSS_LIFETIME. It ignores the wild cap. Returns its id.
function Spawner.spawnBoss(world: World, now: number): string
	local id = world.newId()
	local drop = Fountain.roll(world.rng, id, true)
	local slime = drop.slime
	slime.tier = math.max(slime.tier, Config.BOSS_TIER)
	slime.size = Config.MAX_SIZE
	if slime.mutation == "None" then
		Genome.setMutations(slime, { "Glow" })
	end
	world.wild[id] = {
		slime = slime,
		price = 0,
		spawnedAt = now,
		expiresAt = now + Config.BOSS_LIFETIME,
		angle = drop.angle,
		radius = drop.radius,
		position = nil,
		boss = true,
	}
	World.notify(
		world,
		nil,
		`A BOSS SLIME slid into the plaza: {Genome.displayName(slime)}! Grab it first!`,
		"good",
		"Rain"
	)
	return id
end

-- Id of the live Boss Slime, if any.
function Spawner.bossId(world: World): string?
	for id, wild in world.wild do
		if wild.boss then
			return id
		end
	end
	return nil
end

-- State.boss (CONTRACT.md §8.2): active while the Boss Slime is in the world
-- (wild or carried, until deposited or expired); endsAt = its expiry.
function Spawner.boss(world: World): (boolean, number?)
	local id = Spawner.bossId(world)
	if not id then
		return false, nil
	end
	return true, world.wild[id].expiresAt
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
	if not (Config.FEATURES.CycleModifier and Config.FEATURES.DayNight) then
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
	local raining, _, nextAt = Spawner.rain(world, now)
	if not raining and nextAt and nextAt - now <= Config.RAIN_WARNING_SECONDS and not world.rainWarned then
		world.rainWarned = true
		World.notify(world, nil, "Slime Rain in 1 minute! Head to the fountain.", "info", nil)
	end
	if raining ~= world.raining then
		world.rainWarned = false
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

	-- Removal stays at expiresAt; the telegraph (DespawnAt, Scene) only warns before it.
	for id, wild in world.wild do
		if DespawnTelegraph.shouldRemove(now, wild.expiresAt) and world.carriedBy[id] == nil then
			world.wild[id] = nil
			if ParadeLane.enabled() and ParadeLane.onLane(wild, false) then
				World.emit(world, { type = "Drained", slimeId = id })
			end
		end
	end

	if now >= world.nextBossAt then
		world.nextBossAt = now + Config.BOSS_INTERVAL
		if Config.FEATURES.BossSlime and not Spawner.bossId(world) then
			Spawner.spawnBoss(world, now)
		end
	end

	local bossActive, bossEndsAt = Spawner.boss(world)
	if bossActive ~= world.bossActive or bossEndsAt ~= world.bossEndsAt then
		world.bossActive = bossActive
		world.bossEndsAt = bossEndsAt
		World.markAllDirty(world)
	end

	if now >= world.nextSpawnAt then
		world.nextSpawnAt = now + Fountain.spawnInterval(raining)
		if Fountain.canSpawn(Spawner.wildCount(world), raining) then
			Spawner.spawnOne(world, now)
		end
	end
end

return Spawner
