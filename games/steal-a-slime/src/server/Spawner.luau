--!strict
--[[
	Spawner (pure)

	The volcano: drops a wild slime every SPAWN_INTERVAL while fewer than
	MAX_WILD_SLIMES are alive, expires unclaimed ones after WILD_LIFETIME and
	runs the Slime Rain schedule (every RAIN_INTERVAL for RAIN_DURATION:
	faster spawns, RAIN_LUCK, more mutations, double cap), with a heads-up
	toast RAIN_WARNING_SECONDS before each rain.

	FREE_DROP_CHANCE of drops are free; the rest cost WILD_PRICE_SECONDS of
	the slime's base income, charged on grab (Carry.grab).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local DespawnTelegraph = if Shared then require(Shared.DespawnTelegraph) else require("../shared/DespawnTelegraph")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local Progression = if Shared then require(Shared.Progression) else require("../shared/Progression")
local Volcano = if Shared then require(Shared.Volcano) else require("../shared/Volcano")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

local Spawner = {}

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

-- "A LEGENDARY Glow Globble erupted from the volcano!" (Mythic gets "!!").
function Spawner.rareText(slime: Genome.Slime): string
	local rarity = string.upper(Genome.rarity(slime.tier).name)
	local mutation = if slime.mutation ~= "None" then `{slime.mutation} ` else ""
	local bang = if slime.tier >= Config.MAX_TIER then "!!" else "!"
	return `A {rarity} {mutation}{slime.name} erupted from the volcano{bang}`
end

function Spawner.spawnOne(world: World, now: number): string
	local id = world.newId()
	local drop = Volcano.roll(world.rng, id, world.raining, Spawner.pityTier(world.pity))
	local tier = drop.slime.tier
	local pity = world.pity
	pity.sinceEpic = if tier >= 4 then 0 else pity.sinceEpic + 1
	pity.sinceLegendary = if tier >= 5 then 0 else pity.sinceLegendary + 1
	local rare = if tier >= Config.RARE_ANNOUNCE_TIER then tier else nil
	if rare then
		World.notify(world, nil, Spawner.rareText(drop.slime), "good", "Rare")
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
	local drop = Volcano.roll(world.rng, id, true)
	local slime = drop.slime
	slime.tier = math.max(slime.tier, Config.BOSS_TIER)
	slime.size = Config.MAX_SIZE
	if slime.mutation == "None" then
		slime.mutation = "Glow"
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
	World.notify(world, nil, `A BOSS SLIME erupted: {Genome.displayName(slime)}! Grab it first!`, "good", "Rain")
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

-- Call every frame (or at least every few tenths of a second).
function Spawner.step(world: World, now: number)
	local raining, _, nextAt = Spawner.rain(world, now)
	if not raining and nextAt and nextAt - now <= Config.RAIN_WARNING_SECONDS and not world.rainWarned then
		world.rainWarned = true
		World.notify(world, nil, "Slime Rain in 1 minute! Head to the volcano.", "info", nil)
	end
	if raining ~= world.raining then
		world.rainWarned = false
		world.raining = raining
		World.emit(world, { type = "Rain", active = raining })
		if raining then
			World.notify(world, nil, "SLIME RAIN! The volcano is erupting!", "good", "Rain")
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
		world.nextSpawnAt = now + Volcano.spawnInterval(raining)
		if Volcano.canSpawn(Spawner.wildCount(world), raining) then
			Spawner.spawnOne(world, now)
		end
	end
end

return Spawner
