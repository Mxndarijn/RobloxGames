--!strict
--[[
	MysteryEgg (pure)

	The wild Mystery Egg (FEATURES.MysteryEggs, contract/mystery-egg.md): a
	slime record with an `egg` field (EggKind). The fountain rolls the slime
	inside when the egg spawns; on a pad it incubates for its kind's
	hatchSeconds (faster while the owner is home) and the owner hatches it.
	It goes through Genome.generate and PlayerData, so saves need no new version.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local EggKind = if script then require(script.Parent.EggKind) else require("./EggKind")
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

--[[
	A wild egg: the kind and the slime inside (a Classic species, so no rank gate can
	block the grab or hint at it) are rolled now. Not incubating yet.
]]
function MysteryEgg.rollWild(rng: Rng.Rng, id: string): (Genome.Slime, EggKind.Kind)
	local kind = EggKind.rollKind(rng:float())
	local slime = Genome.generate(rng, {
		id = id,
		tier = EggKind.rollTier(kind, rng:float()),
	})
	slime.egg = { kind = kind.id }
	return slime, kind
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

--[[
	Hatches the owner's ready egg `id` in place: the record turns into the slime
	inside (same id, same pad) and the SlimeDex records it.
	Returns (true, slime) or (false, reason).
]]
function MysteryEgg.hatchEgg(data: Data, id: string, now: number): (boolean, Genome.Slime | string)
	local slime = PlayerData.findSlime(data, id)
	if not slime or not slime.egg then
		return false, "not your egg"
	end
	if not EggKind.isReady(slime, now) then
		return false, "egg is not ready"
	end
	slime.egg = nil
	slime.growth = nil
	PlayerData.discover(data, slime)
	return true, slime
end

function MysteryEgg.view(hatched: { slime: Genome.Slime, at: number }?): Types.EggView
	return { hatched = hatched }
end

return table.freeze(MysteryEgg)
