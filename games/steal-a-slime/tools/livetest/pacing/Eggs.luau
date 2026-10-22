--!strict
--[[
	Mystery Egg maths for the pacing sim and its tables, from the game's own EggKind / MysteryEgg code:
	what a bot expects an egg to be worth, and Monte Carlo hatches through MysteryEgg.rollWild / hatchEgg
	(lucky eggs, the per-kind lucky meter and hatchling sizes included).
]]

local Config = require("../../../src/shared/Config")
local EggKind = require("../../../src/shared/EggKind")
local Genome = require("../../../src/shared/Genome")
local MysteryEgg = require("../../../src/shared/MysteryEgg")
local PlayerData = require("../../../src/shared/PlayerData")
local Rng = require("../../../src/shared/Rng")

local Eggs = {}

-- Mean size of a hatchling (HATCH_SIZE_MIN + HATCH_SIZE_SPAN / 2), before the tier's size floor.
local function meanSize(tier: number): number
	local cfg = Config.MYSTERY_EGG
	return math.max(cfg.HATCH_SIZE_MIN + cfg.HATCH_SIZE_SPAN / 2, Genome.sizeFloor(tier))
end

-- Mean base income (cash/s at 0 rebirths, growth 0) of the slime in a `kind` egg, lucky eggs included, without the lucky meter.
function Eggs.expectedIncome(kind: EggKind.Kind): number
	local lucky = Config.MYSTERY_EGG.LUCKY_CHANCE
	local total = 0
	for tier, p in EggKind.probabilities(kind) do
		local up = math.min(tier + 1, Config.MAX_TIER)
		total += p * ((1 - lucky) * Genome.rarity(tier).income * meanSize(tier) + lucky * Genome.rarity(up).income * meanSize(
			up
		))
	end
	return total
end

export type Outcome = {
	kind: string,
	n: number,
	tiers: { [number]: number }, -- share of hatches by tier
	income: number, -- mean base income of a hatch
	topShare: number, -- share that hit the kind's top tier
	guaranteed: number, -- share that came from a full lucky meter
}

--[[
	Hatches `n` wild eggs back to back through the game's roll and hatch code, one player's lucky meters
	(a meter is per kind, so one mixed stream gives every kind its own run). Returns one Outcome per kind id.
]]
function Eggs.simulate(n: number, seed: number): { [string]: Outcome }
	local rng = Rng.new(seed)
	local data = PlayerData.new()
	local sums: { [string]: { n: number, tiers: { [number]: number }, income: number, top: number, guaranteed: number } } =
		{}
	for i = 1, n do
		local slime, kind = MysteryEgg.rollWild(rng, `e{i}`)
		slime.pad = 1
		(slime.egg :: EggKind.Egg).hatchAt = 0
		data.slimes = { slime }
		local ok, result, info = MysteryEgg.hatchEgg(data, slime.id, 1, rng)
		assert(ok and info, "hatch failed")
		local hatched = result :: Genome.Slime
		local sum = sums[kind.id]
		if not sum then
			sum = { n = 0, tiers = {}, income = 0, top = 0, guaranteed = 0 }
			sums[kind.id] = sum
		end
		sum.n += 1
		sum.tiers[hatched.tier] = (sum.tiers[hatched.tier] or 0) + 1
		sum.income += Genome.baseIncome(hatched)
		if hatched.tier >= EggKind.topTier(kind) then
			sum.top += 1
		end
		if info.guaranteed then
			sum.guaranteed += 1
		end
	end
	local out: { [string]: Outcome } = {}
	for id, sum in sums do
		local tiers = {}
		for tier, c in sum.tiers do
			tiers[tier] = c / sum.n
		end
		out[id] = {
			kind = id,
			n = sum.n,
			tiers = tiers,
			income = sum.income / sum.n,
			topShare = sum.top / sum.n,
			guaranteed = sum.guaranteed / sum.n,
		}
	end
	return out
end

return Eggs
