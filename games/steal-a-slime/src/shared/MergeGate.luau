--!strict
--[[
	MergeGate (pure, contract/merge-vat.md §21.9)

	Which rarities a player may put in the merge vat, by rebirths. Each Config.REBIRTH_TIERS rank that opens a
	rarity carries `merge` (the top input tier it allows); the best reached rank counts. Loading a locked slime
	is fine: only starting the brew and the +2 jump check the gate.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

local MergeGate = {}

local function rarityName(tier: number): string
	local rarity = Config.RARITIES[math.clamp(tier, 1, Config.MAX_TIER)]
	return rarity.name
end

-- The highest rarity tier a player with `rebirths` may merge (put three of in the vat).
function MergeGate.topTier(rebirths: number): number
	local top = 0
	for _, rank in Config.REBIRTH_TIERS do
		if rank.merge and rebirths >= rank.rebirths and rank.merge > top then
			top = rank.merge
		end
	end
	return top
end

function MergeGate.allows(tier: number, rebirths: number): boolean
	return tier <= MergeGate.topTier(rebirths)
end

-- The rebirth count that opens merges of `tier`; nil if no rank does.
function MergeGate.rebirthsFor(tier: number): number?
	local best: number? = nil
	for _, rank in Config.REBIRTH_TIERS do
		if rank.merge and rank.merge >= tier and (best == nil or rank.rebirths < best) then
			best = rank.rebirths
		end
	end
	return best
end

-- Whether the +2 jump from `fromTier` may roll: the rarity it lands on has to be open as a result.
function MergeGate.jumpAllowed(fromTier: number, rebirths: number): boolean
	return fromTier + 2 <= MergeGate.topTier(rebirths) + 1
end

-- "Rebirth 3 to unlock" (the vat's main button and VatStart's refusal); "Locked" if no rank opens `tier`.
function MergeGate.lockText(tier: number): string
	local need = MergeGate.rebirthsFor(tier)
	return if need then `Rebirth {need} to unlock` else "Locked"
end

-- "Epic merges open at Rebirth 3".
function MergeGate.opensText(tier: number): string
	local need = MergeGate.rebirthsFor(tier)
	local name = rarityName(tier)
	return if need then `{name} merges open at Rebirth {need}` else `{name} merges are locked`
end

-- "Up to Rare": the top rarity a player with `rebirths` may merge.
function MergeGate.capText(rebirths: number): string
	local top = MergeGate.topTier(rebirths)
	return if top >= 1 then `Up to {rarityName(top)}` else "Locked"
end

-- "Epic" for a rank that opens Epic merges; nil for a rank that opens nothing new (or the first rank).
function MergeGate.opensAt(rank: Config.RebirthTier): string?
	if not rank.merge or rank.rebirths <= 0 then
		return nil
	end
	local before = MergeGate.topTier(rank.rebirths - 1)
	if rank.merge <= before then
		return nil
	end
	local names = {}
	for tier = before + 1, math.min(rank.merge, Config.MAX_TIER) do
		table.insert(names, rarityName(tier))
	end
	return table.concat(names, " and ")
end

return table.freeze(MergeGate)
