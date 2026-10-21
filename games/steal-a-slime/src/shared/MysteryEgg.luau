--!strict
--[[
	MysteryEgg (pure)

	The wild Mystery Egg (FEATURES.MysteryEggs, contract/mystery-egg.md): a
	slime record with an `egg` field (EggKind). The fountain rolls the slime
	inside when the egg spawns; on a pad it incubates for its kind's
	hatchSeconds (faster while the owner is home) and the owner hatches it.
	A lucky egg (LUCKY_CHANCE) holds a slime one tier higher; hatchlings are
	born bigger than wild slimes; the per-kind lucky meter (data.eggLuck)
	guarantees the kind's top tier after a run of misses.
	It goes through Genome.generate and PlayerData, so saves need no new version.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local EggKind = if script then require(script.Parent.EggKind) else require("./EggKind")
local FountainTiers = if script then require(script.Parent.FountainTiers) else require("./FountainTiers")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local Types = if script then require(script.Parent.Types) else require("./Types")

type Data = PlayerData.Data

local MysteryEgg = {}

-- Chance that one fountain drop is an egg.
function MysteryEgg.dropChance(raining: boolean): number
	local cfg = Config.MYSTERY_EGG
	return cfg.DROP_CHANCE * (if raining then cfg.RAIN_MULT else 1)
end

-- Most loose (wild or carried) eggs at once.
function MysteryEgg.wildCap(raining: boolean): number
	local cfg = Config.MYSTERY_EGG
	return if raining then cfg.RAIN_MAX_WILD else cfg.MAX_WILD
end

-- Grab price of a wild egg: 0 when `roll` < FREE_DROP_CHANCE, else the kind's flat price.
function MysteryEgg.price(kind: EggKind.Kind, roll: number): number
	return if roll < Config.FREE_DROP_CHANCE then 0 else kind.price
end

-- Size of a hatchling of `tier` for one roll in [0, 1): bigger than a wild slime, never under the tier's floor.
function MysteryEgg.hatchSize(tier: number, roll: number): number
	local cfg = Config.MYSTERY_EGG
	local size = math.max(cfg.HATCH_SIZE_MIN + roll * cfg.HATCH_SIZE_SPAN, Genome.sizeFloor(tier))
	return math.clamp(math.floor(size * 100 + 0.5) / 100, Config.MIN_SIZE, Config.MAX_SIZE)
end

-- A hatchling: a slime of `tier` from Classic and every family, at hatchling size.
local function hatchling(rng: Rng.Rng, id: string, tier: number): Genome.Slime
	local slime = Genome.generate(rng, {
		id = id,
		tier = tier,
		families = if Config.FEATURES.FountainTiers then FountainTiers.allFamilies() else nil,
	})
	slime.size = MysteryEgg.hatchSize(tier, rng:float())
	return slime
end

--[[
	A wild egg: the kind, the lucky roll and the slime inside are rolled now (never
	sent to a client before the hatch). Not incubating yet.
]]
function MysteryEgg.rollWild(rng: Rng.Rng, id: string): (Genome.Slime, EggKind.Kind)
	local kind = EggKind.rollKind(rng:float())
	local tier = EggKind.rollTier(kind, rng:float())
	local lucky = rng:float() < Config.MYSTERY_EGG.LUCKY_CHANCE
	if lucky then
		tier = math.min(tier + 1, Config.MAX_TIER)
	end
	local slime = hatchling(rng, id, tier)
	slime.egg = { kind = kind.id, lucky = if lucky then true else nil }
	return slime, kind
end

-- Hatches of `kind` in a row that missed its top tier (the lucky meter).
function MysteryEgg.misses(data: Data, kind: EggKind.Kind): number
	local luck = data.eggLuck
	return if luck then luck[kind.id] or 0 else 0
end

-- Whether the next hatch of `kind` is guaranteed its top tier.
function MysteryEgg.guaranteed(data: Data, kind: EggKind.Kind): boolean
	return MysteryEgg.misses(data, kind) + 1 >= kind.pity
end

-- The lucky meter as the hatch prompt shows it: "Lucky 3/12".
function MysteryEgg.meterText(data: Data, kind: EggKind.Kind): string
	return `Lucky {math.min(MysteryEgg.misses(data, kind), kind.pity - 1)}/{kind.pity - 1}`
end

-- Starts the hatch clock of an egg that has none yet (its first pad). Returns whether it started.
function MysteryEgg.startIncubating(slime: Genome.Slime, now: number): boolean
	local kind = EggKind.of(slime)
	local egg = slime.egg
	if not kind or not egg or egg.hatchAt ~= nil then
		return false
	end
	egg.hatchAt = now + kind.hatchSeconds
	return true
end

--[[
	The owner is home for `seconds`: every incubating egg in `data` on a pad
	(not in `skip`) gets (WARM_SPEED - 1) x `seconds` closer, never past `now`.
	Returns how many eggs moved.
]]
function MysteryEgg.warm(data: Data, seconds: number, now: number, skip: { [string]: any }?): number
	if seconds ~= seconds or seconds <= 0 then
		return 0
	end
	local gain = (Config.MYSTERY_EGG.WARM_SPEED - 1) * seconds
	local moved = 0
	for _, slime in data.slimes do
		local egg = slime.egg
		local hatchAt = egg and egg.hatchAt
		if egg and hatchAt and hatchAt > now and slime.pad and not (skip and skip[slime.id]) then
			egg.hatchAt = math.max(now, hatchAt - gain)
			moved += 1
		end
	end
	return moved
end

export type Hatch = {
	kind: string, -- the egg kind id
	lucky: boolean, -- a lucky egg: the slime inside was one tier higher than its roll
	guaranteed: boolean, -- the lucky meter was full: the slime became the kind's top tier
}

--[[
	Hatches the owner's ready egg `id` in place: the record turns into the slime
	inside (same id, same pad), the lucky meter applies (a full meter rerolls the
	slime at the kind's top tier on `rng`) and the SlimeDex records it.
	Returns (true, slime, hatch) or (false, reason).
]]
function MysteryEgg.hatchEgg(
	data: Data,
	id: string,
	now: number,
	rng: Rng.Rng
): (boolean, Genome.Slime | string, Hatch?)
	local slime, index = PlayerData.findSlime(data, id)
	if not slime or not slime.egg or not index then
		return false, "not your egg"
	end
	if not EggKind.isReady(slime, now) then
		return false, "egg is not ready"
	end
	local kind = EggKind.of(slime) :: EggKind.Kind
	local lucky = slime.egg.lucky == true
	local top = EggKind.topTier(kind)
	local guaranteed = slime.tier < top and MysteryEgg.guaranteed(data, kind)
	if guaranteed then
		local fresh = hatchling(rng, slime.id, top)
		fresh.pad = slime.pad
		data.slimes[index] = fresh
		slime = fresh
	end
	slime.egg = nil
	slime.growth = nil
	local luck = data.eggLuck or {}
	data.eggLuck = luck
	luck[kind.id] = if slime.tier >= top then 0 else MysteryEgg.misses(data, kind) + 1
	PlayerData.discover(data, slime)
	return true, slime, { kind = kind.id, lucky = lucky, guaranteed = guaranteed }
end

-- What the pad shows of a slime hatched at `at` from a `kindId` egg while the hatch show's wobble plays
-- (HATCH_BURST_SECONDS): a copy that is still that egg, ready since `at`. The record itself is untouched.
function MysteryEgg.shell(slime: Genome.Slime, kindId: string, at: number): Genome.Slime
	local copy = table.clone(slime)
	copy.egg = { kind = kindId, hatchAt = at }
	return copy
end

function MysteryEgg.view(hatched: { slime: Genome.Slime, at: number }?): Types.EggView
	return { hatched = hatched }
end

return table.freeze(MysteryEgg)
